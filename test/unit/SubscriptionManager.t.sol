// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";

/**
 * @title SubscriptionManagerTest
 * @dev Comprehensive unit tests for the SubscriptionManager contract
 * @notice This test suite covers all aspects of subscription management including subscription creation,
 *         auto-renewal functionality, expiration handling, cleanup processes, and earnings management.
 *         The SubscriptionManager is critical for our recurring revenue model.
 * 
 * We test time-based subscription logic, auto-renewal with rate limiting, subscription lifecycle
 * management, and complex scenarios like expired subscriptions and refunds. This ensures creators
 * have reliable recurring revenue and users have consistent access to subscribed content.
 */
contract SubscriptionManagerTest is TestSetup {
    
    // Events we'll test for proper emission
    event SubscriptionRenewed(address indexed user, address indexed creator, uint256 price, uint256 newEndTime, uint256 renewalCount);
    event SubscriptionCancelled(address indexed user, address indexed creator, uint256 endTime, bool immediate);
    event AutoRenewalConfigured(address indexed user, address indexed creator, bool enabled, uint256 maxPrice, uint256 depositAmount);
    event AutoRenewalExecuted(address indexed user, address indexed creator, uint256 price, uint256 newEndTime);
    event AutoRenewalFailed(address indexed user, address indexed creator, string reason, uint256 attemptTime);
    event SubscriptionEarningsWithdrawn(address indexed creator, uint256 amount, uint256 timestamp);
    event ExpiredSubscriptionsCleaned(address indexed creator, uint256 cleanedCount, uint256 timestamp);
    event ExternalSubscriptionRecorded(address indexed user, address indexed creator, bytes16 intentId, uint256 usdcAmount, address paymentToken, uint256 actualAmountPaid, uint256 endTime);
    event SubscriptionExpired(address indexed user, address indexed creator, uint256 timestamp);
    event ExternalRefundProcessed(bytes16 indexed intentId, address indexed user, address indexed creator, uint256 refundAmount);
    
    /**
     * @dev Test setup specific to SubscriptionManager tests
     * @notice This runs before each test to set up creators for subscription testing
     */
    function setUp() public override {
        super.setUp();
        
        // Register creators for subscription testing
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Creator 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE * 2, "Creator 2"));
    }
    
    // ============ SUBSCRIPTION CREATION TESTS ============
    
    /**
     * @dev Tests successful subscription creation
     * @notice This is our primary happy path test - subscriptions should work flawlessly
     */
    function test_SubscribeToCreator_Success() public {
        // Arrange: Set up user with USDC balance and approval
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Calculate expected amounts
        uint256 platformFee = calculatePlatformFee(DEFAULT_SUBSCRIPTION_PRICE);
        uint256 creatorEarning = DEFAULT_SUBSCRIPTION_PRICE - platformFee;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + SUBSCRIPTION_DURATION;
        
        // Act: Subscribe to creator
        vm.startPrank(user1);
        
        // Expect the Subscribed event
        vm.expectEmit(true, true, false, true);
        emit Subscribed(user1, creator1, DEFAULT_SUBSCRIPTION_PRICE, platformFee, creatorEarning, startTime, endTime);
        
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
        
        // Assert: Verify subscription was created
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        assertEq(subscriptionManager.getSubscriptionEndTime(user1, creator1), endTime);
        
        // Verify subscription details
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertTrue(record.isActive);
        assertEq(record.startTime, startTime);
        assertEq(record.endTime, endTime);
        assertEq(record.renewalCount, 0);
        assertEq(record.totalPaid, DEFAULT_SUBSCRIPTION_PRICE);
        assertEq(record.lastPayment, DEFAULT_SUBSCRIPTION_PRICE);
        assertEq(record.lastRenewalTime, startTime);
        assertFalse(record.autoRenewalEnabled);
        
        // Verify user is in creator's subscriber list
        address[] memory subscribers = subscriptionManager.getCreatorSubscribers(creator1);
        assertEq(subscribers.length, 1);
        assertEq(subscribers[0], user1);
        
        // Verify creator is in user's subscription list
        address[] memory userSubs = subscriptionManager.getUserSubscriptions(user1);
        assertEq(userSubs.length, 1);
        assertEq(userSubs[0], creator1);
        
        // Verify creator earnings were recorded
        (uint256 totalEarnings, uint256 withdrawable) = subscriptionManager.getCreatorSubscriptionEarnings(creator1);
        assertEq(totalEarnings, creatorEarning);
        assertEq(withdrawable, creatorEarning);
    }
    
    /**
     * @dev Tests subscription to non-registered creator
     * @notice This tests our creator validation
     */
    function test_SubscribeToCreator_CreatorNotRegistered() public {
        // Arrange: Use a non-registered creator
        address nonCreator = address(0x9999);
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.CreatorNotRegistered.selector);
        subscriptionManager.subscribeToCreator(nonCreator);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests subscription when already subscribed
     * @notice This tests our duplicate subscription prevention
     */
    function test_SubscribeToCreator_AlreadySubscribed() public {
        // Arrange: Subscribe first
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Set up for second subscription attempt
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.AlreadySubscribed.selector);
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests subscription with insufficient balance
     * @notice This tests our balance validation
     */
    function test_SubscribeToCreator_InsufficientBalance() public {
        // Arrange: Set up user with insufficient balance
        mockUSDC.forceBalance(user1, DEFAULT_SUBSCRIPTION_PRICE - 1);
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests subscription with insufficient allowance
     * @notice This tests our allowance validation
     */
    function test_SubscribeToCreator_InsufficientAllowance() public {
        // Arrange: Set up user with insufficient allowance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE - 1);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.InsufficientPayment.selector);
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests subscription renewal for existing subscriber
     * @notice This tests that existing subscribers can renew their subscriptions
     */
    function test_SubscribeToCreator_Renewal() public {
        // Arrange: Subscribe first, then let it expire
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Advance time to let subscription expire
        advanceTime(SUBSCRIPTION_DURATION + 1);
        
        // Set up for renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act: Renew subscription
        vm.startPrank(user1);
        
        // Expect the SubscriptionRenewed event
        vm.expectEmit(true, true, false, true);
        emit SubscriptionRenewed(user1, creator1, DEFAULT_SUBSCRIPTION_PRICE, block.timestamp + SUBSCRIPTION_DURATION, 1);
        
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
        
        // Assert: Verify renewal was successful
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Verify renewal details
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertTrue(record.isActive);
        assertEq(record.renewalCount, 1);
        assertEq(record.totalPaid, DEFAULT_SUBSCRIPTION_PRICE * 2);
    }
    
    // ============ AUTO-RENEWAL CONFIGURATION TESTS ============
    
    /**
     * @dev Tests configuring auto-renewal
     * @notice This tests our auto-renewal setup functionality
     */
    function test_ConfigureAutoRenewal_Success() public {
        // Arrange: Set up auto-renewal parameters
        uint256 maxPrice = DEFAULT_SUBSCRIPTION_PRICE * 2;
        uint256 depositAmount = DEFAULT_SUBSCRIPTION_PRICE * 3; // 3 months worth
        
        // Set up user with balance and approval
        approveUSDC(user1, address(subscriptionManager), depositAmount);
        
        // Act: Configure auto-renewal
        vm.startPrank(user1);
        
        // Expect the AutoRenewalConfigured event
        vm.expectEmit(true, true, false, true);
        emit AutoRenewalConfigured(user1, creator1, true, maxPrice, depositAmount);
        
        subscriptionManager.configureAutoRenewal(creator1, true, maxPrice, depositAmount);
        vm.stopPrank();
        
        // Assert: Verify auto-renewal was configured
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertTrue(autoRenewal.enabled);
        assertEq(autoRenewal.maxPrice, maxPrice);
        assertEq(autoRenewal.balance, depositAmount);
        assertEq(autoRenewal.failedAttempts, 0);
    }
    
    /**
     * @dev Tests configuring auto-renewal with invalid max price
     * @notice This tests our price validation for auto-renewal
     */
    function test_ConfigureAutoRenewal_InvalidMaxPrice() public {
        // Arrange: Set up max price below current subscription price
        uint256 invalidMaxPrice = DEFAULT_SUBSCRIPTION_PRICE - 1;
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.InvalidAutoRenewalConfig.selector);
        subscriptionManager.configureAutoRenewal(creator1, true, invalidMaxPrice, 0);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests configuring auto-renewal for non-registered creator
     * @notice This tests our creator validation for auto-renewal
     */
    function test_ConfigureAutoRenewal_CreatorNotRegistered() public {
        // Arrange: Use a non-registered creator
        address nonCreator = address(0x9999);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.CreatorNotRegistered.selector);
        subscriptionManager.configureAutoRenewal(nonCreator, true, DEFAULT_SUBSCRIPTION_PRICE, 0);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests disabling auto-renewal
     * @notice This tests turning off auto-renewal
     */
    function test_ConfigureAutoRenewal_Disable() public {
        // Arrange: Enable auto-renewal first
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act: Disable auto-renewal
        vm.startPrank(user1);
        
        // Expect the AutoRenewalConfigured event
        vm.expectEmit(true, true, false, true);
        emit AutoRenewalConfigured(user1, creator1, false, 0, 0);
        
        subscriptionManager.configureAutoRenewal(creator1, false, 0, 0);
        vm.stopPrank();
        
        // Assert: Verify auto-renewal was disabled
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertFalse(autoRenewal.enabled);
    }
    
    // ============ AUTO-RENEWAL EXECUTION TESTS ============
    
    /**
     * @dev Tests successful auto-renewal execution
     * @notice This tests our auto-renewal bot functionality
     */
    function test_ExecuteAutoRenewal_Success() public {
        // Arrange: Set up subscription with auto-renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Configure auto-renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE * 2, DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        // Advance time to renewal window
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1); // Within renewal window
        
        // Act: Execute auto-renewal
        vm.startPrank(admin); // Admin has RENEWAL_BOT_ROLE
        
        // Expect the AutoRenewalExecuted event
        vm.expectEmit(true, true, false, true);
        emit AutoRenewalExecuted(user1, creator1, DEFAULT_SUBSCRIPTION_PRICE, block.timestamp + SUBSCRIPTION_DURATION);
        
        subscriptionManager.executeAutoRenewal(user1, creator1);
        vm.stopPrank();
        
        // Assert: Verify renewal was successful
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Verify renewal details
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertEq(record.renewalCount, 1);
        assertEq(record.totalPaid, DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        // Verify auto-renewal balance was deducted
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertEq(autoRenewal.balance, DEFAULT_SUBSCRIPTION_PRICE); // Should have 1 payment left
    }
    
    /**
     * @dev Tests auto-renewal execution when not enabled
     * @notice This tests our auto-renewal validation
     */
    function test_ExecuteAutoRenewal_NotEnabled() public {
        // Arrange: Set up subscription without auto-renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Advance time to renewal window
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1);
        
        // Act & Assert: Expect the transaction to revert
        vm.startPrank(admin);
        vm.expectRevert(SubscriptionManager.InvalidAutoRenewalConfig.selector);
        subscriptionManager.executeAutoRenewal(user1, creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests auto-renewal execution with insufficient balance
     * @notice This tests our balance validation for auto-renewal
     */
    function test_ExecuteAutoRenewal_InsufficientBalance() public {
        // Arrange: Set up subscription with auto-renewal but insufficient balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Configure auto-renewal with insufficient balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE - 1);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE - 1);
        
        // Advance time to renewal window
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1);
        
        // Act: Execute auto-renewal
        vm.startPrank(admin);
        
        // Expect the AutoRenewalFailed event
        vm.expectEmit(true, true, false, true);
        emit AutoRenewalFailed(user1, creator1, "Insufficient balance", block.timestamp);
        
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        subscriptionManager.executeAutoRenewal(user1, creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests auto-renewal execution with price increase
     * @notice This tests our price validation for auto-renewal
     */
    function test_ExecuteAutoRenewal_PriceExceeded() public {
        // Arrange: Set up subscription with auto-renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Configure auto-renewal with low max price
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE);
        
        // Creator increases price
        vm.prank(creator1);
        creatorRegistry.updateSubscriptionPrice(DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        // Advance time to renewal window
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1);
        
        // Act: Execute auto-renewal
        vm.startPrank(admin);
        
        // Expect the AutoRenewalFailed event
        vm.expectEmit(true, true, false, true);
        emit AutoRenewalFailed(user1, creator1, "Price exceeded maximum", block.timestamp);
        
        vm.expectRevert("AutoRenewalFailed");
        subscriptionManager.executeAutoRenewal(user1, creator1);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests auto-renewal rate limiting
     * @notice This tests our rate limiting for auto-renewal attempts
     */
    function test_ExecuteAutoRenewal_RateLimiting() public {
        // Arrange: Set up subscription with auto-renewal
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Configure auto-renewal with insufficient balance (to trigger failures)
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE - 1);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE - 1);
        
        // Advance time to renewal window
        advanceTime(SUBSCRIPTION_DURATION - 1 days + 1);
        
        // Act: Try to execute auto-renewal multiple times
        vm.startPrank(admin);
        
        // First attempt should fail due to insufficient balance
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        subscriptionManager.executeAutoRenewal(user1, creator1);
        
        // Second attempt should fail due to cooldown
        vm.expectRevert(SubscriptionManager.RenewalTooSoon.selector);
        subscriptionManager.executeAutoRenewal(user1, creator1);
        
        vm.stopPrank();
    }
    
    // ============ SUBSCRIPTION CANCELLATION TESTS ============
    
    /**
     * @dev Tests subscription cancellation at natural expiry
     * @notice This tests our subscription cancellation functionality
     */
    function test_CancelSubscription_NaturalExpiry() public {
        // Arrange: Set up active subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        uint256 originalEndTime = subscriptionManager.getSubscriptionEndTime(user1, creator1);
        
        // Act: Cancel subscription (not immediate)
        vm.startPrank(user1);
        
        // Expect the SubscriptionCancelled event
        vm.expectEmit(true, true, false, true);
        emit SubscriptionCancelled(user1, creator1, originalEndTime, false);
        
        subscriptionManager.cancelSubscription(creator1, false);
        vm.stopPrank();
        
        // Assert: Verify subscription is still active but auto-renewal is disabled
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        assertEq(subscriptionManager.getSubscriptionEndTime(user1, creator1), originalEndTime);
        
        // Verify auto-renewal was disabled
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertFalse(autoRenewal.enabled);
        
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertFalse(record.autoRenewalEnabled);
    }
    
    /**
     * @dev Tests immediate subscription cancellation
     * @notice This tests our immediate cancellation functionality
     */
    function test_CancelSubscription_Immediate() public {
        // Arrange: Set up active subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Act: Cancel subscription immediately
        vm.startPrank(user1);
        
        // Expect the SubscriptionCancelled event
        vm.expectEmit(true, true, false, true);
        emit SubscriptionCancelled(user1, creator1, block.timestamp, true);
        
        subscriptionManager.cancelSubscription(creator1, true);
        vm.stopPrank();
        
        // Assert: Verify subscription was cancelled immediately
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
        assertEq(subscriptionManager.getSubscriptionEndTime(user1, creator1), block.timestamp);
        
        // Verify subscription record was updated
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertFalse(record.isActive);
        assertEq(record.endTime, block.timestamp);
    }
    
    /**
     * @dev Tests cancellation of non-existent subscription
     * @notice This tests our subscription validation for cancellation
     */
    function test_CancelSubscription_NotSubscribed() public {
        // Act & Assert: Try to cancel non-existent subscription
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.SubscriptionNotFound.selector);
        subscriptionManager.cancelSubscription(creator1, false);
        vm.stopPrank();
    }
    
    /**
     * @dev Tests cancellation of expired subscription
     * @notice This tests our expiry validation for cancellation
     */
    function test_CancelSubscription_AlreadyExpired() public {
        // Arrange: Set up and expire subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Advance time past expiry
        advanceTime(SUBSCRIPTION_DURATION + 1);
        
        // Act & Assert: Try to cancel expired subscription
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.SubscriptionNotFound.selector);
        subscriptionManager.cancelSubscription(creator1, false);
        vm.stopPrank();
    }
    
    // ============ SUBSCRIPTION CLEANUP TESTS ============
    
    /**
     * @dev Tests cleanup of expired subscriptions
     * @notice This tests our cleanup functionality for expired subscriptions
     */
    function test_CleanupExpiredSubscriptions_Success() public {
        // Arrange: Set up multiple subscriptions
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        approveUSDC(user2, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Verify both subscriptions are active
        assertEq(subscriptionManager.getCreatorSubscribers(creator1).length, 2);
        
        // Advance time past expiry + grace period
        advanceTime(SUBSCRIPTION_DURATION + GRACE_PERIOD + 1);
        
        // Act: Cleanup expired subscriptions
        vm.expectEmit(true, false, false, true);
        emit ExpiredSubscriptionsCleaned(creator1, 2, block.timestamp);
        
        subscriptionManager.cleanupExpiredSubscriptions(creator1);
        
        // Assert: Verify subscriptions were cleaned up
        assertEq(subscriptionManager.getCreatorSubscribers(creator1).length, 0);
        
        // Verify subscription records were deactivated
        SubscriptionManager.SubscriptionRecord memory record1 = subscriptionManager.getSubscriptionDetails(user1, creator1);
        SubscriptionManager.SubscriptionRecord memory record2 = subscriptionManager.getSubscriptionDetails(user2, creator1);
        assertFalse(record1.isActive);
        assertFalse(record2.isActive);
    }
    
    /**
     * @dev Tests cleanup rate limiting
     * @notice This tests our cleanup rate limiting functionality
     */
    function test_CleanupExpiredSubscriptions_RateLimiting() public {
        // Arrange: Set up subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Advance time past expiry
        advanceTime(SUBSCRIPTION_DURATION + GRACE_PERIOD + 1);
        
        // Act: First cleanup should succeed
        subscriptionManager.cleanupExpiredSubscriptions(creator1);
        
        // Assert: Second cleanup should fail due to rate limiting
        vm.expectRevert(SubscriptionManager.CleanupTooSoon.selector);
        subscriptionManager.cleanupExpiredSubscriptions(creator1);
    }
    
    /**
     * @dev Tests enhanced cleanup with events
     * @notice This tests our enhanced cleanup functionality
     */
    function test_CleanupExpiredSubscriptionsEnhanced_Success() public {
        // Arrange: Set up multiple subscriptions
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        approveUSDC(user2, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Advance time past expiry + grace period
        advanceTime(SUBSCRIPTION_DURATION + GRACE_PERIOD + 1);
        
        // Act: Enhanced cleanup
        address[] memory cleanedUsers = subscriptionManager.cleanupExpiredSubscriptionsEnhanced(creator1);
        
        // Assert: Verify cleanup results
        assertEq(cleanedUsers.length, 2);
        assertTrue(cleanedUsers[0] == user1 || cleanedUsers[0] == user2);
        assertTrue(cleanedUsers[1] == user1 || cleanedUsers[1] == user2);
        assertTrue(cleanedUsers[0] != cleanedUsers[1]);
    }
    
    // ============ SUBSCRIPTION EARNINGS TESTS ============
    
    /**
     * @dev Tests creator earnings withdrawal
     * @notice This tests our creator earnings withdrawal functionality
     */
    function test_WithdrawSubscriptionEarnings_Success() public {
        // Arrange: Set up subscription to generate earnings
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Fund the contract to pay out earnings
        uint256 creatorEarning = DEFAULT_SUBSCRIPTION_PRICE - calculatePlatformFee(DEFAULT_SUBSCRIPTION_PRICE);
        mockUSDC.mint(address(subscriptionManager), creatorEarning);
        
        // Get initial creator balance
        uint256 initialCreatorBalance = mockUSDC.balanceOf(creator1);
        
        // Act: Withdraw earnings
        vm.startPrank(creator1);
        
        // Expect the SubscriptionEarningsWithdrawn event
        vm.expectEmit(true, false, false, true);
        emit SubscriptionEarningsWithdrawn(creator1, creatorEarning, block.timestamp);
        
        subscriptionManager.withdrawSubscriptionEarnings();
        vm.stopPrank();
        
        // Assert: Verify earnings were withdrawn
        assertEq(mockUSDC.balanceOf(creator1), initialCreatorBalance + creatorEarning);
        
        // Verify earnings were reset
        (uint256 totalEarnings, uint256 withdrawable) = subscriptionManager.getCreatorSubscriptionEarnings(creator1);
        assertEq(totalEarnings, creatorEarning); // Total should remain
        assertEq(withdrawable, 0); // Withdrawable should be reset
    }
    
    /**
     * @dev Tests earnings withdrawal with no earnings
     * @notice This tests our earnings validation
     */
    function test_WithdrawSubscriptionEarnings_NoEarnings() public {
        // Act & Assert: Try to withdraw with no earnings
        vm.startPrank(creator1);
        vm.expectRevert(SubscriptionManager.NoEarningsToWithdraw.selector);
        subscriptionManager.withdrawSubscriptionEarnings();
        vm.stopPrank();
    }
    
    // ============ AUTO-RENEWAL BALANCE TESTS ============
    
    /**
     * @dev Tests withdrawing auto-renewal balance
     * @notice This tests our auto-renewal balance withdrawal functionality
     */
    function test_WithdrawAutoRenewalBalance_Success() public {
        // Arrange: Set up auto-renewal with balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        // Get initial user balance
        uint256 initialUserBalance = mockUSDC.balanceOf(user1);
        
        // Act: Withdraw auto-renewal balance
        vm.startPrank(user1);
        subscriptionManager.withdrawAutoRenewalBalance(creator1, DEFAULT_SUBSCRIPTION_PRICE);
        vm.stopPrank();
        
        // Assert: Verify balance was withdrawn
        assertEq(mockUSDC.balanceOf(user1), initialUserBalance + DEFAULT_SUBSCRIPTION_PRICE);
        
        // Verify auto-renewal balance was reduced
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertEq(autoRenewal.balance, DEFAULT_SUBSCRIPTION_PRICE);
    }
    
    /**
     * @dev Tests withdrawing full auto-renewal balance
     * @notice This tests withdrawing the entire balance
     */
    function test_WithdrawAutoRenewalBalance_Full() public {
        // Arrange: Set up auto-renewal with balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE);
        
        // Get initial user balance
        uint256 initialUserBalance = mockUSDC.balanceOf(user1);
        
        // Act: Withdraw full balance (amount = 0)
        vm.startPrank(user1);
        subscriptionManager.withdrawAutoRenewalBalance(creator1, 0);
        vm.stopPrank();
        
        // Assert: Verify full balance was withdrawn
        assertEq(mockUSDC.balanceOf(user1), initialUserBalance + DEFAULT_SUBSCRIPTION_PRICE);
        
        // Verify auto-renewal balance is now zero
        SubscriptionManager.AutoRenewal memory autoRenewal = subscriptionManager.getAutoRenewalConfig(user1, creator1);
        assertEq(autoRenewal.balance, 0);
    }
    
    /**
     * @dev Tests withdrawing more than available balance
     * @notice This tests our balance validation for withdrawals
     */
    function test_WithdrawAutoRenewalBalance_InsufficientBalance() public {
        // Arrange: Set up auto-renewal with small balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.configureAutoRenewal(creator1, true, DEFAULT_SUBSCRIPTION_PRICE, DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act & Assert: Try to withdraw more than available
        vm.startPrank(user1);
        vm.expectRevert(SubscriptionManager.InsufficientBalance.selector);
        subscriptionManager.withdrawAutoRenewalBalance(creator1, DEFAULT_SUBSCRIPTION_PRICE + 1);
        vm.stopPrank();
    }
    
    // ============ EXTERNAL SUBSCRIPTION RECORDING TESTS ============
    
    /**
     * @dev Tests recording external subscription payment
     * @notice This tests our external subscription recording functionality
     */
    function test_RecordSubscriptionPayment_Success() public {
        // Arrange: Grant subscription processor role
        vm.prank(admin);
        subscriptionManager.grantSubscriptionProcessorRole(address(this));
        
        // Set up payment parameters
        bytes16 intentId = bytes16(keccak256("test-intent"));
        uint256 usdcAmount = DEFAULT_SUBSCRIPTION_PRICE;
        address paymentToken = address(mockUSDC);
        uint256 actualAmountPaid = DEFAULT_SUBSCRIPTION_PRICE;
        
        // Act: Record external subscription payment
        vm.expectEmit(true, true, false, true);
        emit ExternalSubscriptionRecorded(user1, creator1, intentId, usdcAmount, paymentToken, actualAmountPaid, block.timestamp + SUBSCRIPTION_DURATION);
        
        subscriptionManager.recordSubscriptionPayment(user1, creator1, intentId, usdcAmount, paymentToken, actualAmountPaid);
        
        // Assert: Verify subscription was recorded
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Verify subscription details
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertTrue(record.isActive);
        assertEq(record.totalPaid, usdcAmount);
        assertEq(record.lastPayment, usdcAmount);
    }
    
    /**
     * @dev Tests recording external subscription payment for existing subscriber
     * @notice This tests renewal through external payment
     */
    function test_RecordSubscriptionPayment_Renewal() public {
        // Arrange: Set up existing subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Grant subscription processor role
        vm.prank(admin);
        subscriptionManager.grantSubscriptionProcessorRole(address(this));
        
        // Act: Record external renewal payment
        bytes16 intentId = bytes16(keccak256("test-renewal"));
        uint256 usdcAmount = DEFAULT_SUBSCRIPTION_PRICE;
        
        vm.expectEmit(true, true, false, true);
        emit SubscriptionRenewed(user1, creator1, usdcAmount, subscriptionManager.getSubscriptionEndTime(user1, creator1) + SUBSCRIPTION_DURATION, 1);
        
        subscriptionManager.recordSubscriptionPayment(user1, creator1, intentId, usdcAmount, address(mockUSDC), usdcAmount);
        
        // Assert: Verify renewal was recorded
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertEq(record.renewalCount, 1);
        assertEq(record.totalPaid, DEFAULT_SUBSCRIPTION_PRICE * 2);
    }
    
    /**
     * @dev Tests recording external subscription payment for non-registered creator
     * @notice This tests our creator validation for external payments
     */
    function test_RecordSubscriptionPayment_CreatorNotRegistered() public {
        // Arrange: Grant subscription processor role
        vm.prank(admin);
        subscriptionManager.grantSubscriptionProcessorRole(address(this));
        
        // Act & Assert: Try to record payment for non-registered creator
        vm.expectRevert("Creator not registered");
        subscriptionManager.recordSubscriptionPayment(user1, address(0x9999), bytes16(0), DEFAULT_SUBSCRIPTION_PRICE, address(mockUSDC), DEFAULT_SUBSCRIPTION_PRICE);
    }
    
    // ============ EXTERNAL REFUND TESTS ============
    
    /**
     * @dev Tests handling external refund
     * @notice This tests our external refund handling functionality
     */
    function test_HandleExternalRefund_Success() public {
        // Arrange: Set up subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Grant subscription processor role
        vm.prank(admin);
        subscriptionManager.grantSubscriptionProcessorRole(address(this));
        
        // Act: Handle external refund
        bytes16 intentId = bytes16(keccak256("test-refund"));
        
        vm.expectEmit(true, true, true, true);
        emit ExternalRefundProcessed(intentId, user1, creator1, DEFAULT_SUBSCRIPTION_PRICE);
        
        subscriptionManager.handleExternalRefund(intentId, user1, creator1);
        
        // Assert: Verify refund was processed
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
        
        // Verify subscription was deactivated
        SubscriptionManager.SubscriptionRecord memory record = subscriptionManager.getSubscriptionDetails(user1, creator1);
        assertFalse(record.isActive);
        assertEq(record.endTime, block.timestamp);
    }
    
    /**
     * @dev Tests external refund for non-existent subscription
     * @notice This tests our subscription validation for external refunds
     */
    function test_HandleExternalRefund_NoSubscription() public {
        // Arrange: Grant subscription processor role
        vm.prank(admin);
        subscriptionManager.grantSubscriptionProcessorRole(address(this));
        
        // Act & Assert: Try to refund non-existent subscription
        vm.expectRevert("No subscription found");
        subscriptionManager.handleExternalRefund(bytes16(0), user1, creator1);
    }
    
    // ============ SUBSCRIPTION STATUS TESTS ============
    
    /**
     * @dev Tests getting subscription status with grace period
     * @notice This tests our subscription status checking functionality
     */
    function test_GetSubscriptionStatus_Success() public {
        // Arrange: Set up subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Act & Assert: Check active subscription
        (bool isActive, bool inGracePeriod, uint256 endTime, uint256 gracePeriodEnd) = subscriptionManager.getSubscriptionStatus(user1, creator1);
        
        assertTrue(isActive);
        assertFalse(inGracePeriod);
        assertEq(endTime, block.timestamp + SUBSCRIPTION_DURATION);
        assertEq(gracePeriodEnd, endTime + GRACE_PERIOD);
        
        // Advance time past expiry but within grace period
        advanceTime(SUBSCRIPTION_DURATION + 1);
        
        // Act & Assert: Check subscription in grace period
        (isActive, inGracePeriod, endTime, gracePeriodEnd) = subscriptionManager.getSubscriptionStatus(user1, creator1);
        
        assertFalse(isActive);
        assertTrue(inGracePeriod);
        
        // Advance time past grace period
        advanceTime(GRACE_PERIOD + 1);
        
        // Act & Assert: Check expired subscription
        (isActive, inGracePeriod, endTime, gracePeriodEnd) = subscriptionManager.getSubscriptionStatus(user1, creator1);
        
        assertFalse(isActive);
        assertFalse(inGracePeriod);
    }
    
    // ============ PLATFORM METRICS TESTS ============
    
    /**
     * @dev Tests getting platform subscription metrics
     * @notice This tests our analytics and metrics functionality
     */
    function test_GetPlatformSubscriptionMetrics_Success() public {
        // Arrange: Set up multiple subscriptions
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        approveUSDC(user2, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE * 2);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator2);
        
        // Act: Get platform metrics
        (
            uint256 activeSubscriptions,
            uint256 totalVolume,
            uint256 platformFees,
            uint256 totalRenewalCount,
            uint256 totalRefundAmount
        ) = subscriptionManager.getPlatformSubscriptionMetrics();
        
        // Assert: Verify metrics are correct
        assertEq(activeSubscriptions, 2);
        assertEq(totalVolume, DEFAULT_SUBSCRIPTION_PRICE + (DEFAULT_SUBSCRIPTION_PRICE * 2));
        assertEq(platformFees, calculatePlatformFee(DEFAULT_SUBSCRIPTION_PRICE) + calculatePlatformFee(DEFAULT_SUBSCRIPTION_PRICE * 2));
        assertEq(totalRenewalCount, 0);
        assertEq(totalRefundAmount, 0);
    }
    
    // ============ EDGE CASE TESTS ============
    
    /**
     * @dev Tests contract pause functionality
     * @notice This tests our emergency pause system
     */
    function test_PauseUnpause_Success() public {
        // Arrange: Set up user with balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act: Pause the contract
        vm.prank(admin);
        subscriptionManager.pause();
        
        // Assert: Subscriptions should fail when paused
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to whenNotPaused modifier
        subscriptionManager.subscribeToCreator(creator1);
        vm.stopPrank();
        
        // Act: Unpause the contract
        vm.prank(admin);
        subscriptionManager.unpause();
        
        // Assert: Subscriptions should work again
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
    }
    
    /**
     * @dev Tests subscription expiration timing
     * @notice This tests our time-based subscription logic
     */
    function test_SubscriptionExpiration_Timing() public {
        // Arrange: Set up subscription
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Verify subscription is active
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Advance time to just before expiry
        advanceTime(SUBSCRIPTION_DURATION - 1);
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        
        // Advance time to exact expiry
        advanceTime(1);
        assertFalse(subscriptionManager.isSubscribed(user1, creator1));
    }
    
    /**
     * @dev Tests multiple subscriptions by same user
     * @notice This tests our subscription tracking across multiple creators
     */
    function test_MultipleSubscriptions_Success() public {
        // Arrange: Set up user with sufficient balance
        uint256 totalCost = DEFAULT_SUBSCRIPTION_PRICE + (DEFAULT_SUBSCRIPTION_PRICE * 2);
        approveUSDC(user1, address(subscriptionManager), totalCost);
        
        // Act: Subscribe to multiple creators
        vm.startPrank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        subscriptionManager.subscribeToCreator(creator2);
        vm.stopPrank();
        
        // Assert: Verify both subscriptions are active
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        assertTrue(subscriptionManager.isSubscribed(user1, creator2));
        
        // Verify subscription lists
        address[] memory userSubs = subscriptionManager.getUserSubscriptions(user1);
        assertEq(userSubs.length, 2);
        
        address[] memory activeUserSubs = subscriptionManager.getUserActiveSubscriptions(user1);
        assertEq(activeUserSubs.length, 2);
    }
    
    /**
     * @dev Tests subscription isolation between users
     * @notice This tests that subscriptions are properly isolated by user
     */
    function test_SubscriptionIsolation_Success() public {
        // Arrange: Set up both users with balance
        approveUSDC(user1, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        approveUSDC(user2, address(subscriptionManager), DEFAULT_SUBSCRIPTION_PRICE);
        
        // Act: Each user subscribes to the same creator
        vm.prank(user1);
        subscriptionManager.subscribeToCreator(creator1);
        
        vm.prank(user2);
        subscriptionManager.subscribeToCreator(creator1);
        
        // Assert: Both users should have independent subscriptions
        assertTrue(subscriptionManager.isSubscribed(user1, creator1));
        assertTrue(subscriptionManager.isSubscribed(user2, creator1));
        
        // Verify subscription records are separate
        SubscriptionManager.SubscriptionRecord memory record1 = subscriptionManager.getSubscriptionDetails(user1, creator1);
        SubscriptionManager.SubscriptionRecord memory record2 = subscriptionManager.getSubscriptionDetails(user2, creator1);
        
        assertTrue(record1.isActive);
        assertTrue(record2.isActive);
        assertEq(record1.totalPaid, DEFAULT_SUBSCRIPTION_PRICE);
        assertEq(record2.totalPaid, DEFAULT_SUBSCRIPTION_PRICE);
        
        // Verify creator has both users as subscribers
        address[] memory subscribers = subscriptionManager.getCreatorSubscribers(creator1);
        assertEq(subscribers.length, 2);
    }
}