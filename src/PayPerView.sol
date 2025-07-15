// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./CreatorRegistry.sol";
import "./ContentRegistry.sol";

/**
 * @title PayPerView
 * @dev Handles one-time content purchases with USDC payments and access control
 * @notice This contract processes pay-per-view purchases and manages content access permissions
 */
contract PayPerView is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Contract references for validation and fee calculation
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    IERC20 public immutable usdcToken; // USDC token contract on Base
    
    // Payment and access tracking
    // contentId => user => purchase details
    mapping(uint256 => mapping(address => PurchaseRecord)) public purchases;
    
    // User purchase history for analytics and UX
    mapping(address => uint256[]) public userPurchases; // user => content IDs
    mapping(address => uint256) public userTotalSpent; // user => total USDC spent
    
    // Creator earnings tracking
    mapping(address => uint256) public creatorEarnings; // creator => total earnings
    mapping(address => uint256) public withdrawableEarnings; // creator => withdrawable amount
    
    // Platform metrics
    uint256 public totalPlatformFees; // Total fees collected
    uint256 public totalVolume; // Total transaction volume
    uint256 public totalPurchases; // Total number of purchases
    
    /**
     * @dev Purchase record structure containing transaction details
     * @param hasPurchased Whether user has purchased this content
     * @param purchasePrice Price paid for the content (in USDC)
     * @param purchaseTime Timestamp of purchase
     * @param transactionHash Hash of the purchase transaction for reference
     */
    struct PurchaseRecord {
        bool hasPurchased;       // Purchase status
        uint256 purchasePrice;   // Amount paid in USDC
        uint256 purchaseTime;    // Purchase timestamp
        bytes32 transactionHash; // Transaction reference
    }
    
    /**
     * @dev Refund information for failed or disputed purchases
     */
    struct RefundRecord {
        bool isRefunded;         // Refund status
        uint256 refundAmount;    // Amount refunded
        uint256 refundTime;      // Refund timestamp
        string refundReason;     // Reason for refund
    }
    
    // Refund tracking
    mapping(uint256 => mapping(address => RefundRecord)) public refunds;
    
    // Emergency refund capabilities
    uint256 public refundWindow = 24 hours; // 24-hour refund window for disputes
    mapping(uint256 => bool) public refundableContent; // Content eligible for refunds
    
    // Events for comprehensive transaction tracking
    event ContentPurchased(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning,
        uint256 timestamp
    );
    
    event EarningsWithdrawn(
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );
    
    event RefundProcessed(
        uint256 indexed contentId,
        address indexed buyer,
        uint256 amount,
        string reason,
        uint256 timestamp
    );
    
    event PlatformFeesWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
    
    event RefundWindowUpdated(uint256 oldWindow, uint256 newWindow);
    
    // Custom errors for gas-efficient error handling
    error ContentNotFound();
    error ContentNotActive();
    error AlreadyPurchased();
    error InsufficientPayment();
    error CreatorNotRegistered();
    error InsufficientBalance();
    error NoEarningsToWithdraw();
    error RefundNotAllowed();
    error RefundWindowExpired();
    error InvalidRefundAmount();
    error TransferFailed();
    
    /**
     * @dev Constructor initializes contract with required dependencies
     * @param _creatorRegistry Address of the CreatorRegistry contract
     * @param _contentRegistry Address of the ContentRegistry contract
     * @param _usdcToken Address of the USDC token contract on Base
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
     * @dev Purchases content with USDC payment and fee distribution
     * @param contentId ID of content to purchase
     * @notice Requires user to have approved sufficient USDC allowance
     */
    function purchaseContent(uint256 contentId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        // Validate content existence and availability
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        if (content.creator == address(0)) revert ContentNotFound();
        if (!content.isActive) revert ContentNotActive();
        
        // Check if user already purchased this content
        if (purchases[contentId][msg.sender].hasPurchased) revert AlreadyPurchased();
        
        // Validate creator registration
        if (!creatorRegistry.isRegisteredCreator(content.creator)) {
            revert CreatorNotRegistered();
        }
        
        uint256 contentPrice = content.payPerViewPrice;
        
        // Calculate platform fee and creator earnings
        uint256 platformFee = creatorRegistry.calculatePlatformFee(contentPrice);
        uint256 creatorEarning = contentPrice - platformFee;
        
        // Verify user has sufficient USDC balance and allowance
        if (usdcToken.balanceOf(msg.sender) < contentPrice) revert InsufficientBalance();
        if (usdcToken.allowance(msg.sender, address(this)) < contentPrice) {
            revert InsufficientPayment();
        }
        
        // Transfer USDC from buyer to contract
        usdcToken.safeTransferFrom(msg.sender, address(this), contentPrice);
        
        // Record purchase details
        purchases[contentId][msg.sender] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: contentPrice,
            purchaseTime: block.timestamp,
            transactionHash: keccak256(abi.encodePacked(
                contentId, 
                msg.sender, 
                block.timestamp, 
                block.number
            ))
        });
        
        // Update user purchase history
        userPurchases[msg.sender].push(contentId);
        userTotalSpent[msg.sender] += contentPrice;
        
        // Update creator earnings (available for withdrawal)
        creatorEarnings[content.creator] += creatorEarning;
        withdrawableEarnings[content.creator] += creatorEarning;
        
        // Update platform metrics
        totalPlatformFees += platformFee;
        totalVolume += contentPrice;
        totalPurchases++;
        
        // Update creator stats in registry
        try creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 0, 0) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }
        
        // Record purchase in content registry for analytics
        try contentRegistry.recordPurchase(contentId, msg.sender) {
            // Purchase recorded successfully
        } catch {
            // Continue if recording fails (non-critical)
        }
        
        // Mark content as refundable within the refund window
        refundableContent[contentId] = true;
        
        emit ContentPurchased(
            contentId,
            msg.sender,
            content.creator,
            contentPrice,
            platformFee,
            creatorEarning,
            block.timestamp
        );
    }
    
    /**
     * @dev Allows creators to withdraw their earnings
     * @notice Transfers accumulated USDC earnings to creator's wallet
     */
    function withdrawEarnings() external nonReentrant {
        uint256 amount = withdrawableEarnings[msg.sender];
        if (amount == 0) revert NoEarningsToWithdraw();
        
        // Reset withdrawable amount before transfer to prevent reentrancy
        withdrawableEarnings[msg.sender] = 0;
        
        // Transfer USDC to creator
        usdcToken.safeTransfer(msg.sender, amount);
        
        emit EarningsWithdrawn(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Processes refunds for eligible content within refund window
     * @param contentId Content ID to refund
     * @param buyer Address of buyer requesting refund
     * @param reason Reason for refund
     */
    function processRefund(
        uint256 contentId,
        address buyer,
        string memory reason
    ) external onlyOwner {
        
        PurchaseRecord memory purchase = purchases[contentId][buyer];
        if (!purchase.hasPurchased) revert RefundNotAllowed();
        
        // Check if content is eligible for refunds
        if (!refundableContent[contentId]) revert RefundNotAllowed();
        
        // Check refund window (24 hours from purchase)
        if (block.timestamp > purchase.purchaseTime + refundWindow) {
            revert RefundWindowExpired();
        }
        
        // Check if already refunded
        if (refunds[contentId][buyer].isRefunded) revert RefundNotAllowed();
        
        uint256 refundAmount = purchase.purchasePrice;
        
        // Calculate amounts to reverse
        uint256 platformFee = creatorRegistry.calculatePlatformFee(refundAmount);
        uint256 creatorLoss = refundAmount - platformFee;
        
        // Get content creator
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        
        // Reduce creator earnings (if available)
        if (withdrawableEarnings[content.creator] >= creatorLoss) {
            withdrawableEarnings[content.creator] -= creatorLoss;
            creatorEarnings[content.creator] -= creatorLoss;
        }
        
        // Reduce platform fees
        if (totalPlatformFees >= platformFee) {
            totalPlatformFees -= platformFee;
        }
        
        // Record refund
        refunds[contentId][buyer] = RefundRecord({
            isRefunded: true,
            refundAmount: refundAmount,
            refundTime: block.timestamp,
            refundReason: reason
        });
        
        // Remove purchase access
        purchases[contentId][buyer].hasPurchased = false;
        
        // Update metrics
        userTotalSpent[buyer] -= refundAmount;
        totalVolume -= refundAmount;
        totalPurchases--;
        
        // Transfer refund to buyer
        usdcToken.safeTransfer(buyer, refundAmount);
        
        emit RefundProcessed(contentId, buyer, refundAmount, reason, block.timestamp);
    }
    
    /**
     * @dev Admin function to withdraw accumulated platform fees
     * @param recipient Address to receive platform fees
     */
    function withdrawPlatformFees(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        
        uint256 amount = totalPlatformFees;
        if (amount == 0) revert NoEarningsToWithdraw();
        
        // Reset platform fees before transfer
        totalPlatformFees = 0;
        
        // Transfer to fee recipient
        usdcToken.safeTransfer(recipient, amount);
        
        emit PlatformFeesWithdrawn(recipient, amount, block.timestamp);
    }
    
    /**
     * @dev Updates the refund window duration
     * @param newWindow New refund window in seconds
     */
    function updateRefundWindow(uint256 newWindow) external onlyOwner {
        require(newWindow <= 7 days, "Refund window too long"); // Max 7 days
        require(newWindow >= 1 hours, "Refund window too short"); // Min 1 hour
        
        uint256 oldWindow = refundWindow;
        refundWindow = newWindow;
        
        emit RefundWindowUpdated(oldWindow, newWindow);
    }
    
    // View functions for access control and analytics
    
    /**
     * @dev Checks if user has access to specific content
     * @param contentId Content ID to check
     * @param user User address to check
     * @return bool True if user has purchased and not refunded content
     */
    function hasAccess(uint256 contentId, address user) external view returns (bool) {
        return purchases[contentId][user].hasPurchased && 
               !refunds[contentId][user].isRefunded;
    }
    
    /**
     * @dev Gets user's purchase history
     * @param user User address
     * @return uint256[] Array of content IDs purchased by user
     */
    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchases[user];
    }
    
    /**
     * @dev Gets detailed purchase information
     * @param contentId Content ID
     * @param user User address
     * @return PurchaseRecord Purchase details
     */
    function getPurchaseDetails(uint256 contentId, address user) 
        external 
        view 
        returns (PurchaseRecord memory) 
    {
        return purchases[contentId][user];
    }
    
    /**
     * @dev Gets creator's total and withdrawable earnings
     * @param creator Creator address
     * @return total Total lifetime earnings
     * @return withdrawable Current withdrawable amount
     */
    function getCreatorEarnings(address creator) 
        external 
        view 
        returns (uint256 total, uint256 withdrawable) 
    {
        return (creatorEarnings[creator], withdrawableEarnings[creator]);
    }
    
    /**
     * @dev Gets platform analytics and metrics
     * @return totalFees Total platform fees collected
     * @return volume Total transaction volume
     * @return purchaseCount Total number of purchases
     */
    function getPlatformMetrics() 
        external 
        view 
        returns (uint256 totalFees, uint256 volume, uint256 purchaseCount) 
    {
        return (totalPlatformFees, totalVolume, totalPurchases);
    }
    
    /**
     * @dev Gets refund information for a purchase
     * @param contentId Content ID
     * @param buyer Buyer address
     * @return RefundRecord Refund details
     */
    function getRefundDetails(uint256 contentId, address buyer) 
        external 
        view 
        returns (RefundRecord memory) 
    {
        return refunds[contentId][buyer];
    }
    
    /**
     * @dev Checks if a purchase is eligible for refund
     * @param contentId Content ID
     * @param buyer Buyer address
     * @return bool True if refund is allowed within time window
     */
    function isRefundEligible(uint256 contentId, address buyer) 
        external 
        view 
        returns (bool) 
    {
        PurchaseRecord memory purchase = purchases[contentId][buyer];
        
        return purchase.hasPurchased &&
               !refunds[contentId][buyer].isRefunded &&
               refundableContent[contentId] &&
               block.timestamp <= purchase.purchaseTime + refundWindow;
    }
    
    /**
     * @dev Emergency pause function for security
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