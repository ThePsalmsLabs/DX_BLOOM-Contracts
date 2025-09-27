// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../helpers/TestSetup.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";
import { SubscriptionManager } from "../../src/SubscriptionManager.sol";

/**
 * @title UserJourneyIntegrationTest
 * @dev End-to-end user journey testing for complete workflows
 * @notice Tests realistic user scenarios from start to finish
 */
contract UserJourneyIntegrationTest is TestSetup {
    using stdStorage for StdStorage;

    // Test users
    address public alice = address(0x1001); // Regular user
    address public bob = address(0x1002);   // Creator
    address public charlie = address(0x1003); // Another user
    address public david = address(0x1004); // Another creator

    // Content IDs
    uint256 public articleId;
    uint256 public videoId;
    uint256 public audioId;

    function setUp() public override {
        super.setUp();

        // Set up user balances
        mockUSDC.mint(alice, 10000e6); // $10,000
        mockUSDC.mint(charlie, 5000e6); // $5,000
        vm.deal(alice, 10 ether);
        vm.deal(charlie, 10 ether);

        // Register creators
        vm.prank(bob);
        creatorRegistry.registerCreator(1e6, "QmBobProfile"); // $1/month subscription

        vm.prank(david);
        creatorRegistry.registerCreator(2e6, "QmDavidProfile"); // $2/month subscription

        // Create content
        vm.prank(bob);
        articleId = contentRegistry.registerContent(
            "QmBobArticle",
            "Understanding DeFi",
            "Comprehensive guide to decentralized finance",
            ISharedTypes.ContentCategory.Article,
            0.1e6, // $0.10
            new string[](0)
        );

        vm.prank(bob);
        videoId = contentRegistry.registerContent(
            "QmBobVideo",
            "DeFi Tutorial Video",
            "Step-by-step video tutorial",
            ISharedTypes.ContentCategory.Video,
            0.25e6, // $0.25
            new string[](0)
        );

        vm.prank(david);
        audioId = contentRegistry.registerContent(
            "QmDavidAudio",
            "DeFi Podcast",
            "Weekly podcast episode",
            ISharedTypes.ContentCategory.Music,
            0.15e6, // $0.15
            new string[](0)
        );
    }

    // ============ ALICE'S JOURNEY: DISCOVERY TO SUBSCRIPTION ============

    function test_AliceDiscoveryToSubscriptionJourney() public {
        uint256 initialBalance = mockUSDC.balanceOf(alice);

        // Alice discovers Bob's content
        // Note: View recording not implemented in current version

        // Step 2: Alice subscribes to Bob for ongoing access
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: bob,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "alice-subscription");

        vm.prank(alice);
        bool subSuccess = commerceProtocolCore.executePaymentWithSignature(subIntentId);

        assertTrue(subSuccess);
        assertTrue(subscriptionManager.isSubscribed(alice, bob));

        // Step 3: Alice now has access to all Bob's content
        assertTrue(payPerView.hasAccess(articleId, alice));
        assertTrue(payPerView.hasAccess(videoId, alice));

        // Note: View recording not implemented in current version

        // Verify Alice paid for subscription
        assertTrue(mockUSDC.balanceOf(alice) < initialBalance);

        // Verify Bob received earnings
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        assertTrue(bobEarnings > 0);
    }

    // ============ CHARLIE'S JOURNEY: PAY-PER-VIEW USER ============

    function test_CharliePayPerViewJourney() public {
        uint256 initialBalance = mockUSDC.balanceOf(charlie);
        uint256[] memory contentIds = new uint256[](3);
        contentIds[0] = articleId;
        contentIds[1] = videoId;
        contentIds[2] = audioId;

        // Charlie discovers multiple creators
        // Step 1: Charlie reads Bob's article
        ISharedTypes.PlatformPaymentRequest memory articleRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: articleId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 articleIntentId,) = commerceProtocolCore.createPaymentIntent(articleRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(articleIntentId, "charlie-article");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(articleIntentId);

        // Step 2: Charlie watches David's podcast
        ISharedTypes.PlatformPaymentRequest memory audioRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: david,
            contentId: audioId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 audioIntentId,) = commerceProtocolCore.createPaymentIntent(audioRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(audioIntentId, "charlie-audio");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(audioIntentId);

        // Step 3: Charlie watches Bob's video
        ISharedTypes.PlatformPaymentRequest memory videoRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: videoId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 videoIntentId,) = commerceProtocolCore.createPaymentIntent(videoRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(videoIntentId, "charlie-video");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(videoIntentId);

        // Verify Charlie has access to all purchased content
        assertTrue(payPerView.hasAccess(articleId, charlie));
        assertTrue(payPerView.hasAccess(videoId, charlie));
        assertTrue(payPerView.hasAccess(audioId, charlie));

        // Verify Charlie paid for 3 pieces of content
        uint256 finalBalance = mockUSDC.balanceOf(charlie);
        assertTrue(finalBalance < initialBalance);

        // Verify creators received earnings
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        (uint256 davidEarnings,,) = creatorRegistry.getCreatorEarnings(david);

        assertTrue(bobEarnings > 0); // Bob got paid for article + video
        assertTrue(davidEarnings > 0); // David got paid for audio
    }

    // ============ CREATOR JOURNEY: CONTENT CREATION TO EARNINGS ============

    function test_CreatorContentCreationJourney() public {
        // Bob's journey as a creator
        // Step 1: Register as creator
        vm.prank(bob);
        creatorRegistry.registerCreator(1e6, "QmBobProfile");

        // Verify creator registration
        assertTrue(creatorRegistry.isRegisteredCreator(bob));

        // Step 2: Create multiple content pieces
        vm.prank(bob);
        uint256 tutorialId = contentRegistry.registerContent(
            "QmBobTutorial",
            "Solidity Tutorial",
            "Learn Solidity programming",
            ISharedTypes.ContentCategory.Video,
            0.2e6, // $0.20
            new string[](0)
        );

        vm.prank(bob);
        uint256 blogId = contentRegistry.registerContent(
            "QmBobBlog",
            "Web3 Development Blog",
            "Weekly development updates",
            ISharedTypes.ContentCategory.Article,
            0.05e6, // $0.05
            new string[](0)
        );

        // Step 3: Update profile
        vm.prank(bob);
        creatorRegistry.updateProfileData("QmBobUpdatedProfile");

        // Step 4: Get subscribers (Alice subscribes)
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: bob,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "alice-subscribes-bob");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Step 5: Charlie buys content
        ISharedTypes.PlatformPaymentRequest memory purchaseRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: tutorialId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 purchaseIntentId,) = commerceProtocolCore.createPaymentIntent(purchaseRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(purchaseIntentId, "charlie-buys-tutorial");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(purchaseIntentId);

        // Step 6: Creator withdraws earnings
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(bob);
        assertTrue(pending > 0);

        uint256 initialCreatorBalance = mockUSDC.balanceOf(bob);
        vm.prank(bob);
        creatorRegistry.withdrawCreatorEarnings();

        uint256 finalCreatorBalance = mockUSDC.balanceOf(bob);
        assertTrue(finalCreatorBalance > initialCreatorBalance);
    }

    // ============ MULTI-USER ECOSYSTEM JOURNEY ============

    function test_MultiUserEcosystemJourney() public {
        // Complex scenario with multiple users interacting
        address eve = address(0x1005); // Another user
        mockUSDC.mint(eve, 3000e6);
        vm.deal(eve, 10 ether);

        // Step 1: Alice subscribes to Bob
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: bob,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "alice-sub-bob");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Step 2: Charlie buys David's audio
        ISharedTypes.PlatformPaymentRequest memory audioRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: david,
            contentId: audioId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 audioIntentId,) = commerceProtocolCore.createPaymentIntent(audioRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(audioIntentId, "charlie-buys-audio");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(audioIntentId);

        // Step 3: Eve subscribes to David
        vm.prank(eve);
        (bytes16 eveSubIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(eveSubIntentId, "eve-sub-david");

        vm.prank(eve);
        commerceProtocolCore.executePaymentWithSignature(eveSubIntentId);

        // Step 4: Eve also buys Bob's video
        ISharedTypes.PlatformPaymentRequest memory videoRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: videoId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(eve);
        (bytes16 videoIntentId,) = commerceProtocolCore.createPaymentIntent(videoRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(videoIntentId, "eve-buys-video");

        vm.prank(eve);
        commerceProtocolCore.executePaymentWithSignature(videoIntentId);

        // Step 5: Verify all subscriptions and access
        assertTrue(subscriptionManager.isSubscribed(alice, bob)); // Alice subscribes to Bob
        assertTrue(subscriptionManager.isSubscribed(eve, david)); // Eve subscribes to David
        assertTrue(payPerView.hasAccess(audioId, charlie)); // Charlie bought audio
        assertTrue(payPerView.hasAccess(videoId, eve)); // Eve bought video

        // Step 6: Verify creator stats
        CreatorRegistry.Creator memory bobProfile = creatorRegistry.getCreatorProfile(bob);
        CreatorRegistry.Creator memory davidProfile = creatorRegistry.getCreatorProfile(david);

        assertEq(bobProfile.subscriberCount, 1); // Alice
        assertEq(davidProfile.subscriberCount, 1); // Eve

        // Step 7: Verify earnings distribution
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        (uint256 davidEarnings,,) = creatorRegistry.getCreatorEarnings(david);

        assertTrue(bobEarnings > 0); // Bob got subscription + video sale
        assertTrue(davidEarnings > 0); // David got subscription + audio sale
    }

    // ============ ERROR HANDLING JOURNEY ============

    function test_ErrorHandlingJourney() public {
        // Test various error scenarios in user journey
        uint256 initialBalance = mockUSDC.balanceOf(alice);

        // Step 1: Alice tries to pay with insufficient balance
        vm.prank(alice);
        mockUSDC.transfer(address(0x9999), 9999e6); // Drain almost all balance

        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: articleId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "insufficient-balance");

        vm.prank(alice);
        bool paymentSuccess = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertFalse(paymentSuccess); // Should fail

        // Step 2: Request refund
        vm.prank(alice);
        commerceProtocolCore.requestRefund(intentId, "Insufficient balance - refund requested");

        // Step 3: Process refund (after funding)
        mockUSDC.mint(address(refundManager), 1000e6);
        vm.prank(paymentMonitor);
        commerceProtocolCore.processRefund(intentId);

        // Verify refund processed
        (bytes16 originalIntentId, address userAddr, uint256 amount, string memory reason, uint256 requestTime, bool processed) = refundManager.refundRequests(intentId);
        assertTrue(processed);

        // Step 4: Alice adds funds and tries again
        mockUSDC.mint(alice, 100e6);

        vm.prank(alice);
        (bytes16 retryIntentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(retryIntentId, "retry-payment");

        vm.prank(alice);
        bool retrySuccess = commerceProtocolCore.executePaymentWithSignature(retryIntentId);

        assertTrue(retrySuccess); // Should succeed now

        // Verify Alice has access
        assertTrue(payPerView.hasAccess(articleId, alice));
    }

    // ============ SUBSCRIPTION MANAGEMENT JOURNEY ============

    function test_SubscriptionManagementJourney() public {
        // Alice's subscription management journey
        // Step 1: Subscribe to Bob
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: bob,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "alice-sub-bob");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        assertTrue(subscriptionManager.isSubscribed(alice, bob));

        // Note: View recording not implemented in current version

        // Step 3: Subscription auto-renews (simulate)
        vm.warp(block.timestamp + 30 days);

        // Simulate renewal payment
        vm.prank(alice);
        (bytes16 renewalIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(renewalIntentId, "renewal-payment");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(renewalIntentId);

        // Verify subscription still active
        assertTrue(subscriptionManager.isSubscribed(alice, bob));

        // Step 4: Cancel subscription (if implemented)
        // This would be tested if cancellation functionality exists
    }

    // ============ PERFORMANCE JOURNEY TESTING ============

    function test_UserJourneyPerformance() public {
        // Measure performance for realistic user journey
        uint256 gasStart = gasleft();

        // Alice's complete journey
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: bob,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "performance-test");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(intentId);

        uint256 gasEnd = gasleft();
        uint256 journeyGas = gasStart - gasEnd;

        // Assert reasonable gas for complete journey
        assertTrue(journeyGas < 300000, "User journey gas usage too high");

        // Verify journey completed successfully
        assertTrue(subscriptionManager.isSubscribed(alice, bob));
        assertTrue(payPerView.hasAccess(articleId, alice));
    }
}
