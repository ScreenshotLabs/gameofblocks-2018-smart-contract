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
    mapping(address => uint) public nbTransactions;
    uint remainingKingdoms;

    address public winner;
    uint public endTime;
    uint public jackpot = 0;
    address public bookerAddress;
    Kingdom[] public kingdoms;
    Transaction[] public kingdomTransactions;
    uint public round;

    uint public GLOBAL_COMPENSATION_RATIO = 20; 
    uint constant public STARTING_CLAIM_PRICE_WEI = 0.00133 ether;

    uint constant MAXIMUM_CLAIM_PRICE_WEI = 100 ether;
    uint constant GLOBAL_TEAM_COMMISSION_RATIO = 15;
    uint constant GLOBAL_JACKPOT_COMMISSION_RATIO = 15;
    uint constant TEAM_COMMISSION_RATIO = 10;
    uint constant JACKPOT_COMMISSION_RATIO = 10;
    uint constant COMPENSATION_RATIO = 80;

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

    function Map(address _bookerAddress, uint _remainingKingdoms) {
        bookerAddress = _bookerAddress;
        endTime = now + 7 days;
        remainingKingdoms = _remainingKingdoms;
    }

    function createKingdom(address owner, string _key, string _title) public payable {

        require(msg.value >= STARTING_CLAIM_PRICE_WEI);
        require(owner != address(0));
        require(kingdomsCreated[_key] == false);
        require(remainingKingdoms > 0);

        remainingKingdoms--;

        uint currentPrice = msg.value + (msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_COMPENSATION_RATIO / 100);

        uint kingdomId = kingdoms.push(Kingdom(_title, _key, currentPrice, 0, 1, owner)) - 1;
        kingdomsKeys[_key] = kingdomId;
        kingdomsCreated[_key] = true;
        uint transactionId = kingdomTransactions.push(Transaction(_key, owner, msg.value, 0, 0, now)) - 1;
        kingdoms[kingdomId].lastTransaction = transactionId;
        nbTransactions[owner] = 1;
        LandCreatedEvent(_key, owner);
    }

    function isFinalized() public view returns (bool) {
        return now >= endTime;
    }

    function getKingdomsNumberByAddress(address addr) public view returns (uint nb) {
        return nbKingdoms[addr];
    }

    function setWinner() internal {
        uint maxKingdoms = 0;
        for (uint i = 0; i < kingdoms.length; i++) {
            address addr = kingdoms[i].currentOwner;
            nbKingdoms[addr]++;
            if (nbKingdoms[addr] == maxKingdoms) {
                if (nbTransactions[addr] > nbTransactions[winner]) {
                    winner = addr;
                }
            } else if (nbKingdoms[addr] > maxKingdoms) {
                maxKingdoms = nbKingdoms[addr];
                winner = addr;
            }
        }
    }

    function getCurrentOwner(uint kingdomId) public view returns (address addr) {
        return kingdoms[kingdomId].currentOwner;
    }

    function sendJackpot() public onlyOwner() {
        require(kingdoms.length > 0);
        uint payment = jackpot;

        require(payment != 0);
        require(this.balance >= payment);

        setWinner();
        require(winner != address(0));

        jackpot = 0;
        endTime = now + 7 days;
        remainingKingdoms += 3;
        round++;

        assert(winner.send(payment));
    }

    function getKingdomCount() public view returns (uint kingdomCount) {
        return kingdoms.length;
    }

    function currentClaimPriceWei(string kingdomKey) public view returns (uint priceInWei) {
        
        if (kingdoms[kingdomsKeys[kingdomKey]].transactionCount == 0) {
            return STARTING_CLAIM_PRICE_WEI;
        }

        Transaction storage transaction = kingdomTransactions[kingdoms[kingdomsKeys[kingdomKey]].lastTransaction];

        uint lastBuyingPrice = transaction.buyingPrice;
        uint teamCommission = lastBuyingPrice * GLOBAL_TEAM_COMMISSION_RATIO / 100;
        uint jackpotCommision = lastBuyingPrice * GLOBAL_JACKPOT_COMMISSION_RATIO / 100;
        uint compensation = lastBuyingPrice * GLOBAL_COMPENSATION_RATIO / 100;
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

    function getKingdomInformations(string kingdomKey) public view returns (string title, uint currentPrice, uint lastTransaction, uint transactionCount, address currentOwner) {
        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        return (kingdom.title, kingdom.currentPrice, kingdom.lastTransaction, kingdom.transactionCount, kingdom.currentOwner);
    }

    function () { }

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

        teamCommission = msg.value * TEAM_COMMISSION_RATIO / 100;
        jackpotCommission = msg.value * JACKPOT_COMMISSION_RATIO / 100;

        if (teamCommission != 0) {
            recordCommissionEarned(teamCommission);
        }

        uint compensationWei = msg.value * COMPENSATION_RATIO / 100; 
        if (compensationWei > 0) {
            compensateLatestMonarch(kingdomKey, compensationWei);
        }
        
        jackpot = jackpot + jackpotCommission;
        kingdom.title = title;

        kingdom.currentPrice = msg.value + (msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_COMPENSATION_RATIO / 100);
        uint transactionId = kingdomTransactions.push(Transaction("", msg.sender, msg.value, 0, jackpotCommission, now)) - 1;
        kingdomTransactions[transactionId].kingdomKey = kingdomKey;
        kingdom.transactionCount++;
        kingdom.lastTransaction = transactionId;
        kingdom.currentOwner = msg.sender;
        nbTransactions[msg.sender]++;
        LandPurchasedEvent(kingdomKey, msg.sender);
    }

    function recordCommissionEarned(uint _commissionWei) internal {
        asyncSend(bookerAddress, _commissionWei);
    }

    function compensateLatestMonarch(string kingdomKey, uint compensationWei) internal {
        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        address compensationAddress = kingdomTransactions[kingdom.lastTransaction].compensationAddress;
        kingdomTransactions[kingdom.lastTransaction].compensation = compensationWei;
        bool sentOk = compensationAddress.send(compensationWei);
        if (sentOk == false) {
            payments[compensationAddress] += compensationWei;
        }
    }

}
