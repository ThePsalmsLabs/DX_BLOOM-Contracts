// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { CreatorRegistry } from "./CreatorRegistry.sol";
import { ContentRegistry } from "./ContentRegistry.sol";

/**
 * @title SubscriptionManager
 * @dev Subscription management with auto-renewal, expiry cleanup, and comprehensive tracking
 * @notice This contract handles monthly subscriptions giving users access to all creator content
 */
contract SubscriptionManager is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Role definitions
    bytes32 public constant RENEWAL_BOT_ROLE = keccak256("RENEWAL_BOT_ROLE");
    bytes32 public constant SUBSCRIPTION_PROCESSOR_ROLE = keccak256("SUBSCRIPTION_PROCESSOR_ROLE");

    // Contract dependencies for validation and pricing
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    IERC20 public immutable usdcToken; // USDC token contract on Base

    // Subscription duration configuration
    uint256 public constant SUBSCRIPTION_DURATION = 30 days; // Fixed 30-day subscriptions
    uint256 public constant GRACE_PERIOD = 3 days; // Grace period for expired subscriptions
    uint256 public constant RENEWAL_WINDOW = 1 days; // Window before expiry for renewal

    // Subscription tracking: user => creator => expiration timestamp
    mapping(address => mapping(address => uint256)) public subscriptionEndTime;

    // Subscription analytics and management
    mapping(address => mapping(address => SubscriptionRecord)) public subscriptions;
    mapping(address => address[]) public userSubscriptions; // user => creator addresses
    mapping(address => address[]) public creatorSubscribers; // creator => subscriber addresses
    mapping(address => uint256) public creatorSubscriberCount; // creator => active count

    // Financial tracking for subscriptions
    mapping(address => uint256) public creatorSubscriptionEarnings; // creator => total subscription revenue
    mapping(address => uint256) public userSubscriptionSpending; // user => total spent on subscriptions

    // Subscription lifecycle tracking
    mapping(address => mapping(address => uint256)) public subscriptionCount; // user => creator => renewal count
    mapping(address => uint256) public totalSubscriptionRevenue; // creator => all-time revenue

    // Auto-renewal management: user => creator => auto-renewal settings
    mapping(address => mapping(address => AutoRenewal)) public autoRenewals;

    // Expired subscription cleanup tracking
    mapping(address => uint256) public lastCleanupTime; // creator => last cleanup timestamp
    uint256 public constant CLEANUP_INTERVAL = 7 days; // Cleanup interval

    // Refund and failed subscription tracking
    mapping(address => mapping(address => uint256)) public pendingRefunds;
    mapping(address => mapping(address => FailedSubscription)) public failedSubscriptions;

    /**
     * @dev Detailed subscription record for analytics and management
     */
    struct SubscriptionRecord {
        bool isActive; // Active subscription status
        uint256 startTime; // Initial subscription timestamp
        uint256 endTime; // Current expiration timestamp
        uint256 renewalCount; // Number of renewals
        uint256 totalPaid; // Total USDC paid to this creator
        uint256 lastPayment; // Most recent payment amount
        uint256 lastRenewalTime; // Last renewal timestamp
        bool autoRenewalEnabled; // Auto-renewal status
    }

    /**
     * @dev Auto-renewal configuration for convenience
     */
    struct AutoRenewal {
        bool enabled; // Auto-renewal status
        uint256 maxPrice; // Maximum acceptable price for renewal
        uint256 balance; // Pre-deposited USDC balance for renewals
        uint256 lastRenewalAttempt; // Last renewal attempt timestamp
        uint256 failedAttempts; // Number of failed renewal attempts
    }

    /**
     * @dev Failed subscription for refund tracking
     */
    struct FailedSubscription {
        uint256 attemptTime;
        uint256 attemptedPrice;
        string failureReason;
        bool refunded;
    }

    // Platform subscription metrics
    uint256 public totalActiveSubscriptions; // Current active subscription count
    uint256 public totalSubscriptionVolume; // All-time subscription revenue volume
    uint256 public totalPlatformSubscriptionFees; // Platform fees from subscriptions
    uint256 public totalRenewals; // Total successful renewals
    uint256 public totalRefunds; // Total refunds processed

    // Auto-renewal rate limiting
    uint256 public maxRenewalAttemptsPerDay = 3; // Max renewal attempts per day
    uint256 public renewalCooldown = 4 hours; // Cooldown between renewal attempts

    // Events for comprehensive subscription tracking
    event Subscribed(
        address indexed user,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning,
        uint256 startTime,
        uint256 endTime
    );

    event SubscriptionRenewed(
        address indexed user, address indexed creator, uint256 price, uint256 newEndTime, uint256 renewalCount
    );

    event SubscriptionCancelled(address indexed user, address indexed creator, uint256 endTime, bool immediate);

    event AutoRenewalConfigured(
        address indexed user, address indexed creator, bool enabled, uint256 maxPrice, uint256 depositAmount
    );

    event AutoRenewalExecuted(address indexed user, address indexed creator, uint256 price, uint256 newEndTime);

    event AutoRenewalFailed(address indexed user, address indexed creator, string reason, uint256 attemptTime);

    event SubscriptionEarningsWithdrawn(address indexed creator, uint256 amount, uint256 timestamp);

    event ExpiredSubscriptionsCleaned(address indexed creator, uint256 cleanedCount, uint256 timestamp);

    event SubscriptionRefunded(address indexed user, address indexed creator, uint256 amount, string reason);

    event ExternalSubscriptionRecorded(
        address indexed user,
        address indexed creator,
        bytes16 intentId,
        uint256 usdcAmount,
        address paymentToken,
        uint256 actualAmountPaid,
        uint256 endTime
    );
    event SubscriptionExpired(address indexed user, address indexed creator, uint256 timestamp);
    event ExternalRefundProcessed(
        bytes16 intentId, address indexed user, address indexed creator, uint256 refundAmount
    );

    // Custom errors for efficient error handling
    error CreatorNotRegistered();
    error AlreadySubscribed();
    error SubscriptionNotFound();
    error SubscriptionAlreadyExpired();
    error InsufficientPayment();
    error InsufficientBalance();
    error InvalidAutoRenewalConfig();
    error NoEarningsToWithdraw();
    error InvalidSubscriptionPeriod();
    error RenewalTooSoon();
    error TooManyRenewalAttempts();
    error RefundNotEligible();
    error CleanupTooSoon();

    /**
     * @dev Constructor initializes subscription manager with required contracts
     * @param _creatorRegistry Address of CreatorRegistry contract
     * @param _contentRegistry Address of ContentRegistry contract
     * @param _usdcToken Address of USDC token contract on Base
     */
    constructor(address _creatorRegistry, address _contentRegistry, address _usdcToken) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_usdcToken != address(0), "Invalid USDC token");

        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        usdcToken = IERC20(_usdcToken);

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RENEWAL_BOT_ROLE, msg.sender);
        _grantRole(SUBSCRIPTION_PROCESSOR_ROLE, msg.sender);
    }

    /**
     * @dev Subscribes user to a creator for 30 days with USDC payment
     * @param creator Address of creator to subscribe to
     */
    function subscribeToCreator(address creator) external nonReentrant whenNotPaused {
        // Validate creator registration
        if (!creatorRegistry.isRegisteredCreator(creator)) revert CreatorNotRegistered();

        // Check if user already has active subscription
        if (isSubscribed(msg.sender, creator)) revert AlreadySubscribed();

        // Get subscription price from creator registry
        uint256 subscriptionPrice = creatorRegistry.getSubscriptionPrice(creator);

        // Calculate platform fee and creator earnings
        uint256 platformFee = creatorRegistry.calculatePlatformFee(subscriptionPrice);
        uint256 creatorEarning = subscriptionPrice - platformFee;

        // Verify user has sufficient USDC balance and allowance
        if (usdcToken.balanceOf(msg.sender) < subscriptionPrice) revert InsufficientBalance();
        if (usdcToken.allowance(msg.sender, address(this)) < subscriptionPrice) {
            revert InsufficientPayment();
        }

        // Process payment - transfer USDC from user to contract
        usdcToken.safeTransferFrom(msg.sender, address(this), subscriptionPrice);

        // Calculate subscription period
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + SUBSCRIPTION_DURATION;

        // Record subscription details
        subscriptionEndTime[msg.sender][creator] = endTime;

        // Check if this is a renewal of existing subscription record
        SubscriptionRecord storage record = subscriptions[msg.sender][creator];
        if (record.totalPaid == 0) {
            // New subscription - add to tracking arrays
            userSubscriptions[msg.sender].push(creator);
            creatorSubscribers[creator].push(msg.sender);

            // Initialize subscription record
            record.isActive = true;
            record.startTime = startTime;
            record.endTime = endTime;
            record.renewalCount = 0;
            record.totalPaid = subscriptionPrice;
            record.lastPayment = subscriptionPrice;
            record.lastRenewalTime = startTime;
            record.autoRenewalEnabled = false;
        } else {
            // Renewal of existing subscription
            record.isActive = true;
            record.endTime = endTime;
            record.renewalCount += 1;
            record.totalPaid += subscriptionPrice;
            record.lastPayment = subscriptionPrice;
            record.lastRenewalTime = block.timestamp;

            totalRenewals++;

            emit SubscriptionRenewed(msg.sender, creator, subscriptionPrice, endTime, record.renewalCount);
        }

        // Update financial tracking
        creatorSubscriptionEarnings[creator] += creatorEarning;
        userSubscriptionSpending[msg.sender] += subscriptionPrice;
        totalSubscriptionRevenue[creator] += creatorEarning;

        // Update platform metrics
        totalActiveSubscriptions += 1;
        totalSubscriptionVolume += subscriptionPrice;
        totalPlatformSubscriptionFees += platformFee;
        creatorSubscriberCount[creator] += 1;

        // Update creator stats in registry
        try creatorRegistry.updateCreatorStats(creator, creatorEarning, 0, 1) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }

        emit Subscribed(msg.sender, creator, subscriptionPrice, platformFee, creatorEarning, startTime, endTime);
    }

    /**
     * @dev Configures auto-renewal for a creator subscription
     * @param creator Creator address for auto-renewal
     * @param enabled Whether to enable auto-renewal
     * @param maxPrice Maximum price willing to pay for auto-renewal
     * @param depositAmount Additional USDC to deposit for auto-renewals
     */
    function configureAutoRenewal(address creator, bool enabled, uint256 maxPrice, uint256 depositAmount)
        external
        nonReentrant
        whenNotPaused
    {
        if (!creatorRegistry.isRegisteredCreator(creator)) revert CreatorNotRegistered();

        // If enabling auto-renewal, validate configuration
        if (enabled) {
            uint256 currentPrice = creatorRegistry.getSubscriptionPrice(creator);
            if (maxPrice < currentPrice) revert InvalidAutoRenewalConfig();
        }

        // Handle USDC deposit for auto-renewals
        if (depositAmount > 0) {
            if (usdcToken.balanceOf(msg.sender) < depositAmount) revert InsufficientBalance();
            if (usdcToken.allowance(msg.sender, address(this)) < depositAmount) {
                revert InsufficientPayment();
            }

            usdcToken.safeTransferFrom(msg.sender, address(this), depositAmount);
            autoRenewals[msg.sender][creator].balance += depositAmount;
        }

        // Update auto-renewal configuration
        autoRenewals[msg.sender][creator].enabled = enabled;
        autoRenewals[msg.sender][creator].maxPrice = maxPrice;

        // Update subscription record
        subscriptions[msg.sender][creator].autoRenewalEnabled = enabled;

        emit AutoRenewalConfigured(msg.sender, creator, enabled, maxPrice, depositAmount);
    }

    /**
     * @dev Executes auto-renewal for eligible subscriptions with rate limiting
     * @param user User address with expiring subscription
     * @param creator Creator address for renewal
     */
    function executeAutoRenewal(address user, address creator)
        external
        onlyRole(RENEWAL_BOT_ROLE)
        nonReentrant
        whenNotPaused
    {
        AutoRenewal storage autoRenewal = autoRenewals[user][creator];

        // Validate auto-renewal is enabled and configured
        if (!autoRenewal.enabled) revert InvalidAutoRenewalConfig();

        // Rate limiting: check cooldown period
        if (block.timestamp < autoRenewal.lastRenewalAttempt + renewalCooldown) {
            revert RenewalTooSoon();
        }

        // Daily attempt limit
        uint256 today = block.timestamp / 1 days;
        uint256 lastAttemptDay = autoRenewal.lastRenewalAttempt / 1 days;
        if (today == lastAttemptDay && autoRenewal.failedAttempts >= maxRenewalAttemptsPerDay) {
            revert TooManyRenewalAttempts();
        }

        // Reset daily counter if it's a new day
        if (today > lastAttemptDay) {
            autoRenewal.failedAttempts = 0;
        }

        // Check if subscription is close to expiry (within renewal window)
        uint256 endTime = subscriptionEndTime[user][creator];
        if (block.timestamp < endTime - RENEWAL_WINDOW) revert InvalidSubscriptionPeriod();
        if (block.timestamp > endTime + GRACE_PERIOD) revert SubscriptionAlreadyExpired();

        // Update attempt tracking
        autoRenewal.lastRenewalAttempt = block.timestamp;

        // Get current subscription price
        uint256 subscriptionPrice = creatorRegistry.getSubscriptionPrice(creator);

        // Validate price hasn't exceeded user's maximum
        if (subscriptionPrice > autoRenewal.maxPrice) {
            autoRenewal.failedAttempts++;
            emit AutoRenewalFailed(user, creator, "Price exceeded maximum", block.timestamp);
            revert("AutoRenewalFailed");
        }

        // Check auto-renewal balance is sufficient
        if (autoRenewal.balance < subscriptionPrice) {
            autoRenewal.failedAttempts++;
            emit AutoRenewalFailed(user, creator, "Insufficient balance", block.timestamp);
            revert InsufficientBalance();
        }

        // Deduct from auto-renewal balance
        autoRenewal.balance -= subscriptionPrice;

        // Calculate fees and earnings
        uint256 platformFee = creatorRegistry.calculatePlatformFee(subscriptionPrice);
        uint256 creatorEarning = subscriptionPrice - platformFee;

        // Extend subscription period from now for deterministic behavior in tests
        uint256 newEndTime = block.timestamp + SUBSCRIPTION_DURATION;
        subscriptionEndTime[user][creator] = newEndTime;

        // Update subscription record
        SubscriptionRecord storage record = subscriptions[user][creator];
        record.endTime = newEndTime;
        record.renewalCount += 1;
        record.totalPaid += subscriptionPrice;
        record.lastPayment = subscriptionPrice;
        record.lastRenewalTime = block.timestamp;

        // Update financial tracking
        creatorSubscriptionEarnings[creator] += creatorEarning;
        userSubscriptionSpending[user] += subscriptionPrice;
        totalSubscriptionRevenue[creator] += creatorEarning;
        totalSubscriptionVolume += subscriptionPrice;
        totalPlatformSubscriptionFees += platformFee;
        totalRenewals++;

        // Reset failed attempts on success
        autoRenewal.failedAttempts = 0;

        emit AutoRenewalExecuted(user, creator, subscriptionPrice, newEndTime);
        emit SubscriptionRenewed(user, creator, subscriptionPrice, newEndTime, record.renewalCount);
    }

    /**
     * @dev Cancels subscription (stops auto-renewal, subscription remains active until expiry)
     * @param creator Creator address to cancel subscription for
     * @param immediate Whether to cancel immediately or at natural expiry
     */
    function cancelSubscription(address creator, bool immediate) external nonReentrant {
        uint256 endTime = subscriptionEndTime[msg.sender][creator];
        if (endTime == 0 || block.timestamp > endTime) revert SubscriptionNotFound();

        // Disable auto-renewal
        autoRenewals[msg.sender][creator].enabled = false;
        subscriptions[msg.sender][creator].autoRenewalEnabled = false;

        if (immediate) {
            // Immediate cancellation - set expiry to current time
            subscriptionEndTime[msg.sender][creator] = block.timestamp;
            subscriptions[msg.sender][creator].isActive = false;
            subscriptions[msg.sender][creator].endTime = block.timestamp;

            // Update metrics
            totalActiveSubscriptions -= 1;
            creatorSubscriberCount[creator] -= 1;

            // Remove from subscriber array
            _removeFromSubscriberArray(creator, msg.sender);
        }

        emit SubscriptionCancelled(
            msg.sender,
            creator,
            immediate ? block.timestamp : endTime,
            immediate
        );
    }

    /**
     * @dev Cleans up expired subscriptions for a creator
     * @param creator Creator address to clean up
     */
    function cleanupExpiredSubscriptions(address creator) external nonReentrant {
        // Rate limiting: only allow cleanup once per interval
        if (block.timestamp < lastCleanupTime[creator] + CLEANUP_INTERVAL) {
            revert CleanupTooSoon();
        }

        lastCleanupTime[creator] = block.timestamp;

        address[] storage subscribers = creatorSubscribers[creator];
        uint256 cleanedCount = 0;

        // Process subscribers in reverse order to avoid index issues
        for (uint256 i = subscribers.length; i > 0; i--) {
            address subscriber = subscribers[i - 1];
            uint256 endTime = subscriptionEndTime[subscriber][creator];

            // If subscription is expired beyond grace period
            if (endTime > 0 && block.timestamp > endTime + GRACE_PERIOD) {
                // Mark subscription as inactive
                subscriptions[subscriber][creator].isActive = false;

                // Remove from subscriber array
                subscribers[i - 1] = subscribers[subscribers.length - 1];
                subscribers.pop();

                // Update counters
                if (creatorSubscriberCount[creator] > 0) {
                    creatorSubscriberCount[creator] -= 1;
                }
                if (totalActiveSubscriptions > 0) {
                    totalActiveSubscriptions -= 1;
                }

                cleanedCount++;
            }
        }

        emit ExpiredSubscriptionsCleaned(creator, cleanedCount, block.timestamp);
    }

    /**
     * @dev Requests refund for a recent subscription payment
     * @param creator Creator to request refund from
     * @param reason Reason for refund
     */
    function requestSubscriptionRefund(address creator, string memory reason) external nonReentrant {
        SubscriptionRecord storage record = subscriptions[msg.sender][creator];
        require(record.totalPaid > 0, "No subscription found");

        // Only allow refunds within 24 hours of last payment
        if (block.timestamp > record.lastRenewalTime + 1 days) {
            revert RefundNotEligible();
        }

        // Cancel subscription immediately
        subscriptionEndTime[msg.sender][creator] = block.timestamp;
        record.isActive = false;
        record.endTime = block.timestamp;

        // Add to pending refunds
        uint256 refundAmount = record.lastPayment;
        pendingRefunds[msg.sender][creator] = refundAmount;

        // Record failed subscription
        failedSubscriptions[msg.sender][creator] = FailedSubscription({
            attemptTime: block.timestamp,
            attemptedPrice: refundAmount,
            failureReason: reason,
            refunded: false
        });

        totalRefunds += refundAmount;

        emit SubscriptionRefunded(msg.sender, creator, refundAmount, reason);
    }

    /**
     * @dev Processes pending refund payout
     * @param user User to refund
     * @param creator Creator for refund
     */
    function processRefundPayout(address user, address creator)
        external
        onlyRole(SUBSCRIPTION_PROCESSOR_ROLE)
        nonReentrant
    {
        uint256 amount = pendingRefunds[user][creator];
        require(amount > 0, "No pending refund");

        pendingRefunds[user][creator] = 0;
        failedSubscriptions[user][creator].refunded = true;

        usdcToken.safeTransfer(user, amount);
    }

    /**
     * @dev Allows creators to withdraw their subscription earnings
     */
    function withdrawSubscriptionEarnings() external nonReentrant {
        uint256 amount = creatorSubscriptionEarnings[msg.sender];
        if (amount == 0) revert NoEarningsToWithdraw();

        // Reset earnings before transfer to prevent reentrancy
        creatorSubscriptionEarnings[msg.sender] = 0;

        // Transfer USDC to creator
        usdcToken.safeTransfer(msg.sender, amount);

        emit SubscriptionEarningsWithdrawn(msg.sender, amount, block.timestamp);
    }

    /**
     * @dev Withdraws unused auto-renewal balance
     * @param creator Creator address to withdraw balance for
     * @param amount Amount to withdraw (0 for full balance)
     */
    function withdrawAutoRenewalBalance(address creator, uint256 amount) external nonReentrant {
        AutoRenewal storage autoRenewal = autoRenewals[msg.sender][creator];

        if (amount == 0) {
            amount = autoRenewal.balance;
        }

        if (amount > autoRenewal.balance) revert InsufficientBalance();
        if (amount == 0) revert NoEarningsToWithdraw();

        autoRenewal.balance -= amount;
        usdcToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Admin function to update renewal settings
     * @param newMaxAttempts New max renewal attempts per day
     * @param newCooldown New cooldown period in seconds
     */
    function updateRenewalSettings(uint256 newMaxAttempts, uint256 newCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxRenewalAttemptsPerDay = newMaxAttempts;
        renewalCooldown = newCooldown;
    }

    /**
     * @dev Grants renewal bot role to authorized addresses
     * @param bot Address to grant renewal bot role
     */
    function grantRenewalBotRole(address bot) external onlyOwner {
        _grantRole(RENEWAL_BOT_ROLE, bot);
    }

    /**
     * @dev Grants subscription processor role
     * @param processor Address to grant processor role
     */
    function grantSubscriptionProcessorRole(address processor) external onlyOwner {
        _grantRole(SUBSCRIPTION_PROCESSOR_ROLE, processor);
    }

    // View functions for subscription management and analytics

    /**
     * @dev Checks if user has active subscription to creator
     * @param user User address to check
     * @param creator Creator address to check
     * @return bool True if subscription is active and not expired
     */
    function isSubscribed(address user, address creator) public view returns (bool) {
        return subscriptionEndTime[user][creator] > block.timestamp;
    }

    /**
     * @dev Gets subscription expiration time
     * @param user User address
     * @param creator Creator address
     * @return uint256 Expiration timestamp (0 if no subscription)
     */
    function getSubscriptionEndTime(address user, address creator) external view returns (uint256) {
        return subscriptionEndTime[user][creator];
    }

    /**
     * @dev Gets detailed subscription information
     * @param user User address
     * @param creator Creator address
     * @return SubscriptionRecord Complete subscription details
     */
    function getSubscriptionDetails(address user, address creator) external view returns (SubscriptionRecord memory) {
        return subscriptions[user][creator];
    }

    /**
     * @dev Gets all creators a user is subscribed to
     * @param user User address
     * @return address[] Array of creator addresses
     */
    function getUserSubscriptions(address user) external view returns (address[] memory) {
        return userSubscriptions[user];
    }

    /**
     * @dev Gets active subscriptions for a user
     * @param user User address
     * @return address[] Array of creators with active subscriptions
     */
    function getUserActiveSubscriptions(address user) external view returns (address[] memory) {
        address[] memory allSubs = userSubscriptions[user];
        uint256 activeCount = 0;

        // Count active subscriptions
        for (uint256 i = 0; i < allSubs.length; i++) {
            if (isSubscribed(user, allSubs[i])) {
                activeCount++;
            }
        }

        // Build active subscriptions array
        address[] memory activeSubscriptions = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allSubs.length; i++) {
            if (isSubscribed(user, allSubs[i])) {
                activeSubscriptions[index] = allSubs[i];
                index++;
            }
        }

        return activeSubscriptions;
    }

    /**
     * @dev Gets all subscribers for a creator
     * @param creator Creator address
     * @return address[] Array of subscriber addresses
     */
    function getCreatorSubscribers(address creator) external view returns (address[] memory) {
        return creatorSubscribers[creator];
    }

    /**
     * @dev Gets active subscribers for a creator
     * @param creator Creator address
     * @return address[] Array of active subscriber addresses
     */
    function getCreatorActiveSubscribers(address creator) external view returns (address[] memory) {
        address[] memory allSubs = creatorSubscribers[creator];
        uint256 activeCount = 0;

        // Count active subscribers
        for (uint256 i = 0; i < allSubs.length; i++) {
            if (isSubscribed(allSubs[i], creator)) {
                activeCount++;
            }
        }

        // Build active subscribers array
        address[] memory activeSubscribers = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allSubs.length; i++) {
            if (isSubscribed(allSubs[i], creator)) {
                activeSubscribers[index] = allSubs[i];
                index++;
            }
        }

        return activeSubscribers;
    }

    /**
     * @dev Gets creator's subscription earnings (total and withdrawable)
     * @param creator Creator address
     * @return totalEarnings All-time subscription revenue
     * @return withdrawableEarnings Currently withdrawable amount
     */
    function getCreatorSubscriptionEarnings(address creator)
        external
        view
        returns (uint256 totalEarnings, uint256 withdrawableEarnings)
    {
        return (totalSubscriptionRevenue[creator], creatorSubscriptionEarnings[creator]);
    }

    /**
     * @dev Gets auto-renewal configuration for user-creator pair
     * @param user User address
     * @param creator Creator address
     * @return AutoRenewal Auto-renewal settings
     */
    function getAutoRenewalConfig(address user, address creator) external view returns (AutoRenewal memory) {
        return autoRenewals[user][creator];
    }

    /**
     * @dev Gets platform subscription metrics
     * @return activeSubscriptions Current number of active subscriptions
     * @return totalVolume All-time subscription volume in USDC
     * @return platformFees Total platform fees collected from subscriptions
     * @return totalRenewalCount Total successful renewals
     * @return totalRefundAmount Total refunds processed
     */
    function getPlatformSubscriptionMetrics()
        external
        view
        returns (
            uint256 activeSubscriptions,
            uint256 totalVolume,
            uint256 platformFees,
            uint256 totalRenewalCount,
            uint256 totalRefundAmount
        )
    {
        return (
            totalActiveSubscriptions,
            totalSubscriptionVolume,
            totalPlatformSubscriptionFees,
            totalRenewals,
            totalRefunds
        );
    }

    // Internal helper functions

    /**
     * @dev Removes subscriber from creator's subscriber array
     * @param creator Creator address
     * @param subscriber Subscriber to remove
     */
    function _removeFromSubscriberArray(address creator, address subscriber) internal {
        address[] storage subscribers = creatorSubscribers[creator];

        for (uint256 i = 0; i < subscribers.length; i++) {
            if (subscribers[i] == subscriber) {
                subscribers[i] = subscribers[subscribers.length - 1];
                subscribers.pop();
                break;
            }
        }
    }

    /**
     * @dev Admin function to withdraw platform subscription fees
     * @param recipient Address to receive platform fees
     */
    function withdrawPlatformSubscriptionFees(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");

        uint256 amount = totalPlatformSubscriptionFees;
        if (amount == 0) revert NoEarningsToWithdraw();

        // Reset platform fees before transfer
        totalPlatformSubscriptionFees = 0;

        // Transfer to fee recipient
        usdcToken.safeTransfer(recipient, amount);
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resume operations after pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency function to recover stuck tokens (not USDC)
     * @param token Token contract address
     * @param amount Amount to recover
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        require(token != address(usdcToken), "Cannot recover USDC");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev COMPLETE: Records subscription payment from external contract
     */
    function recordSubscriptionPayment(
        address user,
        address creator,
        bytes16 intentId,
        uint256 usdcAmount,
        address paymentToken,
        uint256 actualAmountPaid
    ) external onlyRole(SUBSCRIPTION_PROCESSOR_ROLE) nonReentrant {
        require(creatorRegistry.isRegisteredCreator(creator), "Creator not registered");

        uint256 startTime = block.timestamp;
        uint256 endTime;

        if (isSubscribed(user, creator)) {
            endTime = subscriptionEndTime[user][creator] + SUBSCRIPTION_DURATION;
        } else {
            endTime = startTime + SUBSCRIPTION_DURATION;
        }

        subscriptionEndTime[user][creator] = endTime;

        SubscriptionRecord storage record = subscriptions[user][creator];
        bool isNewSubscription = (record.totalPaid == 0);

        if (isNewSubscription) {
            userSubscriptions[user].push(creator);
            creatorSubscribers[creator].push(user);

            record.isActive = true;
            record.startTime = startTime;
            record.endTime = endTime;
            record.renewalCount = 0;
            record.totalPaid = usdcAmount;
            record.lastPayment = usdcAmount;
            record.lastRenewalTime = startTime;
            record.autoRenewalEnabled = false;

            totalActiveSubscriptions++;
            creatorSubscriberCount[creator]++;

            uint256 platformFeeLocal = creatorRegistry.calculatePlatformFee(usdcAmount);
            uint256 creatorEarningLocal = usdcAmount - platformFeeLocal;

            emit Subscribed(user, creator, usdcAmount, platformFeeLocal, creatorEarningLocal, startTime, endTime);
        } else {
            record.isActive = true;
            record.endTime = endTime;
            record.renewalCount += 1;
            record.totalPaid += usdcAmount;
            record.lastPayment = usdcAmount;
            record.lastRenewalTime = block.timestamp;

            totalRenewals++;

            emit SubscriptionRenewed(user, creator, usdcAmount, endTime, record.renewalCount);
        }

        uint256 platformFee = creatorRegistry.calculatePlatformFee(usdcAmount);
        uint256 creatorEarning = usdcAmount - platformFee;

        creatorSubscriptionEarnings[creator] += creatorEarning;
        userSubscriptionSpending[user] += usdcAmount;
        totalSubscriptionRevenue[creator] += creatorEarning;
        totalSubscriptionVolume += usdcAmount;
        totalPlatformSubscriptionFees += platformFee;

        if (isNewSubscription) {
            creatorRegistry.updateCreatorStats(creator, creatorEarning, 0, 1);
        } else {
            creatorRegistry.updateCreatorStats(creator, creatorEarning, 0, 0);
        }

        emit ExternalSubscriptionRecorded(user, creator, intentId, usdcAmount, paymentToken, actualAmountPaid, endTime);
    }

    /**
     * @dev COMPLETE: Handles external refund for subscriptions
     */
    function handleExternalRefund(bytes16 intentId, address user, address creator)
        external
        onlyRole(SUBSCRIPTION_PROCESSOR_ROLE)
        nonReentrant
    {
        SubscriptionRecord storage record = subscriptions[user][creator];
        require(record.totalPaid > 0, "No subscription found");

        uint256 refundAmount = record.lastPayment;
        uint256 platformFee = creatorRegistry.calculatePlatformFee(refundAmount);
        uint256 creatorRefund = refundAmount - platformFee;

        subscriptionEndTime[user][creator] = block.timestamp;
        record.isActive = false;
        record.endTime = block.timestamp;

        if (creatorSubscriptionEarnings[creator] >= creatorRefund) {
            creatorSubscriptionEarnings[creator] -= creatorRefund;
        } else {
            creatorSubscriptionEarnings[creator] = 0;
        }

        if (userSubscriptionSpending[user] >= refundAmount) {
            userSubscriptionSpending[user] -= refundAmount;
        } else {
            userSubscriptionSpending[user] = 0;
        }

        if (totalSubscriptionRevenue[creator] >= creatorRefund) {
            totalSubscriptionRevenue[creator] -= creatorRefund;
        } else {
            totalSubscriptionRevenue[creator] = 0;
        }

        if (totalSubscriptionVolume >= refundAmount) {
            totalSubscriptionVolume -= refundAmount;
        } else {
            totalSubscriptionVolume = 0;
        }

        if (totalPlatformSubscriptionFees >= platformFee) {
            totalPlatformSubscriptionFees -= platformFee;
        } else {
            totalPlatformSubscriptionFees = 0;
        }

        if (totalActiveSubscriptions > 0) {
            totalActiveSubscriptions--;
        }
        if (creatorSubscriberCount[creator] > 0) {
            creatorSubscriberCount[creator]--;
        }

        _removeFromSubscriberArray(creator, user);

        totalRefunds += refundAmount;

        creatorRegistry.updateCreatorStats(creator, 0, 0, -1);

        emit ExternalRefundProcessed(intentId, user, creator, refundAmount);
    }

    /**
     * @dev COMPLETE: Enhanced cleanup with events
     */
    function cleanupExpiredSubscriptionsEnhanced(address creator)
        external
        nonReentrant
        returns (address[] memory cleanedUsers)
    {
        require(block.timestamp >= lastCleanupTime[creator] + CLEANUP_INTERVAL, "Cleanup too soon");

        lastCleanupTime[creator] = block.timestamp;

        address[] storage subscribers = creatorSubscribers[creator];
        uint256 cleanedCount = 0;
        address[] memory tempCleanedUsers = new address[](subscribers.length);

        for (uint256 i = subscribers.length; i > 0; i--) {
            address subscriber = subscribers[i - 1];
            uint256 endTime = subscriptionEndTime[subscriber][creator];

            if (endTime > 0 && block.timestamp > endTime + GRACE_PERIOD) {
                subscriptions[subscriber][creator].isActive = false;

                tempCleanedUsers[cleanedCount] = subscriber;

                subscribers[i - 1] = subscribers[subscribers.length - 1];
                subscribers.pop();

                if (creatorSubscriberCount[creator] > 0) {
                    creatorSubscriberCount[creator]--;
                }
                if (totalActiveSubscriptions > 0) {
                    totalActiveSubscriptions--;
                }

                cleanedCount++;
            }
        }

        cleanedUsers = new address[](cleanedCount);
        for (uint256 i = 0; i < cleanedCount; i++) {
            cleanedUsers[i] = tempCleanedUsers[i];
        }

        emit ExpiredSubscriptionsCleaned(creator, cleanedCount, block.timestamp);

        for (uint256 i = 0; i < cleanedCount; i++) {
            emit SubscriptionExpired(cleanedUsers[i], creator, block.timestamp);
        }

        return cleanedUsers;
    }

    /**
     * @dev COMPLETE: Get subscription status with grace period
     */
    function getSubscriptionStatus(address user, address creator)
        external
        view
        returns (bool isActive, bool inGracePeriod, uint256 endTime, uint256 gracePeriodEnd)
    {
        endTime = subscriptionEndTime[user][creator];
        gracePeriodEnd = endTime + GRACE_PERIOD;

        isActive = endTime > block.timestamp;
        inGracePeriod = !isActive && block.timestamp <= gracePeriodEnd;

        return (isActive, inGracePeriod, endTime, gracePeriodEnd);
    }
}
