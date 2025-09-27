// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { CommerceProtocolBase } from "../../../src/CommerceProtocolBase.sol";
import { BaseCommerceIntegration } from "../../../src/BaseCommerceIntegration.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title CommerceProtocolBaseTest
 * @dev Unit tests for CommerceProtocolBase contract
 * @notice Tests shared functionality and base contract behavior
 */
contract CommerceProtocolBaseTest is TestSetup {
    // Test contracts - Use existing CommerceProtocolCore from TestSetup
    BaseCommerceIntegration public baseCommerceIntegration;

    // Test addresses
    address public testOperatorFeeDestination = address(0x1001);
    address public testOperatorSigner = address(0x2001);

    // Test data
    ISharedTypes.PlatformPaymentRequest testRequest;
    bytes16 testIntentId = bytes16(keccak256("test-intent"));

    function setUp() public override {
        super.setUp();

        // Deploy BaseCommerceIntegration first (required dependency)
        baseCommerceIntegration = new BaseCommerceIntegration(
            address(mockUSDC),
            testOperatorFeeDestination
        );

        // CommerceProtocolCore is already deployed in TestSetup
        // Grant roles for testing
        vm.prank(admin);
        commerceProtocolCore.grantPaymentMonitorRole(address(this));

        // Set up test payment request
        testRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator1,
            contentId: 1,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        // Fund test accounts (already done in TestSetup)
        // mockUSDC.mint(testUser, 10000e6);
        // vm.deal(testUser, 10 ether);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(commerceProtocolCore.owner(), admin);
        assertTrue(commerceProtocolCore.hasRole(commerceProtocolCore.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(commerceProtocolCore.operatorFeeDestination(), testOperatorFeeDestination);
        assertEq(commerceProtocolCore.operatorSigner(), testOperatorSigner);
        assertEq(commerceProtocolCore.operatorFeeRate(), 50); // 0.5% default
    }


    // ============ INTENT MANAGEMENT TESTS ============

    function test_CreatePaymentIntent_ValidRequest() public {
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

        // Create payment intent
        vm.prank(user1);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(testRequest);

        assertTrue(intentId != bytes16(0));
        assertEq(context.user, user1);
        assertEq(context.creator, creator1);
        assertEq(context.contentId, 1);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
        assertFalse(context.processed);
        assertEq(context.paymentToken, address(mockUSDC));
        assertTrue(context.expectedAmount > 0);
    }

    function test_CreatePaymentIntent_InvalidCreator() public {
        testRequest.creator = address(0); // Invalid creator

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to invalid creator
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    function test_CreatePaymentIntent_InvalidContent() public {
        // Valid creator but invalid content
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        testRequest.contentId = 999; // Non-existent content

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to invalid content
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    function test_CreatePaymentIntent_ExpiredDeadline() public {
        testRequest.deadline = block.timestamp - 1; // Expired

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to expired deadline
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    // ============ PAYMENT CONTEXT TESTS ============

    function test_GetPaymentContext_ExistingIntent() public {
        _setupPaymentIntent();

        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);

        assertEq(context.user, user1);
        assertEq(context.creator, creator1);
        assertEq(context.contentId, 1);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
        assertFalse(context.processed);
    }

    function test_GetPaymentContext_NonExistentIntent() public {
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);

        assertEq(context.user, address(0)); // Should be zero
        assertEq(context.creator, address(0));
        assertEq(context.contentId, 0);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView)); // Default value
        assertFalse(context.processed);
    }

    // ============ INTENT PROCESSING TESTS ============

    function test_ProvideIntentSignature_ValidSignature() public {
        _setupPaymentIntent();

        // Provide signature (mock call - real implementation would verify signature)
        vm.prank(testOperatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "valid-signature");

        // Note: intentSignatures is in SignatureManager, not CommerceProtocolCore
        // The signature provision should succeed without reverting
    }

    function test_ProvideIntentSignature_UnauthorizedSigner() public {
        _setupPaymentIntent();

        vm.prank(user1); // Not the operator signer
        vm.expectRevert(); // Should revert due to unauthorized signer
        commerceProtocolCore.provideIntentSignature(testIntentId, "unauthorized-signature");
    }

    function test_ProvideIntentSignature_IntentNotFound() public {
        vm.prank(testOperatorSigner);
        vm.expectRevert(); // Should revert due to intent not found
        commerceProtocolCore.provideIntentSignature(testIntentId, "signature");
    }

    // ============ PAYMENT EXECUTION TESTS ============

    function test_ExecutePaymentWithSignature_Success() public {
        _setupPaymentIntent();
        _signIntent();

        // Mock successful payment execution
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(true)
        );

        vm.prank(user1);
        bool success = commerceProtocolCore.executePaymentWithSignature(testIntentId);

        assertTrue(success);

        // Verify context is marked as processed
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(testIntentId);
        assertTrue(context.processed);
    }

    function test_ExecutePaymentWithSignature_IntentNotSigned() public {
        _setupPaymentIntent();

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to unsigned intent
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    function test_ExecutePaymentWithSignature_AlreadyProcessed() public {
        _setupPaymentIntent();
        _signIntent();

        // Mock successful payment execution
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(true)
        );

        // Execute first time
        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId);

        // Try to execute again
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to already processed
        commerceProtocolCore.executePaymentWithSignature(testIntentId);
    }

    // ============ FEE MANAGEMENT TESTS ============

    function test_UpdateOperatorFeeRate_ValidRate() public {
        uint256 newRate = 100; // 1%

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.OperatorFeeUpdated(50, newRate);

        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeRate(newRate);

        assertEq(commerceProtocolCore.operatorFeeRate(), newRate);
    }

    function test_UpdateOperatorFeeRate_ZeroRate() public {
        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeRate(0);

        assertEq(commerceProtocolCore.operatorFeeRate(), 0);
    }

    function test_UpdateOperatorFeeRate_MaxRate() public {
        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeRate(1000); // 10%

        assertEq(commerceProtocolCore.operatorFeeRate(), 1000);
    }

    function test_UpdateOperatorFeeRate_TooHigh() public {
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to fee too high
        commerceProtocolCore.updateOperatorFeeRate(1001);
    }

    function test_UpdateOperatorFeeRate_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        commerceProtocolCore.updateOperatorFeeRate(100);
    }

    function test_UpdateOperatorFeeDestination_ValidAddress() public {
        address newDestination = address(0x5001);

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.OperatorFeeDestinationUpdated(testOperatorFeeDestination, newDestination);

        vm.prank(admin);
        commerceProtocolCore.updateOperatorFeeDestination(newDestination);

        assertEq(commerceProtocolCore.operatorFeeDestination(), newDestination);
    }

    function test_UpdateOperatorFeeDestination_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to invalid destination
        commerceProtocolCore.updateOperatorFeeDestination(address(0));
    }

    function test_UpdateOperatorFeeDestination_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        commerceProtocolCore.updateOperatorFeeDestination(address(0x5001));
    }

    // ============ SIGNER MANAGEMENT TESTS ============

    function test_UpdateOperatorSigner_ValidAddress() public {
        address newSigner = address(0x6001);

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.SignerUpdated(testOperatorSigner, newSigner);

        vm.prank(admin);
        commerceProtocolCore.updateOperatorSigner(newSigner);

        assertEq(commerceProtocolCore.operatorSigner(), newSigner);
    }

    function test_UpdateOperatorSigner_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to invalid signer
        commerceProtocolCore.updateOperatorSigner(address(0));
    }

    function test_UpdateOperatorSigner_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        commerceProtocolCore.updateOperatorSigner(address(0x6001));
    }

    // ============ CONTRACT MANAGEMENT TESTS ============

    function test_SetPayPerView_ValidAddress() public {
        address newPayPerView = address(0x7001);

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.ContractAddressUpdated("PayPerView", address(0), newPayPerView);

        vm.prank(admin);
        commerceProtocolCore.setPayPerView(newPayPerView);

        assertEq(address(commerceProtocolCore.payPerView()), newPayPerView);
    }

    function test_SetPayPerView_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to invalid address
        commerceProtocolCore.setPayPerView(address(0));
    }

    function test_SetPayPerView_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to onlyOwner
        commerceProtocolCore.setPayPerView(address(0x7001));
    }

    // Similar pattern for other contract setters
    function test_SetSubscriptionManager_ValidAddress() public {
        address newSubscriptionManager = address(0x8001);

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.ContractAddressUpdated("SubscriptionManager", address(0), newSubscriptionManager);

        vm.prank(admin);
        commerceProtocolCore.setSubscriptionManager(newSubscriptionManager);

        assertEq(address(commerceProtocolCore.subscriptionManager()), newSubscriptionManager);
    }

    // ============ REFUND TESTS ============

    function test_RequestRefund_ValidRequest() public {
        _setupPaymentIntent();
        _signIntent();

        // Mock failed payment
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(false)
        );

        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId); // This will fail

        // Request refund
        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.RefundRequested(testIntentId, user1, 0, "Payment failed");

        vm.prank(user1);
        commerceProtocolCore.requestRefund(testIntentId, "Payment failed");

        // Note: refundRequests is in RefundManager, not directly accessible from CommerceProtocolCore
        // The refund request should succeed without reverting
    }

    function test_RequestRefund_IntentNotFound() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to intent not found
        commerceProtocolCore.requestRefund(testIntentId, "Not found");
    }

    function test_RequestRefund_AlreadyProcessed() public {
        _setupPaymentIntent();
        _signIntent();

        // Mock successful payment
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(true)
        );

        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId);

        // Try to request refund for successful payment
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to already processed
        commerceProtocolCore.requestRefund(testIntentId, "Already processed");
    }

    // ============ PAUSABLE FUNCTIONALITY TESTS ============

    function test_Pause_OnlyOwner() public {
        vm.prank(admin);
        commerceProtocolCore.pause();

        assertTrue(commerceProtocolCore.paused());
    }

    function test_Unpause_OnlyOwner() public {
        // First pause
        vm.prank(admin);
        commerceProtocolCore.pause();

        // Then unpause
        vm.prank(admin);
        commerceProtocolCore.unpause();

        assertFalse(commerceProtocolCore.paused());
    }

    function test_PausableFunctions_WhenPaused() public {
        vm.prank(admin);
        commerceProtocolCore.pause();

        // These functions should be affected by pause
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to paused
        commerceProtocolCore.createPaymentIntent(testRequest);
    }

    // ============ METRICS TESTS ============

    function test_Metrics_InitialState() public {
        assertEq(commerceProtocolCore.totalIntentsCreated(), 0);
        assertEq(commerceProtocolCore.totalPaymentsProcessed(), 0);
        assertEq(commerceProtocolCore.totalOperatorFees(), 0);
        assertEq(commerceProtocolCore.totalRefundsProcessed(), 0);
    }

    function test_Metrics_AfterPayment() public {
        _setupPaymentIntent();
        _signIntent();

        // Mock successful payment
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(true)
        );

        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId);

        assertEq(commerceProtocolCore.totalIntentsCreated(), 1);
        assertEq(commerceProtocolCore.totalPaymentsProcessed(), 1);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyOwnerFunctions() public {
        // Test various owner-only functions
        vm.prank(user1);
        vm.expectRevert(); // updateOperatorFeeRate
        commerceProtocolCore.updateOperatorFeeRate(100);

        vm.prank(user1);
        vm.expectRevert(); // updateOperatorFeeDestination
        commerceProtocolCore.updateOperatorFeeDestination(address(0x5001));

        vm.prank(user1);
        vm.expectRevert(); // updateOperatorSigner
        commerceProtocolCore.updateOperatorSigner(address(0x6001));

        vm.prank(user1);
        vm.expectRevert(); // setPayPerView
        commerceProtocolCore.setPayPerView(address(0x7001));

        vm.prank(user1);
        vm.expectRevert(); // pause
        commerceProtocolCore.pause();

        vm.prank(user1);
        vm.expectRevert(); // unpause
        commerceProtocolCore.unpause();
    }

    function test_RoleBasedAccess() public {
        // Test role-based access control
        bytes32 testRole = keccak256("TEST_ROLE");

        // Grant role to test user
        vm.prank(admin);
        commerceProtocolCore.grantRole(testRole, user1);

        assertTrue(commerceProtocolCore.hasRole(testRole, user1));
    }

    // ============ BOUNDARY TESTS ============

    function test_CreatePaymentIntent_MaxValues() public {
        // Test with maximum values
        testRequest.deadline = type(uint256).max;
        testRequest.maxSlippage = 1000; // 10%

        vm.prank(user1);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(testRequest);

        assertTrue(intentId != bytes16(0));
    }

    function test_CreatePaymentIntent_MinValues() public {
        // Test with minimum values
        testRequest.deadline = block.timestamp + 1;
        testRequest.maxSlippage = 0;

        vm.prank(user1);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(testRequest);

        assertTrue(intentId != bytes16(0));
    }

    // ============ HELPER FUNCTIONS ============

    function _setupPaymentIntent() internal {
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
    }

    function _signIntent() internal {
        vm.prank(testOperatorSigner);
        commerceProtocolCore.provideIntentSignature(testIntentId, "test-signature");
    }

    // ============ EVENT EMISSION TESTS ============

    function test_AllEventsEmittedCorrectly() public {
        _setupPaymentIntent();

        // Test PaymentIntentCreated event
        vm.expectEmit(true, true, true, true);
        emit CommerceProtocolBase.PaymentIntentCreated(
            testIntentId,
            user1,
            creator1,
            ISharedTypes.PaymentType.PayPerView,
            0.1e6, // totalAmount
            0.09e6, // creatorAmount (90% of 0.1e6)
            0.005e6, // platformFee (0.5% of 0.1e6)
            0.005e6, // operatorFee (0.5% of 0.1e6)
            address(mockUSDC),
            0.1e6
        );

        vm.prank(user1);
        (bytes16 newIntentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(testRequest);

        // Test refund events
        _signIntent();
        vm.mockCall(
            address(commerceProtocolCore),
            abi.encodeWithSignature("executePayment(bytes16)"),
            abi.encode(false)
        );

        vm.prank(user1);
        commerceProtocolCore.executePaymentWithSignature(testIntentId);

        vm.expectEmit(true, true, false, true);
        emit CommerceProtocolBase.RefundRequested(testIntentId, user1, 0, "Test refund");

        vm.prank(user1);
        commerceProtocolCore.requestRefund(testIntentId, "Test refund");
    }
}
