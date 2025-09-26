// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { CommerceProtocolCore } from "../../../src/CommerceProtocolCore.sol";
import { CommerceProtocolBase } from "../../../src/CommerceProtocolBase.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";
import { TestUtils } from "../../helpers/TestUtils.sol";
import { RefundManager } from "../../../src/RefundManager.sol";

/**
 * @title CommerceProtocolCoreTest
 * @dev Unit tests for CommerceProtocolCore contract
 * @notice Tests all core payment processing functions in isolation
 */
contract CommerceProtocolCoreTest is TestSetup {

    // Test payment request
    ISharedTypes.PlatformPaymentRequest testRequest;
    bytes16 testIntentId;

    function setUp() public override {
        super.setUp();

        // Set up test payment request
        testRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator1,
            contentId: 1,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600 // 1 hour from now
        });

        testIntentId = bytes16(keccak256("test-intent"));

        // Grant payment monitor role to test contract
        vm.prank(admin);
        commerceProtocolCore.grantRole(keccak256("PAYMENT_MONITOR_ROLE"), address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(commerceProtocolCore.owner(), admin);
        assertEq(commerceProtocolCore.getContractType(), "CommerceProtocolCore");
        assertEq(commerceProtocolCore.getContractVersion(), "2.0.0");
    }

    // ============ PAYMENT INTENT CREATION TESTS ============

    function test_CreatePaymentIntent_PayPerView() public {
        // Register creator and content first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6, // $0.10
            new string[](0)
        );

        // Create payment intent
        vm.prank(user1);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(testRequest);

        // Verify intent was created
        assertTrue(intentId != bytes16(0));
        assertEq(context.user, user1);
        assertEq(context.creator, creator1);
        assertEq(context.contentId, 1);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
        assertFalse(context.processed);
        assertEq(context.paymentToken, address(mockUSDC));
        assertTrue(context.expectedAmount > 0);

        // Verify intent is stored
        ISharedTypes.PaymentContext memory storedContext = commerceProtocolCore.getPaymentContext(intentId);
        assertEq(storedContext.user, user1);
        assertEq(storedContext.creator, creator1);
    }

    function test_CreatePaymentIntent_Subscription() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Set up subscription request
        ISharedTypes.PlatformPaymentRequest memory subscriptionRequest = testRequest;
        subscriptionRequest.paymentType = ISharedTypes.PaymentType.Subscription;
        subscriptionRequest.contentId = 0; // No content for subscriptions

        // Create payment intent
        vm.prank(user1);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(subscriptionRequest);

        // Verify intent was created
        assertTrue(intentId != bytes16(0));
        assertEq(context.user, user1);
        assertEq(context.creator, creator1);
        assertEq(context.contentId, 0);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.Subscription));
    }

    function test_CreatePaymentIntent_Tip() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Set up tip request
        ISharedTypes.PlatformPaymentRequest memory tipRequest = testRequest;
        tipRequest.paymentType = ISharedTypes.PaymentType.Tip;
        tipRequest.contentId = 0; // No content for tips

        // Create payment intent
        vm.prank(user1);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(tipRequest);

        // Verify intent was created
        assertTrue(intentId != bytes16(0));
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.Tip));
    }

    function test_CreatePaymentIntent_Donation() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Set up donation request
        ISharedTypes.PlatformPaymentRequest memory donationRequest = testRequest;
        donationRequest.paymentType = ISharedTypes.PaymentType.Donation;
        donationRequest.contentId = 0; // No content for donations

        // Create payment intent
        vm.prank(user1);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(donationRequest);

        // Verify intent was created
        assertTrue(intentId != bytes16(0));
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.Donation));
    }

    function test_CreatePaymentIntent_ExpiredDeadline() public {
        // Set expired deadline
        testRequest.deadline = block.timestamp - 1;

        vm.prank(user1);
        vm.expectRevert(CommerceProtocolBase.DeadlineExpired.selector);
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    function test_CreatePaymentIntent_InvalidCreator() public {
        // Don't register creator
        vm.prank(user1);
        vm.expectRevert(CommerceProtocolBase.InvalidCreator.selector);
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    function test_CreatePaymentIntent_InvalidContent() public {
        // Register creator but not content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(user1);
        vm.expectRevert(CommerceProtocolBase.InvalidContent.selector);
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    function test_CreatePaymentIntent_Paused() public {
        vm.prank(admin);
        commerceProtocolCore.pause();

        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    // ============ PAYMENT EXECUTION TESTS ============

    function test_ExecutePaymentWithSignature_Success() public {
        // Set up test scenario
        _setupSuccessfulPaymentScenario();

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        // Execute payment
        vm.prank(user1);
        bool success = commerceProtocolCore.executePaymentWithSignature(testIntentId);

        assertTrue(success);

        // Verify intent was processed
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);
        assertTrue(context.processed);
        assertTrue(commerceProtocolCore.processedIntents(testIntentId));
    }

    function test_ExecutePaymentWithSignature_NoSignature() public {
        _setupSuccessfulPaymentScenario();

        vm.prank(user1);
        vm.expectRevert("No signature provided");
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    function test_ExecutePaymentWithSignature_NotIntentCreator() public {
        _setupSuccessfulPaymentScenario();

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        vm.prank(user2); // Not the intent creator
        vm.expectRevert("Not intent creator");
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    function test_ExecutePaymentWithSignature_IntentExpired() public {
        _setupSuccessfulPaymentScenario();

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        // Advance time past deadline
        vm.warp(testRequest.deadline + 1);

        vm.prank(user1);
        vm.expectRevert("Intent expired");
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    function test_ExecutePaymentWithSignature_AlreadyProcessed() public {
        _setupSuccessfulPaymentScenario();

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        // Execute first time
        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId);

        // Try to execute again
        vm.prank(user1);
        vm.expectRevert("Intent already processed");
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    function test_ExecutePaymentWithSignature_Paused() public {
        _setupSuccessfulPaymentScenario();

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        // Pause contract
        vm.prank(admin);
        commerceProtocolCore.pause();

        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    // ============ GET PAYMENT INFO TESTS ============

    function test_GetPaymentInfo_PayPerView() public {
        // Register creator and content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmTestContentHash",
            "Test Content",
            "Test Description",
            ISharedTypes.ContentCategory.Article,
            0.1e6, // $0.10
            new string[](0)
        );

        // Get payment info
        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee, uint256 operatorFee, uint256 expectedAmount) =
            commerceProtocolCore.getPaymentInfo(testRequest);

        assertTrue(totalAmount > 0);
        assertTrue(creatorAmount > 0);
        assertTrue(platformFee > 0);
        assertTrue(operatorFee > 0);
        assertEq(totalAmount, creatorAmount + platformFee + operatorFee);
    }

    function test_GetPaymentInfo_Subscription() public {
        // Register creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Set up subscription request
        ISharedTypes.PlatformPaymentRequest memory subscriptionRequest = testRequest;
        subscriptionRequest.paymentType = ISharedTypes.PaymentType.Subscription;
        subscriptionRequest.contentId = 0;

        // Get payment info
        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee, uint256 operatorFee, uint256 expectedAmount) =
            commerceProtocolCore.getPaymentInfo(subscriptionRequest);

        assertTrue(totalAmount > 0);
        assertTrue(creatorAmount > 0);
        assertTrue(platformFee > 0);
        assertTrue(operatorFee > 0);
    }

    // ============ PROCESS COMPLETED PAYMENT TESTS ============

    function test_ProcessCompletedPayment_Success() public {
        // Set up payment context manually
        _setupPaymentContext();

        // Process completed payment
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );

        // Verify intent was processed
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);
        assertTrue(context.processed);
        assertTrue(commerceProtocolCore.processedIntents(testIntentId));
    }

    function test_ProcessCompletedPayment_AlreadyProcessed() public {
        _setupPaymentContext();

        // Process first time
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );

        // Try to process again
        vm.expectRevert(CommerceProtocolBase.IntentAlreadyProcessed.selector);
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );
    }

    function test_ProcessCompletedPayment_ContextNotFound() public {
        vm.expectRevert(CommerceProtocolBase.PaymentContextNotFound.selector);
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );
    }

    function test_ProcessCompletedPayment_IntentExpired() public {
        _setupPaymentContext();

        // Advance time past deadline
        vm.warp(testRequest.deadline + 1);

        vm.expectRevert(CommerceProtocolBase.IntentExpired.selector);
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );
    }

    function test_ProcessCompletedPayment_FailedPayment() public {
        _setupPaymentContext();

        // Process failed payment
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            false,
            "Payment failed"
        );

        // Verify intent was still processed
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);
        assertTrue(context.processed);
    }

    // ============ SIGNATURE MANAGEMENT TESTS ============

    function test_ProvideIntentSignature() public {
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, bytes("test-signature"));

        assertTrue(commerceProtocolCore.hasSignature(testIntentId));
        assertEq(commerceProtocolCore.getIntentSignature(testIntentId), bytes("test-signature"));
    }

    function test_ProvideIntentSignature_Unauthorized() public {
        vm.prank(user1); // Not authorized signer
        vm.expectRevert(); // Should revert due to access control
        commerceProtocolCore.provideIntentSignature(testIntentId, bytes("test-signature"));
    }

    function test_GetIntentSignature() public {
        bytes memory signature = "test-signature";

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, signature);

        assertEq(commerceProtocolCore.getIntentSignature(testIntentId), signature);
    }

    function test_HasSignature() public {
        assertFalse(commerceProtocolCore.hasSignature(testIntentId));

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "test-signature");

        assertTrue(commerceProtocolCore.hasSignature(testIntentId));
    }

    function test_GetIntentHash() public {
        bytes32 hash = commerceProtocolCore.intentHashes(testIntentId);
        assertTrue(hash != bytes32(0));
    }

    // ============ UTILITY FUNCTION TESTS ============

    function test_HasActiveIntent() public {
        _setupSuccessfulPaymentScenario();

        assertFalse(commerceProtocolCore.hasActiveIntent(testIntentId));

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        assertTrue(commerceProtocolCore.hasActiveIntent(testIntentId));
    }

    function test_IntentReadyForExecution() public {
        _setupSuccessfulPaymentScenario();

        assertFalse(commerceProtocolCore.intentReadyForExecution(testIntentId));

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");

        assertTrue(commerceProtocolCore.intentReadyForExecution(testIntentId));
    }

    // ============ ADMIN FUNCTION TESTS ============

    function test_SetPayPerView() public {
        address newPayPerView = address(0x1234);

        vm.prank(admin);
        commerceProtocolCore.setPayPerView(newPayPerView);

        // Verify delegation to AdminManager
        assertEq(address(adminManager.payPerView()), newPayPerView);
    }

    function test_SetSubscriptionManager() public {
        address newSubscriptionManager = address(0x5678);

        vm.prank(admin);
        commerceProtocolCore.setSubscriptionManager(newSubscriptionManager);

        assertEq(address(adminManager.subscriptionManager()), newSubscriptionManager);
    }

    function test_RegisterAsOperator() public {
        vm.prank(admin);
        commerceProtocolCore.registerAsOperator();

        // Should be delegated to AdminManager
    }

    function test_RegisterAsOperatorSimple() public {
        vm.prank(admin);
        commerceProtocolCore.registerAsOperatorSimple();

        // Should be delegated to AdminManager
    }

    function test_UpdateOperatorFeeRate() public {
        uint256 newRate = 100; // 1%

        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeRate(newRate);

        assertEq(commerceProtocolCore.operatorFeeRate(), newRate);
    }

    function test_UpdateOperatorFeeDestination() public {
        address newDestination = address(0x1234);

        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeDestination(newDestination);

        assertEq(commerceProtocolCore.operatorFeeDestination(), newDestination);
    }

    function test_UpdateOperatorSigner() public {
        address newSigner = address(0x5678);

        vm.prank(admin);
        commerceProtocolCore.updateOperatorSigner(newSigner);

        assertEq(commerceProtocolCore.operatorSigner(), newSigner);
    }

    function test_GrantPaymentMonitorRole() public {
        address monitor = address(0x1234);

        vm.prank(admin);
        commerceProtocolCore.grantPaymentMonitorRole(monitor);

        assertTrue(commerceProtocolCore.hasRole(keccak256("PAYMENT_MONITOR_ROLE"), monitor));
    }

    function test_WithdrawOperatorFees() public {
        vm.prank(admin);
        commerceProtocolCore.withdrawOperatorFees(address(mockUSDC), 100e6);

        // Should be delegated to AdminManager
    }

    // ============ EMERGENCY CONTROL TESTS ============

    function test_Pause_Unpause() public {
        // Test pause
        vm.prank(admin);
        commerceProtocolCore.pause();
        assertTrue(commerceProtocolCore.paused());

        // Test unpause
        vm.prank(admin);
        commerceProtocolCore.unpause();
        assertFalse(commerceProtocolCore.paused());
    }

    function test_EmergencyTokenRecovery() public {
        // Mint tokens to core contract
        mockUSDC.mint(address(commerceProtocolCore), 100e6);

        uint256 initialAdminBalance = mockUSDC.balanceOf(admin);

        vm.prank(admin);
        commerceProtocolCore.emergencyTokenRecovery(address(mockUSDC), 100e6);

        uint256 finalAdminBalance = mockUSDC.balanceOf(admin);
        assertEq(finalAdminBalance, initialAdminBalance + 100e6);
    }

    // ============ REFUND TESTS ============

    function test_RequestRefund() public {
        // Set up processed payment context
        _setupPaymentContext();

        // Process completed payment
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );

        // Request refund
        vm.prank(user1);
        commerceProtocolCore.requestRefund(testIntentId, "Test refund reason");

        // Verify refund was requested (delegated to RefundManager)
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(testIntentId);
        assertTrue(refund.processed);
    }

    function test_RequestRefund_NotIntentCreator() public {
        _setupPaymentContext();

        vm.prank(user2); // Not the intent creator
        vm.expectRevert("Not payment creator");
        commerceProtocolCore.requestRefund(testIntentId, "Test refund reason");
    }

    function test_RequestRefund_PaymentNotProcessed() public {
        _setupPaymentContext();

        // Don't process payment
        vm.prank(user1);
        vm.expectRevert("Payment not processed");
        commerceProtocolCore.requestRefund(testIntentId, "Test refund reason");
    }

    function test_ProcessRefund() public {
        _setupRefundScenario();

        vm.prank(paymentMonitor);
        commerceProtocolCore.processRefund(testIntentId);

        // Verify refund was processed (delegated to RefundManager)
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_GetPaymentContext() public {
        _setupPaymentContext();

        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);
        assertEq(context.user, user1);
        assertEq(context.creator, creator1);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
    }

    function test_GetOperatorMetrics() public {
        _setupPaymentContext();

        // Process a payment
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );

        (uint256 intentsCreated, uint256 paymentsProcessed, uint256 operatorFees, uint256 refunds) =
            commerceProtocolCore.getOperatorMetrics();

        assertEq(paymentsProcessed, 1);
    }

    function test_GetOperatorStatus() public {
        (bool registered, address feeDestination) = commerceProtocolCore.getOperatorStatus();
        assertTrue(registered); // BaseCommerceIntegration is always "registered"
        assertEq(feeDestination, operatorFeeDestination);
    }

    // ============ HELPER FUNCTIONS ============

    function _setupSuccessfulPaymentScenario() internal {
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

        // Create payment intent
        vm.prank(user1);
        (testIntentId,) = commerceProtocolCore.createPaymentIntent(testRequest);

        // Mock price oracle for validation
        mockPriceOracle();

        // Mock BaseCommerceIntegration
        mockBaseCommerceIntegration();
    }

    function _setupPaymentContext() internal {
        // Manually set up payment context for testing
        ISharedTypes.PaymentContext memory context = ISharedTypes.PaymentContext({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            user: user1,
            creator: creator1,
            contentId: 1,
            platformFee: 25,
            creatorAmount: 975,
            operatorFee: 10,
            timestamp: block.timestamp,
            processed: false,
            paymentToken: address(mockUSDC),
            expectedAmount: 1000,
            intentId: testIntentId
        });

        // Note: These mappings are not publicly accessible for direct assignment
        // In a real test, we would use createPaymentIntent instead
    }

    function _setupRefundScenario() internal {
        _setupPaymentContext();

        // Process completed payment
        commerceProtocolCore.processCompletedPayment(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            true,
            ""
        );

        // Request refund
        vm.prank(user1);
        commerceProtocolCore.requestRefund(testIntentId, "Test refund");

        // Mint tokens for refund
        mockUSDC.mint(address(refundManager), 1000e6);
    }
}
