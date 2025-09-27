// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { AccessManager } from "../../../src/AccessManager.sol";
import { PayPerView } from "../../../src/PayPerView.sol";
import { SubscriptionManager } from "../../../src/SubscriptionManager.sol";
import { CreatorRegistry } from "../../../src/CreatorRegistry.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title AccessManagerTest
 * @dev Unit tests for AccessManager contract
 * @notice Tests all access management and payment processing functions in isolation
 */
contract AccessManagerTest is TestSetup {
    // Test contracts
    // AccessManager is already declared in TestSetup

    // Test data
    AccessManager.PaymentContext testContext;
    bytes16 testIntentId = bytes16(keccak256("test-intent"));

    function setUp() public override {
        super.setUp();

        // Use existing contracts from TestSetup
        // Deploy AccessManager with existing contracts
        accessManager = new AccessManager(
            address(payPerView),
            address(subscriptionManager),
            address(creatorRegistry)
        );

        // Set up test payment context
        testContext = AccessManager.PaymentContext({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            user: user1,
            creator: creator1,
            contentId: 1,
            platformFee: 10e6, // $10
            creatorAmount: 80e6, // $80
            operatorFee: 10e6, // $10
            timestamp: block.timestamp,
            processed: false,
            paymentToken: address(mockUSDC),
            expectedAmount: 100e6, // $100
            intentId: testIntentId
        });

        // Grant necessary roles
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(accessManager));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(accessManager.payPerView()), address(payPerView));
        assertEq(address(accessManager.subscriptionManager()), address(subscriptionManager));
        assertEq(address(accessManager.creatorRegistry()), address(creatorRegistry));

        // Test initial metrics
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 0);
        assertEq(fees, 0);
    }

    function test_Constructor_ZeroAddresses() public {
        // Test constructor with zero addresses should revert or handle gracefully
        vm.expectRevert();
        new AccessManager(address(0), address(0), address(0));
    }

    function test_Constructor_PartialZeroAddresses() public {
        // Test constructor with some zero addresses
        vm.expectRevert();
        new AccessManager(address(payPerView), address(0), address(creatorRegistry));
    }

    // ============ VIEW FUNCTIONS TESTS ============

    function test_GetMetrics_InitialState() public {
        (uint256 paymentsProcessed, uint256 operatorFees) = accessManager.getMetrics();

        assertEq(paymentsProcessed, 0);
        assertEq(operatorFees, 0);
    }

    function test_GetMetrics_AfterProcessing() public {
        // Process a payment
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            testContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        (uint256 paymentsProcessed, uint256 operatorFees) = accessManager.getMetrics();

        assertEq(paymentsProcessed, 1);
        assertEq(operatorFees, 10e6);
    }

    function test_IsConfigured_ProperlyConfigured() public {
        bool configured = accessManager.isConfigured();
        assertTrue(configured);
    }

    function test_IsConfigured_ZeroContracts() public {
        // Deploy with zero addresses to test
        AccessManager unconfiguredManager = new AccessManager(address(0), address(0), address(0));
        assertFalse(unconfiguredManager.isConfigured());
    }

    // ============ PAYMENT HANDLING TESTS ============

    function test_HandleSuccessfulPayment_PayPerView() public {
        // Register creator and content first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AccessManager.ContentAccessGranted(user1, 1, testIntentId, address(mockUSDC), 100e6);

        // Handle payment
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            testContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    function test_HandleSuccessfulPayment_Subscription() public {
        // Set up subscription context
        AccessManager.PaymentContext memory subscriptionContext = testContext;
        subscriptionContext.paymentType = ISharedTypes.PaymentType.Subscription;
        subscriptionContext.contentId = 0; // No content for subscriptions

        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit AccessManager.SubscriptionAccessGranted(user1, creator1, testIntentId, address(mockUSDC), 100e6);

        // Handle payment
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            subscriptionContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    function test_HandleSuccessfulPayment_Tip() public {
        // Set up tip context
        AccessManager.PaymentContext memory tipContext = testContext;
        tipContext.paymentType = ISharedTypes.PaymentType.Tip;
        tipContext.contentId = 0; // No content for tips

        // Handle payment
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            tipContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    function test_HandleSuccessfulPayment_Donation() public {
        // Set up donation context
        AccessManager.PaymentContext memory donationContext = testContext;
        donationContext.paymentType = ISharedTypes.PaymentType.Donation;
        donationContext.contentId = 0; // No content for donations

        // Handle payment
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            donationContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    // ============ ERROR HANDLING TESTS ============

    function test_HandleSuccessfulPayment_PayPerView_ContractNotSet() public {
        // Deploy AccessManager with zero PayPerView address
        AccessManager noPayPerViewManager = new AccessManager(
            address(0),
            address(subscriptionManager),
            address(creatorRegistry)
        );

        // Expect PaymentProcessingCompleted event with zero creator (indicating failure)
        vm.expectEmit(true, true, false, true);
        emit AccessManager.PaymentProcessingCompleted(testIntentId, user1, address(0), ISharedTypes.PaymentType.PayPerView);

        // Handle payment - should not revert but emit failure event
        vm.prank(address(this));
        noPayPerViewManager.handleSuccessfulPayment(
            testContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );
    }

    function test_HandleSuccessfulPayment_Subscription_ContractNotSet() public {
        // Deploy AccessManager with zero SubscriptionManager address
        AccessManager noSubscriptionManager = new AccessManager(
            address(payPerView),
            address(0),
            address(creatorRegistry)
        );

        // Set up subscription context
        AccessManager.PaymentContext memory subscriptionContext = testContext;
        subscriptionContext.paymentType = ISharedTypes.PaymentType.Subscription;

        // Expect PaymentProcessingCompleted event
        vm.expectEmit(true, true, true, true);
        emit AccessManager.PaymentProcessingCompleted(testIntentId, user1, creator1, ISharedTypes.PaymentType.Subscription);

        // Handle payment - should not revert but emit failure event
        vm.prank(address(this));
        noSubscriptionManager.handleSuccessfulPayment(
            subscriptionContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );
    }

    function test_HandleSuccessfulPayment_CreatorStatsUpdateFailure() public {
        // Test when creator stats update fails but payment still succeeds
        AccessManager.PaymentContext memory context = testContext;
        context.creator = address(0x9999); // Non-existent creator

        // Handle payment - should not revert even if stats update fails
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            context,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify metrics still updated despite stats failure
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    // ============ MULTIPLE PAYMENTS TESTS ============

    function test_HandleMultiplePayments_Sequential() public {
        // Register creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Process multiple payments
        for (uint256 i = 0; i < 5; i++) {
            AccessManager.PaymentContext memory context = testContext;
            context.intentId = bytes16(keccak256(abi.encodePacked("test-intent-", i)));
            context.contentId = i + 1;

            vm.prank(address(this));
            accessManager.handleSuccessfulPayment(
                context,
                context.intentId,
                address(mockUSDC),
                100e6,
                10e6
            );
        }

        // Verify metrics
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 5);
        assertEq(fees, 50e6); // 5 * 10e6
    }

    function test_HandleMixedPaymentTypes() public {
        // Register creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Test different payment types
        ISharedTypes.PaymentType[] memory paymentTypes = new ISharedTypes.PaymentType[](4);
        paymentTypes[0] = ISharedTypes.PaymentType.PayPerView;
        paymentTypes[1] = ISharedTypes.PaymentType.Subscription;
        paymentTypes[2] = ISharedTypes.PaymentType.Tip;
        paymentTypes[3] = ISharedTypes.PaymentType.Donation;

        for (uint256 i = 0; i < paymentTypes.length; i++) {
            AccessManager.PaymentContext memory context = testContext;
            context.paymentType = paymentTypes[i];
            context.intentId = bytes16(keccak256(abi.encodePacked("mixed-intent-", i)));

            vm.prank(address(this));
            accessManager.handleSuccessfulPayment(
                context,
                context.intentId,
                address(mockUSDC),
                100e6,
                10e6
            );
        }

        // Verify metrics
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 4);
        assertEq(fees, 40e6); // 4 * 10e6
    }

    // ============ BOUNDARY TESTS ============

    function test_HandlePayment_ZeroAmount() public {
        AccessManager.PaymentContext memory context = testContext;
        context.expectedAmount = 0;
        context.creatorAmount = 0;
        context.platformFee = 0;
        context.operatorFee = 0;

        // Should not revert
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            context,
            testIntentId,
            address(mockUSDC),
            0,
            0
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 0);
    }

    function test_HandlePayment_MaxUint256Amount() public {
        AccessManager.PaymentContext memory context = testContext;
        context.expectedAmount = type(uint256).max;
        context.creatorAmount = type(uint256).max / 2;
        context.platformFee = type(uint256).max / 4;
        context.operatorFee = type(uint256).max / 4;

        // Should not revert
        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            context,
            testIntentId,
            address(mockUSDC),
            type(uint256).max,
            type(uint256).max / 4
        );

        // Verify metrics updated
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, type(uint256).max / 4);
    }

    // ============ UNAUTHORIZED ACCESS TESTS ============

    function test_HandlePayment_UnauthorizedCaller() public {
        // Try to call handleSuccessfulPayment from unauthorized address
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to access control
        accessManager.handleSuccessfulPayment(
            testContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );
    }

    function test_AccessMetrics_AnyoneCanRead() public {
        // Anyone should be able to read metrics
        vm.prank(user1);
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 0);
        assertEq(fees, 0);
    }

    // ============ EVENT EMISSION TESTS ============

    function test_AllEventsEmittedCorrectly() public {
        // Register creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(1e6, "QmTestProfileHash");

        // Test PayPerView event
        vm.expectEmit(true, true, true, true);
        emit AccessManager.ContentAccessGranted(user1, 1, testIntentId, address(mockUSDC), 100e6);

        AccessManager.PaymentContext memory ppvContext = testContext;
        ppvContext.paymentType = ISharedTypes.PaymentType.PayPerView;

        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            ppvContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Test Subscription event
        bytes16 subscriptionIntentId = bytes16(keccak256("subscription-intent"));
        vm.expectEmit(true, true, true, true);
        emit AccessManager.SubscriptionAccessGranted(user1, creator1, subscriptionIntentId, address(mockUSDC), 100e6);

        AccessManager.PaymentContext memory subContext = testContext;
        subContext.paymentType = ISharedTypes.PaymentType.Subscription;
        subContext.intentId = subscriptionIntentId;

        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            subContext,
            subscriptionIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );
    }

    // ============ INTEGRATION TESTS WITH MOCK CONTRACTS ============

    function test_PayPerViewIntegration_SuccessfulCall() public {
        // Set up mock to return success
        vm.mockCall(
            address(payPerView),
            abi.encodeWithSignature("completePurchase(bytes16,uint256,bool,string)"),
            abi.encode(true)
        );

        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            testContext,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify the call was made (can be checked via events or state)
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }

    function test_SubscriptionIntegration_SuccessfulCall() public {
        // Set up mock to return success
        vm.mockCall(
            address(subscriptionManager),
            abi.encodeWithSignature("recordSubscriptionPayment(address,address,bytes16,uint256,address,uint256)"),
            abi.encode(true)
        );

        AccessManager.PaymentContext memory context = testContext;
        context.paymentType = ISharedTypes.PaymentType.Subscription;

        vm.prank(address(this));
        accessManager.handleSuccessfulPayment(
            context,
            testIntentId,
            address(mockUSDC),
            100e6,
            10e6
        );

        // Verify the call was made
        (uint256 payments, uint256 fees) = accessManager.getMetrics();
        assertEq(payments, 1);
        assertEq(fees, 10e6);
    }
}
