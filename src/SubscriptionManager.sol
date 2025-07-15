// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./CreatorRegistry.sol";
import "./ContentRegistry.sol";

**
 * @title SubscriptionManager
 * @dev Manages time-based subscriptions to creators with automatic access control
 * @notice This contract handles monthly subscriptions giving users access to all creator content
 */
contract SubscriptionManager is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Contract dependencies for validation and pricing
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    IERC20 public immutable usdcToken; // USDC token contract on Base
    
    // Subscription duration configuration
    uint256 public constant SUBSCRIPTION_DURATION = 30 days; // Fixed 30-day subscriptions
    uint256 public constant GRACE_PERIOD = 3 days; // Grace period for expired subscriptions
    
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
    
    /**
     * @dev Detailed subscription record for analytics and management
     * @param isActive Current subscription status
     * @param startTime When subscription began
     * @param endTime When subscription expires
     * @param renewalCount Number of times subscription has been renewed
     * @param totalPaid Total amount paid for this creator's subscription
     * @param lastPayment Amount of most recent payment
     */
    struct SubscriptionRecord {
        bool isActive;              // Active subscription status
        uint256 startTime;          // Initial subscription timestamp
        uint256 endTime;            // Current expiration timestamp
        uint256 renewalCount;       // Number of renewals
        uint256 totalPaid;          // Total USDC paid to this creator
        uint256 lastPayment;        // Most recent payment amount
    }
    
    /**
     * @dev Auto-renewal configuration for convenience
     * @param enabled Whether auto-renewal is enabled
     * @param maxPrice Maximum price willing to pay for auto-renewal
     * @param balance Pre-deposited balance for auto-renewals
     */
    struct AutoRenewal {
        bool enabled;               // Auto-renewal status
        uint256 maxPrice;           // Maximum acceptable price for renewal
        uint256 balance;            // Pre-deposited USDC balance for renewals
    }
    
    // Auto-renewal management: user => creator => auto-renewal settings
    mapping(address => mapping(address => AutoRenewal)) public autoRenewals;
    
    // Platform subscription metrics
    uint256 public totalActiveSubscriptions;    // Current active subscription count
    uint256 public totalSubscriptionVolume;     // All-time subscription revenue volume
    uint256 public totalPlatformSubscriptionFees; // Platform fees from subscriptions
    
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
        address indexed user,
        address indexed creator,
        uint256 price,
        uint256 newEndTime,
        uint256 renewalCount
    );
    
    event SubscriptionCancelled(
        address indexed user,
        address indexed creator,
        uint256 endTime,
        bool immediate
    );
    
    event AutoRenewalConfigured(
        address indexed user,
        address indexed creator,
        bool enabled,
        uint256 maxPrice,
        uint256 depositAmount
    );
    
    event AutoRenewalExecuted(
        address indexed user,
        address indexed creator,
        uint256 price,
        uint256 newEndTime
    );
    
    event SubscriptionEarningsWithdrawn(
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );
    
    // Custom errors for efficient error handling
    error CreatorNotRegistered();
    error AlreadySubscribed();
    error SubscriptionNotFound();
    error SubscriptionExpired();
    error InsufficientPayment();
    error InsufficientBalance();
    error InvalidAutoRenewalConfig();
    error AutoRenewalFailed();
    error NoEarningsToWithdraw();
    error InvalidSubscriptionPeriod();
    
    /**
     * @dev Constructor initializes subscription manager with required contracts
     * @param _creatorRegistry Address of CreatorRegistry contract
     * @param _contentRegistry Address of ContentRegistry contract  
     * @param _usdcToken Address of USDC token contract on Base
     */
    constructor(
        address _creatorRegistry,
        address _contentRegistry,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_usdcToken != address(0), "Invalid USDC token");
        
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        usdcToken = IERC20(_usdcToken);
    }
    
    /**
     * @dev Subscribes user to a creator for 30 days with USDC payment
     * @param creator Address of creator to subscribe to
     * @notice Requires USDC allowance for subscription price + platform fee
     */
    function subscribeToCreator(address creator) 
        external 
        nonReentrant 
        whenNotPaused 
    {
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
        } else {
            // Renewal of existing subscription
            record.isActive = true;
            record.endTime = endTime;
            record.renewalCount += 1;
            record.totalPaid += subscriptionPrice;
            record.lastPayment = subscriptionPrice;
            
            emit SubscriptionRenewed(
                msg.sender,
                creator,
                subscriptionPrice,
                endTime,
                record.renewalCount
            );
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
        
        emit Subscribed(
            msg.sender,
            creator,
            subscriptionPrice,
            platformFee,
            creatorEarning,
            startTime,
            endTime
        );
    }
    
    /**
     * @dev Configures auto-renewal for a creator subscription
     * @param creator Creator address for auto-renewal
     * @param enabled Whether to enable auto-renewal
     * @param maxPrice Maximum price willing to pay for auto-renewal
     * @param depositAmount Additional USDC to deposit for auto-renewals
     */
    function configureAutoRenewal(
        address creator,
        bool enabled,
        uint256 maxPrice,
        uint256 depositAmount
    ) external nonReentrant whenNotPaused {
        
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
        
        emit AutoRenewalConfigured(msg.sender, creator, enabled, maxPrice, depositAmount);
    }
    
    /**
     * @dev Executes auto-renewal for eligible subscriptions (can be called by anyone)
     * @param user User address with expiring subscription
     * @param creator Creator address for renewal
     * @notice This function enables automated subscription renewals via keepers or bots
     */
    function executeAutoRenewal(address user, address creator) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        AutoRenewal storage autoRenewal = autoRenewals[user][creator];
        
        // Validate auto-renewal is enabled and configured
        if (!autoRenewal.enabled) revert InvalidAutoRenewalConfig();
        
        // Check if subscription is close to expiry (within 24 hours)
        uint256 endTime = subscriptionEndTime[user][creator];
        if (block.timestamp < endTime - 1 days) revert InvalidSubscriptionPeriod();
        if (block.timestamp > endTime + GRACE_PERIOD) revert SubscriptionExpired();
        
        // Get current subscription price
        uint256 subscriptionPrice = creatorRegistry.getSubscriptionPrice(creator);
        
        // Validate price hasn't exceeded user's maximum
        if (subscriptionPrice > autoRenewal.maxPrice) revert AutoRenewalFailed();
        
        // Check auto-renewal balance is sufficient
        if (autoRenewal.balance < subscriptionPrice) revert InsufficientBalance();
        
        // Deduct from auto-renewal balance
        autoRenewal.balance -= subscriptionPrice;
        
        // Calculate fees and earnings
        uint256 platformFee = creatorRegistry.calculatePlatformFee(subscriptionPrice);
        uint256 creatorEarning = subscriptionPrice - platformFee;
        
        // Extend subscription period
        uint256 newEndTime = endTime + SUBSCRIPTION_DURATION;
        subscriptionEndTime[user][creator] = newEndTime;
        
        // Update subscription record
        SubscriptionRecord storage record = subscriptions[user][creator];
        record.endTime = newEndTime;
        record.renewalCount += 1;
        record.totalPaid += subscriptionPrice;
        record.lastPayment = subscriptionPrice;
        
        // Update financial tracking
        creatorSubscriptionEarnings[creator] += creatorEarning;
        userSubscriptionSpending[user] += subscriptionPrice;
        totalSubscriptionRevenue[creator] += creatorEarning;
        totalSubscriptionVolume += subscriptionPrice;
        totalPlatformSubscriptionFees += platformFee;
        
        emit AutoRenewalExecuted(user, creator, subscriptionPrice, newEndTime);
        emit SubscriptionRenewed(user, creator, subscriptionPrice, newEndTime, record.renewalCount);
    }
    
    /**
     * @dev Cancels subscription (stops auto-renewal, subscription remains active until expiry)
     * @param creator Creator address to cancel subscription for
     * @param immediate Whether to cancel immediately or at natural expiry
     */
    function cancelSubscription(address creator, bool immediate) 
        external 
        nonReentrant 
    {
        uint256 endTime = subscriptionEndTime[msg.sender][creator];
        if (endTime == 0 || block.timestamp > endTime) revert SubscriptionNotFound();
        
        // Disable auto-renewal
        autoRenewals[msg.sender][creator].enabled = false;
        
        if (immediate) {
            // Immediate cancellation - set expiry to current time
            subscriptionEndTime[msg.sender][creator] = block.timestamp;
            subscriptions[msg.sender][creator].isActive = false;
            subscriptions[msg.sender][creator].endTime = block.timestamp;
            
            // Update metrics
            totalActiveSubscriptions -= 1;
            creatorSubscriberCount[creator] -= 1;
        }
        
        emit SubscriptionCancelled(msg.sender, creator, endTime, immediate);
    }
    
    /**
     * @dev Allows creators to withdraw their subscription earnings
     * @notice Transfers accumulated USDC subscription revenue to creator
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
    function withdrawAutoRenewalBalance(address creator, uint256 amount) 
        external 
        nonReentrant 
    {
        AutoRenewal storage autoRenewal = autoRenewals[msg.sender][creator];
        
        if (amount == 0) {
            amount = autoRenewal.balance;
        }
        
        if (amount > autoRenewal.balance) revert InsufficientBalance();
        if (amount == 0) revert NoEarningsToWithdraw();
        
        autoRenewal.balance -= amount;
        usdcToken.safeTransfer(msg.sender, amount);
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
    function getSubscriptionEndTime(address user, address creator) 
        external 
        view 
        returns (uint256) 
    {
        return subscriptionEndTime[user][creator];
    }
    
    /**
     * @dev Gets detailed subscription information
     * @param user User address
     * @param creator Creator address
     * @return SubscriptionRecord Complete subscription details
     */
    function getSubscriptionDetails(address user, address creator) 
        external 
        view 
        returns (SubscriptionRecord memory) 
    {
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
     * @dev Gets all subscribers for a creator
     * @param creator Creator address
     * @return address[] Array of subscriber addresses
     */
    function getCreatorSubscribers(address creator) external view returns (address[] memory) {
        return creatorSubscribers[creator];
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
    function getAutoRenewalConfig(address user, address creator) 
        external 
        view 
        returns (AutoRenewal memory) 
    {
        return autoRenewals[user][creator];
    }
    
    /**
     * @dev Gets platform subscription metrics
     * @return activeSubscriptions Current number of active subscriptions
     * @return totalVolume All-time subscription volume in USDC
     * @return platformFees Total platform fees collected from subscriptions
     */
    function getPlatformSubscriptionMetrics() 
        external 
        view 
        returns (uint256 activeSubscriptions, uint256 totalVolume, uint256 platformFees) 
    {
        return (totalActiveSubscriptions, totalSubscriptionVolume, totalPlatformSubscriptionFees);
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
}