// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { PayPerView } from "../../../src/PayPerView.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title PayPerViewTest
 * @dev Unit tests for PayPerView contract
 * @notice Tests core PayPerView functionality in isolation
 */
contract PayPerViewTest is TestSetup {
    function setUp() public override {
        super.setUp();

        // Grant roles for testing
        vm.prank(admin);
        payPerView.grantRole(payPerView.PAYMENT_PROCESSOR_ROLE(), address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(payPerView.owner(), admin);
        assertTrue(payPerView.hasRole(payPerView.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(payPerView.PAYMENT_TIMEOUT(), 1 hours);
        assertEq(payPerView.REFUND_WINDOW(), 24 hours);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_HasAccess_True() public {
        // Register creator and content first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        // Complete purchase to grant access
        bytes16 testIntentId = bytes16(keccak256("test-intent"));
        vm.prank(address(this));
        payPerView.completePurchase(testIntentId, 0.1e6, true, "");

        // Check access is granted
        assertTrue(payPerView.hasAccess(1, user1));
    }

    function test_HasAccess_False() public {
        // Register creator and content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        // Check access is not granted without purchase
        assertFalse(payPerView.hasAccess(1, user1));
    }

    function test_CompletePurchase_Success() public {
        // Register creator and content first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        // Complete purchase
        bytes16 testIntentId = bytes16(keccak256("test-intent"));
        vm.prank(address(this));
        payPerView.completePurchase(testIntentId, 0.1e6, true, "");

        // Verify access is granted
        assertTrue(payPerView.hasAccess(1, user1));
    }

    function test_CompletePurchase_Failure() public {
        // Register creator and content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        // Complete purchase with failure
        bytes16 testIntentId = bytes16(keccak256("test-intent"));
        vm.prank(address(this));
        payPerView.completePurchase(testIntentId, 0.1e6, false, "Payment failed");

        // Verify access is not granted
        assertFalse(payPerView.hasAccess(1, user1));
    }

    function test_RecordExternalPurchase() public {
        // Register creator and content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        // Record external purchase
        bytes16 testIntentId = bytes16(keccak256("test-intent"));
        vm.prank(address(this));
        payPerView.recordExternalPurchase(1, user1, testIntentId, 0.1e6, address(mockUSDC), 0.1e6);

        // Verify access is granted
        assertTrue(payPerView.hasAccess(1, user1));
    }

    // ============ PLATFORM METRICS TESTS ============

    function test_PlatformMetrics_InitialState() public {
        assertEq(payPerView.totalVolume(), 0);
        assertEq(payPerView.totalPurchases(), 0);
        assertEq(payPerView.totalPlatformFees(), 0);
        assertEq(payPerView.totalRefunds(), 0);
    }

    function test_PlatformMetrics_AfterPurchase() public {
        // Register creator and content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        uint256 initialVolume = payPerView.totalVolume();
        uint256 initialPurchases = payPerView.totalPurchases();
        uint256 initialFees = payPerView.totalPlatformFees();

        // Complete purchase
        bytes16 testIntentId = bytes16(keccak256("test-intent"));
        vm.prank(address(this));
        payPerView.completePurchase(testIntentId, 0.1e6, true, "");

        assertEq(payPerView.totalVolume(), initialVolume + 0.1e6);
        assertEq(payPerView.totalPurchases(), initialPurchases + 1);
        assertEq(payPerView.totalPlatformFees(), initialFees + 0.01e6); // 10% platform fee
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyRoleFunctions() public {
        // Test that functions require proper roles
        vm.prank(user1);
        vm.expectRevert(); // completePurchase requires PAYMENT_PROCESSOR_ROLE
        payPerView.completePurchase(bytes16(0), 0.1e6, true, "");

        vm.prank(user1);
        vm.expectRevert(); // recordExternalPurchase requires PAYMENT_PROCESSOR_ROLE
        payPerView.recordExternalPurchase(1, user1, bytes16(0), 0.1e6, address(mockUSDC), 0.1e6);
    }

    // ============ PAUSABLE FUNCTIONALITY TESTS ============

    function test_Pause_OnlyOwner() public {
        vm.prank(admin);
        payPerView.pause();

        assertTrue(payPerView.paused());
    }

    function test_Unpause_OnlyOwner() public {
        // First pause
        vm.prank(admin);
        payPerView.pause();

        // Then unpause
        vm.prank(admin);
        payPerView.unpause();

        assertFalse(payPerView.paused());
    }
}