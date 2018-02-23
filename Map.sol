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
        // uint jackpotContribution;
        // uint date;
    }

    struct Kingdom {
        string title;
        string key;
        uint8 kingdomTier;
        uint8 kingdomType;
        uint currentPrice;
        uint lastTransaction;
        uint transactionCount;
        uint lastPrice;
        address owner;
    }

    struct Jackpot {
        address owner;
        uint balance;
        uint endTime;
        uint nbKingdoms;
    }

    uint remainingKingdoms;

    mapping(string => uint) kingdomsKeys;
    mapping(string => bool) kingdomsCreated;
    mapping(address => uint) nbKingdoms;
    mapping(address => uint) public nbTransactions;
    // mapping(uint => address) public localJackpotsWinners;
    // mapping(uint => address) public localJackpotsMaxKingdoms;

    Jackpot[] public jackpots;
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
        globalJackpot.endTime = now + 7 days;
        remainingKingdoms = _remainingKingdoms;

        jackpots.push(Jackpot(address(0), 0, now + 7 days, 0));
        jackpots.push(Jackpot(address(0), 0, now + 7 days, 0));
        jackpots.push(Jackpot(address(0), 0, now + 7 days, 0));
        jackpots.push(Jackpot(address(0), 0, now + 7 days, 0));

        globalJackpot = Jackpot(address(0), 0, now + 7 days, 0);
    }

    function () { }

    //
    //  This is the main function. It is called to buy a kingdom
    //
    function purchaseKingdom(string _key, string _title, uint8 _type,  uint8 _tier) public 
    payable 
    nonReentrant()
    checkMaxPrice()
    checkIsOpen()
    checkKingdomExistence(_key)
    {
        uint kingdomId = kingdomsKeys[_key];
        Kingdom storage kingdom = kingdoms[kingdomId];

        uint bet = (kingdom.lastPrice.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint jackpotCommission = kingdom.lastPrice.mul(JACKPOT_COMMISSION_RATIO).div(100);
        uint teamCommission = kingdom.lastPrice.mul(TEAM_COMMISSION_RATIO).div(100);

        uint price = kingdom.lastPrice.add(jackpotCommission).add(teamCommission).add(bet);
        require (msg.value >= price);

        uint currentPrice = price.add(bet);

        if (teamCommission != 0) {
            recordCommissionEarned(teamCommission);
        }

        if (kingdom.lastPrice > 0) {
            compensateLatestMonarch(kingdom.lastTransaction, kingdom.lastPrice);
        }
        
        globalJackpot.balance = globalJackpot.balance.add(jackpotCommission.mul(90).div(100));

        // uint localJackpotCommission = jackpotCommission.mul(0.1);
        // if (_type == 1) {
        //     localJackpot1 = localJackpot1 + localJackpotCommission;
        // } else if (_type == 2) {
        //     localJackpot2 = localJackpot2 + localJackpotCommission;
        // } else if (_type == 3) {
        //     localJackpot3 = localJackpot3 + localJackpotCommission;
        // } else {
        //     localJackpot4 = localJackpot4 + localJackpotCommission;
        // }

        kingdom.kingdomType = _type;
        kingdom.kingdomTier = _tier;
        kingdom.title = _title;
        kingdom.lastPrice = currentPrice;
        kingdom.currentPrice = calculatePrice(currentPrice, _tier);
        kingdom.owner = msg.sender;
        // kingdomOwner[kingdomId] = msg.sender;

        uint transactionId = kingdomTransactions.push(Transaction("", msg.sender, msg.value, 0, _tier)) - 1;
        kingdomTransactions[transactionId].kingdomKey = _key;
        
        kingdom.transactionCount++;
        kingdom.lastTransaction = transactionId;

        nbTransactions[msg.sender]++;
        nbKingdoms[msg.sender]++;

        setNewWinner(msg.sender);
        LandPurchasedEvent(_key, msg.sender);
    }

    function calculatePrice(uint _lastPrice, uint _tier) internal pure returns (uint price) {
        uint jackpotComission = _lastPrice.mul(JACKPOT_COMMISSION_RATIO).div(100);
        uint teamComission = _lastPrice.mul(TEAM_COMMISSION_RATIO).div(100);
        uint bet = (_lastPrice.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint calculatePrice = _lastPrice.add(jackpotComission).add(teamComission).add(bet);
        return calculatePrice;
    }

    function upgradeKingdomTier(string _key, uint8 _tier) public payable  checkKingdomExistence(_key) onlyKingdomOwner(_key, msg.sender) {
        require(msg.value >= 0.05 ether);
        require(_tier > 0);
        kingdoms[kingdomsKeys[_key]].kingdomTier = _tier;
    }

    function upgradeKingdomType(string _key, uint8 _type) public payable  checkKingdomExistence(_key) onlyKingdomOwner(_key, msg.sender) {
        require(msg.value >= 0.05 ether);
        require(_type > 0);
        kingdoms[kingdomsKeys[_key]].kingdomType = _type;
    }

    //
    //  User can call this function to generate new kingdoms (within the limits of available land)
    //
    function createKingdom(string _key, string _title, uint8 _type, uint8 _tier) public payable {

        require(_type > 0);
        require(_tier > 0);

        uint bet = (STARTING_CLAIM_PRICE_WEI.mul(KINGDOM_MULTIPLIER).div(100)).mul(_tier);
        uint minimumPrice = STARTING_CLAIM_PRICE_WEI.add(bet);

        require(msg.value >= minimumPrice);
        require(kingdomsCreated[_key] == false);
        require(remainingKingdoms > 0);

        remainingKingdoms--;

        uint price = minimumPrice.add(bet);
        uint nextBuyingPrice = calculatePrice(price, _tier);

        uint kingdomId = kingdoms.push(Kingdom(_title, _key, _tier, _type, nextBuyingPrice, 0, 1, price, msg.sender)) - 1;
        // kingdomOwner[kingdomId] = msg.sender;
        
        kingdomsKeys[_key] = kingdomId;
        kingdomsCreated[_key] = true;

        uint transactionId = kingdomTransactions.push(Transaction(_key, msg.sender, msg.value, 0, _tier)) - 1;
        kingdoms[kingdomId].lastTransaction = transactionId;
       
        nbTransactions[msg.sender]++;
        nbKingdoms[msg.sender]++;

        setNewWinner(msg.sender);
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
    function sendGlobalJackpot() public onlyOwner() {
        require(kingdoms.length > 0);
        uint payment = globalJackpot.balance;

        require(payment != 0);
        require(this.balance >= payment);
        require(globalJackpot.owner != address(0));

        globalJackpot.balance = 0;
        globalJackpot.endTime = now + 7 days;
        remainingKingdoms += 3;
        round++;

        asyncSend(globalJackpot.owner, payment);
    }

    // GETTER AND SETTER FUNCTIONS

    function setNewWinner(address sender) internal {
        if (globalJackpot.owner == address(0)) {
            globalJackpot.owner = sender;
        } else {
            if (nbKingdoms[sender] == nbKingdoms[globalJackpot.owner]) {
                if (nbTransactions[sender] > nbTransactions[globalJackpot.owner]) {
                    globalJackpot.owner = sender;
                }
            } else if (nbKingdoms[sender] > nbKingdoms[globalJackpot.owner]) {
                globalJackpot.owner = sender;
            }
        }
    }

    function isFinalized() public view returns (bool) {
        return now >= globalJackpot.endTime;
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

    function getKingdomInformations(string kingdomKey) public view returns (string title, uint currentPrice, uint lastTransaction, uint transactionCount, address currentOwner) {
        uint kingdomId = kingdomsKeys[kingdomKey];
        Kingdom storage kingdom = kingdoms[kingdomId];
        return (kingdom.title, kingdom.currentPrice, kingdom.lastTransaction, kingdom.transactionCount, kingdom.owner);
    }

}
