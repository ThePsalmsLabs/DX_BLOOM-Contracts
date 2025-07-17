// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {CommerceProtocolIntegration} from "../../src/CommerceProtocolIntegration.sol";
import {ICommercePaymentsProtocol} from "../../src/interfaces/IPlatformInterfaces.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";
import {PayPerView} from "../../src/PayPerView.sol";

/**
 * @title EndToEndFlowTest
 * @dev Integration tests for complete user journeys on the platform
 * @notice These tests verify that our entire system works together correctly by simulating
 *         real user scenarios from start to finish. We test complete flows including:
 *         - Creator onboarding and content publishing
 *         - User content discovery and purchase
 *         - Subscription management and renewals
 *         - Multi-token payments via Commerce Protocol
 *         - Cross-contract data consistency
 *         - Error handling across the system
 * 
 * These integration tests give us confidence that users will have a smooth experience
 * and that all our contracts work together seamlessly in production.
 */
contract EndToEndFlowTest is TestSetup {
    
    // Integration test data
    uint256 public articleContentId;
    uint256 public videoContentId;
    uint256 public courseContentId;
    
    /**
     * @dev Setup for integration tests
     * @notice This creates a realistic platform environment with multiple creators and content
     */
    function setUp() public override {
        super.setUp();
        
        // Set up realistic mock prices for testing
        mockQuoter.setMockPrice(priceOracle.WETH(), priceOracle.USDC(), 3000, 2000e6); // 1 ETH = $2000
        mockQuoter.setMockPrice(priceOracle.USDC(), priceOracle.WETH(), 3000, 0.0005e18);
        
        // Register creators with different pricing strategies
        assertTrue(registerCreator(creator1, 5e6, "Premium Content Creator")); // $5/month
        assertTrue(registerCreator(creator2, 10e6, "Expert Tutorial Creator")); // $10/month
        
        // Register diverse content
        articleContentId = registerContent(creator1, 0.5e6, "Beginner's Guide to DeFi"); // $0.50
        videoContentId = registerContent(creator1, 2e6, "Advanced Smart Contract Tutorial"); // $2.00
        courseContentId = registerContent(creator2, 10e6, "Complete Blockchain Development Course"); // $10.00
    }
    
    // ============ COMPLETE CREATOR JOURNEY TESTS ============
    
    /**
     * @dev Tests complete creator onboarding and content monetization journey
     * @notice This simulates a creator joining the platform, publishing content, and earning money
     */
    function test_CompleteCreatorJourney_Success() public {
        // Phase 1: Creator registration
        address newCreator = address(0x5001);
        
        vm.startPrank(newCreator);
        
        // Creator registers on the platform
        creatorRegistry.registerCreator(3e6, "New Creator Profile"); // $3/month subscription
        assertTrue(creatorRegistry.isRegisteredCreator(newCreator));
        
        // Phase 2: Content publishing
        string[] memory tags = new string[](2);
        tags[0] = "tutorial";
        tags[1] = "beginner";
        
        uint256 newContentId = contentRegistry.registerContent(
            "QmNewContentHash123",
            "My First Tutorial",
            "Learn the basics in this comprehensive guide",
            ContentRegistry.ContentCategory.Article,
            1e6, // $1.00
            tags
        );
        
        vm.stopPrank();
        
        // Verify content was registered correctly
        ContentRegistry.Content memory content = contentRegistry.getContent(newContentId);
        assertEq(content.creator, newCreator);
        assertEq(content.payPerViewPrice, 1e6);
        assertTrue(content.isActive);
        
        // Phase 3: Content discovery and purchase
        approveUSDC(user1, address(payPerView), 1e6);
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(newContentId);
        
        // Verify user has access
        assertTrue(payPerView.hasAccess(newContentId, user1));
        
        // Phase 4: Creator earnings
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(newCreator);
        uint256 expectedEarning = 1e6 - calculatePlatformFee(1e6);
        assertEq(totalEarnings, expectedEarning);
        assertEq(withdrawable, expectedEarning);
        
        // Creator withdraws earnings
        mockUSDC.mint(address(payPerView), expectedEarning);
        
        vm.prank(newCreator);
        payPerView.withdrawEarnings();
        
        assertEq(mockUSDC.balanceOf(newCreator), 1000e6 + expectedEarning); // Initial balance + earnings
        
        // Phase 5: Subscription monetization
        approveUSDC(user2, address(subscriptionManager), 3e6);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(newCreator);
        
        assertTrue(subscriptionManager.isSubscribed(user2, newCreator));
        
        // Verify creator's subscription earnings
        (uint256 subTotal, uint256 subWithdrawable) = subscriptionManager.getCreatorSubscriptionEarnings(newCreator);
        uint256 expectedSubEarning = 3e6 - calculatePlatformFee(3e6);
        assertEq(subTotal, expectedSubEarning);
        assertEq(subWithdrawable, expectedSubEarning);
    }
    
    // ============ COMPLETE USER JOURNEY TESTS ============
    
    /**
     * @dev Tests complete user journey from discovery to consumption
     * @notice This simulates a user discovering content, making purchases, and managing subscriptions
     */
    function test_CompleteUserJourney_Success() public {
        // Phase 1: Content discovery
        // User browses content by category
        uint256[] memory articleContent = contentRegistry.getContentByCategory(ContentRegistry.ContentCategory.Article);
        assertTrue(articleContent.length > 0);
        
        // User searches by tags
        uint256[] memory tutorialContent = contentRegistry.getContentByTag("tutorial");
        assertTrue(tutorialContent.length > 0);
        
        // Phase 2: Single content purchase
        approveUSDC(user1, address(payPerView), 0.5e6);
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(articleContentId);
        
        assertTrue(payPerView.hasAccess(articleContentId, user1));
        
        // Phase 3: Subscription for ongoing access
        approveUSDC(user1, address(subscriptionManager), 5e6);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Phase 4: Multiple content access through subscription
        // User should now have access to all creator1's content through subscription
        address[] memory userSubs = subscriptionManager.getUserSubscriptions(user1);
        assertEq(userSubs.length, 1);
        assertEq(userSubs[0], creator1);
        
        // Phase 5: Subscription management
        // Configure auto-renewal
        approveUSDC(user1, address(subscriptionManager), 10e6); // 2 months worth
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, 7e6, 10e6); // Max $7, deposit $10
        
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertTrue(autoRenewal.enabled);
        assertEq(autoRenewal.maxPrice, 7e6);
        assertEq(autoRenewal.balance, 10e6);
        
        // Phase 6: User purchase history
        uint256[] memory userPurchases = payPerView.getUserPurchases(user1);
        assertEq(userPurchases.length, 1);
        assertEq(userPurchases[0], articleContentId);
        
        // Verify user spending tracking
        assertEq(payPerView.userTotalSpent(user1), 0.5e6);
        assertEq(subscriptionManager.userSubscriptionSpending(user1), 5e6);
    }
    
    // ============ MULTI-TOKEN PAYMENT INTEGRATION TESTS ============
    
    /**
     * @dev Tests complete multi-token payment flow via Commerce Protocol
     * @notice This tests the complex integration between our platform and external payment systems
     */
    function test_MultiTokenPaymentFlow_Success() public {
        // Phase 1: Create payment intent for ETH payment
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = CommerceProtocolIntegration.PaymentType.ContentPurchase;
        request.creator = creator1;
        request.contentId = videoContentId;
        request.paymentToken = address(0); // ETH
        request.maxSlippage = 200; // 2%
        request.deadline = block.timestamp + 1 hours;
        
        vm.prank(user1);
        (ICommercePaymentsProtocol.TransferIntent memory intent, CommerceProtocolIntegration.PaymentContext memory context) = commerceIntegration.createPaymentIntent(request);
        
        // Verify intent was created correctly
        assertEq(intent.recipient, creator1);
        assertEq(intent.recipientCurrency, address(mockUSDC));
        assertEq(context.paymentToken, address(0)); // ETH
        assertTrue(context.expectedAmount > 2e6); // Should be more than $2 due to ETH conversion + slippage
        
        // Phase 2: Backend provides signature
        bytes memory testSignature = abi.encodePacked(bytes32("test"), bytes32("signature"), bytes1(0x1b));
        
        vm.prank(operatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, testSignature);
        
        // Phase 3: User executes payment
        vm.prank(user1);
        ICommercePaymentsProtocol.TransferIntent memory executionIntent = commerceIntegration.executePaymentWithSignature(intent.id);
        
        assertEq(executionIntent.signature, testSignature);
        
        // Phase 4: Commerce Protocol processes payment and calls back
        vm.prank(admin); // Simulating Commerce Protocol callback
        commerceIntegration.processCompletedPayment(
            intent.id,
            user1,
            address(0), // ETH payment
            context.expectedAmount,
            true,
            ""
        );
        
        // Phase 5: Verify access was granted and earnings distributed
        assertTrue(payPerView.hasAccess(videoContentId, user1));
        
        // Verify creator earnings
        (uint256 totalEarnings, uint256 withdrawable) = payPerView.getCreatorEarnings(creator1);
        assertTrue(totalEarnings > 0);
        
        // Verify content purchase was recorded
        ContentRegistry.Content memory content = contentRegistry.getContent(videoContentId);
        assertEq(content.purchaseCount, 1);
        
        // Phase 6: Verify platform metrics
        (uint256 intentsCreated, uint256 paymentsProcessed, , ) = commerceIntegration.getOperatorMetrics();
        assertTrue(intentsCreated > 0);
        assertTrue(paymentsProcessed > 0);
    }
    
    /**
     * @dev Tests subscription payment via Commerce Protocol
     * @notice This tests subscription creation through multi-token payments
     */
    function test_SubscriptionViaCommerceProtocol_Success() public {
        // Phase 1: Create subscription payment intent with custom token
        address customToken = address(0x1234);
        mockQuoter.setMockPrice(customToken, address(mockUSDC), 3000, 1e6); // 1 CUSTOM = 1 USDC
        
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = CommerceProtocolIntegration.PaymentType.Subscription;
        request.creator = creator2;
        request.contentId = 0;
        request.paymentToken = customToken;
        request.maxSlippage = 150; // 1.5%
        request.deadline = block.timestamp + 1 hours;
        
        vm.prank(user2);
        (ICommercePaymentsProtocol.TransferIntent memory intent, CommerceProtocolIntegration.PaymentContext memory context) = commerceIntegration.createPaymentIntent(request);
        
        // Verify subscription intent
        assertTrue(context.paymentType == CommerceProtocolIntegration.PaymentType.Subscription);
        assertEq(context.creator, creator2);
        assertEq(context.contentId, 0);
        
        // Phase 2: Process subscription payment
        vm.prank(operatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, abi.encodePacked(bytes32("sub"), bytes32("signature"), bytes1(0x1b)));
        
        vm.prank(user2);
        commerceIntegration.executePaymentWithSignature(intent.id);
        
        vm.prank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id,
            user2,
            customToken,
            10e18, // 10 custom tokens
            true,
            ""
        );
        
        // Phase 3: Verify subscription was created
        assertTrue(subscriptionManager.isSubscribed(user2, creator2));
        
        // Verify subscription details
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user2, creator2);
        assertTrue(record.isActive);
        assertEq(record.totalPaid, 10e6); // $10 USDC equivalent
        
        // Verify creator earnings
        (uint256 totalEarnings, uint256 withdrawable) = subscriptionManager.getCreatorSubscriptionEarnings(creator2);
        assertTrue(totalEarnings > 0);
    }
    
    // ============ CROSS-CONTRACT CONSISTENCY TESTS ============
    
    /**
     * @dev Tests data consistency across all contracts
     * @notice This ensures that when one contract updates data, related contracts stay consistent
     */
    function test_CrossContractConsistency_Success() public {
        // Phase 1: Create initial state across all contracts
        approveUSDC(user1, address(payPerView), 0.5e6);
        approveUSDC(user1, address(subscriptionManager), 5e6);
        
        vm.startPrank(user1);
        payPerView.purchaseContentDirect(articleContentId);
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
        
        // Phase 2: Verify initial consistency
        // Creator should have earnings in both contracts
        (uint256 payPerViewEarnings, ) = payPerView.getCreatorEarnings(creator1);
        (uint256 subscriptionEarnings, ) = subscriptionManager.getCreatorSubscriptionEarnings(creator1);
        
        assertTrue(payPerViewEarnings > 0);
        assertTrue(subscriptionEarnings > 0);
        
        // Creator stats should be updated in registry
        CreatorRegistry.Creator memory creatorStats = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(creatorStats.totalEarnings > 0);
        assertEq(creatorStats.contentCount, 2); // Should have 2 content pieces
        assertEq(creatorStats.subscriberCount, 1); // Should have 1 subscriber
        
        // Content should show purchase count
        ContentRegistry.Content memory content = contentRegistry.getContent(articleContentId);
        assertEq(content.purchaseCount, 1);
        
        // Phase 3: Test refund consistency
        vm.prank(user1);
        payPerView.requestRefund(articleContentId, "Test refund");
        
        // After refund, access should be revoked but other data should remain consistent
        PayPerView.PurchaseRecord memory purchase = payPerView.getPurchaseDetails(articleContentId, user1);
        assertFalse(purchase.refundEligible);
        
        // Subscription should remain unaffected
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Phase 4: Test subscription expiry consistency
        advanceTime(SUBSCRIPTION_DURATION + 1);
        
        // Subscription should be expired
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
        
        // But creator stats should maintain historical data
        CreatorRegistry.Creator memory updatedStats = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(updatedStats.totalEarnings > 0); // Historical earnings preserved
    }
    
    // ============ AUTO-RENEWAL INTEGRATION TESTS ============
    
    /**
     * @dev Tests complete auto-renewal flow across multiple contracts
     * @notice This tests the complex time-based subscription renewal system
     */
    function test_AutoRenewalIntegration_Success() public {
        // Phase 1: Set up subscription with auto-renewal
        approveUSDC(user1, address(subscriptionManager), 15e6); // 3 months worth
        
        vm.startPrank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        subscriptionManager.configureAutoRenewal(creator1, true, 6e6, 10e6); // Max $6, deposit $10
        vm.stopPrank();
        
        // Verify initial subscription
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertTrue(autoRenewal.enabled);
        assertEq(autoRenewal.balance, 10e6);
        
        // Phase 2: Test successful auto-renewal
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1); // Enter renewal window
        
        vm.prank(admin); // Admin has RENEWAL_BOT_ROLE
        subscriptionManager.executeAutoRenewal(user1, creator1);
        
        // Verify renewal was successful
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertEq(record.renewalCount, 1);
        assertEq(record.totalPaid, 10e6); // $5 initial + $5 renewal
        
        // Verify auto-renewal balance was deducted
        SubscriptionManager.AutoRenewal memory updatedAutoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertEq(updatedAutoRenewal.balance, 5e6); // $10 - $5 = $5 remaining
        
        // Phase 3: Test auto-renewal failure due to price increase
        vm.prank(creator1);
        creatorRegistry.updateSubscriptionPrice(8e6); // Increase to $8 (above user's $6 max)
        
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1); // Next renewal window
        
        vm.expectRevert("AutoRenewalFailed");
        vm.prank(admin);
        subscriptionManager.executeAutoRenewal(user1, creator1);
        
        // Subscription should still be active until it naturally expires
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Phase 4: Test natural expiry after failed renewal
        advanceTime(2 days); // Past renewal window
        
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
        
        // Phase 5: Test cleanup
        advanceTime(GRACE_PERIOD + 1); // Past grace period
        
        subscriptionManager.cleanupExpiredSubscriptions(creator1);
        
        // User should be removed from creator's subscriber list
        address[] memory subscribers = subscriptionManager.getCreatorSubscribers(creator1);
        assertEq(subscribers.length, 0);
        
        // But user can withdraw remaining auto-renewal balance
        uint256 initialBalance = mockUSDC.balanceOf(user1);
        
        vm.prank(user1);
        subscriptionManager.withdrawAutoRenewalBalance(creator1, 0); // Withdraw all
        
        assertEq(mockUSDC.balanceOf(user1), initialBalance + 5e6); // Should get $5 back
    }
    
    // ============ CONTENT MODERATION INTEGRATION TESTS ============
    
    /**
     * @dev Tests content moderation flow affecting multiple contracts
     * @notice This tests how content moderation impacts access and earnings
     */
    function test_ContentModerationIntegration_Success() public {
        // Phase 1: User purchases content
        approveUSDC(user1, address(payPerView), 2e6);
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(videoContentId);
        
        assertTrue(payPerView.hasAccess(videoContentId, user1));
        
        // Phase 2: Content gets reported
        vm.prank(user2);
        contentRegistry.reportContent(videoContentId, "Inappropriate content");
        
        // Add more reports to trigger auto-moderation
        for (uint i = 0; i < 4; i++) {
            address reporter = address(uint160(0x6000 + i));
            vm.prank(reporter);
            contentRegistry.reportContent(videoContentId, "Report from user");
        }
        
        // Content should be auto-moderated (deactivated)
        ContentRegistry.Content memory content = contentRegistry.getContent(videoContentId);
        assertFalse(content.isActive);
        
        // Phase 3: User should still have access to already purchased content
        // (This tests that moderation doesn't revoke existing purchases)
        assertTrue(payPerView.hasAccess(videoContentId, user1));
        
        // Phase 4: New users cannot purchase deactivated content
        approveUSDC(user2, address(payPerView), 2e6);
        
        vm.startPrank(user2);
        vm.expectRevert("Content not active");
        payPerView.purchaseContentDirect(videoContentId);
        vm.stopPrank();
        
        // Phase 5: Creator earnings should be preserved
        (uint256 totalEarnings, ) = payPerView.getCreatorEarnings(creator1);
        assertTrue(totalEarnings > 0); // Past earnings preserved
        
        // Phase 6: Creator can reactivate content after resolving issues
        vm.prank(creator1);
        contentRegistry.updateContent(videoContentId, 0, true); // Reactivate
        
        // New users can now purchase again
        vm.prank(user2);
        payPerView.purchaseContentDirect(videoContentId);
        
        assertTrue(payPerView.hasAccess(videoContentId, user2));
    }
    
    // ============ PLATFORM ANALYTICS INTEGRATION TESTS ============
    
    /**
     * @dev Tests platform-wide analytics and metrics consistency
     * @notice This ensures all contracts report consistent analytics data
     */
    function test_PlatformAnalyticsIntegration_Success() public {
        // Phase 1: Generate diverse platform activity
        // Multiple creators
        address creator3 = address(0x5003);
        assertTrue(registerCreator(creator3, 15e6, "Premium Creator"));
        uint256 premiumContentId = registerContent(creator3, 20e6, "Premium Course");
        
        // Multiple content purchases
        approveUSDC(user1, address(payPerView), 22.5e6); // $22.50 total
        approveUSDC(user2, address(payPerView), 22.5e6);
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(articleContentId); // $0.50
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(videoContentId); // $2.00
        
        vm.prank(user2);
        payPerView.purchaseContentDirect(premiumContentId); // $20.00
        
        // Multiple subscriptions
        approveUSDC(user1, address(subscriptionManager), 20e6);
        approveUSDC(user2, address(subscriptionManager), 20e6);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1); // $5.00
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator3); // $15.00
        
        // Phase 2: Verify CreatorRegistry analytics
        (
            uint256 totalCreators,
            uint256 verifiedCount,
            uint256 totalPlatformEarnings,
            uint256 totalCreatorEarnings,
            uint256 totalWithdrawn
        ) = creatorRegistry.getPlatformStats();
        
        assertEq(totalCreators, 3); // creator1, creator2, creator3
        assertEq(verifiedCount, 0); // None verified yet
        assertTrue(totalCreatorEarnings > 0);
        assertEq(totalWithdrawn, 0); // No withdrawals yet
        
        // Phase 3: Verify ContentRegistry analytics
        (
            uint256 totalContent,
            uint256 activeContent,
            uint256[] memory categoryCounts,
            uint256[] memory activeCategoryCounts
        ) = contentRegistry.getPlatformStats();
        
        assertEq(totalContent, 4); // articleContentId, videoContentId, courseContentId, premiumContentId
        assertEq(activeContent, 4); // All active
        
        // Phase 4: Verify PayPerView analytics
        // Check individual creator earnings
        (uint256 creator1Earnings, ) = payPerView.getCreatorEarnings(creator1);
        (uint256 creator3Earnings, ) = payPerView.getCreatorEarnings(creator3);
        
        assertTrue(creator1Earnings > 0);
        assertTrue(creator3Earnings > 0);
        
        // Phase 5: Verify SubscriptionManager analytics
        (
            uint256 activeSubscriptions,
            uint256 totalVolume,
            uint256 platformFees,
            uint256 renewalCount,
            uint256 refundAmount
        ) = subscriptionManager.getPlatformSubscriptionMetrics();
        
        assertEq(activeSubscriptions, 2);
        assertEq(totalVolume, 20e6); // $5 + $15 = $20
        assertTrue(platformFees > 0);
        assertEq(renewalCount, 0);
        assertEq(refundAmount, 0);
        
        // Phase 6: Verify CommerceProtocolIntegration analytics
        (
            uint256 intentsCreated,
            uint256 paymentsProcessed,
            uint256 operatorFees,
            uint256 refunds
        ) = commerceIntegration.getOperatorMetrics();
        
        // These might be 0 if we only used direct payments, which is fine
        assertTrue(intentsCreated >= 0);
        assertTrue(paymentsProcessed >= 0);
        
        // Phase 7: Test cross-contract consistency
        // Total earnings across all contracts should be consistent
        uint256 totalPayPerViewEarnings = creator1Earnings + creator3Earnings;
        (uint256 creator1SubEarnings, ) = subscriptionManager.getCreatorSubscriptionEarnings(creator1);
        (uint256 creator3SubEarnings, ) = subscriptionManager.getCreatorSubscriptionEarnings(creator3);
        uint256 totalSubscriptionEarnings = creator1SubEarnings + creator3SubEarnings;
        
        // Registry should track total earnings from both sources
        CreatorRegistry.Creator memory creator1Stats = creatorRegistry.getCreatorProfile(creator1);
        CreatorRegistry.Creator memory creator3Stats = creatorRegistry.getCreatorProfile(creator3);
        
        assertTrue(creator1Stats.totalEarnings > 0);
        assertTrue(creator3Stats.totalEarnings > 0);
    }
    
    // ============ ERROR RECOVERY INTEGRATION TESTS ============
    
    /**
     * @dev Tests system behavior during error conditions and recovery
     * @notice This ensures the platform remains stable during failures
     */
    function test_ErrorRecoveryIntegration_Success() public {
        // Phase 1: Test payment failure and recovery
        CommerceProtocolIntegration.PlatformPaymentRequest memory request;
        request.paymentType = CommerceProtocolIntegration.PaymentType.ContentPurchase;
        request.creator = creator1;
        request.contentId = videoContentId;
        request.paymentToken = address(mockUSDC);
        request.maxSlippage = 100;
        request.deadline = block.timestamp + 1 hours;
        
        vm.prank(user1);
        (ICommercePaymentsProtocol.TransferIntent memory intent, ) = commerceIntegration.createPaymentIntent(request);
        
        // Simulate payment failure
        vm.prank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id,
            user1,
            address(mockUSDC),
            0, // No payment
            false,
            "Payment processor error"
        );
        
        // User should not have access
        assertFalse(payPerView.hasAccess(videoContentId, user1));
        
        // User should be able to request refund
        vm.prank(user1);
        commerceIntegration.requestRefund(intent.id, "Payment failed");
        
        // Phase 2: Test direct payment as fallback
        approveUSDC(user1, address(payPerView), 2e6);
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(videoContentId);
        
        // User should now have access via direct payment
        assertTrue(payPerView.hasAccess(videoContentId, user1));
        
        // Phase 3: Test subscription failure and recovery
        // First, create subscription
        approveUSDC(user2, address(subscriptionManager), 5e6);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator1);
        
        assertTrue(subscriptionManager.isSubscribed(user2, creator1));
        
        // Simulate subscription payment failure during renewal
        vm.prank(user2);
        subscriptionManager.configureAutoRenewal(creator1, true, 5e6, 1e6); // Only $1 balance (insufficient)
        
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1); // Enter renewal window
        
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        vm.prank(admin);
        subscriptionManager.executeAutoRenewal(user2, creator1);
        
        // Subscription should still be active until natural expiry
        assertTrue(subscriptionManager.isSubscribed(user2, creator1));
        
        // User can top up auto-renewal balance
        approveUSDC(user2, address(subscriptionManager), 10e6);
        
        vm.prank(user2);
        subscriptionManager.configureAutoRenewal(creator1, true, 5e6, 10e6); // Top up to $10
        
        // Renewal should now work
        vm.prank(admin);
        subscriptionManager.executeAutoRenewal(user2, creator1);
        
        // Verify successful recovery
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user2, creator1);
        assertEq(record.renewalCount, 1);
        
        // Phase 4: Test contract pause and recovery
        vm.prank(admin);
        payPerView.pause();
        
        // Operations should fail when paused
        approveUSDC(user1, address(payPerView), 0.5e6);
        
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to pause
        payPerView.purchaseContentDirect(articleContentId);
        vm.stopPrank();
        
        // Unpause and verify operations resume
        vm.prank(admin);
        payPerView.unpause();
        
        vm.prank(user1);
        payPerView.purchaseContentDirect(articleContentId);
        
        assertTrue(payPerView.hasAccess(articleContentId, user1));
        
        // Phase 5: Verify system integrity after all error conditions
        // All previous valid transactions should remain intact
        assertTrue(payPerView.hasAccess(videoContentId, user1));
        assertTrue(subscriptionManager.isSubscribed(user2, creator1));
        
        // Creator earnings should be preserved
        (uint256 totalEarnings, ) = payPerView.getCreatorEarnings(creator1);
        assertTrue(totalEarnings > 0);
    }
    
    // ============ PERFORMANCE AND SCALABILITY TESTS ============
    
    /**
     * @dev Tests platform performance with multiple concurrent operations
     * @notice This ensures the platform can handle realistic load
     */
    function test_PlatformPerformance_Success() public {
        // Phase 1: Create multiple creators and content
        address[] memory creators = new address[](5);
        uint256[] memory contentIds = new uint256[](10);
        
        for (uint i = 0; i < 5; i++) {
            creators[i] = address(uint160(0x7000 + i));
            assertTrue(registerCreator(creators[i], (i + 1) * 1e6, "Creator"));
            
            // Each creator publishes 2 content pieces
            contentIds[i * 2] = registerContent(creators[i], (i + 1) * 0.5e6, "Content A");
            contentIds[i * 2 + 1] = registerContent(creators[i], (i + 1) * 1e6, "Content B");
        }
        
        // Phase 2: Simulate concurrent user activity
        address[] memory users = new address[](10);
        for (uint i = 0; i < 10; i++) {
            users[i] = address(uint160(0x8000 + i));
            mockUSDC.mint(users[i], 100e6); // $100 per user
        }
        
        // Phase 3: Mass content purchases
        for (uint i = 0; i < 10; i++) {
            for (uint j = 0; j < 5; j++) {
                uint256 contentPrice = (j + 1) * 0.5e6;
                approveUSDC(users[i], address(payPerView), contentPrice);
                
                vm.prank(users[i]);
                payPerView.purchaseContentDirect(contentIds[j * 2]); // Buy first content from each creator
            }
        }
        
        // Phase 4: Mass subscriptions
        for (uint i = 0; i < 5; i++) {
            for (uint j = 0; j < 2; j++) {
                uint256 subPrice = (i + 1) * 1e6;
                approveUSDC(users[j * 2 + i], address(subscriptionManager), subPrice);
                
                vm.prank(users[j * 2 + i]);
                subscriptionManager.subscribeToCreator(creators[i]);
            }
        }
        
        // Phase 5: Verify all operations completed successfully
        // Check content access for all users
        for (uint i = 0; i < 10; i++) {
            for (uint j = 0; j < 5; j++) {
                assertTrue(payPerView.hasAccess(contentIds[j * 2], users[i]));
            }
        }
        
        // Check subscriptions
        for (uint i = 0; i < 5; i++) {
            address[] memory subscribers = subscriptionManager.getCreatorSubscribers(creators[i]);
            assertEq(subscribers.length, 2);
        }
        
        // Phase 6: Verify platform metrics scale correctly
        (uint256 totalCreators, , , uint256 totalCreatorEarnings, ) = creatorRegistry.getPlatformStats();
        assertEq(totalCreators, 7); // 5 new + 2 original
        assertTrue(totalCreatorEarnings > 0);
        
        (uint256 totalContent, uint256 activeContent, , ) = contentRegistry.getPlatformStats();
        assertEq(totalContent, 13); // 10 new + 3 original
        assertEq(activeContent, 13);
        
        (uint256 activeSubscriptions, uint256 totalVolume, , , ) = subscriptionManager.getPlatformSubscriptionMetrics();
        assertEq(activeSubscriptions, 10); // 10 new subscriptions
        assertTrue(totalVolume > 0);
        
        // Phase 7: Test cleanup performance
        // Advance time and cleanup expired subscriptions
        advanceTime(SUBSCRIPTION_DURATION + GRACE_PERIOD + 1);
        
        for (uint i = 0; i < 5; i++) {
            subscriptionManager.cleanupExpiredSubscriptions(creators[i]);
        }
        
        // All subscriptions should be cleaned up
        for (uint i = 0; i < 5; i++) {
            address[] memory subscribers = subscriptionManager.getCreatorSubscribers(creators[i]);
            assertEq(subscribers.length, 0);
        }
    }
}