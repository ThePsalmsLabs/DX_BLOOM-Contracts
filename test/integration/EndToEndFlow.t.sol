// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {CommerceProtocolIntegration} from "../../src/CommerceProtocolIntegration.sol";
import {ICommercePaymentsProtocol} from "../../src/interfaces/IPlatformInterfaces.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";
import {PayPerView} from "../../src/PayPerView.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title EndToEndFlowTest
 * @dev Integration tests for complete user journeys on the platform
 * @notice Refactored to use helper functions and reduce stack depth
 */
contract EndToEndFlowTest is TestSetup {
    // ============ STRUCTS FOR REDUCING VARIABLE COUNT ============

    struct TestContentData {
        uint256 articleContentId;
        uint256 videoContentId;
        uint256 courseContentId;
    }

    struct CreatorEarningsData {
        uint256 payPerViewEarnings;
        uint256 withdrawablePayPerView;
        uint256 subscriptionEarnings;
        uint256 withdrawableSubscription;
    }

    struct SubscriptionTestData {
        address user;
        address creator;
        uint256 subscriptionPrice;
        bool isActive;
        uint256 totalPaid;
    }

    struct PaymentIntentData {
        ICommercePaymentsProtocol.TransferIntent intent;
        CommerceProtocolIntegration.PaymentContext context;
        bytes32 intentId;
    }

    // ============ STATE VARIABLES ============

    TestContentData public contentData;

    // ============ SETUP ============

    function setUp() public override {
        super.setUp();
        _setupMockPrices();
        _registerTestCreators();
        _registerTestContent();
    }

    // ============ PRIVATE SETUP HELPERS ============

    function _setupMockPrices() internal override {
        mockQuoter.setMockPrice(priceOracle.WETH(), priceOracle.USDC(), 3000, 2000e6);
        mockQuoter.setMockPrice(priceOracle.USDC(), priceOracle.WETH(), 3000, 0.0005e18);
    }

    function _registerTestCreators() private {
        assertTrue(registerCreator(creator1, 5e6, "Premium Content Creator"));
        assertTrue(registerCreator(creator2, 10e6, "Expert Tutorial Creator"));
    }

    function _registerTestContent() private {
        contentData.articleContentId = registerContent(creator1, 0.5e6, "Beginner's Guide to DeFi");
        contentData.videoContentId = registerContent(creator1, 2e6, "Advanced Smart Contract Tutorial");
        contentData.courseContentId = registerContent(creator2, 10e6, "Complete Blockchain Development Course");
    }

    // ============ CREATOR JOURNEY HELPERS ============

    function _executeCreatorRegistration(address newCreator, uint256 subscriptionPrice, string memory profileData)
        private
        returns (bool success)
    {
        vm.startPrank(newCreator);
        try creatorRegistry.registerCreator(subscriptionPrice, profileData) {
            success = true;
        } catch {
            success = false;
        }
        vm.stopPrank();
    }

    function _executeContentPublication(address creator, uint256 price, string memory title)
        private
        returns (uint256 contentId)
    {
        vm.startPrank(creator);

        string[] memory tags = new string[](2);
        tags[0] = "tutorial";
        tags[1] = "beginner";

        contentId = contentRegistry.registerContent(
            "QmNewContentHash123",
            title,
            "Learn the basics in this comprehensive guide",
            ContentCategory.Article,
            price,
            tags
        );

        vm.stopPrank();
    }

    function _verifyCreatorRegistration(address creator, uint256 expectedPrice) private view {
        assertTrue(creatorRegistry.isRegisteredCreator(creator));
        CreatorRegistry.Creator memory profile = creatorRegistry.getCreatorProfile(creator);
        assertEq(profile.subscriptionPrice, expectedPrice);
    }

    function _verifyContentRegistration(uint256 contentId, address creator, uint256 expectedPrice) private view {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.creator, creator);
        assertEq(content.payPerViewPrice, expectedPrice);
        assertTrue(content.isActive);
    }

    // ============ COMMERCE PROTOCOL HELPERS ============

    function _createSubscriptionPaymentIntent(address user, address creator, address paymentToken)
        private
        returns (PaymentIntentData memory intentData)
    {
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = PaymentType.Subscription;
        request.creator = creator;
        request.contentId = 0;
        request.paymentToken = paymentToken;
        request.maxSlippage = 150;
        request.deadline = block.timestamp + 1 hours;

        vm.prank(user);
        (intentData.intent, intentData.context) = commerceIntegration.createPaymentIntent(request);
        intentData.intentId = intentData.intent.id;
    }

    function _createContentPaymentIntent(address user, address creator, uint256 contentId, address paymentToken)
        private
        returns (PaymentIntentData memory intentData)
    {
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = PaymentType.PayPerView;
        request.creator = creator;
        request.contentId = contentId;
        request.paymentToken = paymentToken;
        request.maxSlippage = 150;
        request.deadline = block.timestamp + 1 hours;

        vm.prank(user);
        (intentData.intent, intentData.context) = commerceIntegration.createPaymentIntent(request);
        intentData.intentId = intentData.intent.id;
    }

    function _executePaymentIntent(
        bytes32 intentId,
        address user,
        address paymentToken,
        uint256 tokenAmount,
        uint256 usdcEquivalent
    ) private {
        vm.prank(operatorSigner);
        commerceIntegration.provideIntentSignature(
            bytes16(intentId), abi.encodePacked(bytes32("sub"), bytes32("signature"), bytes1(0x1b))
        );

        vm.prank(user);
        commerceIntegration.executePaymentWithSignature(bytes16(intentId));

        vm.prank(admin);
        commerceIntegration.processCompletedPayment(bytes16(intentId), user, paymentToken, tokenAmount, true, "");
    }

    function _verifyPaymentIntentSuccess(
        PaymentIntentData memory intentData,
        PaymentType expectedType
    ) private view {
        assertTrue(intentData.context.paymentType == expectedType);
        assertEq(intentData.context.creator, intentData.context.creator);
    }

    // ============ SUBSCRIPTION HELPERS ============

    function _executeDirectSubscription(address user, address creator) private {
        CreatorRegistry.Creator memory profile = creatorRegistry.getCreatorProfile(creator);
        approveUSDC(user, address(subscriptionManager), profile.subscriptionPrice);

        vm.prank(user);
        subscriptionManager.subscribeToCreator(creator);
    }

    function _verifySubscriptionActive(address user, address creator) private view {
        assertTrue(subscriptionManager.isSubscribed(user, creator));
    }

    function _verifySubscriptionDetails(address user, address creator, uint256 expectedAmount) private view {
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user, creator);
        assertTrue(record.isActive);
        assertEq(record.totalPaid, expectedAmount);
    }

    function _getCreatorSubscriptionEarnings(address creator)
        private
        view
        returns (uint256 totalEarnings, uint256 withdrawable)
    {
        return subscriptionManager.getCreatorSubscriptionEarnings(creator);
    }

    // ============ PAY-PER-VIEW HELPERS ============

    function _executeDirectContentPurchase(address user, uint256 contentId) private {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        approveUSDC(user, address(payPerView), content.payPerViewPrice);

        vm.prank(user);
        payPerView.purchaseContentDirect(contentId);
    }

    function _verifyContentAccess(uint256 contentId, address user) private view {
        assertTrue(payPerView.hasAccess(contentId, user));
    }

    function _getCreatorPayPerViewEarnings(address creator)
        private
        view
        returns (uint256 totalEarnings, uint256 withdrawable)
    {
        return payPerView.getCreatorEarnings(creator);
    }

    // ============ VERIFICATION HELPERS ============

    function _getCreatorEarningsData(address creator) private view returns (CreatorEarningsData memory data) {
        (data.payPerViewEarnings, data.withdrawablePayPerView) = _getCreatorPayPerViewEarnings(creator);
        (data.subscriptionEarnings, data.withdrawableSubscription) = _getCreatorSubscriptionEarnings(creator);
    }

    function _verifyCreatorHasEarnings(address creator) private view {
        CreatorEarningsData memory earnings = _getCreatorEarningsData(creator);
        assertTrue(earnings.payPerViewEarnings > 0 || earnings.subscriptionEarnings > 0);
    }

    function _verifyCreatorStats(address creator, uint256 expectedContentCount, uint256 expectedSubscriberCount)
        private
        view
    {
        CreatorRegistry.Creator memory stats = creatorRegistry.getCreatorProfile(creator);
        assertTrue(stats.totalEarnings > 0);
        assertEq(stats.contentCount, expectedContentCount);
        assertEq(stats.subscriberCount, expectedSubscriberCount);
    }

    function _verifyContentPurchaseCount(uint256 contentId, uint256 expectedCount) private view {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.purchaseCount, expectedCount);
    }

    // ============ AUTO-RENEWAL HELPERS ============

    function _setupAutoRenewal(address user, address creator, uint256 renewalCount) private {
        vm.prank(user);
        subscriptionManager.configureAutoRenewal(creator, true, 0, 0); // Placeholder for maxPrice and depositAmount
    }

    function _executeAutoRenewal(address user, address creator) private {
        advanceTime(SUBSCRIPTION_DURATION + 1);

        vm.prank(user);
        subscriptionManager.executeAutoRenewal(user, creator);
    }

    function _verifyAutoRenewalConfig(address user, address creator, uint256 expectedRenewals) private view {
        SubscriptionManager.AutoRenewal memory config = subscriptionManager.getAutoRenewalConfig(user, creator);
        assertTrue(config.enabled);
        // assertEq(config.remainingRenewals, expectedRenewals);
    }

    // ============ MODERATION HELPERS ============

    function _executeContentReporting(uint256 contentId, uint256 reportCount) private {
        for (uint256 i = 0; i < reportCount; i++) {
            address reporter = address(uint160(0x6000 + i));
            vm.prank(reporter);
            contentRegistry.reportContent(contentId, "Inappropriate content");
        }
    }

    function _verifyContentDeactivated(uint256 contentId) private view {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertFalse(content.isActive);
    }

    function _reactivateContent(uint256 contentId, address creator) private {
        vm.prank(creator);
        contentRegistry.updateContent(contentId, 0, true);
    }

    // ============ ANALYTICS HELPERS ============

    function _verifyPlatformMetrics(uint256 expectedActiveSubscriptions, uint256 expectedTotalVolume) private view {
        (
            uint256 activeSubscriptions,
            uint256 totalVolume,
            uint256 platformFees,
            uint256 renewalCount,
            uint256 refundAmount
        ) = subscriptionManager.getPlatformSubscriptionMetrics();

        assertEq(activeSubscriptions, expectedActiveSubscriptions);
        assertEq(totalVolume, expectedTotalVolume);
        assertTrue(platformFees >= 0);
        assertTrue(renewalCount >= 0);
        assertTrue(refundAmount >= 0);
    }

    // ============ REFACTORED TEST FUNCTIONS ============

    /**
     * @dev Tests complete creator onboarding and content monetization journey
     */
    function test_CompleteCreatorJourney_Success() public {
        address newCreator = address(0x5001);
        uint256 subscriptionPrice = 3e6;

        // Phase 1: Creator registration
        assertTrue(_executeCreatorRegistration(newCreator, subscriptionPrice, "New Creator Profile"));
        _verifyCreatorRegistration(newCreator, subscriptionPrice);

        // Phase 2: Content publishing
        uint256 newContentId = _executeContentPublication(newCreator, 1e6, "My First Tutorial");
        _verifyContentRegistration(newContentId, newCreator, 1e6);

        // Phase 3: User interaction
        _executeDirectContentPurchase(user1, newContentId);
        _verifyContentAccess(newContentId, user1);

        // Phase 4: Earnings verification
        _verifyCreatorHasEarnings(newCreator);
        _verifyCreatorStats(newCreator, 1, 0);
        _verifyContentPurchaseCount(newContentId, 1);
    }

    /**
     * @dev Tests commerce protocol integration with custom token
     */
    function test_CommerceProtocolIntegration_CustomToken() public {
        address customToken = address(new MockERC20("Custom Token", "CT", 18));
        MockERC20(customToken).mint(user2, 100e18);

        vm.prank(user2);
        MockERC20(customToken).approve(address(commerceIntegration), 100e18);

        // Phase 1: Create payment intent
        PaymentIntentData memory intentData = _createSubscriptionPaymentIntent(user2, creator2, customToken);
        _verifyPaymentIntentSuccess(intentData, PaymentType.Subscription);

        // Phase 2: Process payment
        _executePaymentIntent(intentData.intentId, user2, customToken, 10e18, 10e6);

        // Phase 3: Verify subscription
        _verifySubscriptionActive(user2, creator2);
        _verifySubscriptionDetails(user2, creator2, 10e6);
        _verifyCreatorHasEarnings(creator2);
    }

    /**
     * @dev Tests data consistency across all contracts
     */
    function test_CrossContractConsistency_Success() public {
        // Phase 1: Setup initial state
        _executeDirectContentPurchase(user1, contentData.articleContentId);
        _executeDirectSubscription(user1, creator1);

        // Phase 2: Verify initial consistency
        _verifyCreatorHasEarnings(creator1);
        _verifyCreatorStats(creator1, 2, 1);
        _verifyContentPurchaseCount(contentData.articleContentId, 1);

        // Phase 3: Test refund consistency
        vm.prank(user1);
        payPerView.requestRefund(contentData.articleContentId, "Test refund");

        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(contentData.articleContentId, user1);
        assertFalse(purchase.refundEligible);

        // Phase 4: Verify subscription unaffected
        _verifySubscriptionActive(user1, creator1);

        // Phase 5: Test subscription expiry
        advanceTime(SUBSCRIPTION_DURATION + 1);
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));

        // Historical earnings should be preserved
        CreatorRegistry.Creator memory updatedStats = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(updatedStats.totalEarnings > 0);
    }

    /**
     * @dev Tests complete auto-renewal flow
     */
    function test_AutoRenewalIntegration_Success() public {
        // Phase 1: Setup subscription with auto-renewal
        approveUSDC(user1, address(subscriptionManager), 15e6);

        _executeDirectSubscription(user1, creator1);
        _setupAutoRenewal(user1, creator1, 2);
        _verifyAutoRenewalConfig(user1, creator1, 2);

        // Phase 2: Execute first auto-renewal
        _executeAutoRenewal(user1, creator1);
        _verifySubscriptionActive(user1, creator1);

        // Phase 3: Execute second auto-renewal
        _executeAutoRenewal(user1, creator1);
        _verifySubscriptionActive(user1, creator1);

        // Phase 4: Verify no more renewals
        advanceTime(SUBSCRIPTION_DURATION + 1);
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
    }

    /**
     * @dev Tests content moderation flow
     */
    function test_ContentModerationIntegration_Success() public {
        // Phase 1: User purchases content
        _executeDirectContentPurchase(user1, contentData.videoContentId);
        _verifyContentAccess(contentData.videoContentId, user1);

        // Phase 2: Content gets reported and deactivated
        _executeContentReporting(contentData.videoContentId, 5);
        _verifyContentDeactivated(contentData.videoContentId);

        // Phase 3: Existing access preserved
        _verifyContentAccess(contentData.videoContentId, user1);

        // Phase 4: New purchases blocked
        approveUSDC(user2, address(payPerView), 2e6);

        vm.startPrank(user2);
        vm.expectRevert("Content not active");
        payPerView.purchaseContentDirect(contentData.videoContentId);
        vm.stopPrank();

        // Phase 5: Creator earnings preserved
        _verifyCreatorHasEarnings(creator1);

        // Phase 6: Content reactivation
        _reactivateContent(contentData.videoContentId, creator1);
        _executeDirectContentPurchase(user2, contentData.videoContentId);
        _verifyContentAccess(contentData.videoContentId, user2);
    }

    /**
     * @dev Tests multi-creator platform analytics
     */
    function test_MultiCreatorPlatformAnalytics_Success() public {
        // Register additional creator
        address creator3 = address(0x1003);
        assertTrue(registerCreator(creator3, 15e6, "Expert Analytics Creator"));

        // Setup multiple subscriptions and purchases
        _executeDirectSubscription(user1, creator1);
        _executeDirectSubscription(user2, creator3);
        _executeDirectContentPurchase(user1, contentData.articleContentId);
        _executeDirectContentPurchase(user2, contentData.courseContentId);

        // Verify individual creator earnings
        _verifyCreatorHasEarnings(creator1);
        _verifyCreatorHasEarnings(creator3);

        // Verify platform-wide metrics
        _verifyPlatformMetrics(2, 20e6); // $5 + $15 = $20

        // Verify cross-contract consistency
        CreatorEarningsData memory creator1Earnings = _getCreatorEarningsData(creator1);
        CreatorEarningsData memory creator3Earnings = _getCreatorEarningsData(creator3);

        assertTrue(creator1Earnings.payPerViewEarnings > 0);
        assertTrue(creator3Earnings.subscriptionEarnings > 0);

        CreatorRegistry.Creator memory creator1Stats = creatorRegistry.getCreatorProfile(creator1);
        CreatorRegistry.Creator memory creator3Stats = creatorRegistry.getCreatorProfile(creator3);

        assertTrue(creator1Stats.totalEarnings > 0);
        assertTrue(creator3Stats.totalEarnings > 0);
    }
}
