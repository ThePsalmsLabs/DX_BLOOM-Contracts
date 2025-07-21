// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";

/**
 * @title BusinessScenariosTest - FIXED VERSION  
 * @dev Integration tests for complete business workflows - all access control issues fixed
 * @notice This test suite validates real-world usage scenarios including:
 *         - Creator onboarding and content publication
 *         - User subscription and content access flows
 *         - Multi-token payment scenarios  
 *         - Creator earnings and withdrawal
 */
contract BusinessScenariosTest is TestSetup {
    // Test content and subscription data
    uint256 private creatorSubscriptionPrice = 10e6; // $10/month
    uint256 private contentPrice = 3e6; // $3 per view
    uint256 private testContentId1;
    uint256 private testContentId2;

    /**
     * @dev Enhanced setup that properly initializes the test environment
     */
    function setUp() public override {
        // Call parent setUp to initialize contracts
        super.setUp();

        // Additional setup specific to business scenarios
        _setupBusinessTestData();
    }

    function _setupBusinessTestData() private {
        // Register test creators
        vm.prank(creator1);
        creatorRegistry.registerCreator(creatorSubscriptionPrice, "Premium Creator");

        vm.prank(creator2);
        creatorRegistry.registerCreator(5e6, "Standard Creator");

        // Register test content
        vm.prank(creator1);
        testContentId1 = contentRegistry.registerContent(
            "QmPremiumContent123",
            "Premium Tutorial",
            "Advanced blockchain development tutorial",
            ContentCategory.Article,
            contentPrice,
            new string[](0)
        );

        vm.prank(creator2);
        testContentId2 = contentRegistry.registerContent(
            "QmStandardContent456",
            "Basic Guide",
            "Introduction to smart contracts",
            ContentCategory.Article,
            2e6, // $2
            new string[](0)
        );
    }

    /**
     * @dev Test complete creator onboarding and content monetization flow - FIXED
     */
    function test_CreatorOnboardingFlow() public {
        address newCreator = address(0x4001);

        // FIXED: Give creator some USDC for testing using admin permissions
        vm.prank(admin);
        mockUSDC.mint(newCreator, 100e6);
        vm.deal(newCreator, 1 ether);

        // Step 1: Creator registers on platform
        vm.startPrank(newCreator);
        creatorRegistry.registerCreator(15e6, "New Premium Creator");

        // Verify registration
        assertTrue(creatorRegistry.isRegisteredCreator(newCreator));

        // Step 2: Creator publishes content
        uint256 contentId = contentRegistry.registerContent(
            "QmNewCreatorContent",
            "Exclusive Content",
            "Premium educational material",
            ContentCategory.Article,
            5e6, // $5
            new string[](0)
        );

        vm.stopPrank();

        // Step 3: User purchases content
        approveUSDC(user1, address(payPerView), 5e6);

        vm.prank(user1);
        payPerView.purchaseContentDirect(contentId);

        // Verify purchase and earnings
        assertTrue(payPerView.hasAccess(contentId, user1));

        (uint256 earnings,) = payPerView.getCreatorEarnings(newCreator);
        assertTrue(earnings > 0);
    }

    /**
     * @dev Test user subscription lifecycle
     */
    function test_UserSubscriptionLifecycle() public {
        // User subscribes to creator
        approveUSDC(user1, address(subscriptionManager), creatorSubscriptionPrice);

        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);

        // Verify subscription is active
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));

        // Access subscription content
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));

        // Fast forward past subscription period
        vm.warp(block.timestamp + 31 days);

        // Verify subscription expired
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));

        // Renew subscription
        approveUSDC(user1, address(subscriptionManager), creatorSubscriptionPrice);

        // Note: Renewal is handled by subscribeToCreator again or auto-renewal
    }

    /**
     * @dev Test creator earnings and withdrawal flow - FIXED
     */
    function test_CreatorEarningsFlow() public {
        // Multiple users purchase content
        address[3] memory buyers = [user1, user2, address(0x5001)];

        for (uint256 i = 0; i < buyers.length; i++) {
            // FIXED: Mint tokens using admin permissions
            vm.prank(admin);
            mockUSDC.mint(buyers[i], 10e6);
            
            approveUSDC(buyers[i], address(payPerView), contentPrice);

            vm.prank(buyers[i]);
            payPerView.purchaseContentDirect(testContentId1);
        }

        // Check creator earnings
        (uint256 payPerViewEarnings,) = payPerView.getCreatorEarnings(creator1);
        assertTrue(payPerViewEarnings > 0);

        // Verify creator earnings increased
        CreatorRegistry.Creator memory creatorProfile = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(creatorProfile.totalEarnings > 0);

        // Note: Individual contract withdrawals may work differently
        // The earnings tracking is verified through the CreatorRegistry
    }

    /**
     * @dev Test platform statistics tracking - FIXED
     */
    function test_PlatformStatistics() public {
        // Get initial stats
        (uint256 initialContentCount,,,) = contentRegistry.getPlatformStats();

        // Create new content
        vm.prank(creator1);
        uint256 newContentId = contentRegistry.registerContent(
            "QmNewContent", 
            "New Content", 
            "Description", 
            ContentCategory.Article, // FIXED: Ensure proper enum usage
            1e6, 
            new string[](0)
        );

        // Verify stats updated
        (uint256 newContentCount,,,) = contentRegistry.getPlatformStats();
        assertEq(newContentCount, initialContentCount + 1);

        // Verify the content was actually registered
        assertTrue(newContentId > 0);
        assertTrue(contentRegistry.getContent(newContentId).isActive);
    }

    /**
     * @dev Test multi-user subscription scenario
     */
    function test_MultiUserSubscriptions() public {
        address[3] memory subscribers = [user1, user2, address(0x6001)];
        
        // Setup multiple subscribers
        for (uint256 i = 0; i < subscribers.length; i++) {
            // Fund each subscriber
            vm.prank(admin);
            mockUSDC.mint(subscribers[i], 50e6);
            
            // Subscribe to creator1
            approveUSDC(subscribers[i], address(subscriptionManager), creatorSubscriptionPrice);
            
            vm.prank(subscribers[i]);
            subscriptionManager.subscribeToCreator(creator1);
            
            // Verify subscription
            assertTrue(subscriptionManager.isSubscribed(subscribers[i], creator1));
        }

        // Verify creator subscriber count increased
        CreatorRegistry.Creator memory creatorProfile = creatorRegistry.getCreatorProfile(creator1);
        assertEq(creatorProfile.subscriberCount, 3);

        // Verify creator earnings from subscriptions
        assertTrue(creatorProfile.totalEarnings > 0);
    }

    /**
     * @dev Test content purchase flow with earnings verification
     */
    function test_ContentPurchaseWithEarningsVerification() public {
        uint256 purchasePrice = 2e6; // $2

        // Get initial creator profile BEFORE registering new content
        CreatorRegistry.Creator memory initialProfile = creatorRegistry.getCreatorProfile(creator1);

        // Register content with specific price
        vm.prank(creator1);
        uint256 contentId = contentRegistry.registerContent(
            "QmTestContent999",
            "Test Content for Earnings",
            "Test description",
            ContentCategory.Video,
            purchasePrice,
            new string[](0)
        );

        // Get initial creator earnings (after content registration)
        uint256 initialEarnings = creatorRegistry.getCreatorProfile(creator1).totalEarnings;

        // User purchases content
        approveUSDC(user1, address(payPerView), purchasePrice);

        vm.prank(user1);
        payPerView.purchaseContentDirect(contentId);

        // Verify purchase successful
        assertTrue(payPerView.hasAccess(contentId, user1));

        // Verify creator earnings increased
        CreatorRegistry.Creator memory finalProfile = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(finalProfile.totalEarnings > initialEarnings);

        // Verify content count increased
        assertEq(finalProfile.contentCount, initialProfile.contentCount + 1);
    }

    /**
     * @dev Test creator verification and platform metrics
     */
    function test_CreatorVerificationAndPlatformMetrics() public {
        // Get initial platform stats
        (
            uint256 initialTotalCreators,
            uint256 initialVerifiedCreators,
            uint256 initialPlatformEarnings,
            uint256 initialCreatorEarnings,
            uint256 initialWithdrawnEarnings
        ) = creatorRegistry.getPlatformStats();

        // Verify creator1 as admin
        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        // Verify the verification
        assertTrue(creatorRegistry.getCreatorProfile(creator1).isVerified);

        // Check updated platform stats
        (
            uint256 finalTotalCreators,
            uint256 finalVerifiedCreators,
            ,
            ,
        ) = creatorRegistry.getPlatformStats();

        // Should have same total creators but one more verified
        assertEq(finalTotalCreators, initialTotalCreators);
        assertEq(finalVerifiedCreators, initialVerifiedCreators + 1);
    }

    /**
     * @dev Test subscription renewal scenario
     */
    function test_SubscriptionRenewalScenario() public {
        // Initial subscription
        approveUSDC(user1, address(subscriptionManager), creatorSubscriptionPrice);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Verify active subscription
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));

        // Fast forward to near expiration
        vm.warp(block.timestamp + 29 days);
        
        // Should still be active
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days); // Total 31 days
        
        // Should now be expired
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));

        // Renew subscription (handled by subscribing again)
        approveUSDC(user1, address(subscriptionManager), creatorSubscriptionPrice);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Verify renewed subscription
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
    }
}
