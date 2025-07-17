// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CreatorRegistry
 * @dev Manages creator profiles, subscription pricing, verification status, and earnings
 * @notice This contract handles creator registration and subscription management for the content platform
 */
contract CreatorRegistry is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Role definitions for access control
    bytes32 public constant PLATFORM_CONTRACT_ROLE = keccak256("PLATFORM_CONTRACT_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    
    // USDC token for earnings
    IERC20 public immutable usdcToken;
    
    // State variables for subscription pricing limits (in USDC with 6 decimals)
    uint256 public constant MIN_SUBSCRIPTION_PRICE = 0.01e6; // $0.01 minimum
    uint256 public constant MAX_SUBSCRIPTION_PRICE = 100e6;  // $100 maximum
    uint256 public constant SUBSCRIPTION_DURATION = 30 days; // Fixed 30-day subscriptions
    
    // Platform fee configuration (basis points - 250 = 2.5%)
    uint256 public platformFee = 250; // 2.5% platform fee
    address public feeRecipient;
    
    // Creator earnings tracking
    mapping(address => uint256) public creatorPendingEarnings; // Withdrawable earnings
    mapping(address => uint256) public creatorWithdrawnEarnings; // Historical withdrawals
    
    /**
     * @dev Creator profile structure containing essential creator information
     */
    struct Creator {
        bool isRegistered;           // Registration status
        uint256 subscriptionPrice;  // Monthly price in USDC (6 decimals)
        bool isVerified;            // Verification badge status
        uint256 totalEarnings;      // Cumulative earnings for analytics and reputation
        uint256 contentCount;       // Number of content pieces published by creator
        uint256 subscriberCount;    // Current number of active subscribers
        uint256 registrationTime;   // When creator registered
        string profileData;         // IPFS hash for profile metadata
    }
    
    // Storage mappings for efficient data access
    mapping(address => Creator) public creators;
    mapping(address => uint256) public creatorJoinDate; // Track registration timestamp
    
    // Dynamic arrays for iteration and analytics
    address[] public allCreators;
    address[] public verifiedCreators;
    
    // Platform metrics
    uint256 public totalPlatformEarnings;
    uint256 public totalCreatorEarnings;
    uint256 public totalWithdrawnEarnings;
    
    // Events for frontend integration and analytics
    event CreatorRegistered(
        address indexed creator, 
        uint256 subscriptionPrice, 
        uint256 timestamp,
        string profileData
    );
    
    event SubscriptionPriceUpdated(
        address indexed creator, 
        uint256 oldPrice, 
        uint256 newPrice
    );
    
    event CreatorVerified(address indexed creator, bool verified);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    
    event CreatorEarningsUpdated(
        address indexed creator,
        uint256 amount,
        string source // "content_purchase", "subscription", "bonus"
    );
    
    event CreatorEarningsWithdrawn(
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );
    
    event ProfileDataUpdated(
        address indexed creator,
        string oldProfileData,
        string newProfileData
    );
    
    event PlatformFeesWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    
    // Custom errors for gas-efficient error handling
    error CreatorAlreadyRegistered();
    error CreatorNotRegistered();
    error InvalidSubscriptionPrice();
    error InvalidFeePercentage();
    error InvalidFeeRecipient();
    error UnauthorizedAccess();
    error NoEarningsToWithdraw();
    error InvalidProfileData();
    error CreatorNotFound();
    
    /**
     * @dev Constructor sets up the contract with initial configuration
     * @param _feeRecipient Address that will receive platform fees
     * @param _usdcToken USDC token contract address
     */
    constructor(address _feeRecipient, address _usdcToken) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();
        if (_usdcToken == address(0)) revert InvalidFeeRecipient();
        
        feeRecipient = _feeRecipient;
        usdcToken = IERC20(_usdcToken);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MODERATOR_ROLE, msg.sender);
    }
    
    /**
     * @dev Registers a new creator with subscription pricing and profile data
     * @param subscriptionPrice Monthly subscription price in USDC (6 decimals)
     * @param profileData IPFS hash containing creator profile metadata
     */
    function registerCreator(uint256 subscriptionPrice, string memory profileData) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (creators[msg.sender].isRegistered) revert CreatorAlreadyRegistered();
        if (subscriptionPrice < MIN_SUBSCRIPTION_PRICE || 
            subscriptionPrice > MAX_SUBSCRIPTION_PRICE) {
            revert InvalidSubscriptionPrice();
        }
        if (bytes(profileData).length == 0) revert InvalidProfileData();
        
        // Initialize creator profile
        creators[msg.sender] = Creator({
            isRegistered: true,
            subscriptionPrice: subscriptionPrice,
            isVerified: false,           // Verification requires admin approval
            totalEarnings: 0,            // Starts at zero
            contentCount: 0,             // No content initially
            subscriberCount: 0,          // No subscribers initially
            registrationTime: block.timestamp,
            profileData: profileData
        });
        
        // Track registration timestamp and add to creator list
        creatorJoinDate[msg.sender] = block.timestamp;
        allCreators.push(msg.sender);
        
        emit CreatorRegistered(msg.sender, subscriptionPrice, block.timestamp, profileData);
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
     * @dev Updates creator profile metadata
     * @param newProfileData New IPFS hash for profile data
     */
    function updateProfileData(string memory newProfileData) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!creators[msg.sender].isRegistered) revert CreatorNotRegistered();
        if (bytes(newProfileData).length == 0) revert InvalidProfileData();
        
        string memory oldProfileData = creators[msg.sender].profileData;
        creators[msg.sender].profileData = newProfileData;
        
        emit ProfileDataUpdated(msg.sender, oldProfileData, newProfileData);
    }
    
    /**
     * @dev Admin function to verify creators (adds verification badge)
     * @param creator Address of creator to verify/unverify
     * @param verified True to verify, false to remove verification
     */
    function setCreatorVerification(address creator, bool verified) 
        external 
        onlyRole(MODERATOR_ROLE)
    {
        if (!creators[creator].isRegistered) revert CreatorNotRegistered();
        
        bool wasVerified = creators[creator].isVerified;
        creators[creator].isVerified = verified;
        
        // Update verified creators array
        if (verified && !wasVerified) {
            verifiedCreators.push(creator);
        } else if (!verified && wasVerified) {
            _removeFromVerifiedArray(creator);
        }
        
        emit CreatorVerified(creator, verified);
    }
    
    /**
     * @dev Updates creator stats (called by authorized platform contracts only)
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
    ) external onlyRole(PLATFORM_CONTRACT_ROLE) {
        if (!creators[creator].isRegistered) revert CreatorNotRegistered();
        
        // Update earnings
        if (earnings > 0) {
            creators[creator].totalEarnings += earnings;
            creatorPendingEarnings[creator] += earnings;
            totalCreatorEarnings += earnings;
            
            emit CreatorEarningsUpdated(creator, earnings, "platform_activity");
        }
        
        // Handle content count updates safely
        if (contentDelta > 0) {
            creators[creator].contentCount += uint256(contentDelta);
        } else if (contentDelta < 0 && creators[creator].contentCount > 0) {
            uint256 decrease = uint256(-contentDelta);
            if (decrease > creators[creator].contentCount) {
                creators[creator].contentCount = 0;
            } else {
                creators[creator].contentCount -= decrease;
            }
        }
        
        // Handle subscriber count updates safely
        if (subscriberDelta > 0) {
            creators[creator].subscriberCount += uint256(subscriberDelta);
        } else if (subscriberDelta < 0 && creators[creator].subscriberCount > 0) {
            uint256 decrease = uint256(-subscriberDelta);
            if (decrease > creators[creator].subscriberCount) {
                creators[creator].subscriberCount = 0;
            } else {
                creators[creator].subscriberCount -= decrease;
            }
        }
    }
    
    /**
     * @dev Allows creators to withdraw their pending earnings
     */
    function withdrawCreatorEarnings() external nonReentrant {
        if (!creators[msg.sender].isRegistered) revert CreatorNotRegistered();
        
        uint256 amount = creatorPendingEarnings[msg.sender];
        if (amount == 0) revert NoEarningsToWithdraw();
        
        // Update state before transfer to prevent reentrancy
        creatorPendingEarnings[msg.sender] = 0;
        creatorWithdrawnEarnings[msg.sender] += amount;
        totalWithdrawnEarnings += amount;
        
        // Transfer USDC to creator
        usdcToken.safeTransfer(msg.sender, amount);
        
        emit CreatorEarningsWithdrawn(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Admin function to add bonus earnings to creators
     * @param creator Creator to receive bonus
     * @param amount Bonus amount in USDC
     * @param reason Reason for bonus
     */
    function addBonusEarnings(
        address creator,
        uint256 amount,
        string memory reason
    ) external onlyRole(MODERATOR_ROLE) nonReentrant {
        if (!creators[creator].isRegistered) revert CreatorNotRegistered();
        if (amount == 0) return;
        
        // Transfer USDC from admin/platform to contract first
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update creator earnings
        creators[creator].totalEarnings += amount;
        creatorPendingEarnings[creator] += amount;
        totalCreatorEarnings += amount;
        
        emit CreatorEarningsUpdated(creator, amount, reason);
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
    
    /**
     * @dev Grants platform contract role to authorized contracts
     * @param contractAddress Address of platform contract
     */
    function grantPlatformRole(address contractAddress) external onlyOwner {
        _grantRole(PLATFORM_CONTRACT_ROLE, contractAddress);
    }
    
    /**
     * @dev Revokes platform contract role
     * @param contractAddress Address to revoke role from
     */
    function revokePlatformRole(address contractAddress) external onlyOwner {
        _revokeRole(PLATFORM_CONTRACT_ROLE, contractAddress);
    }
    
    /**
     * @dev COMPLETE: Withdraw platform fees
     */
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 totalCreatorEarningsSum = 0;
        
        for (uint256 i = 0; i < allCreators.length; i++) {
            totalCreatorEarningsSum += creators[allCreators[i]].totalEarnings;
        }
        
        uint256 totalPlatformFeesEarned = (totalCreatorEarningsSum * platformFee) / (10000 - platformFee);
        
        uint256 availableForWithdrawal = totalPlatformFeesEarned - totalPlatformEarnings;
        require(availableForWithdrawal > 0, "No platform fees to withdraw");
        
        totalPlatformEarnings = totalPlatformFeesEarned;
        
        usdcToken.safeTransfer(feeRecipient, availableForWithdrawal);
        
        emit PlatformFeesWithdrawn(feeRecipient, availableForWithdrawal, block.timestamp);
    }

    /**
     * @dev COMPLETE: Validate IPFS hash format
     */
    function _validateIPFSHash(string memory ipfsHash) internal pure returns (bool) {
        bytes memory hashBytes = bytes(ipfsHash);
        
        if (hashBytes.length < 46 || hashBytes.length > 62) return false;
        
        if (hashBytes.length >= 2) {
            if (hashBytes[0] == 0x51 && hashBytes[1] == 0x6d) return true; // "Qm"
        }
        if (hashBytes.length >= 4) {
            if (hashBytes[0] == 0x62 && hashBytes[1] == 0x61 && 
                hashBytes[2] == 0x66 && hashBytes[3] == 0x79) return true; // "bafy"
        }
        
        return false;
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
     * @dev Gets creator earnings information
     * @param creator Creator address
     * @return pending Currently withdrawable earnings
     * @return total Total lifetime earnings
     * @return withdrawn Amount already withdrawn
     */
    function getCreatorEarnings(address creator) 
        external 
        view 
        returns (uint256 pending, uint256 total, uint256 withdrawn) 
    {
        return (
            creatorPendingEarnings[creator],
            creators[creator].totalEarnings,
            creatorWithdrawnEarnings[creator]
        );
    }
    
    /**
     * @dev Gets total number of registered creators
     * @return uint256 Total creator count
     */
    function getTotalCreators() external view returns (uint256) {
        return allCreators.length;
    }
    
    /**
     * @dev Gets total number of verified creators
     * @return uint256 Verified creator count
     */
    function getVerifiedCreatorCount() external view returns (uint256) {
        return verifiedCreators.length;
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
     * @dev Gets verified creator by index
     * @param index Index in verified creators array
     * @return address Verified creator address
     */
    function getVerifiedCreatorByIndex(uint256 index) external view returns (address) {
        require(index < verifiedCreators.length, "Index out of bounds");
        return verifiedCreators[index];
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
     * @dev Gets platform statistics
     * @return totalCreators Total registered creators
     * @return verifiedCount Verified creators
     * @return totalEarnings Total platform earnings
     * @return creatorEarnings Total creator earnings
     * @return withdrawnAmount Total withdrawn by creators
     */
    function getPlatformStats() external view returns (
        uint256 totalCreators,
        uint256 verifiedCount,
        uint256 totalEarnings,
        uint256 creatorEarnings,
        uint256 withdrawnAmount
    ) {
        return (
            allCreators.length,
            verifiedCreators.length,
            totalPlatformEarnings,
            totalCreatorEarnings,
            totalWithdrawnEarnings
        );
    }
    
    // Internal helper functions
    
    /**
     * @dev Removes creator from verified array
     * @param creator Creator to remove
     */
    function _removeFromVerifiedArray(address creator) internal {
        for (uint256 i = 0; i < verifiedCreators.length; i++) {
            if (verifiedCreators[i] == creator) {
                verifiedCreators[i] = verifiedCreators[verifiedCreators.length - 1];
                verifiedCreators.pop();
                break;
            }
        }
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
    
    /**
     * @dev Emergency token recovery (only non-USDC tokens)
     * @param token Token to recover
     * @param amount Amount to recover
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        require(token != address(usdcToken), "Cannot recover USDC");
        IERC20(token).safeTransfer(owner(), amount);
    }
}