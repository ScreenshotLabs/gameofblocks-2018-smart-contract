pragma solidity ^0.4.15;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/payment/PullPayment.sol';
import 'zeppelin-solidity/contracts/lifecycle/Destructible.sol';
import 'zeppelin-solidity/contracts/ReentrancyGuard.sol';

contract Map is PullPayment, Destructible, ReentrancyGuard {

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

    address public winner = address(0);
    uint public endTime;
    uint public jackpot = 0;
    address public bookerAddress;
    Kingdom[] public kingdoms;
    Transaction[] public kingdomTransactions;
    uint public round;
    
    uint constant public GLOBAL_COMPENSATION_RATIO = 20; 
    uint constant public STARTING_CLAIM_PRICE_WEI = 0.00133 ether;

    uint constant MAXIMUM_CLAIM_PRICE_WEI = 500 ether;
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
    
    modifier checkKingdomCost(uint kingdomIndex) {
        require (msg.value >= kingdoms[kingdomIndex].currentPrice);
        _;
    }

    modifier checkMaxPrice() {
        require (msg.value <= MAXIMUM_CLAIM_PRICE_WEI);
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
        endTime = now + 7 days;
        remainingKingdoms = _remainingKingdoms;
    }

    function () { }

    //
    //  This is the main function. It is called to buy a kingdom
    //
    function purchaseKingdom(string kingdomKey, string title) public 
    payable 
    nonReentrant()
    checkMaxPrice()
    checkIsOpen()
    checkKingdomExistence(kingdomKey)
    checkKingdomCost(kingdomsKeys[kingdomKey])
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
        nbKingdoms[msg.sender]++;

        setNewWinner(msg.sender);
        LandPurchasedEvent(kingdomKey, msg.sender);
    }

    //
    //  User can call this function to generate new kingdoms (within the limits of available land)
    //
    function createKingdom(address sender, string _key, string _title) public payable {

        require(msg.value >= STARTING_CLAIM_PRICE_WEI);
        require(sender != address(0));
        require(kingdomsCreated[_key] == false);
        require(remainingKingdoms > 0);

        remainingKingdoms--;

        uint nextPrice = msg.value + (msg.value * GLOBAL_JACKPOT_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_TEAM_COMMISSION_RATIO / 100) + (msg.value * GLOBAL_COMPENSATION_RATIO / 100);
        uint kingdomId = kingdoms.push(Kingdom(_title, _key, nextPrice, 0, 1, sender)) - 1;
        kingdomsKeys[_key] = kingdomId;
        kingdomsCreated[_key] = true;
        uint transactionId = kingdomTransactions.push(Transaction(_key, sender, msg.value, 0, 0, now)) - 1;
        kingdoms[kingdomId].lastTransaction = transactionId;
       
        nbTransactions[sender]++;
        nbKingdoms[sender]++;

        setNewWinner(sender);
        LandCreatedEvent(_key, sender);
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
    function compensateLatestMonarch(string kingdomKey, uint compensationWei) internal {
        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        address compensationAddress = kingdomTransactions[kingdom.lastTransaction].compensationAddress;
        kingdomTransactions[kingdom.lastTransaction].compensation = compensationWei;
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
    function sendJackpot() public onlyOwner() {
        require(kingdoms.length > 0);
        uint payment = jackpot;

        require(payment != 0);
        require(this.balance >= payment);
        require(winner != address(0));

        jackpot = 0;
        endTime = now + 7 days;
        remainingKingdoms += 3;
        round++;

        assert(winner.send(payment));
    }

    // GETTER AND SETTER FUNCTIONS

    function setNewWinner(address sender) internal {
        if (winner == address(0)) {
            winner = sender;
        } else {
            if (nbKingdoms[sender] == nbKingdoms[winner]) {
                if (nbTransactions[sender] > nbTransactions[winner]) {
                    winner = sender;
                }
            } else if (nbKingdoms[sender] > nbKingdoms[winner]) {
                winner = sender;
            }
        }
    }

    function isFinalized() public view returns (bool) {
        return now >= endTime;
    }

    function getKingdomsNumberByAddress(address addr) public view returns (uint nb) {
        return nbKingdoms[addr];
    }

    function getCurrentOwner(uint kingdomId) public view returns (address addr) {
        return kingdoms[kingdomId].currentOwner;
    }

    function getKingdomCount() public view returns (uint kingdomCount) {
        return kingdoms.length;
    }

    function getKingdomInformations(string kingdomKey) public view returns (string title, uint currentPrice, uint lastTransaction, uint transactionCount, address currentOwner) {
        Kingdom storage kingdom = kingdoms[kingdomsKeys[kingdomKey]];
        return (kingdom.title, kingdom.currentPrice, kingdom.lastTransaction, kingdom.transactionCount, kingdom.currentOwner);
    }

}
