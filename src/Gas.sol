// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract Constants {
    uint104 public tradeFlag = 1;
    uint8 public basicFlag = 0;
    uint8 public dividendFlag = 1;
}

contract GasContract is Ownable, Constants {
    uint256 public immutable totalSupply = 0; // cannot be updated
    uint256 public paymentCounter = 0;
    mapping(address => uint256) public balances;
    // address public contractOwner;
    uint256 public tradePercent = 12;
    uint8 public tradeMode = 0; //changed to uint8
    mapping(address => Payment[]) public payments;
    mapping(address => uint8) public whitelist; // store the tier of the user so uint8 is enough
    address[5] public administrators;

    bool public isReady = false;
    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }
    PaymentType constant defaultPayment = PaymentType.Unknown;

    History[] public paymentHistory; // when a payment was updated

    struct Payment {
        // from low to high
        PaymentType paymentType;
        bool adminUpdated; // 1 byte
        bytes8 recipientName; // max 8 characters
        address admin; // administrators address
        address recipient;
        uint32 paymentID; // may not exceed 4 billion
        uint256 amount;
    }

    struct History {
        uint256 lastUpdate;
        address updatedBy;
        uint256 blockNumber;
    }
    // uint8 wasLastOdd = 1; // 0 or 1
    //NEVER USED
    // mapping(address => uint256) public isOddWhitelistUser;

    struct ImportantStruct {
        //ordered by size
        bool paymentStatus;
        uint16 valueA; // max 3 digits
        uint16 valueB; // max 3 digits
        address sender;
        uint256 amount;
        uint256 bigValue;
    }
    mapping(address => ImportantStruct) public whiteListStruct;

    event AddedToWhitelist(address userAddress, uint256 tier);

    error CallerNotAdmin();

    error invalidTierLevel();

    function onlyAdminOrOwner() private view returns (bool adminOrOwner) {
        if (!(checkForAdmin(_msgSender()) || _msgSender() == owner())) {
            revert CallerNotAdmin();
        }
        adminOrOwner = true;
    }

    // modifier onlyAdminOrOwner() {
    //     address senderOfTx = msg.sender;
    //     if (checkForAdmin(senderOfTx)) {
    //         require(
    //             checkForAdmin(senderOfTx),
    //             "Gas Contract Only Admin Check-  Caller not admin"
    //         );
    //         _;
    //     } else if (senderOfTx == owner()) {
    //         _;
    //     } else {
    //         revert(
    //             "Error in Gas contract - onlyAdminOrOwner modifier : revert happened because the originator of the transaction was not the admin, and furthermore he wasn't the owner of the contract, so he cannot run this function"
    //         );
    //     }
    // }

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

    event supplyChanged(address indexed, uint256 indexed);
    event Transfer(address recipient, uint256 amount);
    event PaymentUpdated(
        address admin,
        uint256 ID,
        uint256 amount,
        string recipient
    );
    event WhiteListTransfer(address indexed);
    //============OPTIMIZATION NOTES=========
    // - sstore and sload to directly read/write storage
    //-  mload and mstore to directly access memory
    constructor(address[] memory _admins, uint256 _totalSupply) Ownable() {
        //The contractOwner variable is unnecessary because
        //ownership is managed by the Ownable contract, and _owner is stored at slot 0.
        //As a result, the contractOwner
        //storage variable has been deleted. Additionally, since the address occupies
        //20 bytes and we do not want the remaining 12 bytes to be occupied by the
        //tradeFlag uint in the Constants contract,
        //the tradeFlag has been changed to a uint104.

        // contractOwner = msg.sender;
        totalSupply = _totalSupply;

        //ADMINISTRATORS HAS A FIXED SIZE OF 5
        assembly {
            // STORAGE  [administrators.slot  :         0x05                 ]
            //                index             fixedLength of administrators
            let administratorsSlot := administrators.slot

            // for (uint256 ii = 0; ii < administrators.length; ii++) {
            //_owner is at slot 0
            let ownerAddress := sload(0)
            for {
                let i := 0
            } lt(i, 5) {
                i := add(i, 1)
            } {
                // Calculate the storage slot for the current administrator

                let slot := add(administratorsSlot, i)
                //THE DATA IS COMING FROM MEMORY THEN:
                //       MEMORY   [ _admins + i * 32bytes  :  adminAddress   ]
                //                     slot_index:            data(32bytes)
                let adminAddress := mload(add(_admins, mul(add(i, 1), 0x20)))
                //=======-X: administrators.slot : administrators[0]-=====

                //sstore(X, mload(frptr) = 0x123)
                //sstore(X+1, mload(frptr+0x20) = 0x456)
                //sstore(X+2, mload(frptr+0x20+0x20) =0x789)
                //sstore(X+3, mload(frptr+0x20+0x20+0x20) = 0x876)
                //sstore(X+4, mload(frptr+0x20+0x20+0x20+0x20)0x768)

                // STORAGE [administrators+i: adminAddress(32bytes)]
                // administrators[ii] = _admins[ii]
                sstore(slot, adminAddress)

                // if (_admins[ii] == contractOwner) {
                //   balances[contractOwner] = totalSupply;
                if eq(adminAddress, ownerAddress) {
                    //FULL USAGE OF SCRATCH SPACE IN MEMORY, IT DOES NOT OVERWRITE MEMORY POINTER AT 0X40
                    mstore(0x00, adminAddress)
                    mstore(0x20, balances.slot)
                    //The value corresponding to a mapping key k is located at keccak256(h(k) . p)
                    //SEE: https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html
                    let balanceSlot := keccak256(0, 0x40)
                    sstore(balanceSlot, _totalSupply)
                }

                //else {
                //  balances[_admins[ii]] = 0;
                if iszero(eq(adminAddress, ownerAddress)) {
                    //FULL USAGE OF SCRATCH SPACE IN MEMORY, IT DOES NOT OVERWRITE MEMORY POINTER AT 0X40
                    mstore(0x00, adminAddress)
                    mstore(0x20, balances.slot)
                    //The value corresponding to a mapping key k is located at keccak256(h(k) . p)
                    //SEE: https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html
                    let balanceSlot := keccak256(0x00, 0x40)
                    sstore(balanceSlot, 0)
                }
            }
        }

        // for (uint256 ii = 0; ii < administrators.length; ii++) {
        //     if (_admins[ii] != address(0)) {
        //         administrators[ii] = _admins[ii];
        //         if (_admins[ii] == contractOwner) {
        //             balances[contractOwner] = totalSupply;
        //         } else {
        //             balances[_admins[ii]] = 0;
        //         }

        //         //THIS IF IS UNNECESSARY AS THE SUPPLY IS IMMUTABLE
        //         if (_admins[ii] == contractOwner) {
        //             //EVENT supplyChanged is ambigoud as it is nver called in tests
        //             // and totalSupply is immutable
        //             emit supplyChanged(_admins[ii], totalSupply);
        //         } else if (_admins[ii] != contractOwner) {
        //             emit supplyChanged(_admins[ii], 0);
        //         }
        //     }
        // }
    }

    function checkForAdmin(address _user) public view returns (bool admin_) {
        admin_ = false;
        assembly {
            let administratorsSlot := administrators.slot
            for {
                let i := 0
            } lt(i, 5) {
                i := add(i, 1)
            } {
                let slot := add(administratorsSlot, i)
                let adminAddress := sload(slot)
                if eq(adminAddress, _user) {
                    admin_ := true
                }
            }
        }
    }

    function balanceOf(address _user) public view returns (uint256 balance_) {
        return balances[_user]; //directly return the balance
    }

    function getTradingMode() public view returns (bool mode_) {
        bool mode = false;
        if (tradeFlag == 1 || dividendFlag == 1) {
            mode = true;
        } else {
            mode = false;
        }
        return mode;
    }

    function addHistory(
        address _updateAddress,
        bool _tradeMode
    ) public returns (bool status_, bool tradeMode_) {
        History memory history;
        history.blockNumber = block.number;
        history.lastUpdate = block.timestamp;
        history.updatedBy = _updateAddress;
        paymentHistory.push(history);
        bool[] memory status = new bool[](tradePercent);
        for (uint256 i = 0; i < tradePercent; i++) {
            status[i] = true;
        }
        return ((status[0] == true), _tradeMode);
    }

    function transfer(
        address _recipient,
        uint256 _amount,
        string calldata _name
    ) public returns (bool status_) {
        address senderOfTx = msg.sender;
        require(balances[senderOfTx] >= _amount, "Insufficient balance");

        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;

        emit Transfer(_recipient, _amount);

        Payment memory payment;
        payment.recipient = _recipient;
        payment.amount = _amount;
        payment.recipientName = bytes8(bytes(_name));

        return true;
    }

    function updatePayment(
        address _user,
        uint256 _ID,
        uint256 _amount,
        PaymentType _type
    ) public {
        onlyAdminOrOwner();
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

        for (uint256 ii = 0; ii < payments[_user].length; ii++) {
            if (payments[_user][ii].paymentID == _ID) {
                payments[_user][ii].adminUpdated = true;
                payments[_user][ii].admin = _user;
                payments[_user][ii].paymentType = _type;
                payments[_user][ii].amount = _amount;
                bool tradingMode = getTradingMode();
                addHistory(_user, tradingMode);
                emit PaymentUpdated(
                    senderOfTx,
                    _ID,
                    _amount,
                    string(abi.encodePacked(payments[_user][ii].recipientName)) //changed to bytes8
                );
            }
        }
    }

    function addToWhitelist(address _userAddrs, uint256 _tier) public {
        uint8 __tier;
        //pre condition 1
        onlyAdminOrOwner();
        //pre condition 2
        assembly ("memory-safe") {
            if gt(_tier, 244) {
                revert(0, 0)
            }

            __tier := _tier
        }
        //======DONE WITH PRE-CONDITIONS=========

        // Note:
        //1. Original code never ends up storing the _tier
        //2. event is emmited with the __tier and it is independent
        // of the actualTier sotred in the whitelist
        //---EVENT EMISSION is more efficient if done first
        // is it more efficient if done in Yul?
        emit AddedToWhitelist(_userAddrs, _tier);
        //=============PROGRAM===================
        assembly ("memory-safe") {
            mstore(0x00, _userAddrs)
            mstore(0x20, whitelist.slot)
            let slot := keccak256(0x00, 0x40)

            let actualTier
            switch _tier
            // } else if (_tier == 1) {
            //     whitelist[_userAddrs] -= uint8(_tier);
            //     whitelist[_userAddrs] = 1;

            case 1 {
                actualTier := 1
            }
            // } else if (_tier > 0 && _tier < 3) {
            //     whitelist[_userAddrs] -= uint8(_tier);
            //     whitelist[_userAddrs] = 2;
            case 2 {
                actualTier := 2
            }
            case 3 {
                actualTier := 2
            }
            // if (_tier > 3) {   3<_tier <= 244
            //     whitelist[_userAddrs] -= uint8(_tier);
            //     whitelist[_userAddrs] = 3;
            default {
                actualTier := 3
            }

            sstore(slot, actualTier)
        }

        //THIS IS NEVER USED IN TESTS
        // uint256 wasLastAddedOdd = wasLastOdd;
        // if (wasLastAddedOdd == 1) {
        //     wasLastOdd = 0;
        //     isOddWhitelistUser[_userAddrs] = wasLastAddedOdd;
        // } else if (wasLastAddedOdd == 0) {
        //     wasLastOdd = 1;
        //     isOddWhitelistUser[_userAddrs] = wasLastAddedOdd;
        // } else {
        //     revert("Contract hacked, imposible, call help");
        // }
    }

    function whiteTransfer(
        address _recipient,
        uint256 _amount
    ) public checkIfWhiteListed(msg.sender) {
        address senderOfTx = msg.sender;
        whiteListStruct[senderOfTx] = ImportantStruct(
            true,
            0,
            0,
            msg.sender,
            _amount,
            0
        );
        require(
            balances[senderOfTx] >= _amount,
            "Gas Contract - whiteTransfers function - Sender has insufficient Balance"
        );
        require(
            _amount > 3,
            "Gas Contract - whiteTransfers function - amount to send have to be bigger than 3"
        );
        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;
        balances[senderOfTx] += whitelist[senderOfTx];
        balances[_recipient] -= whitelist[senderOfTx];

        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(
        address sender
    ) public view returns (bool, uint256) {
        return (
            whiteListStruct[sender].paymentStatus,
            whiteListStruct[sender].amount
        );
    }

    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
    }
}
