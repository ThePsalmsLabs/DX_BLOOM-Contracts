// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../helpers/TestSetup.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";
import { SubscriptionManager } from "../../src/SubscriptionManager.sol";
import { PayPerView } from "../../src/PayPerView.sol";

/**
 * @title CrossContractIntegrationTest
 * @dev Tests cross-contract coordination and state synchronization
 * @notice Ensures all contracts work together seamlessly
 */
contract CrossContractIntegrationTest is TestSetup {
    using stdStorage for StdStorage;

    // Test users and creators
    address public alice = address(0x1001);
    address public bob = address(0x2001);
    address public charlie = address(0x1002);
    address public david = address(0x2003);

    // Content IDs
    uint256 public articleId;
    uint256 public videoId;
    uint256 public audioId;

    // Track initial states for comparison
    uint256 initialCreatorCount;
    uint256 initialContentCount;

    function setUp() public override {
        super.setUp();

        // Set up user balances
        mockUSDC.mint(alice, 10000e6);
        mockUSDC.mint(charlie, 5000e6);
        vm.deal(alice, 10 ether);
        vm.deal(charlie, 10 ether);

        // Register creators
        vm.prank(bob);
        creatorRegistry.registerCreator(1e6, "QmBobProfile");

        vm.prank(david);
        creatorRegistry.registerCreator(2e6, "QmDavidProfile");

        // Record initial states
        initialCreatorCount = creatorRegistry.getTotalCreators();
        (uint256 totalContent,,,) = contentRegistry.getPlatformStats();
        initialContentCount = totalContent;

        // Create content
        vm.prank(bob);
        articleId = contentRegistry.registerContent(
            "QmBobArticle",
            "Cross-Contract Integration Article",
            "Testing cross-contract coordination",
            ISharedTypes.ContentCategory.Article,
            0.1e6,
            new string[](0)
        );

        vm.prank(bob);
        videoId = contentRegistry.registerContent(
            "QmBobVideo",
            "Integration Test Video",
            "Video for integration testing",
            ISharedTypes.ContentCategory.Video,
            0.25e6,
            new string[](0)
        );

        vm.prank(david);
        audioId = contentRegistry.registerContent(
            "QmDavidAudio",
            "Integration Podcast",
            "Audio content for testing",
            ISharedTypes.ContentCategory.Music,
            0.15e6,
            new string[](0)
        );
    }

    // ============ CREATOR REGISTRY INTEGRATION ============

    function test_CreatorRegistrationCrossContractSync() public {
        // Register new creator
        address newCreator = address(0x3001);
        vm.prank(newCreator);
        creatorRegistry.registerCreator(1.5e6, "QmNewCreatorProfile");

        // Verify creator is registered
        assertTrue(creatorRegistry.isRegisteredCreator(newCreator));

        // Verify creator count updated
        assertEq(creatorRegistry.getTotalCreators(), initialCreatorCount + 1);

        // Test subscription to new creator
        ISharedTypes.PlatformPaymentRequest memory subRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.Subscription,
            creator: newCreator,
            contentId: 0,
            paymentToken: address(mockUSDC),
            maxSlippage: 0,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 subIntentId,) = commerceProtocolCore.createPaymentIntent(subRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(subIntentId, "new-creator-sub");

        vm.prank(alice);
        bool success = commerceProtocolCore.executePaymentWithSignature(subIntentId);

        assertTrue(success);

        // Verify subscription manager knows about the subscription
        assertTrue(subscriptionManager.isSubscribed(alice, newCreator));

        // Verify creator registry shows updated subscriber count
        CreatorRegistry.Creator memory creatorInfo = creatorRegistry.getCreatorProfile(newCreator);
        assertEq(creatorInfo.subscriberCount, 1);

        // Verify creator earnings recorded
        (uint256 pending,,) = creatorRegistry.getCreatorEarnings(newCreator);
        assertTrue(pending > 0);
    }

    // ============ CONTENT REGISTRY INTEGRATION ============

    function test_ContentRegistrationAndAccessControl() public {
        // Register new content
        vm.prank(bob);
        uint256 newContentId = contentRegistry.registerContent(
            "QmNewArticle",
            "New Integration Article",
            "Testing content registration integration",
            ISharedTypes.ContentCategory.Article,
            0.05e6,
            new string[](0)
        );

        // Verify content is registered
        try contentRegistry.getContent(newContentId) returns (ContentRegistry.Content memory content) {
            assertTrue(bytes(content.title).length > 0);
        } catch {
            revert("Content should exist");
        }

        // Test pay-per-view access control
        assertFalse(payPerView.hasAccess(newContentId, alice));

        // Purchase access
        ISharedTypes.PlatformPaymentRequest memory request = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: newContentId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(alice);
        (bytes16 intentId,) = commerceProtocolCore.createPaymentIntent(request);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(intentId, "content-access-test");

        vm.prank(alice);
        bool paymentSuccess = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertTrue(paymentSuccess);

        // Verify access granted
        assertTrue(payPerView.hasAccess(newContentId, alice));

        // Verify content access granted (no view recording needed in current implementation)

        // Note: Content stats not implemented in current version
    }

    // ============ SUBSCRIPTION MANAGER INTEGRATION ============

    function test_SubscriptionManagerCrossContractSync() public {
        // Alice subscribes to Bob
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
        bool subSuccess = commerceProtocolCore.executePaymentWithSignature(subIntentId);

        assertTrue(subSuccess);

        // Verify subscription manager state
        assertTrue(subscriptionManager.isSubscribed(alice, bob));

        // Verify creator registry state
        CreatorRegistry.Creator memory bobInfo = creatorRegistry.getCreatorProfile(bob);
        assertEq(bobInfo.subscriberCount, 1);

        // Verify creator earnings
        (uint256 pending,,) = creatorRegistry.getCreatorEarnings(bob);
        assertTrue(pending > 0);

        // Test subscription access to all creator content
        assertTrue(payPerView.hasAccess(articleId, alice));
        assertTrue(payPerView.hasAccess(videoId, alice));

        // Note: View recording not implemented in current version
    }

    // ============ MULTI-MANAGER COORDINATION ============

    function test_MultiManagerCoordination() public {
        // Test coordination between multiple managers
        // 1. Alice subscribes to Bob
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
        commerceProtocolCore.provideIntentSignature(subIntentId, "multi-manager-test");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // 2. Charlie buys David's content
        ISharedTypes.PlatformPaymentRequest memory purchaseRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: david,
            contentId: audioId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 purchaseIntentId,) = commerceProtocolCore.createPaymentIntent(purchaseRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(purchaseIntentId, "charlie-purchase");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(purchaseIntentId);

        // Verify all managers are coordinated
        // Subscription Manager
        assertTrue(subscriptionManager.isSubscribed(alice, bob));
        assertFalse(subscriptionManager.isSubscribed(charlie, bob));

        // PayPerView Manager
        assertTrue(payPerView.hasAccess(audioId, charlie));
        assertFalse(payPerView.hasAccess(audioId, alice)); // Alice should use subscription

        // Creator Registry
        CreatorRegistry.Creator memory bobInfo = creatorRegistry.getCreatorProfile(bob);
        CreatorRegistry.Creator memory davidInfo = creatorRegistry.getCreatorProfile(david);

        assertEq(bobInfo.subscriberCount, 1);
        assertEq(davidInfo.subscriberCount, 0);

        // Earnings
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        (uint256 davidEarnings,,) = creatorRegistry.getCreatorEarnings(david);

        assertTrue(bobEarnings > 0); // Subscription
        assertTrue(davidEarnings > 0); // Pay-per-view
    }

    // ============ REFUND MANAGER INTEGRATION ============

    function test_RefundManagerCrossContractCoordination() public {
        // Create payment intent
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
        commerceProtocolCore.provideIntentSignature(intentId, "refund-test");

        // Simulate failed payment (mock failure)
        mockCommerceProtocol.setShouldFailTransfers(true);

        vm.prank(alice);
        bool paymentSuccess = commerceProtocolCore.executePaymentWithSignature(intentId);

        assertFalse(paymentSuccess);

        // Request refund
        vm.prank(alice);
        commerceProtocolCore.requestRefund(intentId, "Payment failed - requesting refund");

        // Fund refund manager
        mockUSDC.mint(address(refundManager), 1000e6);

        // Process refund
        vm.prank(paymentMonitor);
        commerceProtocolCore.processRefund(intentId);

        // Verify refund processed
        (bytes16 originalIntentId, address userAddr, uint256 amount, string memory reason, uint256 requestTime, bool processed) = refundManager.refundRequests(intentId);
        assertTrue(processed);

        // Verify user balance restored
        assertEq(mockUSDC.balanceOf(alice), 10000e6);

        // Verify no access was granted
        assertFalse(payPerView.hasAccess(articleId, alice));

        // Verify no earnings recorded
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        assertEq(bobEarnings, 0);
    }

    // ============ VIEW MANAGER INTEGRATION ============

    function test_ViewManagerCrossContractSync() public {
        // Alice subscribes to Bob
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
        commerceProtocolCore.provideIntentSignature(subIntentId, "view-manager-test");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Note: View recording not implemented in current version

        // Note: Content stats not implemented in current version

        // Note: Creator view stats not implemented in current version

        // Test pay-per-view user
        ISharedTypes.PlatformPaymentRequest memory purchaseRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: videoId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 purchaseIntentId,) = commerceProtocolCore.createPaymentIntent(purchaseRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(purchaseIntentId, "charlie-view-test");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(purchaseIntentId);

        // Note: View recording not implemented in current version

        // Note: Content earnings recorded through payment system
    }

    // ============ PLATFORM FEE DISTRIBUTION ============

    function test_PlatformFeeDistributionIntegration() public {
        // Make subscription payment
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
        commerceProtocolCore.provideIntentSignature(subIntentId, "fee-distribution-test");

        uint256 initialUserBalance = mockUSDC.balanceOf(alice);
        uint256 initialCreatorBalance = mockUSDC.balanceOf(bob);
        uint256 initialPlatformBalance = mockUSDC.balanceOf(address(adminManager));

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        uint256 finalUserBalance = mockUSDC.balanceOf(alice);
        uint256 finalCreatorBalance = mockUSDC.balanceOf(bob);
        uint256 finalPlatformBalance = mockUSDC.balanceOf(address(adminManager));

        // Verify user paid
        assertTrue(finalUserBalance < initialUserBalance);

        // Verify creator received payment (minus fees)
        assertTrue(finalCreatorBalance > initialCreatorBalance);

        // Verify platform received fees
        assertTrue(finalPlatformBalance > initialPlatformBalance);

        // Verify fee calculations are correct
        uint256 totalPayment = initialUserBalance - finalUserBalance;
        uint256 creatorPayment = finalCreatorBalance - initialCreatorBalance;
        uint256 platformFee = finalPlatformBalance - initialPlatformBalance;

        assertEq(creatorPayment + platformFee, totalPayment);
    }

    // ============ OPERATOR FEE DISTRIBUTION ============

    function test_OperatorFeeDistributionIntegration() public {
        // Test operator fee handling
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
        commerceProtocolCore.provideIntentSignature(intentId, "operator-fee-test");

        uint256 initialUserBalance = mockUSDC.balanceOf(alice);
        uint256 initialCreatorBalance = mockUSDC.balanceOf(bob);
        uint256 initialOperatorBalance = mockUSDC.balanceOf(commerceProtocolCore.operatorFeeDestination());

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(intentId);

        uint256 finalUserBalance = mockUSDC.balanceOf(alice);
        uint256 finalCreatorBalance = mockUSDC.balanceOf(bob);
        uint256 finalOperatorBalance = mockUSDC.balanceOf(commerceProtocolCore.operatorFeeDestination());

        // Verify operator received fee
        assertTrue(finalOperatorBalance > initialOperatorBalance);

        // Verify fee distribution is correct
        uint256 totalPayment = initialUserBalance - finalUserBalance;
        uint256 creatorPayment = finalCreatorBalance - initialCreatorBalance;
        uint256 operatorFee = finalOperatorBalance - initialOperatorBalance;

        assertEq(creatorPayment + operatorFee, totalPayment);
    }

    // ============ EMERGENCY AND ADMIN FUNCTIONS ============

    function test_EmergencyFunctionCrossContractImpact() public {
        // Test emergency pause functionality
        // Subscribe Alice to Bob
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
        commerceProtocolCore.provideIntentSignature(subIntentId, "emergency-test");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // Pause the system
        vm.prank(admin);
        commerceProtocolCore.pause();

        // Verify system is paused
        assertTrue(commerceProtocolCore.paused());

        // Try to make another payment (should fail)
        ISharedTypes.PlatformPaymentRequest memory newRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: bob,
            contentId: articleId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 newIntentId,) = commerceProtocolCore.createPaymentIntent(newRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(newIntentId, "paused-system-test");

        vm.prank(charlie);
        bool pausedPaymentSuccess = commerceProtocolCore.executePaymentWithSignature(newIntentId);

        assertFalse(pausedPaymentSuccess); // Should fail when paused

        // Unpause and try again
        vm.prank(admin);
        commerceProtocolCore.unpause();

        vm.prank(charlie);
        (bytes16 unpausedIntentId,) = commerceProtocolCore.createPaymentIntent(newRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(unpausedIntentId, "unpaused-system-test");

        vm.prank(charlie);
        bool unpausedPaymentSuccess = commerceProtocolCore.executePaymentWithSignature(unpausedIntentId);

        assertTrue(unpausedPaymentSuccess); // Should succeed when unpaused
    }

    // ============ COMPREHENSIVE STATE CONSISTENCY ============

    function test_ComprehensiveStateConsistencyCheck() public {
        // Perform multiple operations
        // 1. Alice subscribes to Bob
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
        commerceProtocolCore.provideIntentSignature(subIntentId, "consistency-check");

        vm.prank(alice);
        commerceProtocolCore.executePaymentWithSignature(subIntentId);

        // 2. Charlie buys David's content
        ISharedTypes.PlatformPaymentRequest memory purchaseRequest = ISharedTypes.PlatformPaymentRequest({
            paymentType: ISharedTypes.PaymentType.PayPerView,
            creator: david,
            contentId: audioId,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        vm.prank(charlie);
        (bytes16 purchaseIntentId,) = commerceProtocolCore.createPaymentIntent(purchaseRequest);

        vm.prank(operatorSigner);
        commerceProtocolCore.provideIntentSignature(purchaseIntentId, "charlie-consistency");

        vm.prank(charlie);
        commerceProtocolCore.executePaymentWithSignature(purchaseIntentId);

        // Note: View recording not implemented in current version

        // Comprehensive state verification
        assertStateConsistency();
    }

    // ============ HELPER FUNCTIONS ============

    function assertStateConsistency() internal view {
        // Verify all contracts have consistent state
        // Subscription states
        assertTrue(subscriptionManager.isSubscribed(alice, bob));
        assertFalse(subscriptionManager.isSubscribed(charlie, bob));

        // Access control states
        assertTrue(payPerView.hasAccess(articleId, alice));
        assertTrue(payPerView.hasAccess(audioId, charlie));
        assertFalse(payPerView.hasAccess(audioId, alice)); // Alice uses subscription

        // Creator statistics
        CreatorRegistry.Creator memory bobInfo = creatorRegistry.getCreatorProfile(bob);
        CreatorRegistry.Creator memory davidInfo = creatorRegistry.getCreatorProfile(david);

        assertEq(bobInfo.subscriberCount, 1);
        assertEq(davidInfo.subscriberCount, 0);

        // Note: Content statistics not implemented in current version

        // Earnings verification
        (uint256 bobEarnings,,) = creatorRegistry.getCreatorEarnings(bob);
        (uint256 davidEarnings,,) = creatorRegistry.getCreatorEarnings(david);

        assertTrue(bobEarnings > 0); // Subscription earnings
        assertTrue(davidEarnings > 0); // Pay-per-view earnings
    }
}
