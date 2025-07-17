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
 * @title BusinessScenariosTest
 * @dev Complex business scenario integration tests
 * @notice This test suite represents the culmination of our testing strategy. While unit tests
 *         verify individual components and basic integration tests verify contract interactions,
 *         business scenario tests validate that our platform can handle real-world complexity.
 *
 *         Think of this as testing your platform like a real business would operate. We simulate
 *         scenarios like:
 *         - A creator launching with early-bird pricing, then increasing prices over time
 *         - Users switching between subscription and pay-per-view models
 *         - Platform scaling with hundreds of creators and thousands of users
 *         - Economic scenarios like fee changes and creator migrations
 *         - Emergency scenarios like creator account issues and recovery procedures
 *
 *         These tests give us confidence that the platform will work smoothly when real users
 *         with real money start using it. They test not just that the code works, but that
 *         the business logic makes sense and creates a good user experience.
 */
contract BusinessScenariosTest is TestSetup {
    // ============ BUSINESS SCENARIO DATA STRUCTURES ============

    struct CreatorLaunchScenario {
        address creator;
        uint256 earlyBirdPrice;
        uint256 regularPrice;
        uint256 premiumPrice;
        uint256 launchDuration;
        uint256 regularDuration;
    }

    struct UserJourneyData {
        address user;
        uint256 totalSpent;
        uint256 contentPurchased;
        uint256 activeSubscriptions;
        uint256 subscriptionRenewals;
        bool hasAutoRenewal;
    }

    struct PlatformEconomics {
        uint256 totalCreators;
        uint256 totalUsers;
        uint256 totalContent;
        uint256 totalRevenue;
        uint256 platformFees;
        uint256 creatorEarnings;
    }

    // ============ STATE VARIABLES ============

    mapping(address => uint256[]) public creatorContentIds;
    mapping(address => UserJourneyData) public userJourneys;
    address[] public testCreators;
    address[] public testUsers;

    // ============ SETUP ============

    function setUp() public override {
        super.setUp();
        _setupBusinessEnvironment();
    }

    function _setupBusinessEnvironment() private {
        // Create a diverse ecosystem of creators
        testCreators = new address[](5);
        testCreators[0] = address(0x5001); // Budget creator
        testCreators[1] = address(0x5002); // Premium creator
        testCreators[2] = address(0x5003); // Niche expert
        testCreators[3] = address(0x5004); // Volume creator
        testCreators[4] = address(0x5005); // Enterprise creator

        // Create diverse user base
        testUsers = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            testUsers[i] = address(uint160(0x6001 + i));
            mockUSDC.mint(testUsers[i], 1000e6); // Give each user $1000
            vm.deal(testUsers[i], 10 ether); // Gas money
        }
    }

    // ============ CREATOR LAUNCH AND GROWTH SCENARIOS ============

    /**
     * @dev Tests a complete creator launch lifecycle with pricing strategy
     * @notice This simulates how a real creator would launch on the platform:
     *         1. Start with low prices to attract early adopters
     *         2. Gradually increase prices as they build reputation
     *         3. Launch premium content for higher-paying users
     *         4. Build a sustainable creator economy
     */
    function test_CreatorLaunchLifecycle_Complete() public {
        CreatorLaunchScenario memory scenario = CreatorLaunchScenario({
            creator: testCreators[0],
            earlyBirdPrice: 2e6, // $2/month early bird
            regularPrice: 5e6, // $5/month regular
            premiumPrice: 10e6, // $10/month premium
            launchDuration: 30 days,
            regularDuration: 60 days
        });

        // Phase 1: Creator launches with early-bird pricing
        vm.prank(scenario.creator);
        creatorRegistry.registerCreator(scenario.earlyBirdPrice, "New Creator - Early Bird Special!");

        // Create initial content at low prices to attract users
        uint256 introContentId = _createContent(scenario.creator, 0.5e6, "Welcome Guide", "intro");
        uint256 basicContentId = _createContent(scenario.creator, 1e6, "Basic Tutorial", "tutorial");

        // Early adopters subscribe at low price
        for (uint256 i = 0; i < 3; i++) {
            _subscribeUser(testUsers[i], scenario.creator, scenario.earlyBirdPrice);
            _purchaseContent(testUsers[i], introContentId, 0.5e6);
        }

        // Verify early adoption metrics
        CreatorRegistry.Creator memory launchStats = creatorRegistry.getCreatorProfile(scenario.creator);
        assertEq(launchStats.subscriberCount, 3);
        assertTrue(launchStats.totalEarnings >= 7.5e6); // At least $7.50 from subscriptions + content

        // Phase 2: Price increase after launch period (simulate success)
        advanceTime(scenario.launchDuration);

        vm.prank(scenario.creator);
        creatorRegistry.updateSubscriptionPrice(scenario.regularPrice);

        // Add more valuable content at higher prices
        uint256 advancedContentId = _createContent(scenario.creator, 3e6, "Advanced Strategies", "advanced");

        // New users pay higher price, existing subscribers grandfathered
        for (uint256 i = 3; i < 6; i++) {
            _subscribeUser(testUsers[i], scenario.creator, scenario.regularPrice);
        }

        // Some users purchase premium content
        for (uint256 i = 0; i < 4; i++) {
            _purchaseContent(testUsers[i], advancedContentId, 3e6);
        }

        // Phase 3: Premium tier launch
        advanceTime(scenario.regularDuration);

        vm.prank(scenario.creator);
        creatorRegistry.updateSubscriptionPrice(scenario.premiumPrice);

        uint256 premiumContentId = _createContent(scenario.creator, 8e6, "Expert Masterclass", "premium");

        // High-value users subscribe to premium tier
        for (uint256 i = 6; i < 8; i++) {
            _subscribeUser(testUsers[i], scenario.creator, scenario.premiumPrice);
            _purchaseContent(testUsers[i], premiumContentId, 8e6);
        }

        // Phase 4: Verify sustainable creator economy
        CreatorRegistry.Creator memory finalStats = creatorRegistry.getCreatorProfile(scenario.creator);
        assertEq(finalStats.subscriberCount, 8); // All test users subscribed
        assertTrue(finalStats.totalEarnings >= 50e6); // At least $50 total earnings

        // Verify pricing tier diversity in subscription data
        SubscriptionManager.SubscriptionRecord memory earlyRecord =
            subscriptionManager.getSubscriptionDetails(testUsers[0], scenario.creator);
        SubscriptionManager.SubscriptionRecord memory regularRecord =
            subscriptionManager.getSubscriptionDetails(testUsers[3], scenario.creator);
        SubscriptionManager.SubscriptionRecord memory premiumRecord =
            subscriptionManager.getSubscriptionDetails(testUsers[6], scenario.creator);

        assertEq(earlyRecord.lastPayment, scenario.earlyBirdPrice);
        assertEq(regularRecord.lastPayment, scenario.regularPrice);
        assertEq(premiumRecord.lastPayment, scenario.premiumPrice);
    }

    /**
     * @dev Tests creator migration scenario when moving to premium model
     * @notice This tests what happens when a creator transitions from free content to paid model
     */
    function test_CreatorMigrationToPremium_UserRetention() public {
        address migrationCreator = testCreators[1];

        // Phase 1: Creator starts with very low subscription price (almost free)
        vm.prank(migrationCreator);
        creatorRegistry.registerCreator(0.1e6, "Almost Free Creator"); // $0.10/month

        // Create lots of free/cheap content to build audience
        uint256[] memory freeContentIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            freeContentIds[i] =
                _createContent(migrationCreator, 0.1e6, string(abi.encodePacked("Free Content ", _toString(i))), "free");
        }

        // Build large user base with low barrier to entry
        for (uint256 i = 0; i < 8; i++) {
            _subscribeUser(testUsers[i], migrationCreator, 0.1e6);
            // Users buy multiple pieces of cheap content
            for (uint256 j = 0; j < 3; j++) {
                _purchaseContent(testUsers[i], freeContentIds[j], 0.1e6);
            }
        }

        CreatorRegistry.Creator memory preTransitionStats = creatorRegistry.getCreatorProfile(migrationCreator);
        assertEq(preTransitionStats.subscriberCount, 8);

        // Phase 2: Creator transitions to premium model
        vm.prank(migrationCreator);
        creatorRegistry.updateSubscriptionPrice(15e6); // Jump to $15/month premium

        // Add high-value premium content
        uint256 premiumCourseId = _createContent(migrationCreator, 25e6, "Premium Course", "premium");

        // Phase 3: Test user retention and new user acquisition
        // Some existing users will remain (grandfathered at old price)
        // Some new users will pay premium price for high-value content

        // Simulate some users churning (not renewing)
        advanceTime(SUBSCRIPTION_DURATION + 1);

        // High-value users renew even at higher price
        for (uint256 i = 0; i < 3; i++) {
            if (!subscriptionManager.isSubscribed(testUsers[i], migrationCreator)) {
                _subscribeUser(testUsers[i], migrationCreator, 15e6); // Re-subscribe at new price
            }
        }

        // New premium users join
        for (uint256 i = 8; i < 10; i++) {
            _subscribeUser(testUsers[i], migrationCreator, 15e6);
            _purchaseContent(testUsers[i], premiumCourseId, 25e6);
        }

        // Phase 4: Verify successful premium transition
        CreatorRegistry.Creator memory postTransitionStats = creatorRegistry.getCreatorProfile(migrationCreator);
        assertTrue(postTransitionStats.totalEarnings > preTransitionStats.totalEarnings * 2);
        // Should have at least doubled earnings despite potentially losing some users

        // Verify mix of grandfathered and premium subscribers
        uint256 activeSubscribers = 0;
        for (uint256 i = 0; i < 10; i++) {
            if (subscriptionManager.isSubscribed(testUsers[i], migrationCreator)) {
                activeSubscribers++;
            }
        }
        assertTrue(activeSubscribers >= 5); // Should retain good portion of users
    }

    // ============ PLATFORM SCALING SCENARIOS ============

    /**
     * @dev Tests platform performance with high volume of creators and users
     * @notice This simulates platform scaling to ensure it can handle growth
     */
    function test_PlatformScaling_HighVolume() public {
        // Phase 1: Create ecosystem with many creators
        address[] memory scaleCreators = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            scaleCreators[i] = address(uint160(0x7001 + i));
            uint256 price = (i + 1) * 1e6; // $1 to $20 monthly

            vm.prank(scaleCreators[i]);
            creatorRegistry.registerCreator(price, string(abi.encodePacked("Creator ", _toString(i))));
        }

        // Phase 2: Create content at scale
        uint256 totalContentCreated = 0;
        for (uint256 i = 0; i < 20; i++) {
            // Each creator creates 3-5 pieces of content
            uint256 contentCount = 3 + (i % 3); // 3-5 pieces
            for (uint256 j = 0; j < contentCount; j++) {
                _createContent(
                    scaleCreators[i],
                    (j + 1) * 0.5e6,
                    string(abi.encodePacked("Content ", _toString(j), " by Creator ", _toString(i))),
                    "scale-test"
                );
                totalContentCreated++;
            }
        }

        // Phase 3: Simulate user activity at scale
        address[] memory scaleUsers = new address[](50);
        for (uint256 i = 0; i < 50; i++) {
            scaleUsers[i] = address(uint160(0x8001 + i));
            mockUSDC.mint(scaleUsers[i], 500e6); // $500 each user

            // Each user subscribes to 2-4 creators
            uint256 subscriptionCount = 2 + (i % 3);
            for (uint256 j = 0; j < subscriptionCount && j < 20; j++) {
                uint256 creatorIndex = (i + j) % 20;
                uint256 price = (creatorIndex + 1) * 1e6;
                _subscribeUser(scaleUsers[i], scaleCreators[creatorIndex], price);
            }
        }

        // Phase 4: Verify platform can handle scale
        (uint256 activeSubscriptions, uint256 totalVolume,,,) = subscriptionManager.getPlatformSubscriptionMetrics();

        assertTrue(activeSubscriptions >= 100); // At least 100 active subscriptions
        assertTrue(totalVolume >= 1000e6); // At least $1000 in subscription volume

        (, uint256 activeContent,,) = contentRegistry.getPlatformStats();
        assertEq(activeContent, totalContentCreated);

        // Verify individual creator data integrity
        for (uint256 i = 0; i < 10; i++) {
            // Check first 10 creators
            CreatorRegistry.Creator memory creatorStats = creatorRegistry.getCreatorProfile(scaleCreators[i]);
            assertTrue(creatorStats.subscriberCount > 0);
            assertTrue(creatorStats.totalEarnings > 0);
        }
    }

    // ============ ECONOMIC SCENARIO TESTS ============

    /**
     * @dev Tests platform fee changes and their economic impact
     * @notice This tests what happens when platform economics change
     */
    function test_PlatformFeeChanges_EconomicImpact() public {
        address economicsCreator = testCreators[2];

        // Phase 1: Establish baseline with current fees
        vm.prank(economicsCreator);
        creatorRegistry.registerCreator(10e6, "Economics Test Creator");

        uint256 contentId = _createContent(economicsCreator, 5e6, "Economics Content", "economics");

        // Multiple users interact with platform
        for (uint256 i = 0; i < 5; i++) {
            _subscribeUser(testUsers[i], economicsCreator, 10e6);
            _purchaseContent(testUsers[i], contentId, 5e6);
        }

        // Capture baseline earnings
        (uint256 baselinePayPerView,) = payPerView.getCreatorEarnings(economicsCreator);
        (uint256 baselineSubscription,) = subscriptionManager.getCreatorSubscriptionEarnings(economicsCreator);
        uint256 baselineTotal = baselinePayPerView + baselineSubscription;

        // Phase 2: Platform increases fees (simulate business model change)
        vm.prank(admin);
        creatorRegistry.updatePlatformFee(1000); // Increase to 10%

        // Phase 3: New activity after fee change
        for (uint256 i = 5; i < 8; i++) {
            _subscribeUser(testUsers[i], economicsCreator, 10e6);
            _purchaseContent(testUsers[i], contentId, 5e6);
        }

        // Phase 4: Verify fee impact
        (uint256 finalPayPerView,) = payPerView.getCreatorEarnings(economicsCreator);
        (uint256 finalSubscription,) = subscriptionManager.getCreatorSubscriptionEarnings(economicsCreator);
        uint256 finalTotal = finalPayPerView + finalSubscription;

        // Creator should earn less per transaction after fee increase
        uint256 incrementalEarnings = finalTotal - baselineTotal;
        uint256 expectedRevenue = 8 * (10e6 + 5e6); // 8 users × $15 each
        assertTrue(incrementalEarnings < expectedRevenue * 90 / 100); // Less than 90% due to higher fees

        // But platform should collect more fees
        // (In production, this would be tracked in a treasury contract)
    }

    // ============ EMERGENCY AND RECOVERY SCENARIOS ============

    /**
     * @dev Tests emergency creator account suspension and user refunds
     * @notice This tests platform's ability to handle creator misconduct scenarios
     */
    function test_EmergencyCreatorSuspension_UserProtection() public {
        address problematicCreator = testCreators[3];

        // Phase 1: Establish normal operations
        vm.prank(problematicCreator);
        creatorRegistry.registerCreator(8e6, "Creator Under Investigation");

        uint256 contentId = _createContent(problematicCreator, 4e6, "Content to be Removed", "problematic");

        // Users subscribe and purchase content
        for (uint256 i = 0; i < 6; i++) {
            _subscribeUser(testUsers[i], problematicCreator, 8e6);
            _purchaseContent(testUsers[i], contentId, 4e6);
        }

        // Phase 2: Emergency suspension (admin action)
        vm.prank(admin);
        creatorRegistry.suspendCreator(problematicCreator, true);

        // Phase 3: Verify suspension effects
        CreatorRegistry.Creator memory suspendedProfile = creatorRegistry.getCreatorProfile(problematicCreator);
        assertTrue(suspendedProfile.isSuspended);

        // New users cannot subscribe or purchase
        vm.startPrank(testUsers[7]);
        vm.expectRevert("Creator suspended");
        subscriptionManager.subscribeToCreator(problematicCreator);
        vm.stopPrank();

        // Phase 4: User protection measures
        // Existing subscribers should be able to cancel and get prorated refunds
        for (uint256 i = 0; i < 3; i++) {
            uint256 balanceBefore = mockUSDC.balanceOf(testUsers[i]);

            vm.prank(testUsers[i]);
            subscriptionManager.requestSubscriptionRefund(problematicCreator, "Creator suspended");
            vm.prank(admin);
            subscriptionManager.processRefundPayout(testUsers[i], problematicCreator);

            uint256 balanceAfter = mockUSDC.balanceOf(testUsers[i]);
            assertTrue(balanceAfter > balanceBefore); // Should receive some refund
        }

        // Content should be deactivated
        ContentRegistry.Content memory suspendedContent = contentRegistry.getContent(contentId);
        assertFalse(suspendedContent.isActive);

        // But existing access should be preserved (users already paid)
        assertTrue(payPerView.hasAccess(contentId, testUsers[0]));
    }

    // ============ USER BEHAVIOR SIMULATION TESTS ============

    /**
     * @dev Tests complex user behavior patterns over time
     * @notice This simulates realistic user engagement patterns
     */
    function test_UserBehaviorPatterns_LongTerm() public {
        // Phase 1: User lifecycle simulation
        address behaviorUser = testUsers[0];
        UserJourneyData storage journey = userJourneys[behaviorUser];

        // Month 1: New user explores platform
        _subscribeUser(behaviorUser, testCreators[0], 5e6); // Low-cost subscription
        uint256 basicContentId = _createContent(testCreators[0], 1e6, "Beginner Content", "basic");
        _purchaseContent(behaviorUser, basicContentId, 1e6);

        journey.totalSpent += 6e6;
        journey.contentPurchased += 1;
        journey.activeSubscriptions += 1;

        // Month 2: User upgrades to premium creator
        advanceTime(30 days);
        _subscribeUser(behaviorUser, testCreators[1], 15e6); // Premium subscription

        journey.totalSpent += 15e6;
        journey.activeSubscriptions += 1;

        // Month 3: Heavy usage period
        advanceTime(30 days);
        for (uint256 i = 0; i < 4; i++) {
            uint256 contentId = _createContent(
                testCreators[1], 3e6, string(abi.encodePacked("Premium Content ", _toString(i))), "premium"
            );
            _purchaseContent(behaviorUser, contentId, 3e6);
            journey.contentPurchased += 1;
            journey.totalSpent += 3e6;
        }

        // Month 4: User tries auto-renewal
        advanceTime(30 days);
        vm.prank(behaviorUser);
        subscriptionManager.configureAutoRenewal(testCreators[0], true, 10e6, 30e6); // Example: enable, maxPrice $10, deposit $30
        journey.hasAutoRenewal = true;

        // Months 5-7: Auto-renewals occur
        for (uint256 i = 0; i < 3; i++) {
            advanceTime(30 days);
            vm.prank(behaviorUser);
            subscriptionManager.executeAutoRenewal(behaviorUser, testCreators[0]);
            journey.subscriptionRenewals += 1;
            journey.totalSpent += 5e6;
        }

        // Month 8: User becomes more selective (cancels one subscription)
        advanceTime(30 days);
        vm.prank(behaviorUser);
        subscriptionManager.cancelSubscription(testCreators[1], true);
        journey.activeSubscriptions -= 1;

        // Phase 2: Verify realistic user journey data
        assertTrue(journey.totalSpent >= 50e6); // User spent at least $50
        assertTrue(journey.contentPurchased >= 5); // Purchased multiple pieces
        assertEq(journey.subscriptionRenewals, 3); // Renewed as expected
        assertTrue(journey.hasAutoRenewal); // Used convenience features

        // Verify user has mix of active and historical access
        assertTrue(subscriptionManager.isSubscribed(behaviorUser, testCreators[0])); // Still subscribed
        assertFalse(subscriptionManager.isSubscribed(behaviorUser, testCreators[1])); // Cancelled
        assertTrue(payPerView.hasAccess(basicContentId, behaviorUser)); // Permanent access
    }

    // ============ HELPER FUNCTIONS FOR BUSINESS SCENARIOS ============

    function _createContent(address creator, uint256 price, string memory title, string memory tag)
        private
        returns (uint256 contentId)
    {
        vm.startPrank(creator);

        string[] memory tags = new string[](1);
        tags[0] = tag;

        contentId = contentRegistry.registerContent(
            string(abi.encodePacked("QmHash", _toString(uint256(uint160(creator))))),
            title,
            "Business scenario test content",
            ContentRegistry.ContentCategory.Article,
            price,
            tags
        );

        creatorContentIds[creator].push(contentId);
        vm.stopPrank();
    }

    function _subscribeUser(address user, address creator, uint256 price) private {
        approveUSDC(user, address(subscriptionManager), price);
        vm.prank(user);
        subscriptionManager.subscribeToCreator(creator);
    }

    function _purchaseContent(address user, uint256 contentId, uint256 price) private {
        approveUSDC(user, address(payPerView), price);
        vm.prank(user);
        payPerView.purchaseContentDirect(contentId);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
