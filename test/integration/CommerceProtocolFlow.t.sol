// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { CommerceProtocolIntegration } from "../../src/CommerceProtocolIntegration.sol";
import { ICommercePaymentsProtocol } from "../../src/interfaces/IPlatformInterfaces.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";
import { SubscriptionManager } from "../../src/SubscriptionManager.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { PayPerView } from "../../src/PayPerView.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title CommerceProtocolFlowTest
 * @dev Comprehensive integration tests for Commerce Protocol payment flows
 * @notice This test suite focuses specifically on the Commerce Protocol integration layer,
 *         testing how our platform handles multi-token payments through the Commerce Protocol.
 *
 *         The Commerce Protocol allows users to pay with any supported token while creators
 *         receive USDC. This is crucial for user experience since it removes the friction
 *         of having to acquire specific tokens before making purchases.
 *
 *         We test the complete payment flow: intent creation → signature provision →
 *         execution → processing → verification. Each step must work flawlessly for
 *         the payment system to be reliable.
 */
contract CommerceProtocolFlowTest is TestSetup {
    // ============ TEST DATA STRUCTURES ============

    struct PaymentFlowTest {
        address user;
        address creator;
        address paymentToken;
        uint256 tokenAmount;
        uint256 usdcEquivalent;
        PaymentType paymentType;
        uint256 contentId;
    }

    struct IntentVerification {
        bytes32 intentId;
        bool shouldSucceed;
        string expectedError;
    }

    // ============ STATE VARIABLES ============

    MockERC20 public testToken;
    MockERC20 public altToken;
    uint256 public testContentId;

    // ============ SETUP ============

    function setUp() public override {
        super.setUp();
        _setupTestTokens();
        _setupTestContent();
        _configureMockPrices();
    }

    function _setupTestTokens() private {
        // Create test tokens with different decimals to test decimal handling
        testToken = new MockERC20("Test Token", "TEST", 18);
        altToken = new MockERC20("Alternative Token", "ALT", 6);

        // Mint tokens to test users
        testToken.mint(user1, 1000e18);
        testToken.mint(user2, 1000e18);
        altToken.mint(user1, 1000e6);
        altToken.mint(user2, 1000e6);
    }

    function _setupTestContent() private {
        // Register creators and content for testing
        assertTrue(registerCreator(creator1, 5e6, "Test Creator 1"));
        assertTrue(registerCreator(creator2, 10e6, "Test Creator 2"));
        testContentId = registerContent(creator1, 2e6, "Test Content");
    }

    function _configureMockPrices() internal override {
        // Set up realistic token prices for testing
        mockQuoter.setMockPrice(address(testToken), priceOracle.USDC(), 3000, 2e6); // 1 TEST = $2
        mockQuoter.setMockPrice(address(altToken), priceOracle.USDC(), 3000, 0.5e6); // 1 ALT = $0.50
        mockQuoter.setMockPrice(priceOracle.WETH(), priceOracle.USDC(), 3000, 2000e6); // 1 ETH = $2000
    }

    // ============ PAYMENT INTENT CREATION TESTS ============

    /**
     * @dev Tests creating payment intent for content purchase with alternative token
     * @notice This is the foundation of our multi-token payment system
     */
    function test_CreateContentPaymentIntent_AlternativeToken() public {
        // Arrange: Set up payment scenario
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18, // 1 TEST token = $2, content costs $2
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        // Act: Create payment intent
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (
            ICommercePaymentsProtocol.TransferIntent memory intent,
            CommerceProtocolIntegration.PaymentContext memory context
        ) = commerceIntegration.createPaymentIntent(request);

        // Assert: Verify intent was created correctly
        _verifyPaymentIntent(intent, context, testData);

        // Verify intent is stored and retrievable
        assertTrue(commerceIntegration.intentReadyForExecution(intent.id));
        CommerceProtocolIntegration.PaymentContext memory storedContext =
            commerceIntegration.getPaymentContext(intent.id);
        assertEq(uint256(storedContext.paymentType), uint256(testData.paymentType));
        assertEq(storedContext.creator, testData.creator);
        assertEq(storedContext.contentId, testData.contentId);
    }

    /**
     * @dev Tests creating payment intent for subscription with non-standard decimals
     * @notice This tests our decimal handling across different token standards
     */
    function test_CreateSubscriptionPaymentIntent_NonStandardDecimals() public {
        // Arrange: Use ALT token (6 decimals) for subscription ($10)
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user2,
            creator: creator2,
            paymentToken: address(altToken),
            tokenAmount: 20e6, // 20 ALT tokens = $10
            usdcEquivalent: 10e6,
            paymentType: PaymentType.Subscription,
            contentId: 0
        });

        vm.prank(testData.user);
        altToken.approve(address(commerceIntegration), testData.tokenAmount);

        // Act: Create subscription payment intent
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (
            ICommercePaymentsProtocol.TransferIntent memory intent,
            CommerceProtocolIntegration.PaymentContext memory context
        ) = commerceIntegration.createPaymentIntent(request);

        // Assert: Verify subscription intent
        _verifyPaymentIntent(intent, context, testData);
        assertEq(intent.recipientAmount, testData.tokenAmount);
        assertEq(intent.recipientCurrency, testData.paymentToken);
    }

    /**
     * @dev Tests intent creation with insufficient token balance
     * @notice This tests our balance validation
     */
    function test_CreatePaymentIntent_InsufficientBalance() public {
        // Arrange: Create user with insufficient balance
        address poorUser = address(0x8888);
        testToken.mint(poorUser, 0.5e18); // Only 0.5 TEST tokens, need 1

        vm.prank(poorUser);
        testToken.approve(address(commerceIntegration), 1e18);

        PaymentFlowTest memory testData = PaymentFlowTest({
            user: poorUser,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        // Act & Assert: Should revert with insufficient balance
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.startPrank(poorUser);
        vm.expectRevert("Insufficient token balance");
        commerceIntegration.createPaymentIntent(request);
        vm.stopPrank();
    }

    // ============ SIGNATURE AND EXECUTION TESTS ============

    /**
     * @dev Tests complete payment flow from intent to execution
     * @notice This tests the critical signature → execution → processing flow
     */
    function test_CompletePaymentFlow_Success() public {
        // Phase 1: Create intent
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Phase 2: Provide operator signature
        bytes memory signature = abi.encodePacked(bytes32("test"), bytes32("signature"), bytes1(0x1b));

        vm.prank(operatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, signature);

        // Verify signature was stored
        assertTrue(commerceIntegration.hasSignature(intent.id));

        // Phase 3: Execute payment with signature
        uint256 userBalanceBefore = testToken.balanceOf(testData.user);

        vm.prank(testData.user);
        commerceIntegration.executePaymentWithSignature(intent.id);

        // Verify user's tokens were deducted
        assertEq(testToken.balanceOf(testData.user), userBalanceBefore - testData.tokenAmount);

        // Phase 4: Process completed payment
        vm.prank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id, testData.user, testData.paymentToken, testData.tokenAmount, true, ""
        );

        // Phase 5: Verify final state
        assertTrue(commerceIntegration.processedIntents(intent.id));
        assertTrue(payPerView.hasAccess(testData.contentId, testData.user));

        // Verify creator earnings
        (uint256 earnings,) = payPerView.getCreatorEarnings(testData.creator);
        assertTrue(earnings > 0);
    }

    /**
     * @dev Tests payment execution with invalid signature
     * @notice This tests our signature validation security
     */
    function test_ExecutePayment_InvalidSignature() public {
        // Phase 1: Create intent
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Phase 2: Provide signature from wrong signer
        bytes memory invalidSignature = abi.encodePacked(bytes32("invalid"), bytes32("signature"), bytes1(0x1b));

        vm.startPrank(user2); // Wrong signer
        vm.expectRevert("Only operator can provide signature");
        commerceIntegration.provideIntentSignature(intent.id, invalidSignature);
        vm.stopPrank();

        // Phase 3: Try to execute without signature
        vm.startPrank(testData.user);
        vm.expectRevert("No signature provided");
        commerceIntegration.executePaymentWithSignature(intent.id);
        vm.stopPrank();
    }

    // ============ SUBSCRIPTION FLOW TESTS ============

    /**
     * @dev Tests complete subscription flow through Commerce Protocol
     * @notice This tests subscription creation via alternative tokens
     */
    function test_SubscriptionFlow_AlternativeToken() public {
        // Phase 1: Create subscription intent
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user2,
            creator: creator2,
            paymentToken: address(testToken),
            tokenAmount: 5e18, // 5 TEST = $10 for subscription
            usdcEquivalent: 10e6,
            paymentType: PaymentType.Subscription,
            contentId: 0
        });

        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Phase 2: Complete payment flow
        _executeCompletePaymentFlow(intent, testData);

        // Phase 3: Verify subscription was created
        assertTrue(subscriptionManager.isSubscribed(testData.user, testData.creator));

        SubscriptionManager.SubscriptionRecord memory record =
            subscriptionManager.getSubscriptionDetails(testData.user, testData.creator);
        assertTrue(record.isActive);
        assertEq(record.totalPaid, testData.usdcEquivalent);

        // Verify creator earnings
        (uint256 totalEarnings,) = subscriptionManager.getCreatorSubscriptionEarnings(testData.creator);
        assertTrue(totalEarnings > 0);
    }

    // ============ ERROR HANDLING AND EDGE CASES ============

    /**
     * @dev Tests payment processing failure and recovery
     * @notice This tests what happens when external payment processing fails
     */
    function test_PaymentProcessing_Failure() public {
        // Phase 1: Create and execute intent normally
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        _provideSignatureAndExecute(intent.id, testData.user);

        // Phase 2: Process payment as failed
        vm.prank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id,
            testData.user,
            testData.paymentToken,
            testData.tokenAmount,
            false, // Mark as failed
            "External processing failed"
        );

        // Phase 3: Verify failure was handled correctly
        assertTrue(commerceIntegration.processedIntents(intent.id));
        assertFalse(payPerView.hasAccess(testData.contentId, testData.user)); // Should not have access

        // User should get refund (in real implementation)
        // Note: In production, failure handling would include refund logic
    }

    /**
     * @dev Tests concurrent payment intents for same user
     * @notice This tests our ability to handle multiple simultaneous payments
     */
    function test_ConcurrentPaymentIntents_Success() public {
        // Create two different payment intents for the same user
        PaymentFlowTest memory contentPayment = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        PaymentFlowTest memory subscriptionPayment = PaymentFlowTest({
            user: user1,
            creator: creator2,
            paymentToken: address(altToken),
            tokenAmount: 20e6,
            usdcEquivalent: 10e6,
            paymentType: PaymentType.Subscription,
            contentId: 0
        });

        // Approve tokens for both payments
        vm.startPrank(user1);
        testToken.approve(address(commerceIntegration), contentPayment.tokenAmount);
        altToken.approve(address(commerceIntegration), subscriptionPayment.tokenAmount);
        vm.stopPrank();

        // Create both intents
        CommerceProtocolIntegration.PlatformPaymentRequest memory contentRequest = _buildPaymentRequest(contentPayment);
        CommerceProtocolIntegration.PlatformPaymentRequest memory subscriptionRequest =
            _buildPaymentRequest(subscriptionPayment);

        vm.prank(user1);
        (ICommercePaymentsProtocol.TransferIntent memory contentIntent,) =
            commerceIntegration.createPaymentIntent(contentRequest);

        vm.prank(user1);
        (ICommercePaymentsProtocol.TransferIntent memory subscriptionIntent,) =
            commerceIntegration.createPaymentIntent(subscriptionRequest);

        // Verify both intents exist
        assertTrue(commerceIntegration.intentReadyForExecution(contentIntent.id));
        assertTrue(commerceIntegration.intentReadyForExecution(subscriptionIntent.id));
        assertFalse(contentIntent.id == subscriptionIntent.id); // Should be different

        // Execute both payments
        _executeCompletePaymentFlow(contentIntent, contentPayment);
        _executeCompletePaymentFlow(subscriptionIntent, subscriptionPayment);

        // Verify both payments succeeded
        assertTrue(payPerView.hasAccess(testContentId, user1));
        assertTrue(subscriptionManager.isSubscribed(user1, creator2));
    }

    // ============ ANALYTICS AND METRICS TESTS ============

    /**
     * @dev Tests operator metrics tracking
     * @notice This verifies our analytics collection for operators
     */
    function test_OperatorMetrics_Tracking() public {
        // Get initial metrics
        (uint256 initialIntents, uint256 initialProcessed, uint256 initialFees, uint256 initialRefunds) =
            commerceIntegration.getOperatorMetrics();

        // Execute a complete payment flow
        PaymentFlowTest memory testData = PaymentFlowTest({
            user: user1,
            creator: creator1,
            paymentToken: address(testToken),
            tokenAmount: 1e18,
            usdcEquivalent: 2e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId
        });

        _executeCompleteTestPayment(testData);

        // Check updated metrics
        (uint256 finalIntents, uint256 finalProcessed, uint256 finalFees, uint256 finalRefunds) =
            commerceIntegration.getOperatorMetrics();

        assertEq(finalIntents, initialIntents + 1);
        assertEq(finalProcessed, initialProcessed + 1);
        assertTrue(finalFees >= initialFees); // Fees might have increased
        assertEq(finalRefunds, initialRefunds); // No refunds in this test
    }

    // ============ HELPER FUNCTIONS ============

    function _buildPaymentRequest(PaymentFlowTest memory testData)
        private
        view
        returns (CommerceProtocolIntegration.PlatformPaymentRequest memory)
    {
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = testData.paymentType;
        request.creator = testData.creator;
        request.contentId = testData.contentId;
        request.paymentToken = testData.paymentToken;
        request.maxSlippage = 200; // 2%
        request.deadline = block.timestamp + 1 hours;
        return request;
    }

    function _verifyPaymentIntent(
        ICommercePaymentsProtocol.TransferIntent memory intent,
        CommerceProtocolIntegration.PaymentContext memory context,
        PaymentFlowTest memory expected
    ) private pure {
        assertEq(intent.sender, expected.user);
        assertEq(intent.token, expected.paymentToken);
        assertTrue(intent.recipientAmount > 0);
        assertEq(uint256(context.paymentType), uint256(expected.paymentType));
        assertEq(context.creator, expected.creator);
        assertEq(context.contentId, expected.contentId);
    }

    function _provideSignatureAndExecute(bytes16 intentId, address user) private {
        bytes memory signature = abi.encodePacked(bytes32("test"), bytes32("signature"), bytes1(0x1b));

        vm.prank(operatorSigner);
        commerceIntegration.provideIntentSignature(intentId, signature);

        vm.prank(user);
        commerceIntegration.executePaymentWithSignature(intentId);
    }

    function _executeCompletePaymentFlow(
        ICommercePaymentsProtocol.TransferIntent memory intent,
        PaymentFlowTest memory testData
    ) private {
        _provideSignatureAndExecute(intent.id, testData.user);

        vm.prank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id, testData.user, testData.paymentToken, testData.tokenAmount, true, ""
        );
    }

    function _executeCompleteTestPayment(PaymentFlowTest memory testData) private {
        vm.prank(testData.user);
        testToken.approve(address(commerceIntegration), testData.tokenAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(testData);

        vm.prank(testData.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        _executeCompletePaymentFlow(intent, testData);
    }
}
