// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0; 

import "./Ownable.sol";

/**
 * Turn these into true constants to save gas on reading them from storage.
 * The tests do not appear to write to them, so it's safe to make them `constant`.
 */
contract Constants {
    uint256 public constant tradeFlag = 1;
    uint256 public constant basicFlag = 0;
    uint256 public constant dividendFlag = 1;
}

contract GasContract is Ownable, Constants {
    // Use immutable for values set once in constructor and never changed.
    uint256 public immutable totalSupply; 
    uint256 public paymentCounter;
    
    // Mappings default to 0, so we don't need to set them to 0 explicitly.
    mapping(address => uint256) public balances;

    // Also safe to make tradePercent a constant if tests never set it.
    uint256 public constant tradePercent = 12;

    address public immutable contractOwner;
    uint256 public tradeMode = 0; 

    // Store all Payments for each user.
    mapping(address => Payment[]) public payments;
    mapping(address => uint256) public whitelist;

    // Keep a fixed-size array of 5 administrators.
    address[5] public administrators;

    bool public isReady = false;

    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }

    // Payment struct
    struct Payment {
        PaymentType paymentType;
        uint256 paymentID;
        bool adminUpdated;
        string recipientName; // max 8 characters
        address recipient;
        address admin; 
        uint256 amount;
    }

    // Keep track of updates in a History array.
    struct History {
        uint256 lastUpdate;
        address updatedBy;
        uint256 blockNumber;
    }

    // We keep the entire payment history here.
    History[] public paymentHistory; 

    // Toggling odd/even for whitelisted users
    uint256 wasLastOdd = 1;
    mapping(address => uint256) public isOddWhitelistUser;

    // Extra struct used for whiteListTransfer
    struct ImportantStruct {
        uint256 amount;
        uint256 valueA; 
        uint256 bigValue;
        uint256 valueB; 
        bool paymentStatus;
        address sender;
    }
    mapping(address => ImportantStruct) public whiteListStruct;

    // Events
    event AddedToWhitelist(address userAddress, uint256 tier);
    event supplyChanged(address indexed, uint256 indexed);
    event Transfer(address recipient, uint256 amount);
    event PaymentUpdated(address admin, uint256 ID, uint256 amount, string recipient);
    event WhiteListTransfer(address indexed);

    modifier onlyAdminOrOwner() {
        address senderOfTx = msg.sender;
        if (checkForAdmin(senderOfTx)) {
            // fine
            _;
        } else if (senderOfTx == contractOwner) {
            // fine
            _;
        } else {
            revert(
                "Error in Gas contract - onlyAdminOrOwner modifier : revert happened because the originator of the transaction was not the admin, and furthermore he wasn't the owner of the contract, so he cannot run this function"
            );
        }
    }

    modifier checkIfWhiteListed(address sender) {
        address senderOfTx = msg.sender;
        require(
            senderOfTx == sender,
            "Gas Contract CheckIfWhiteListed modifier : revert happened because the originator of the transaction was not the sender"
        );
        uint256 usersTier = whitelist[senderOfTx];
        require(
            usersTier > 0,
            "Gas Contract CheckIfWhiteListed modifier : revert happened because the user is not whitelisted"
        );
        require(
            usersTier < 4,
            "Gas Contract CheckIfWhiteListed modifier : revert happened because the user's tier is incorrect, it cannot be over 4 as the only tier we have are: 1, 2, 3; therfore 4 is an invalid tier for the whitlist of this contract. make sure whitlist tiers were set correctly"
        );
        _;
    }

    constructor(address[] memory _admins, uint256 _totalSupply) {
        contractOwner = msg.sender;
        totalSupply = _totalSupply;

        // Give the owner the entire totalSupply upfront
        balances[contractOwner] = _totalSupply;

        // Set the administrators array and emit events
        for (uint256 i = 0; i < administrators.length; i++) {
            administrators[i] = _admins[i];
            if (_admins[i] == contractOwner) {
                emit supplyChanged(_admins[i], _totalSupply);
            } else {
                emit supplyChanged(_admins[i], 0);
            }
        }
    }

    function getPaymentHistory() public payable returns (History[] memory) {
        return paymentHistory;
    }

    function checkForAdmin(address _user) public view returns (bool) {
        // For a small fixed array of 5, a simple loop is fine.
        for (uint256 i = 0; i < administrators.length; i++) {
            if (administrators[i] == _user) {
                return true;
            }
        }
        return false;
    }

    function balanceOf(address _user) public view returns (uint256) {
        return balances[_user];
    }

    // This must remain a function so that testCheckForAdmin() works
    function getTradingMode() public view returns (bool) {
        return (tradeFlag == 1 || dividendFlag == 1);
    }

    /**
     * Instead of building a bool[] of length tradePercent and looping,
     * we can just return (true, _tradeMode).
     */
    function addHistory(address _updateAddress, bool _tradeMode)
        public
        returns (bool status_, bool tradeMode_)
    {
        History memory history;
        history.blockNumber = block.number;
        history.lastUpdate = block.timestamp;
        history.updatedBy = _updateAddress;
        paymentHistory.push(history);

        // Return true for status_ instead of looping
        return (true, _tradeMode);
    }

    function getPayments(address _user)
        public
        view
        returns (Payment[] memory)
    {
        require(
            _user != address(0),
            "Gas Contract - getPayments function - User must have a valid non zero address"
        );
        return payments[_user];
    }

    /**
     * Same logic, but skip the loop for the status array. We only need to return true.
     */
    function transfer(
        address _recipient,
        uint256 _amount,
        string calldata _name
    ) public returns (bool) {
        address senderOfTx = msg.sender;
        require(
            balances[senderOfTx] >= _amount,
            "Gas Contract - Transfer function - Sender has insufficient Balance"
        );
        require(
            bytes(_name).length < 9,
            "Gas Contract - Transfer function -  The recipient name is too long, there is a max length of 8 characters"
        );

        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;

        emit Transfer(_recipient, _amount);

        paymentCounter++;
        Payment memory payment;
        payment.admin = address(0);
        payment.adminUpdated = false;
        payment.paymentType = PaymentType.BasicPayment;
        payment.recipient = _recipient;
        payment.amount = _amount;
        payment.recipientName = _name;
        payment.paymentID = paymentCounter;
        payments[senderOfTx].push(payment);

        return true;
    }

    function updatePayment(
        address _user,
        uint256 _ID,
        uint256 _amount,
        PaymentType _type
    ) public onlyAdminOrOwner {
        require(
            _ID > 0,
            "Gas Contract - Update Payment function - ID must be greater than 0"
        );
        require(
            _amount > 0,
            "Gas Contract - Update Payment function - Amount must be greater than 0"
        );
        require(
            _user != address(0),
            "Gas Contract - Update Payment function - Administrator must have a valid non zero address"
        );

        address senderOfTx = msg.sender;
        Payment[] storage userPayments = payments[_user];
        uint256 length = userPayments.length;

        for (uint256 i = 0; i < length; i++) {
            if (userPayments[i].paymentID == _ID) {
                userPayments[i].adminUpdated = true;
                userPayments[i].admin = _user;
                userPayments[i].paymentType = _type;
                userPayments[i].amount = _amount;

                bool tradingMode = getTradingMode();
                addHistory(_user, tradingMode);

                emit PaymentUpdated(
                    senderOfTx,
                    _ID,
                    _amount,
                    userPayments[i].recipientName
                );
            }
        }
    }

    /**
     * Simplified logic:
     *   - require tier < 255
     *   - finalTier = min(tier, 3)
     *   - store finalTier in whitelist
     *   - toggle wasLastOdd
     */
    function addToWhitelist(address _userAddrs, uint256 _tier)
        public
        onlyAdminOrOwner
    {
        require(
            _tier < 255,
            "Gas Contract - addToWhitelist function -  tier level should not be greater than 255"
        );

        // final tier = 1,2,3 if input is >3
        uint256 finalTier = _tier > 3 ? 3 : _tier;
        whitelist[_userAddrs] = finalTier;

        uint256 oldVal = wasLastOdd;
        // toggle wasLastOdd between 0 and 1
        wasLastOdd = 1 - wasLastOdd;
        // record oldVal as the "odd" flag for this user
        isOddWhitelistUser[_userAddrs] = oldVal;

        emit AddedToWhitelist(_userAddrs, _tier);
    }

    /**
     * WhiteTransfer must keep the same revert messages & the same final logic.
     */
    function whiteTransfer(
        address _recipient,
        uint256 _amount
    ) public checkIfWhiteListed(msg.sender) {
        address senderOfTx = msg.sender;
        // store data in ImportantStruct
        whiteListStruct[senderOfTx] = ImportantStruct(
            _amount,
            0,
            0,
            0,
            true,
            senderOfTx
        );

        require(
            balances[senderOfTx] >= _amount,
            "Gas Contract - whiteTransfers function - Sender has insufficient Balance"
        );
        require(
            _amount > 3,
            "Gas Contract - whiteTransfers function - amount to send have to be bigger than 3"
        );

        // Move the amount, then apply the tier 'adjustment'
        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;

        // Add and subtract the tier from both sides
        uint256 tier = whitelist[senderOfTx];
        balances[senderOfTx] += tier;
        balances[_recipient] -= tier;

        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(address sender)
        public
        view
        returns (bool, uint256)
    {
        return (
            whiteListStruct[sender].paymentStatus,
            whiteListStruct[sender].amount
        );
    }

    // The tests do not actually send Ether, but we keep the fallback/receive to avoid breaking anything.
    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
    }
}
