// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { RefundManager } from "../../../src/RefundManager.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title RefundManagerTest
 * @dev Unit tests for RefundManager contract
 * @notice Tests core refund functionality in isolation
 */
contract RefundManagerTest is TestSetup {
    function setUp() public override {
        super.setUp();

        // Grant roles for testing
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(refundManager.owner(), admin);
        assertTrue(refundManager.hasRole(refundManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(refundManager.totalRefundsProcessed(), 0);
    }

    // ============ REFUND REQUEST TESTS ============

    function test_RequestRefund_Success() public {
        uint256 creatorAmount = 0.08e6;
        uint256 platformFee = 0.01e6;
        uint256 operatorFee = 0.01e6;
        string memory reason = "Payment failed";

        // Request refund
        vm.prank(user1);
        refundManager.requestRefund(
            bytes16(keccak256("test-intent")),
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            reason
        );

        // Note: Direct access to refundRequests mapping is not available
        // The refund request should succeed without reverting
    }

    function test_RequestRefund_Unauthorized() public {
        vm.prank(creator1); // Not the user who should request refund
        vm.expectRevert("Not payment creator");
        refundManager.requestRefund(
            bytes16(keccak256("test-intent")),
            user1, // Different from msg.sender
            0.08e6,
            0.01e6,
            0.01e6,
            "Payment failed"
        );
    }

    function test_RequestRefund_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Invalid refund amount");
        refundManager.requestRefund(
            bytes16(keccak256("test-intent")),
            user1,
            0,
            0,
            0,
            "Zero amount"
        );
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyRoleFunctions() public {
        // Test that functions require proper roles
        vm.prank(user1);
        vm.expectRevert(); // processRefund requires PAYMENT_MONITOR_ROLE
        refundManager.processRefund(bytes16(keccak256("test-intent")));
    }

    function test_OnlyOwnerFunctions() public {
        // Test owner-only functions
        vm.prank(user1);
        vm.expectRevert(); // setPayPerView requires onlyOwner
        refundManager.setPayPerView(address(0x5001));

        vm.prank(user1);
        vm.expectRevert(); // setSubscriptionManager requires onlyOwner
        refundManager.setSubscriptionManager(address(0x6001));
    }
}