// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { RefundManager } from "../../src/RefundManager.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";

/**
 * @title RefundManager Unit Tests
 * @dev Tests the refund management functions of the RefundManager contract
 * @notice Tests refund requests, processing, coordination with other contracts, etc.
 */
contract RefundManagerTest is TestSetup {
    bytes16 public testIntentId = bytes16(keccak256("test-refund-intent"));
    address public paymentMonitor = address(0x7777);

    // Mock refund data
    uint256 public creatorAmount = 900e6; // 900 USDC
    uint256 public platformFee = 90e6;   // 90 USDC
    uint256 public operatorFee = 10e6;   // 10 USDC

    function setUp() public override {
        super.setUp();

        // RefundManager is already deployed in TestSetup
        refundManager = RefundManager(commerceIntegration.refundManager());
    }

    // ============ CONTRACT MANAGEMENT TESTS ============

    function test_SetPayPerView_Success() public {
        vm.prank(admin);

        address newPayPerView = address(0x1234);
        refundManager.setPayPerView(newPayPerView);

        // Note: We can't directly check the internal state, but the call should succeed
    }

    function test_SetPayPerView_RevertIfNotOwner() public {
        vm.prank(user1);

        address newPayPerView = address(0x1234);
        vm.expectRevert("Ownable: caller is not the owner");
        refundManager.setPayPerView(newPayPerView);
    }

    function test_SetPayPerView_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid address");
        refundManager.setPayPerView(address(0));
    }

    function test_SetSubscriptionManager_Success() public {
        vm.prank(admin);

        address newSubscriptionManager = address(0x5678);
        refundManager.setSubscriptionManager(newSubscriptionManager);
    }

    function test_SetSubscriptionManager_RevertIfNotOwner() public {
        vm.prank(user1);

        address newSubscriptionManager = address(0x5678);
        vm.expectRevert("Ownable: caller is not the owner");
        refundManager.setSubscriptionManager(newSubscriptionManager);
    }

    function test_SetSubscriptionManager_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid address");
        refundManager.setSubscriptionManager(address(0));
    }

    // ============ REFUND REQUEST TESTS ============

    function test_RequestRefund_Success() public {
        vm.prank(user1);

        // Request refund
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Verify refund request was created
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertEq(refund.originalIntentId, testIntentId);
        assertEq(refund.user, user1);
        assertEq(refund.amount, creatorAmount + platformFee + operatorFee);
        assertEq(refund.reason, "Test refund reason");
        assertFalse(refund.processed);

        // Verify pending refund was recorded
        assertEq(refundManager.getPendingRefund(user1), refund.amount);
    }

    function test_RequestRefund_RevertIfNotPaymentCreator() public {
        vm.prank(user2); // Wrong user

        vm.expectRevert("Not payment creator");
        refundManager.requestRefund(
            testIntentId,
            user1, // Original creator
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );
    }

    function test_RequestRefund_RevertIfAlreadyRequested() public {
        vm.prank(user1);

        // First request
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "First refund reason"
        );

        // Second request should fail
        vm.expectRevert("Refund already requested");
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Second refund reason"
        );
    }

    function test_RequestRefund_CalculatesCorrectAmount() public {
        vm.prank(user1);

        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        uint256 expectedTotal = creatorAmount + platformFee + operatorFee;

        assertEq(refund.amount, expectedTotal);
    }

    function test_RequestRefund_Events() public {
        vm.prank(user1);

        uint256 expectedAmount = creatorAmount + platformFee + operatorFee;

        vm.expectEmit(true, true, false, true);
        emit RefundManager.RefundRequested(testIntentId, user1, expectedAmount, "Test refund reason");

        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );
    }

    // ============ REFUND PROCESSING TESTS ============

    function test_ProcessRefund_Success() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Mint tokens to the refund manager for refund processing
        mockUSDC.mint(address(refundManager), 1000e6);

        // Grant payment monitor role to admin
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Process the refund
        vm.prank(admin);
        refundManager.processRefund(testIntentId);

        // Verify refund was processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);

        // Verify tokens were transferred
        uint256 expectedAmount = creatorAmount + platformFee + operatorFee;
        assertEq(mockUSDC.balanceOf(user1), expectedAmount);

        // Verify pending refund was cleared
        assertEq(refundManager.getPendingRefund(user1), 0);
    }

    function test_ProcessRefund_RevertIfNotPaymentMonitor() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Try to process without payment monitor role
        vm.prank(user2);
        vm.expectRevert();
        refundManager.processRefund(testIntentId);
    }

    function test_ProcessRefund_RevertIfNotRequested() public {
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.prank(admin);
        vm.expectRevert("Refund not requested");
        refundManager.processRefund(testIntentId);
    }

    function test_ProcessRefund_RevertIfAlreadyProcessed() public {
        // First create and process a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Mint tokens and grant role
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Process refund first time
        vm.prank(admin);
        refundManager.processRefund(testIntentId);

        // Try to process again
        vm.expectRevert("Already processed");
        refundManager.processRefund(testIntentId);
    }

    function test_ProcessRefund_Events() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Mint tokens and grant role
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        uint256 expectedAmount = creatorAmount + platformFee + operatorFee;

        vm.expectEmit(true, true, false, true);
        emit RefundManager.RefundProcessed(testIntentId, user1, expectedAmount);

        vm.prank(admin);
        refundManager.processRefund(testIntentId);
    }

    // ============ COORDINATED REFUND PROCESSING TESTS ============

    function test_ProcessRefundWithCoordination_PayPerView() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Mint tokens and grant role
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Mock the PayPerView handleExternalRefund call
        vm.mockCall(
            address(payPerView),
            abi.encodeWithSignature("handleExternalRefund(bytes16,address,uint256)", testIntentId, user1, uint256(0)),
            abi.encode()
        );

        // Process refund with coordination
        vm.prank(admin);
        refundManager.processRefundWithCoordination(
            testIntentId,
            ISharedTypes.PaymentType.PayPerView,
            uint256(0), // contentId
            creator1
        );

        // Verify refund was processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
    }

    function test_ProcessRefundWithCoordination_Subscription() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.Subscription,
            "Test refund reason"
        );

        // Mint tokens and grant role
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Mock the SubscriptionManager handleExternalRefund call
        vm.mockCall(
            address(subscriptionManager),
            abi.encodeWithSignature("handleExternalRefund(bytes16,address,address)", testIntentId, user1, creator1),
            abi.encode()
        );

        // Process refund with coordination
        vm.prank(admin);
        refundManager.processRefundWithCoordination(
            testIntentId,
            ISharedTypes.PaymentType.Subscription,
            uint256(0), // contentId (not used for subscriptions)
            creator1
        );

        // Verify refund was processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
    }

    function test_ProcessRefundWithCoordination_FailsGracefully() public {
        // First create a refund request
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        // Mint tokens and grant role
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Mock the PayPerView call to revert (simulate failure)
        vm.mockCallRevert(
            address(payPerView),
            abi.encodeWithSignature("handleExternalRefund(bytes16,address,uint256)", testIntentId, user1, uint256(0)),
            "Mock revert"
        );

        // Process refund should still succeed despite coordination failure
        vm.prank(admin);
        refundManager.processRefundWithCoordination(
            testIntentId,
            ISharedTypes.PaymentType.PayPerView,
            uint256(0),
            creator1
        );

        // Verify refund was still processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
    }

    // ============ FAILED PAYMENT HANDLING TESTS ============

    function test_HandleFailedPayment_Success() public {
        vm.prank(admin);

        refundManager.handleFailedPayment(
            testIntentId,
            user1,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Payment failed"
        );

        // Verify refund request was created
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(bytes16(keccak256(abi.encodePacked(testIntentId, user1, "Payment failed", "refund"))));
        assertEq(refund.originalIntentId, testIntentId);
        assertEq(refund.user, user1);
        assertEq(refund.amount, creatorAmount + platformFee + operatorFee);
        assertEq(refund.reason, "Payment failed");
    }

    function test_HandleFailedPayment_Events() public {
        vm.prank(admin);

        bytes16 expectedRefundId = bytes16(keccak256(abi.encodePacked(testIntentId, user1, "Payment failed", "refund")));
        uint256 expectedAmount = creatorAmount + platformFee + operatorFee;

        vm.expectEmit(true, true, false, true);
        emit RefundManager.RefundRequested(expectedRefundId, user1, expectedAmount, "Payment failed");

        refundManager.handleFailedPayment(
            testIntentId,
            user1,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Payment failed"
        );
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_GetRefundRequest_Success() public {
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);

        assertEq(refund.originalIntentId, testIntentId);
        assertEq(refund.user, user1);
        assertEq(refund.amount, creatorAmount + platformFee + operatorFee);
        assertEq(refund.reason, "Test refund reason");
        assertFalse(refund.processed);
    }

    function test_GetPendingRefund_Success() public {
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        uint256 pendingRefund = refundManager.getPendingRefund(user1);
        assertEq(pendingRefund, creatorAmount + platformFee + operatorFee);
    }

    function test_GetRefundMetrics_Success() public {
        // Initially should be 0
        assertEq(refundManager.getRefundMetrics(), 0);

        // Create and process a refund
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund reason"
        );

        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.prank(admin);
        refundManager.processRefund(testIntentId);

        // Should now reflect the processed refund
        assertEq(refundManager.getRefundMetrics(), creatorAmount + platformFee + operatorFee);
    }

    // ============ EDGE CASE TESTS ============

    function test_ZeroAmountHandling() public {
        vm.prank(user1);

        refundManager.requestRefund(
            testIntentId,
            user1,
            0, // Zero creator amount
            0, // Zero platform fee
            0, // Zero operator fee
            ISharedTypes.PaymentType.PayPerView,
            "Zero amount refund"
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertEq(refund.amount, 0);
    }

    function test_LargeAmountHandling() public {
        vm.prank(user1);

        uint256 largeCreatorAmount = 1000000e6; // 1M USDC
        uint256 largePlatformFee = 100000e6;   // 100K USDC
        uint256 largeOperatorFee = 10000e6;    // 10K USDC

        refundManager.requestRefund(
            testIntentId,
            user1,
            largeCreatorAmount,
            largePlatformFee,
            largeOperatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Large amount refund"
        );

        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertEq(refund.amount, largeCreatorAmount + largePlatformFee + largeOperatorFee);
    }

    function test_MultipleRefundsPerUser() public {
        vm.prank(user1);

        // First refund
        bytes16 intentId1 = bytes16(keccak256("intent1"));
        refundManager.requestRefund(
            intentId1,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "First refund"
        );

        // Second refund
        bytes16 intentId2 = bytes16(keccak256("intent2"));
        refundManager.requestRefund(
            intentId2,
            user1,
            creatorAmount * 2,
            platformFee * 2,
            operatorFee * 2,
            ISharedTypes.PaymentType.PayPerView,
            "Second refund"
        );

        // Check total pending refund
        uint256 totalExpected = (creatorAmount + platformFee + operatorFee) +
                               (creatorAmount * 2 + platformFee * 2 + operatorFee * 2);
        assertEq(refundManager.getPendingRefund(user1), totalExpected);
    }

    // ============ INTEGRATION TESTS ============

    function test_CompleteRefundFlow_PayPerView() public {
        // Step 1: Request refund
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Integration test refund"
        );

        // Verify request created
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertFalse(refund.processed);
        assertGt(refundManager.getPendingRefund(user1), 0);

        // Step 2: Process refund
        mockUSDC.mint(address(refundManager), 2000e6); // Plenty of tokens
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.prank(admin);
        refundManager.processRefund(testIntentId);

        // Step 3: Verify completion
        refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
        assertEq(refundManager.getPendingRefund(user1), 0);
        assertEq(mockUSDC.balanceOf(user1), refund.amount);
    }

    function test_CompleteRefundFlow_Subscription() public {
        // Step 1: Request refund
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.Subscription,
            "Subscription refund"
        );

        // Step 2: Process with coordination
        mockUSDC.mint(address(refundManager), 2000e6);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.mockCall(
            address(subscriptionManager),
            abi.encodeWithSignature("handleExternalRefund(bytes16,address,address)", testIntentId, user1, creator1),
            abi.encode()
        );

        vm.prank(admin);
        refundManager.processRefundWithCoordination(
            testIntentId,
            ISharedTypes.PaymentType.Subscription,
            uint256(0),
            creator1
        );

        // Step 3: Verify completion
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
        assertEq(mockUSDC.balanceOf(user1), refund.amount);
    }

    function test_InsufficientBalanceHandling() public {
        // Request refund
        vm.prank(user1);
        refundManager.requestRefund(
            testIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Insufficient balance test"
        );

        // Try to process without enough tokens
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.prank(admin);
        vm.expectRevert(); // Should revert due to insufficient balance
        refundManager.processRefund(testIntentId);
    }
}
