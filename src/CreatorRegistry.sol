// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";


/**
 * @title CreatorRegistry
 * @dev Manages creator profiles, subscription pricing, and verification status
 * @notice This contract handles creator registration and subscription management for the content platform
 */
contract CreatorRegistry is Ownable, ReentrancyGuard, Pausable {
    // State variables for subscription pricing limits (in USDC with 6 decimals)
    uint256 public constant MIN_SUBSCRIPTION_PRICE = 0.01e6; // $0.01 minimum
    uint256 public constant MAX_SUBSCRIPTION_PRICE = 100e6;  // $100 maximum
    uint256 public constant SUBSCRIPTION_DURATION = 30 days; // Fixed 30-day subscriptions
    
    // Platform fee configuration (basis points - 250 = 2.5%)
    uint256 public platformFee = 250; // 2.5% platform fee
    address public feeRecipient;
    
    /**
     * @dev Creator profile structure containing essential creator information
     * @param isRegistered Whether the creator is registered on the platform
     * @param subscriptionPrice Monthly subscription price in USDC (6 decimals)
     * @param isVerified Platform verification status for trusted creators
     * @param totalEarnings Cumulative earnings for analytics and reputation
     * @param contentCount Number of content pieces published by creator
     * @param subscriberCount Current number of active subscribers
     */
    struct Creator {
        bool isRegistered;           // Registration status
        uint256 subscriptionPrice;  // Monthly price in USDC (6 decimals)
        bool isVerified;            // Verification badge status
        uint256 totalEarnings;      // Lifetime earnings for reputation
        uint256 contentCount;       // Published content counter
        uint256 subscriberCount;    // Active subscriber count
    }
    
    // Storage mappings for efficient data access
    mapping(address => Creator) public creators;
    mapping(address => uint256) public creatorJoinDate; // Track registration timestamp
    
    // Dynamic arrays for iteration and analytics
    address[] public allCreators;
    
    // Events for frontend integration and analytics
    event CreatorRegistered(
        address indexed creator, 
        uint256 subscriptionPrice, 
        uint256 timestamp
    );
    
    event SubscriptionPriceUpdated(
        address indexed creator, 
        uint256 oldPrice, 
        uint256 newPrice
    );
    
    event CreatorVerified(address indexed creator, bool verified);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    
    // Custom errors for gas-efficient error handling
    error CreatorAlreadyRegistered();
    error CreatorNotRegistered();
    error InvalidSubscriptionPrice();
    error InvalidFeePercentage();
    error InvalidFeeRecipient();
    error UnauthorizedAccess();
    
    /**
     * @dev Constructor sets up the contract with initial configuration
     * @param _feeRecipient Address that will receive platform fees
     */
    constructor(address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev Registers a new creator with subscription pricing
     * @param subscriptionPrice Monthly subscription price in USDC (6 decimals)
     * @notice Price must be between $0.01 and $100 to prevent abuse
     */
    function registerCreator(uint256 subscriptionPrice) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (creators[msg.sender].isRegistered) revert CreatorAlreadyRegistered();
        if (subscriptionPrice < MIN_SUBSCRIPTION_PRICE || 
            subscriptionPrice > MAX_SUBSCRIPTION_PRICE) {
            revert InvalidSubscriptionPrice();
        }
        
        // Initialize creator profile with provided subscription price
        creators[msg.sender] = Creator({
            isRegistered: true,
            subscriptionPrice: subscriptionPrice,
            isVerified: false,           // Verification requires admin approval
            totalEarnings: 0,            // Starts at zero
            contentCount: 0,             // No content initially
            subscriberCount: 0           // No subscribers initially
        });
        
        // Track registration timestamp and add to creator list
        creatorJoinDate[msg.sender] = block.timestamp;
        allCreators.push(msg.sender);
        
        emit CreatorRegistered(msg.sender, subscriptionPrice, block.timestamp);
    }
    
    /**
     * @dev Updates creator's subscription price with validation
     * @param newPrice New monthly subscription price in USDC (6 decimals)
     */
    function updateSubscriptionPrice(uint256 newPrice) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!creators[msg.sender].isRegistered) revert CreatorNotRegistered();
        if (newPrice < MIN_SUBSCRIPTION_PRICE || newPrice > MAX_SUBSCRIPTION_PRICE) {
            revert InvalidSubscriptionPrice();
        }
        
        uint256 oldPrice = creators[msg.sender].subscriptionPrice;
        creators[msg.sender].subscriptionPrice = newPrice;
        
        emit SubscriptionPriceUpdated(msg.sender, oldPrice, newPrice);
    }
    
    /**
     * @dev Admin function to verify creators (adds verification badge)
     * @param creator Address of creator to verify/unverify
     * @param verified True to verify, false to remove verification
     */
    function setCreatorVerification(address creator, bool verified) 
        external 
        onlyOwner 
    {
        if (!creators[creator].isRegistered) revert CreatorNotRegistered();
        
        creators[creator].isVerified = verified;
        emit CreatorVerified(creator, verified);
    }
    
    /**
     * @dev Updates creator stats (called by other platform contracts)
     * @param creator Creator address to update
     * @param earnings Additional earnings to add
     * @param contentDelta Change in content count (+1 for new content)
     * @param subscriberDelta Change in subscriber count (+1/-1)
     */
    function updateCreatorStats(
        address creator,
        uint256 earnings,
        int256 contentDelta,
        int256 subscriberDelta
    ) external {
        // Only allow calls from other platform contracts (ContentRegistry, SubscriptionManager)
        // This would be enhanced with a proper access control system in production
        if (!creators[creator].isRegistered) revert CreatorNotRegistered();
        
        creators[creator].totalEarnings += earnings;
        
        // Handle content count updates safely
        if (contentDelta > 0) {
            creators[creator].contentCount += uint256(contentDelta);
        } else if (contentDelta < 0 && creators[creator].contentCount > 0) {
            creators[creator].contentCount -= uint256(-contentDelta);
        }
        
        // Handle subscriber count updates safely
        if (subscriberDelta > 0) {
            creators[creator].subscriberCount += uint256(subscriberDelta);
        } else if (subscriberDelta < 0 && creators[creator].subscriberCount > 0) {
            creators[creator].subscriberCount -= uint256(-subscriberDelta);
        }
    }
    
    /**
     * @dev Admin function to update platform fee percentage
     * @param newFee New fee in basis points (250 = 2.5%)
     */
    function updatePlatformFee(uint256 newFee) external onlyOwner {
        if (newFee > 1000) revert InvalidFeePercentage(); // Max 10% fee
        
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @dev Admin function to update fee recipient address
     * @param newRecipient New address to receive platform fees
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert InvalidFeeRecipient();
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }
    
    // View functions for frontend integration and analytics
    
    /**
     * @dev Checks if an address is a registered creator
     * @param creator Address to check
     * @return bool True if registered, false otherwise
     */
    function isRegisteredCreator(address creator) external view returns (bool) {
        return creators[creator].isRegistered;
    }
    
    /**
     * @dev Gets creator's subscription price
     * @param creator Creator address
     * @return uint256 Subscription price in USDC (6 decimals)
     */
    function getSubscriptionPrice(address creator) external view returns (uint256) {
        return creators[creator].subscriptionPrice;
    }
    
    /**
     * @dev Gets complete creator profile information
     * @param creator Creator address
     * @return Creator struct with all profile data
     */
    function getCreatorProfile(address creator) external view returns (Creator memory) {
        return creators[creator];
    }
    
    /**
     * @dev Gets total number of registered creators
     * @return uint256 Total creator count
     */
    function getTotalCreators() external view returns (uint256) {
        return allCreators.length;
    }
    
    /**
     * @dev Gets creator address by index (for pagination)
     * @param index Index in the creators array
     * @return address Creator address at given index
     */
    function getCreatorByIndex(uint256 index) external view returns (address) {
        require(index < allCreators.length, "Index out of bounds");
        return allCreators[index];
    }
    
    /**
     * @dev Calculates platform fee for a given amount
     * @param amount Amount to calculate fee for
     * @return uint256 Fee amount
     */
    function calculatePlatformFee(uint256 amount) external view returns (uint256) {
        return (amount * platformFee) / 10000;
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Emergency unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}