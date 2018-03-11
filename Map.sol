pragma solidity ^0.4.15;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/payment/PullPayment.sol';
import 'zeppelin-solidity/contracts/lifecycle/Destructible.sol';
import 'zeppelin-solidity/contracts/ReentrancyGuard.sol';
import "zeppelin-solidity/contracts/math/SafeMath.sol";

contract Map is PullPayment, Destructible, ReentrancyGuard {
    using SafeMath for uint256;
    
    // STRUCTS

    struct Transaction {
        string kingdomKey;
        address compensationAddress;
        uint buyingPrice;
        uint compensation;
        uint tier;
        uint jackpotContribution;
    }

    struct Kingdom {
        string title;
        string key;
        uint kingdomTier;
        uint kingdomType;
        uint minimumPrice;
        uint lastTransaction;
        uint transactionCount;
        uint returnPrice;
        address owner;
    }

    struct Jackpot {
        address winner;
        uint balance;
    }

    mapping(string => uint) kingdomsKeys;
    mapping(string => bool) kingdomsCreated;
    mapping(address => uint) nbKingdoms;
    mapping(address => uint) public nbTransactions;
    mapping(uint => uint) public winnerCapByType;

    Jackpot public jackpot1;
    Jackpot public jackpot2;
    Jackpot public jackpot3;
    Jackpot public jackpot4;
    Jackpot public jackpot5;

    mapping(address => uint) public nbKingdomsType1;
    mapping(address => uint) public nbKingdomsType2;
    mapping(address => uint) public nbKingdomsType3;
    mapping(address => uint) public nbKingdomsType4;
    mapping(address => uint) public nbKingdomsType5;

    uint public endTime;
    uint public remainingKingdoms;
    Jackpot public globalJackpot;
    address public bookerAddress;
    Kingdom[] public kingdoms;
    Transaction[] public kingdomTransactions;
    uint public round;

    uint constant public STARTING_CLAIM_PRICE_WEI = 0.00133 ether;
    uint constant MAXIMUM_CLAIM_PRICE_WEI = 300 ether;
    uint constant KINGDOM_MULTIPLIER = 20;
    uint constant TEAM_COMMISSION_RATIO = 10;
    uint constant JACKPOT_COMMISSION_RATIO = 10;

    // MODIFIERS

    modifier checkKingdomExistence(string key) {
        require(kingdomsCreated[key] == true);
        _;
    }

    modifier checkIsOpen() {
        require(!isFinalized());
        _;
    }

    modifier checkIsClosed() {
        require(isFinalized());
        _;
    }

    modifier checkMaxPrice() {
        require (msg.value <= MAXIMUM_CLAIM_PRICE_WEI);
        _;
    }

    modifier onlyKingdomOwner(string _key, address _sender) {
        require (kingdoms[kingdomsKeys[_key]].owner == _sender);
        _;
    }
    
    // EVENTS

    event LandCreatedEvent(string kingdomKey, address monarchAddress);
    event LandPurchasedEvent(string kingdomKey, address monarchAddress);
 
    //
    //  CONTRACT CONSTRUCTOR
    //
    function Map(address _bookerAddress, uint _remainingKingdoms) {
        bookerAddress = _bookerAddress;
        remainingKingdoms = _remainingKingdoms;

        jackpot1 = Jackpot(address(0), 0);
        jackpot2 = Jackpot(address(0), 0);
        jackpot3 = Jackpot(address(0), 0);
        jackpot4 = Jackpot(address(0), 0);
        jackpot5 = Jackpot(address(0), 0);

        endTime = now + 7 days;
        globalJackpot = Jackpot(address(0), 0);
    }

    function () { }

    // function getMinimumPrice(string _key, uint _tier) public view returns (uint nextPrice) {
    //     uint kingdomId = kingdomsKeys[_key];
    //     Kingdom storage kingdom = kingdoms[kingdomId];

    //     uint bet = (kingdom.returnPrice.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
    //     uint jackpotCommission = kingdom.returnPrice * JACKPOT_COMMISSION_RATIO / 100;
    //     uint teamCommission = kingdom.returnPrice * TEAM_COMMISSION_RATIO / 100;

    //     uint price = kingdom.returnPrice + jackpotCommission + teamCommission + bet;
    //     return price;
    // }

    function setTypedJackpotWinner(address _user, uint _type, uint _value) internal {
        if (_type == 1) {
            if (nbKingdomsType1[_user] >= winnerCapByType[_type]) {
                jackpot1.winner = _user;
            }
        } else if (_type == 2) {
            if (nbKingdomsType2[_user] >= winnerCapByType[_type]) {
                jackpot2.winner = _user;
            }
        } else if (_type == 3) {
            if (nbKingdomsType3[_user] >= winnerCapByType[_type]) {
                jackpot3.winner = _user;
            }
        } else if (_type == 4) {
            if (nbKingdomsType4[_user] >= winnerCapByType[_type]) {
                jackpot4.winner = _user;
            }
        } else if (_type == 5) {
            if (nbKingdomsType5[_user] >= winnerCapByType[_type]) {
                jackpot5.winner = _user;
            }
        }
    }

    //
    //  This is the main function. It is called to buy a kingdom
    //
    function purchaseKingdom(string _key, string _title, uint _type,  uint _tier) public 
    payable 
    nonReentrant()
    checkMaxPrice()
    checkIsOpen()
    checkKingdomExistence(_key)
    {
        uint kingdomId = kingdomsKeys[_key];
        Kingdom storage kingdom = kingdoms[kingdomId];

        uint bet = (kingdom.returnPrice.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint jackpotCommission = kingdom.returnPrice.mul(JACKPOT_COMMISSION_RATIO).div(100);
        uint teamCommission = kingdom.returnPrice.mul(TEAM_COMMISSION_RATIO).div(100);

        uint price = kingdom.returnPrice.add(jackpotCommission).add(teamCommission).add(bet);
        require (msg.value >= price);

        uint minimumPrice = price.add(bet);

        if (teamCommission != 0) {
            recordCommissionEarned(teamCommission);
        }

        if (kingdom.returnPrice > 0) {
            nbKingdoms[kingdom.owner]--;
            
            if (kingdom.kingdomType == 1) {
                nbKingdomsType1[kingdom.owner]--;
            } else if (kingdom.kingdomType == 2) {
                nbKingdomsType2[kingdom.owner]--;
            } else if (kingdom.kingdomType == 3) {
                nbKingdomsType3[kingdom.owner]--;
            } else if (kingdom.kingdomType == 4) {
                nbKingdomsType4[kingdom.owner]--;
            } else if (kingdom.kingdomType == 5) {
                nbKingdomsType5[kingdom.owner]--;
            }
            
            compensateLatestMonarch(kingdom.lastTransaction, kingdom.returnPrice);
        }
        
        uint jackpotSplitted = jackpotCommission.mul(50).div(100);
        globalJackpot.balance = globalJackpot.balance.add(jackpotSplitted);

        kingdom.kingdomType = _type;
        kingdom.kingdomTier = _tier;
        kingdom.title = _title;
        kingdom.returnPrice = minimumPrice;
        kingdom.minimumPrice = calculatePrice(minimumPrice, 1);
        kingdom.owner = msg.sender;

        uint transactionId = kingdomTransactions.push(Transaction("", msg.sender, msg.value, 0, 0, 0)) - 1;
        kingdomTransactions[transactionId].tier = _tier;
        kingdomTransactions[transactionId].jackpotContribution = jackpotSplitted;
        kingdomTransactions[transactionId].kingdomKey = _key;
        
        kingdom.transactionCount++;
        kingdom.lastTransaction = transactionId;

        nbTransactions[msg.sender]++;
        nbKingdoms[msg.sender]++;
        
        if (_type == 1) {
            nbKingdomsType1[msg.sender]++;
            jackpot1.balance = jackpot1.balance.add(jackpotSplitted);
        } else if (_type == 2) {
            nbKingdomsType2[msg.sender]++;
            jackpot2.balance = jackpot2.balance.add(jackpotSplitted);
        } else if (_type == 3) {
            nbKingdomsType3[msg.sender]++;
            jackpot3.balance = jackpot3.balance.add(jackpotSplitted);
        } else if (_type == 4) {
            nbKingdomsType4[msg.sender]++;
            jackpot4.balance = jackpot4.balance.add(jackpotSplitted);
        } else if (_type == 5) {
            nbKingdomsType5[msg.sender]++;
            jackpot5.balance = jackpot5.balance.add(jackpotSplitted);
        }

        setNewWinner(msg.sender, _type, jackpotSplitted);
        LandPurchasedEvent(_key, msg.sender);
    }

    function calculatePrice(uint _returnPrice, uint _tier) internal pure returns (uint price) {
        uint jackpotComission = _returnPrice.mul(JACKPOT_COMMISSION_RATIO).div(100);
        uint teamComission = _returnPrice.mul(TEAM_COMMISSION_RATIO).div(100);
        uint bet = (_returnPrice.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint calculatePrice = _returnPrice.add(jackpotComission).add(teamComission).add(bet);
        return calculatePrice;
    }

    function upgradeKingdomTier(string _key, uint _tier) public payable  checkKingdomExistence(_key) onlyKingdomOwner(_key, msg.sender) {
        require(msg.value >= 0.05 ether);
        require(_tier > 0);
        kingdoms[kingdomsKeys[_key]].kingdomTier = _tier;
    }

    function upgradeKingdomType(string _key, uint _type) public payable  checkKingdomExistence(_key) onlyKingdomOwner(_key, msg.sender) {
        require(msg.value >= 0.05 ether);
        require(_type > 0);
        kingdoms[kingdomsKeys[_key]].kingdomType = _type;
    }

    //
    //  User can call this function to generate new kingdoms (within the limits of available land)
    //
    function createKingdom(string _key, string _title, uint _type, uint _tier) public payable {

        require(_type > 0);
        require(_tier > 0);

        uint bet = (STARTING_CLAIM_PRICE_WEI.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint minimumPrice = STARTING_CLAIM_PRICE_WEI.add(bet);

        require(msg.value >= minimumPrice);
        require(kingdomsCreated[_key] == false);
        require(remainingKingdoms > 0);

        remainingKingdoms--;

        uint returnPrice = minimumPrice.add(bet);
        uint nextMinimumPrice = calculatePrice(returnPrice, 1);

        uint kingdomId = kingdoms.push(Kingdom(_title, _key, _tier, _type, nextMinimumPrice, 0, 1, returnPrice, msg.sender)) - 1;
        kingdomsKeys[_key] = kingdomId;
        kingdomsCreated[_key] = true;

        uint transactionId = kingdomTransactions.push(Transaction(_key, msg.sender, msg.value, 0, 0, 0)) - 1;
        kingdomTransactions[transactionId].tier = _tier;
        kingdoms[kingdomId].lastTransaction = transactionId;
       
        nbTransactions[msg.sender]++;
        nbKingdoms[msg.sender]++;
        
        if (_type == 1) {
            nbKingdomsType1[msg.sender]++;
        } else if (_type == 2) {
            nbKingdomsType2[msg.sender]++;
        } else if (_type == 3) {
            nbKingdomsType3[msg.sender]++;
        } else if (_type == 4) {
            nbKingdomsType4[msg.sender]++;
        } else if (_type == 5) {
            nbKingdomsType5[msg.sender]++;
        }

        setNewWinner(msg.sender, _type, 0);
        winnerCapByType[_type]++;

        LandCreatedEvent(_key, msg.sender);
    }

    //
    //  Record fees payment 
    //
    function recordCommissionEarned(uint _commissionWei) internal {
        asyncSend(bookerAddress, _commissionWei);
    }

    //
    //  Send transaction to compensate the previous owner
    //
    function compensateLatestMonarch(uint lastTransaction, uint compensationWei) internal {
        address compensationAddress = kingdomTransactions[lastTransaction].compensationAddress;
        kingdomTransactions[lastTransaction].compensation = compensationWei;
        asyncSend(compensationAddress, compensationWei);
    }

    //
    //  This function may be useful to force withdraw if user never come back to get his money
    //
    function forceWithdrawPayments(address payee) public onlyOwner {
        uint256 payment = payments[payee];

        require(payment != 0);
        require(this.balance >= payment);

        totalPayments = totalPayments.sub(payment);
        payments[payee] = 0;

        assert(payee.send(payment));
    }

    //
    //  After time expiration, owner can call this function to activate the next round of the game
    //
    function activateNextRound() public onlyOwner() checkIsClosed() {

        endTime = now + 7 days;
        remainingKingdoms += 3;
        round++;

        if (globalJackpot.winner != address(0) && globalJackpot.balance > 0) {
            require(this.balance >= globalJackpot.balance);
            asyncSend(globalJackpot.winner, globalJackpot.balance);
            globalJackpot.winner = address(0);
            globalJackpot.balance = 0;
        }

        if (jackpot1.winner != address(0) && jackpot1.balance > 0) {
            require(this.balance >= jackpot1.balance);
            asyncSend(jackpot1.winner, jackpot1.balance);
            jackpot1.winner = address(0);
            jackpot1.balance = 0;
        }

        if (jackpot2.winner != address(0) && jackpot2.balance > 0) {
            require(this.balance >= jackpot2.balance);
            asyncSend(jackpot2.winner, jackpot2.balance);
            jackpot2.winner = address(0);
            jackpot2.balance = 0;
        }

        if (jackpot3.winner != address(0) && jackpot3.balance > 0) {
            require(this.balance >= jackpot3.balance);
            asyncSend(jackpot3.winner, jackpot3.balance);
            jackpot3.winner = address(0);
            jackpot3.balance = 0;
        }

        if (jackpot4.winner != address(0) && jackpot4.balance > 0) {
            require(this.balance >= jackpot4.balance);
            asyncSend(jackpot4.winner, jackpot4.balance);
            jackpot4.winner = address(0);
            jackpot4.balance = 0;
        }

        if (jackpot5.winner != address(0) && jackpot5.balance > 0) {
            require(this.balance >= jackpot5.balance);
            asyncSend(jackpot5.winner, jackpot5.balance);
            jackpot5.winner = address(0);
            jackpot5.balance = 0;
        }
    }

    // GETTER AND SETTER FUNCTIONS

    function setNewWinner(address _sender, uint _type, uint _jackpot) internal {
        if (globalJackpot.winner == address(0)) {
            globalJackpot.winner = _sender;
        } else {
            if (nbKingdoms[_sender] == nbKingdoms[globalJackpot.winner]) {
                if (nbTransactions[_sender] > nbTransactions[globalJackpot.winner]) {
                    globalJackpot.winner = _sender;
                }
            } else if (nbKingdoms[_sender] > nbKingdoms[globalJackpot.winner]) {
                globalJackpot.winner = _sender;
            }
        }

        setTypedJackpotWinner(_sender, _type, _jackpot);
    }

    function isFinalized() public view returns (bool) {
        return now >= endTime;
    }

    function getKingdomsNumberByAddress(address addr) public view returns (uint nb) {
        return nbKingdoms[addr];
    }

    function getCurrentOwner(string key) public view returns (address addr) {
        return kingdoms[kingdomsKeys[key]].owner;
    }

    function getKingdomCount() public view returns (uint kingdomCount) {
        return kingdoms.length;
    }

    function getKingdomIndex(string key) public view returns (uint index) {
        return kingdomsKeys[key];
    }

    function getKingdomInformations(string kingdomKey) public view returns (string title, uint minimumPrice, uint lastTransaction, uint transactionCount, address currentOwner) {
        uint kingdomId = kingdomsKeys[kingdomKey];
        Kingdom storage kingdom = kingdoms[kingdomId];
        return (kingdom.title, kingdom.minimumPrice, kingdom.lastTransaction, kingdom.transactionCount, kingdom.owner);
    }

}
