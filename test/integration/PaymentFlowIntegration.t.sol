// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../helpers/TestSetup.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title PaymentFlowIntegrationTest
 * @dev Integration tests for complete payment workflows
 * @notice Tests the entire flow from creator registration to payment completion
 */
contract PaymentFlowIntegrationTest is TestSetup {
    using stdStorage for StdStorage;

    // Test users and creators
    address public testUser = address(0x1001);
    address public testCreator = address(0x2001);

    // Test content
    uint256 public testContentId;
    string constant TEST_PROFILE_DATA = "QmCreatorProfileHash123456789012345678901234567890123456789";
    string constant TEST_CONTENT_HASH = "QmContentHash123456789012345678901234567890123456789";

    function setUp() public override {
        super.setUp();

        // Set up test balances
        mockUSDC.mint(testUser, 10000e6); // $10,000 for testing
        vm.deal(testUser, 10 ether); // ETH for gas

        // Register creator
        vm.prank(testCreator);
        creatorRegistry.registerCreator(1e6, TEST_PROFILE_DATA); // $1 subscription

        // Register content
        vm.prank(testCreator);
        testContentId = contentRegistry.registerContent(
            TEST_CONTENT_HASH,
            "Integration Test Article",
            "This is a test article for integration testing",
            ISharedTypes.ContentCategory.Article,
            0.1e6, // $0.10 per view
            new string[](0)
        );
    }

    // ============ PAY PER VIEW INTEGRATION TESTS ============

    function test_CompletePayPerViewFlow() public {
        // Step 1: Create payment intent
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: testCreator,
            contentId: testContentId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100, // 1%
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(request);

        assertTrue(intentId != bytes16(0));
        assertEq(context.user, testUser);
        assertEq(context.creator, testCreator);
        assertEq(context.contentId, testContentId);
        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));

        // Step 2: Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "integration-test-signature");

        // Step 3: Execute payment
        uint256 initialBalance = mockUSDC.balanceOf(testUser);
        uint256 initialCreatorBalance = mockUSDC.balanceOf(testCreator);

        vm.prank(testUser);
        bool paymentSuccess = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertTrue(paymentSuccess);

        // Step 4: Verify payment completion
        ISharedTypes.PaymentContext memory completedContext = commerceProtocolCore.getPaymentContext(intentId);
        assertTrue(completedContext.processed);

        // Step 5: Verify balances updated
        uint256 finalBalance = mockUSDC.balanceOf(testUser);
        uint256 finalCreatorBalance = mockUSDC.balanceOf(testCreator);

        // User should have paid
        assertTrue(finalBalance < initialBalance);

        // Creator should have received payment (minus fees)
        assertTrue(finalCreatorBalance > initialCreatorBalance);

        // Step 6: Verify access granted
        assertTrue(payPerView.hasAccess(testContentId, testUser));
    }

    function test_PayPerViewWithDifferentTokens() public {
        // Test payment with different token (simulate WETH payment)
        address wethToken = address(0x1234); // Mock WETH address
        MockERC20 mockWETH = new MockERC20("Wrapped ETH", "WETH", 18);
        mockWETH.mint(testUser, 1e18); // 1 WETH

        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: testCreator,
            contentId: testContentId,
            paymentToken: wethToken,
            maxSlippage: 500, // 5%
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        // Mock price oracle for WETH
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSignature("validateQuoteBeforeSwap(address,address,uint256,uint256,uint256,uint24)"),
            abi.encode(true, 200e6) // 1 WETH = 2000 USDC
        );

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "weth-payment-signature");

        vm.prank(testUser);
        bool success = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertTrue(success);
    }

    // ============ SUBSCRIPTION INTEGRATION TESTS ============

    function test_CompleteSubscriptionFlow() public {
        // Step 1: Create subscription payment intent
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: testCreator,
            contentId: 0, // No specific content for subscription
            paymentToken: address(mockUSDC),
            maxSlippage: 0, // No slippage for USDC
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 intentId, ISharedTypes.PaymentContext memory context) =
            commerceProtocolCore.createPaymentIntent(request);

        assertEq(uint8(context.paymentType), uint8(ISharedTypes.PaymentType.Subscription));

        // Step 2: Provide signature and execute
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "subscription-signature");

        uint256 initialBalance = mockUSDC.balanceOf(testUser);
        uint256 initialCreatorBalance = mockUSDC.balanceOf(testCreator);

        vm.prank(testUser);
        bool success = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertTrue(success);

        // Step 3: Verify subscription access
        assertTrue(subscriptionManager.isSubscribed(testUser, testCreator));

        // Step 4: Verify creator earnings
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(testCreator);
        assertTrue(total > 0);
        assertTrue(pending > 0);

        // Step 5: Verify balances
        assertTrue(mockUSDC.balanceOf(testUser) < initialBalance);
        assertTrue(mockUSDC.balanceOf(testCreator) > initialCreatorBalance);
    }

    // ============ MULTI-CREATOR WORKFLOW TESTS ============

    function test_MultipleCreatorsSingleUser() public {
        // Register second creator
        address creator2 = address(0x3001);
        vm.prank(creator2);
        creatorRegistry.registerCreator(2e6, "QmCreator2Profile");

        // Register content for second creator
        vm.prank(creator2);
        uint256 contentId2 = contentRegistry.registerContent(
            "QmContentHash2",
            "Second Creator Article",
            "Article from second creator",
            ISharedTypes.ContentCategory.Article,
            0.2e6, // $0.20
            new string[](0)
        );

        // Test user subscribes to first creator
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: testCreator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "sub-signature");

        vm.prank(testUser);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Test user purchases content from second creator
        ISharedTypes.PlatformPaymentRequest memory purchaseRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: creator2,
            contentId: contentId2,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 purchaseIntentId,) = commerceProtocolCore.createPaymentIntent(purchaseRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(purchaseIntentId, "purchase-signature");

        vm.prank(testUser);
        commerceProtocolCore.executePaymentWithSignature(purchaseIntentId);

        // Verify user has subscription to first creator
        assertTrue(subscriptionManager.isSubscribed(testUser, testCreator));

        // Verify user has access to second creator's content
        assertTrue(payPerView.hasAccess(contentId2, testUser));

        // Verify both creators received earnings
        (uint256 pending1,,) = creatorRegistry.getCreatorEarnings(testCreator);
        (uint256 pending2,,) = creatorRegistry.getCreatorEarnings(creator2);

        assertTrue(pending1 > 0);
        assertTrue(pending2 > 0);
    }

    // ============ ERROR RECOVERY INTEGRATION TESTS ============

    function test_FailedPaymentRefundWorkflow() public {
        // Create payment intent
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: testCreator,
            contentId: testContentId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        // Provide signature
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "failed-payment-signature");

        // Simulate failed payment (mock failure)
        mockCommerceProtocol.setShouldFailTransfers(true);

        vm.prank(testUser);
        bool paymentSuccess = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertFalse(paymentSuccess); // Payment should fail

        // Request refund
        vm.prank(testUser);
        commerceProtocolCore.requestRefund(intentId, "Payment failed - requesting refund");

        // Process refund
        mockUSDC.mint(address(refundManager), 1000e6); // Fund refund manager
        vm.prank(paymentMonitor);
        commerceProtocolCore.processRefund(intentId);

        // Verify refund was processed
        (bytes16 originalIntentId, address userAddr, uint256 amount, string memory reason, uint256 requestTime, bool processed) = refundManager.refundRequests(intentId);
        assertTrue(processed);

        // Verify user balance restored
        assertEq(mockUSDC.balanceOf(testUser), 10000e6); // Back to initial balance
    }

    // ============ CROSS-CONTRACT STATE SYNCHRONIZATION ============

    function test_CrossContractStateConsistency() public {
        // Subscribe to creator
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: testCreator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(testUser);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "subscription-signature");

        vm.prank(testUser);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Verify state consistency across contracts
        assertTrue(subscriptionManager.isSubscribed(testUser, testCreator));

        // Creator stats should be updated
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(testCreator);
        assertEq(creator.subscriberCount, 1);

        // Verify earnings recorded
        (uint256 pending,,) = creatorRegistry.getCreatorEarnings(testCreator);
        assertTrue(pending > 0);
    }

    // ============ BATCH OPERATIONS INTEGRATION ============

    function test_BatchContentPurchases() public {
        // Register multiple content pieces
        uint256[] memory contentIds = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            string memory contentHash = string(abi.encodePacked("QmContentHash", i));
            string memory title = string(abi.encodePacked("Test Article ", i));
            string memory description = string(abi.encodePacked("Test description ", i));

            vm.prank(testCreator);
            contentIds[i] = contentRegistry.registerContent(
                contentHash,
                title,
                description,
                ISharedTypes.ContentCategory.Article,
                0.1e6, // $0.10 each
                new string[](0)
            );
        }

        // Purchase all content pieces
        for (uint256 i = 0; i < 3; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: testCreator,
                contentId: contentIds[i],
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(testUser);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("batch-signature-", i)));

            vm.prank(testUser);
            commerceProtocolCore.executePaymentWithSignature(intentId);
        }

        // Verify access to all content
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(payPerView.hasAccess(contentIds[i], testUser));
        }

        // Verify creator earnings accumulated
        (uint256 pending,,) = creatorRegistry.getCreatorEarnings(testCreator);
        assertEq(pending, 0.3e6); // 3 * $0.10
    }

    // ============ PERFORMANCE AND GAS TESTING ============

    function test_PaymentFlowGasUsage() public {
        // Measure gas for complete payment flow
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: testCreator,
            contentId: testContentId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        // Create intent
        vm.prank(testUser);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        // Sign and execute
        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "gas-test-signature");

        uint256 gasBefore = gasleft();
        vm.prank(testUser);
        commerceProtocolCore.executePaymentWithSignature(intentId);
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;

        // Assert reasonable gas usage (should be under 200k gas)
        assertTrue(gasUsed < 200000, "Gas usage too high for payment flow");
    }

    function test_MultiplePaymentsEfficiency() public {
        // Test gas efficiency for multiple payments
        uint256 totalGasUsed = 0;

        for (uint256 i = 0; i < 5; i++) {
            ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
                paymentType: ISharedTypes.PaymentType.PayPerView,
                creator: testCreator,
                contentId: testContentId,
                paymentToken: address(mockUSDC),
                maxSlippage: 100,
                deadline: block.timestamp + 3600
            });

            vm.prank(testUser);
            (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

            vm.prank(operatorSigner);
            commerceProtocolCore.provideIntentSignature(intentId, bytes(abi.encodePacked("efficiency-", i)));

            uint256 gasBefore = gasleft();
            vm.prank(testUser);
            commerceProtocolCore.executePaymentWithSignature(intentId);
            uint256 gasAfter = gasleft();

            totalGasUsed += (gasBefore - gasAfter);
        }

        uint256 averageGas = totalGasUsed / 5;
        assertTrue(averageGas < 150000, "Average gas per payment too high");
    }
}
