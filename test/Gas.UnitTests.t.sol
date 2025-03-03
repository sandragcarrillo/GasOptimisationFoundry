// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Gas.sol";

contract GasTest is Test {
    GasContract public gas;
    uint256 public totalSupply = 1000000000;
    address owner = address(0x1234);
    address addr1 = address(0x5678);
    address addr2 = address(0x9101);
    address addr3 = address(0x1213);

    address[] admins = [
        address(0x1),
        address(0x2),
        address(0x3),
        address(0x4),
        owner
    ];

    function get_random_address(uint256 offset) internal returns (address) {
        uint time_now = vm.unixTime();
        return (vm.addr(time_now + offset));
    }

    function setUp() public {
        for (uint8 ii = 0; ii < 4; ii++) {
            admins[ii] = get_random_address(ii);
        }

        vm.startPrank(owner);
        gas = new GasContract(admins);
        vm.stopPrank();
    }
    // OPTIMIZED _init_
    function test_admins() public view {
        for (uint8 i = 0; i < admins.length; ++i) {
            assertEq(admins[i], gas.administrators(i));
        }
    }
    // OPTIMIZED whitelist
    function test_onlyOwner(address _userAddrs, uint256 _tier) public {
        vm.assume(_userAddrs != address(gas));
        _tier = bound(_tier, 1, 244);
        vm.expectRevert();
        gas.addToWhitelist(_userAddrs, _tier);
    }
    // OPTIMIZED whitelist
    function test_tiers(address _userAddrs, uint256 _tier) public {
        vm.assume(_userAddrs != address(gas));
        _tier = bound(_tier, 1, 244);
        vm.prank(owner);
        gas.addToWhitelist(_userAddrs, _tier);
    }

    //OPTIMIZED WHITELIST

    // Expect Event -->
    event AddedToWhitelist(address userAddress, uint256 tier);
    function test_whitelistEvents(address _userAddrs, uint256 _tier) public {
        vm.startPrank(owner);
        vm.assume(_userAddrs != address(gas));
        _tier = bound(_tier, 1, 244);
        vm.expectEmit(true, true, false, true);
        emit AddedToWhitelist(_userAddrs, _tier);
        gas.addToWhitelist(_userAddrs, _tier);
        vm.stopPrank();
    }

    //----------------------------------------------------//
    //------------- Test whitelist Transfers -------------//
    //----------------------------------------------------//

    function test_whitelistTransfer(
        address _recipient,
        address _sender,
        uint256 _amount,
        string calldata _name,
        uint256 _tier
    ) public {
        _amount = bound(_amount, 0, gas.balanceOf(owner));
        vm.assume(_amount > 3);
        vm.assume(bytes(_name).length < 9);
        _tier = bound(_tier, 1, 244);
        vm.startPrank(owner);
        gas.transfer(_sender, _amount, _name);
        gas.addToWhitelist(_sender, _tier);
        vm.stopPrank();
        vm.prank(_sender);
        gas.whiteTransfer(_recipient, _amount);
        (bool a, uint256 b) = gas.getPaymentStatus(address(_sender));
        // console.log(a);
        assertEq(a, true);
        assertEq(b, _amount);
    }

    // Reverts if tiers out of bounds
    //OPTIMIZED whitelist
    function test_tiersReverts(address _userAddrs, uint256 _tier) public {
        vm.assume(_userAddrs != address(gas));
        vm.assume(_tier > 254);
        vm.prank(owner);
        vm.expectRevert();
        gas.addToWhitelist(_userAddrs, _tier);
    }

    // Expect Event -->
    event WhiteListTransfer(address indexed);

    function test_whitelistEvents(
        address _recipient,
        address _sender,
        uint256 _amount,
        string calldata _name,
        uint256 _tier
    ) public {
        _amount = bound(_amount, 0, gas.balanceOf(owner));
        vm.assume(_amount > 3);
        vm.assume(bytes(_name).length < 9);
        _tier = bound(_tier, 1, 244);
        vm.startPrank(owner);
        gas.transfer(_sender, _amount, _name);
        gas.addToWhitelist(_sender, _tier);
        vm.stopPrank();
        vm.startPrank(_sender);
        vm.expectEmit(true, false, false, true);
        emit WhiteListTransfer(_recipient);
        gas.whiteTransfer(_recipient, _amount);
        vm.stopPrank();
    }

    /* whiteTranfer balance logic. 
        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;
        balances[senderOfTx] += whitelist[senderOfTx];
        balances[_recipient] -= whitelist[senderOfTx]; 
        */

    // check balances update

    function testWhiteTranferAmountUpdate(
        uint256 _amount,
        string calldata _name,
        uint256 _tier
    ) public {
        address _recipient = get_random_address(23);
        address _sender = get_random_address(37);

        uint256 _preRecipientAmount = gas.balances(_recipient) + 0;
        vm.assume(_recipient != address(0));
        vm.assume(_sender != address(0));
        _amount = bound(_amount, 0, gas.balanceOf(owner));
        _tier = bound(_tier, 1, 244);
        vm.assume(_amount > 3);
        vm.assume(bytes(_name).length < 9 && bytes(_name).length > 0);
        vm.startPrank(owner);
        gas.transfer(_sender, _amount, _name);
        uint256 _preSenderAmount = gas.balances(_sender);
        gas.addToWhitelist(_sender, _tier);
        vm.stopPrank();
        vm.prank(_sender);
        gas.whiteTransfer(_recipient, _amount);
        assertEq(
            gas.balances(_sender),
            (_preSenderAmount - _amount) + gas.whitelist(_sender)
        );
        assertEq(
            gas.balances(_recipient),
            (_preRecipientAmount + _amount) - gas.whitelist(_sender)
        );
    }
    //OPTIMIZED _init_
    function testBalanceOf() public view {
        uint256 bal = gas.balanceOf(owner);
        assertEq(bal, totalSupply);
    }

    //OPTIMIZED whitelist

    function testCheckForAdmin() public view {
        bool isAdmin = gas.checkForAdmin(owner);
        assertEq(isAdmin, true);
    }
    // OPTIMIZED transfer
    function testTransfer(uint256 _amount, address _recipient) public {
        vm.assume(_amount <= totalSupply);
        vm.startPrank(owner);

        uint256 ownerBal = gas.balanceOf(owner);
        uint256 balBefore = gas.balanceOf(_recipient);
        gas.transfer(_recipient, _amount, "name");
        uint256 balAfter = gas.balanceOf(_recipient);

        if (_recipient == owner) {
            assertEq(balAfter, balBefore);
            assertEq(gas.balanceOf(owner), ownerBal);
        } else {
            assertEq(balAfter, balBefore + _amount);
            assertEq(gas.balanceOf(owner), ownerBal - _amount);
        }
    }

    //OPTIMIZED whitelist

    function testAddToWhitelist(uint256 tier) public {
        vm.expectRevert();
        address user = get_random_address(13);
        vm.startPrank(user);
        vm.assume(user != owner);
        gas.addToWhitelist(user, tier);
        vm.stopPrank();
    }
}
