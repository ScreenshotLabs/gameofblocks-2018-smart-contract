pragma solidity ^0.4.15;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/payment/PullPayment.sol';
import 'zeppelin-solidity/contracts/lifecycle/Destructible.sol';
import 'zeppelin-solidity/contracts/ReentrancyGuard.sol';

import './mixins/MoneyRounderMixin.sol';

contract Map is MoneyRounderMixin, PullPayment, Destructible, ReentrancyGuard {

    // STRUCTS

    struct Transaction {
        string kingdomKey;
        address compensationAddress;
        uint buyingPrice;
        uint compensation;
        uint jackpotContribution;
        uint date;
    }

    struct Kingdom {
        string title;
        string key;
        uint currentPrice;
        uint lastTransaction;
        uint transactionCount;
        address currentOwner;
    }

    mapping(string => uint) kingdomsKeys;
    mapping(string => bool) kingdomsCreated;
    mapping(address => uint) nbKingdoms;
    uint remainingKingdoms;
    
    address public winner;
    uint public round = 1;
    uint public endTime;
    uint public jackpot = 0;
    address public bookerAddress;
    Kingdom[] public kingdoms;
    Transaction[] public kingdomTransactions;

    uint constant public STARTING_CLAIM_PRICE_WEI = 0.00133 ether;
    uint constant public MAXIMUM_CLAIM_PRICE_WEI = 100 ether;

    uint constant public GLOBAL_TEAM_COMMISSION_RATIO = 15;
    uint constant public GLOBAL_JACKPOT_COMMISSION_RATIO = 15;
    
    uint constant public GLOBAL_STEP1_COMPENSATION_RATIO = 100;
    uint constant public GLOBAL_STEP2_COMPENSATION_RATIO = 50;
    uint constant public GLOBAL_STEP3_COMPENSATION_RATIO = 25;

    
    // MODIFIERS

    modifier checkKingdomExistence(string key) {
        require(kingdomsCreated[key] == true);
        _;
    }

    modifier checkIsOpen() {
        require(!isFinalized());
        _;
    }
    
    modifier checkKingdomCost(uint price) {
        require (msg.value >= price);
        _;
    }

    modifier checkMaxPrice() {
        require (msg.value <= MAXIMUM_CLAIM_PRICE_WEI);
        _;
    }
    
    // EVENTS

    event LandCreatedEvent(string kingdomKey, address monarchAddress);
    event LandPurchasedEvent(string kingdomKey, address monarchAddress);
    event CompensationSentEvent(address toAddress, uint valueWei);
    event JackpotSendedEvent(address winner);

    function Map(address _bookerAddress, uint _remainingKingdoms) {
        bookerAddress = _bookerAddress;
        endTime = now + 7 days;
        remainingKingdoms = _remainingKingdoms;
    }

    function createKingdom(address owner, string _key, string _title) public payable {

        require(owner != address(0));
        require(kingdomsCreated[_key] == false);
        require(remainingKingdoms > 0);

        remainingKingdoms--;

        uint compensationRatio;
        if (msg.value >= 1 ether) {
            compensationRatio = GLOBAL_STEP3_COMPENSATION_RATIO;
        } else if (msg.value >= 0.5 ether) {
            compensationRatio = GLOBAL_STEP2_COMPENSATION_RATIO;
        } else {
            compensationRatio = GLOBAL_STEP1_COMPENSATION_RATIO;
        }

        uint currentPrice = msg.value + (msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (msg.value * compensationRatio / 100);

        uint kingdomId = kingdoms.push(Kingdom(_title, _key, currentPrice, 0, 1, owner)) - 1;
        kingdomsKeys[_key] = kingdomId;
        kingdomsCreated[_key] = true;
        uint transactionId = kingdomTransactions.push(Transaction(_key, owner, msg.value, 0, 0, now)) - 1;
        kingdoms[kingdomId].lastTransaction = transactionId;
        
        nbKingdoms[owner]++;
        LandCreatedEvent(_key, owner);
    }

    function isFinalized() public returns (bool) {
        return now >= endTime;
    }

    function getKingdomsNumberByAddress(address addr) public returns (uint nb) {
        return nbKingdoms[addr];
    }

    function setWinner() internal {
        uint maxKingdoms = 0;
        for (uint i = 0; i < kingdoms.length; i++) {
            nbKingdoms[kingdoms[i].currentOwner]++;
            if (nbKingdoms[kingdoms[i].currentOwner] > maxKingdoms) {
                maxKingdoms = nbKingdoms[kingdoms[i].currentOwner];
                winner = kingdoms[i].currentOwner;
            }
        }
    }

    function getCurrentOwner(uint kingdomId) public returns (address addr) {
        return kingdoms[kingdomId].currentOwner;
    }

    function sendJackpot() public payable onlyOwner() {
        require(kingdoms.length > 0);
        uint payment = jackpot;

        require(payment != 0);
        require(this.balance >= payment);

        setWinner();
        require(winner != address(0));

        jackpot = 0;
        endTime = now + 7 days;
        round++;

        remainingKingdoms += 3;
        assert(winner.send(payment));
        JackpotSendedEvent(winner);
    }

    function getKingdomCount() public constant returns (uint kingdomCount) {
        return kingdoms.length;
    }

    function currentClaimPriceWei(string kingdomKey) public constant returns (uint priceInWei) {
        
        if (kingdoms[kingdomsKeys[kingdomKey]].transactionCount == 0) {
            return STARTING_CLAIM_PRICE_WEI;
        }

        Transaction storage transaction = kingdomTransactions[kingdoms[kingdomsKeys[kingdomKey]].lastTransaction];

        uint lastBuyingPrice = transaction.buyingPrice;
        uint teamCommission = lastBuyingPrice * GLOBAL_TEAM_COMMISSION_RATIO / 100;
        uint jackpotCommision = lastBuyingPrice * GLOBAL_JACKPOT_COMMISSION_RATIO / 100;


        uint compensationRatio;
        if (msg.value >= 1 ether) {
            compensationRatio = GLOBAL_STEP3_COMPENSATION_RATIO;
        } else if (msg.value >= 0.5 ether) {
            compensationRatio = GLOBAL_STEP2_COMPENSATION_RATIO;
        } else {
            compensationRatio = GLOBAL_STEP1_COMPENSATION_RATIO;
        }

        uint compensation = lastBuyingPrice * compensationRatio / 100;

        uint newClaimPrice = lastBuyingPrice + teamCommission + jackpotCommision + compensation;
        newClaimPrice = roundMoneyDownNicely(lastBuyingPrice);

        if (newClaimPrice < STARTING_CLAIM_PRICE_WEI) {
            newClaimPrice = STARTING_CLAIM_PRICE_WEI;
        }

        if (newClaimPrice > MAXIMUM_CLAIM_PRICE_WEI) {
            newClaimPrice = MAXIMUM_CLAIM_PRICE_WEI;
        }

        return newClaimPrice;
    }

    function getKingdomInformations(string kingdomKey) public constant returns (string title, uint currentPrice, uint lastTransaction, uint transactionCount, address currentOwner) {
        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        return (kingdom.title, kingdom.currentPrice, kingdom.lastTransaction, kingdom.transactionCount, kingdom.currentOwner);
    }

    function () { }


    // function getKingdomIndex(string key) public returns (uint index) {
    //     return kingdomsKeys[key];
    // }

    function purchaseKingdom(string kingdomKey, string title) public 
    payable 
    nonReentrant()
    checkMaxPrice()
    checkIsOpen()
    checkKingdomExistence(kingdomKey)
    checkKingdomCost(currentClaimPriceWei(kingdomKey))
    {
        uint kingdomId = kingdomsKeys[kingdomKey];
        Kingdom storage kingdom = kingdoms[kingdomId];
        
        uint jackpotCommission = 0;
        uint teamCommission = 0; 

        teamCommission = msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100;
        jackpotCommission = msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100;


        if (teamCommission != 0) {
            recordCommissionEarned(teamCommission);
        }


        uint compensationRatio;
        if (msg.value >= 1 ether) {
            compensationRatio = GLOBAL_STEP3_COMPENSATION_RATIO;
        } else if (msg.value >= 0.5 ether) {
            compensationRatio = GLOBAL_STEP2_COMPENSATION_RATIO;
        } else {
            compensationRatio = GLOBAL_STEP1_COMPENSATION_RATIO;
        }

        uint lastBuyingPrice = kingdomTransactions[kingdom.lastTransaction].buyingPrice;
        uint compensationWei = (msg.value * compensationRatio / 100) + (lastBuyingPrice - ((lastBuyingPrice * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (lastBuyingPrice * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (lastBuyingPrice * compensationRatio / 100)));
        if (compensationWei > 0) {
            compensateLatestMonarch(kingdomKey, compensationWei);
        }
        
        jackpot = jackpot + jackpotCommission;
        kingdom.title = title;

        kingdom.currentPrice = msg.value + (msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (msg.value * compensationRatio / 100);
        uint transactionId = kingdomTransactions.push(Transaction("", msg.sender, msg.value, 0, jackpotCommission, now)) - 1;
        kingdomTransactions[transactionId].kingdomKey = kingdomKey;
        kingdom.transactionCount++;
        kingdom.lastTransaction = transactionId;
        kingdom.currentOwner = msg.sender;

        LandPurchasedEvent(kingdomKey, msg.sender);
    }

    // Allow commission funds to build up in contract for the wizards
    // to withdraw (carefully ring-fenced).
    function recordCommissionEarned(uint _commissionWei) internal {
        asyncSend(bookerAddress, _commissionWei);
    }

    // Send compensation to latest monarch (or hold funds for them
    // if cannot through no fault of current caller).
    function compensateLatestMonarch(string kingdomKey, uint compensationWei) internal {

        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        address compensationAddress = kingdomTransactions[kingdom.lastTransaction].compensationAddress;
        kingdomTransactions[kingdom.lastTransaction].compensation = compensationWei;

        bool sentOk = compensationAddress.send(compensationWei);
        if (sentOk) {
            CompensationSentEvent(compensationAddress, compensationWei);
        } else {
            payments[compensationAddress] += compensationWei;
        }
    }

}