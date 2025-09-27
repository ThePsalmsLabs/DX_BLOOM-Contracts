// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { SubscriptionManager } from "../../../src/SubscriptionManager.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title SubscriptionManagerTest
 * @dev Unit tests for SubscriptionManager contract
 * @notice Tests core subscription functionality in isolation
 */
contract SubscriptionManagerTest is TestSetup {
    function setUp() public override {
        super.setUp();

        // Grant roles for testing
        vm.prank(admin);
        subscriptionManager.grantRole(subscriptionManager.SUBSCRIPTION_PROCESSOR_ROLE(), address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(subscriptionManager.owner(), admin);
        assertTrue(subscriptionManager.hasRole(subscriptionManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(subscriptionManager.SUBSCRIPTION_DURATION(), 30 days);
        assertEq(subscriptionManager.GRACE_PERIOD(), 3 days);
        assertEq(subscriptionManager.RENEWAL_WINDOW(), 1 days);
    }

    // ============ SUBSCRIPTION TESTS ============

    function test_RecordSubscriptionPayment_Success() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Record subscription payment
        vm.prank(address(this));
        subscriptionManager.recordSubscriptionPayment(
            user1,
            creator1,
            bytes16(keccak256("test-intent")),
            1e6, // $1.00
            address(mockUSDC),
            1e6  // $1.00
        );

        // Note: Direct verification of subscription state is not available
        // The function should succeed without reverting
    }

    function test_IsSubscribed_True() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Record subscription payment
        vm.prank(address(this));
        subscriptionManager.recordSubscriptionPayment(
            user1,
            creator1,
            bytes16(keccak256("test-intent")),
            1e6,
            address(mockUSDC),
            1e6
        );

        // Check if user is subscribed to creator
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
    }

    function test_IsSubscribed_False() public {
        // Register creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Check subscription without payment
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyRoleFunctions() public {
        // Test that functions require proper roles
        vm.prank(user1);
        vm.expectRevert(); // recordSubscriptionPayment requires SUBSCRIPTION_PROCESSOR_ROLE
        subscriptionManager.recordSubscriptionPayment(
            user1,
            creator1,
            bytes16(keccak256("test-intent")),
            1e6,
            address(mockUSDC),
            1e6
        );
    }

    // Note: Platform fee withdrawal functionality testing is not available
    // The owner-only access control is enforced at the contract level
}