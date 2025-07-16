// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";
import {ContentRegistry} from "./ContentRegistry.sol";
import {PriceOracle} from "./PriceOracle.sol";
import {ICommercePaymentsProtocol} from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title PayPerView
 * @dev Enhanced PayPerView contract integrated with Base Commerce Protocol and Uniswap pricing
 * @notice This contract handles content purchases using the Commerce Protocol for
 *         advanced payment options including ETH payments, token swaps, and multi-currency support
 */
contract PayPerView is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Role definitions
    bytes32 public constant PAYMENT_PROCESSOR_ROLE = keccak256("PAYMENT_PROCESSOR_ROLE");
    bytes32 public constant REFUND_MANAGER_ROLE = keccak256("REFUND_MANAGER_ROLE");
    
    // Contract references
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    PriceOracle public immutable priceOracle;
    IERC20 public immutable usdcToken;
    
    // Payment timeout and refund settings
    uint256 public constant PAYMENT_TIMEOUT = 1 hours; // Payment intent expiry
    uint256 public constant REFUND_WINDOW = 24 hours;  // Refund eligibility window
    
    // Access and purchase tracking
    mapping(uint256 => mapping(address => PurchaseRecord)) public purchases;
    mapping(address => uint256[]) public userPurchases;
    mapping(address => uint256) public userTotalSpent;
    mapping(bytes16 => PendingPurchase) public pendingPurchases; // Intent -> Purchase details
    
    // Creator earnings and platform metrics
    mapping(address => uint256) public creatorEarnings;
    mapping(address => uint256) public withdrawableEarnings;
    uint256 public totalPlatformFees;
    uint256 public totalVolume;
    uint256 public totalPurchases;
    uint256 public totalRefunds;
    
    // Failed purchase tracking for refunds
    mapping(bytes16 => FailedPurchase) public failedPurchases;
    mapping(address => uint256) public pendingRefunds; // User -> USDC amount
    
    /**
     * @dev Enhanced purchase record with Commerce Protocol integration
     */
    struct PurchaseRecord {
        bool hasPurchased;           // Purchase status
        uint256 purchasePrice;       // Amount paid in USDC
        uint256 purchaseTime;        // Purchase timestamp
        bytes16 intentId;            // Commerce Protocol intent ID
        address paymentToken;        // Token used for payment (ETH, USDC, etc.)
        uint256 actualAmountPaid;    // Actual amount paid in payment token
        bool refundEligible;         // Whether purchase can be refunded
        uint256 refundDeadline;      // Refund deadline timestamp
    }
    
    /**
     * @dev Pending purchase awaiting completion
     */
    struct PendingPurchase {
        uint256 contentId;
        address user;
        uint256 usdcPrice;
        address paymentToken;
        uint256 expectedAmount;
        uint256 deadline;
        bool isProcessed;
    }
    
    /**
     * @dev Failed purchase eligible for refund
     */
    struct FailedPurchase {
        uint256 contentId;
        address user;
        uint256 usdcAmount;
        address paymentToken;
        uint256 paidAmount;
        uint256 failureTime;
        string reason;
        bool refunded;
    }
    
    /**
     * @dev Payment method options for users
     */
    enum PaymentMethod {
        USDC,                // Direct USDC payment
        ETH,                 // ETH payment (swapped to USDC)
        WETH,                // WETH payment (converted to USDC)
        OTHER_TOKEN          // Other ERC-20 token (swapped to USDC)
    }
    
    // Events for comprehensive payment tracking
    event ContentPurchaseInitiated(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        bytes16 intentId,
        PaymentMethod paymentMethod,
        uint256 usdcPrice,
        uint256 expectedPaymentAmount
    );
    
    event ContentPurchaseCompleted(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        bytes16 intentId,
        uint256 usdcPrice,
        uint256 actualAmountPaid,
        address paymentToken
    );
    
    event DirectPurchaseCompleted(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning
    );
    
    event PurchaseFailed(
        bytes16 indexed intentId,
        uint256 indexed contentId,
        address indexed user,
        string reason
    );
    
    event RefundProcessed(
        bytes16 indexed intentId,
        address indexed user,
        uint256 amount,
        string reason
    );
    
    event CreatorEarningsWithdrawn(
        address indexed creator,
        uint256 amount,
        uint256 timestamp
    );
    
    // Custom errors
    error InvalidPaymentMethod();
    error PurchaseAlreadyCompleted();
    error IntentNotFound();
    error CommerceProtocolError(string reason);
    error PurchaseExpired();
    error NotRefundEligible();
    error RefundWindowExpired();
    error InsufficientRefundBalance();
    error NoEarningsToWithdraw();
    
    /**
     * @dev Constructor initializes the enhanced PayPerView system
     * @param _creatorRegistry Address of CreatorRegistry contract
     * @param _contentRegistry Address of ContentRegistry contract
     * @param _priceOracle Address of PriceOracle contract
     * @param _usdcToken Address of USDC token contract
     */
    constructor(
        address _creatorRegistry,
        address _contentRegistry,
        address _priceOracle,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_usdcToken != address(0), "Invalid USDC token");
        
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_PROCESSOR_ROLE, msg.sender);
        _grantRole(REFUND_MANAGER_ROLE, msg.sender);
    }
    
    /**
     * @dev Creates a purchase intent with accurate pricing using Uniswap
     * @param contentId Content to purchase
     * @param paymentMethod How user wants to pay
     * @param paymentToken Token address for OTHER_TOKEN method
     * @param maxSlippage Maximum slippage tolerance in basis points
     * @return intentId Unique intent identifier
     * @return expectedAmount Expected payment amount in chosen token
     * @return deadline Payment deadline timestamp
     */
    function createPurchaseIntent(
        uint256 contentId,
        PaymentMethod paymentMethod,
        address paymentToken,
        uint256 maxSlippage
    ) external nonReentrant whenNotPaused returns (
        bytes16 intentId,
        uint256 expectedAmount,
        uint256 deadline
    ) {
        // Validate content and access
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        require(content.isActive, "Content not active");
        require(!purchases[contentId][msg.sender].hasPurchased, "Already purchased");
        
        // Generate unique intent ID
        intentId = _generateIntentId(msg.sender, contentId);
        deadline = block.timestamp + PAYMENT_TIMEOUT;
        
        // Get accurate price quote using Uniswap
        address tokenAddress = _getPaymentTokenAddress(paymentMethod, paymentToken);
        expectedAmount = _getAccurateTokenAmount(
            tokenAddress,
            content.payPerViewPrice,
            maxSlippage
        );
        
        // Store pending purchase
        pendingPurchases[intentId] = PendingPurchase({
            contentId: contentId,
            user: msg.sender,
            usdcPrice: content.payPerViewPrice,
            paymentToken: tokenAddress,
            expectedAmount: expectedAmount,
            deadline: deadline,
            isProcessed: false
        });
        
        emit ContentPurchaseInitiated(
            contentId,
            msg.sender,
            content.creator,
            intentId,
            paymentMethod,
            content.payPerViewPrice,
            expectedAmount
        );
        
        return (intentId, expectedAmount, deadline);
    }
    
    /**
     * @dev Completes content purchase after payment verification
     * @param intentId Payment intent ID that was executed
     * @param actualAmountPaid Actual amount paid in payment token
     * @param success Whether the payment was successful
     * @param failureReason Reason for failure (if applicable)
     */
    function completePurchase(
        bytes16 intentId,
        uint256 actualAmountPaid,
        bool success,
        string memory failureReason
    ) external onlyRole(PAYMENT_PROCESSOR_ROLE) nonReentrant {
        
        PendingPurchase storage pending = pendingPurchases[intentId];
        require(pending.user != address(0), "Intent not found");
        require(!pending.isProcessed, "Already processed");
        require(block.timestamp <= pending.deadline, "Purchase expired");
        
        pending.isProcessed = true;
        
        if (!success) {
            _handleFailedPurchase(intentId, pending, failureReason);
            return;
        }
        
        // Validate actual payment amount (allow small variance for slippage)
        uint256 variance = (pending.expectedAmount * 50) / 10000; // 0.5% variance
        require(
            actualAmountPaid >= pending.expectedAmount - variance,
            "Insufficient payment"
        );
        
        // Get content and creator details
        ContentRegistry.Content memory content = contentRegistry.getContent(pending.contentId);
        uint256 platformFee = creatorRegistry.calculatePlatformFee(pending.usdcPrice);
        uint256 creatorEarning = pending.usdcPrice - platformFee;
        
        // Record the purchase
        purchases[pending.contentId][pending.user] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: pending.usdcPrice,
            purchaseTime: block.timestamp,
            intentId: intentId,
            paymentToken: pending.paymentToken,
            actualAmountPaid: actualAmountPaid,
            refundEligible: true,
            refundDeadline: block.timestamp + REFUND_WINDOW
        });
        
        // Update user purchase history
        userPurchases[pending.user].push(pending.contentId);
        userTotalSpent[pending.user] += pending.usdcPrice;
        
        // Update creator earnings (through registry for proper access control)
        try creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 0, 0) {
            creatorEarnings[content.creator] += creatorEarning;
            withdrawableEarnings[content.creator] += creatorEarning;
        } catch {
            // If registry update fails, still track earnings locally
            creatorEarnings[content.creator] += creatorEarning;
            withdrawableEarnings[content.creator] += creatorEarning;
        }
        
        // Update platform metrics
        totalPlatformFees += platformFee;
        totalVolume += pending.usdcPrice;
        totalPurchases++;
        
        // Record purchase in content registry
        try contentRegistry.recordPurchase(pending.contentId, pending.user) {
            // Purchase recorded successfully
        } catch {
            // Continue if recording fails (non-critical)
        }
        
        emit ContentPurchaseCompleted(
            pending.contentId,
            pending.user,
            content.creator,
            intentId,
            pending.usdcPrice,
            actualAmountPaid,
            pending.paymentToken
        );
    }
    
    /**
     * @dev Direct USDC purchase (legacy method for users who prefer simple payments)
     * @param contentId Content to purchase
     */
    function purchaseContentDirect(uint256 contentId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        // Validate content and access
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        require(content.isActive, "Content not active");
        require(!purchases[contentId][msg.sender].hasPurchased, "Already purchased");
        require(creatorRegistry.isRegisteredCreator(content.creator), "Creator not registered");
        
        uint256 contentPrice = content.payPerViewPrice;
        uint256 platformFee = creatorRegistry.calculatePlatformFee(contentPrice);
        uint256 creatorEarning = contentPrice - platformFee;
        
        // Verify user has sufficient USDC
        require(usdcToken.balanceOf(msg.sender) >= contentPrice, "Insufficient balance");
        require(usdcToken.allowance(msg.sender, address(this)) >= contentPrice, "Insufficient allowance");
        
        // Transfer USDC from user
        usdcToken.safeTransferFrom(msg.sender, address(this), contentPrice);
        
        // Record purchase
        purchases[contentId][msg.sender] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: contentPrice,
            purchaseTime: block.timestamp,
            intentId: 0, // No intent ID for direct purchases
            paymentToken: address(usdcToken),
            actualAmountPaid: contentPrice,
            refundEligible: true,
            refundDeadline: block.timestamp + REFUND_WINDOW
        });
        
        // Update tracking
        userPurchases[msg.sender].push(contentId);
        userTotalSpent[msg.sender] += contentPrice;
        
        // Update creator earnings
        try creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 0, 0) {
            creatorEarnings[content.creator] += creatorEarning;
            withdrawableEarnings[content.creator] += creatorEarning;
        } catch {
            creatorEarnings[content.creator] += creatorEarning;
            withdrawableEarnings[content.creator] += creatorEarning;
        }
        
        // Update platform metrics
        totalPlatformFees += platformFee;
        totalVolume += contentPrice;
        totalPurchases++;
        
        // Record in content registry
        try contentRegistry.recordPurchase(contentId, msg.sender) {} catch {}
        
        emit DirectPurchaseCompleted(
            contentId,
            msg.sender,
            content.creator,
            contentPrice,
            platformFee,
            creatorEarning
        );
    }
    
    /**
     * @dev Requests refund for a purchase within the refund window
     * @param contentId Content to refund
     * @param reason Reason for refund request
     */
    function requestRefund(uint256 contentId, string memory reason) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        PurchaseRecord storage purchase = purchases[contentId][msg.sender];
        require(purchase.hasPurchased, "No purchase found");
        require(purchase.refundEligible, "Not refund eligible");
        require(block.timestamp <= purchase.refundDeadline, "Refund window expired");
        
        // Mark as not refund eligible and add to pending refunds
        purchase.refundEligible = false;
        pendingRefunds[msg.sender] += purchase.purchasePrice;
        
        // Create failed purchase record for tracking
        bytes16 refundId = _generateIntentId(msg.sender, contentId);
        failedPurchases[refundId] = FailedPurchase({
            contentId: contentId,
            user: msg.sender,
            usdcAmount: purchase.purchasePrice,
            paymentToken: purchase.paymentToken,
            paidAmount: purchase.actualAmountPaid,
            failureTime: block.timestamp,
            reason: reason,
            refunded: false
        });
        
        totalRefunds += purchase.purchasePrice;
        
        emit RefundProcessed(refundId, msg.sender, purchase.purchasePrice, reason);
    }
    
    /**
     * @dev Processes refund payout to user
     * @param user User to refund
     */
    function processRefundPayout(address user) 
        external 
        onlyRole(REFUND_MANAGER_ROLE) 
        nonReentrant 
    {
        uint256 amount = pendingRefunds[user];
        require(amount > 0, "No pending refunds");
        
        pendingRefunds[user] = 0;
        usdcToken.safeTransfer(user, amount);
    }
    
    /**
     * @dev Gets payment options and pricing for content
     * @param contentId Content to check pricing for
     * @return methods Array of available payment methods
     * @return prices Expected payment amounts for each method (with 1% slippage)
     */
    function getPaymentOptions(uint256 contentId) 
        external
        returns (
            PaymentMethod[] memory methods,
            uint256[] memory prices
        ) 
    {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        
        methods = new PaymentMethod[](3);
        prices = new uint256[](3);
        
        methods[0] = PaymentMethod.USDC;
        prices[0] = content.payPerViewPrice;
        
        methods[1] = PaymentMethod.ETH;
        try priceOracle.getETHPrice(content.payPerViewPrice) returns (uint256 ethAmount) {
            prices[1] = priceOracle.applySlippage(ethAmount, 100); // 1% slippage
        } catch {
            prices[1] = 0; // Price unavailable
        }
        
        methods[2] = PaymentMethod.WETH;
        prices[2] = prices[1]; // Same as ETH
        
        return (methods, prices);
    }
    
    /**
     * @dev Enhanced access check supporting both direct and Commerce Protocol purchases
     * @param contentId Content ID to check
     * @param user User address to check
     * @return bool True if user has purchased content
     */
    function hasAccess(uint256 contentId, address user) external view returns (bool) {
        return purchases[contentId][user].hasPurchased;
    }
    
    /**
     * @dev Gets detailed purchase information including payment method used
     * @param contentId Content ID
     * @param user User address
     * @return PurchaseRecord Complete purchase details
     */
    function getPurchaseDetails(uint256 contentId, address user) 
        external 
        view 
        returns (PurchaseRecord memory) 
    {
        return purchases[contentId][user];
    }
    
    /**
     * @dev Gets user's purchase history
     * @param user User address
     * @return contentIds Array of purchased content IDs
     */
    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchases[user];
    }
    
    /**
     * @dev Creator earnings withdrawal
     */
    function withdrawEarnings() external nonReentrant {
        uint256 amount = withdrawableEarnings[msg.sender];
        require(amount > 0, "No earnings to withdraw");
        
        withdrawableEarnings[msg.sender] = 0;
        usdcToken.safeTransfer(msg.sender, amount);
        
        emit CreatorEarningsWithdrawn(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Gets creator earnings information
     * @param creator Creator address
     * @return total Total earnings
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
     * @dev Admin function to grant payment processor role
     * @param processor Address to grant role to
     */
    function grantPaymentProcessorRole(address processor) external onlyOwner {
        _grantRole(PAYMENT_PROCESSOR_ROLE, processor);
    }
    
    /**
     * @dev Admin function to grant refund manager role
     * @param manager Address to grant role to
     */
    function grantRefundManagerRole(address manager) external onlyOwner {
        _grantRole(REFUND_MANAGER_ROLE, manager);
    }
    
    // Internal helper functions
    
    /**
     * @dev Gets the appropriate token address for payment method
     */
    function _getPaymentTokenAddress(PaymentMethod method, address providedToken) 
        internal 
        pure 
        returns (address) 
    {
        if (method == PaymentMethod.USDC) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        if (method == PaymentMethod.ETH) return address(0); // ETH is address(0)
        if (method == PaymentMethod.WETH) return 0x4200000000000000000000000000000000000006; // WETH on Base
        if (method == PaymentMethod.OTHER_TOKEN) return providedToken;
        
        revert InvalidPaymentMethod();
    }
    
    /**
     * @dev Gets accurate token amount using Uniswap oracle
     */
    function _getAccurateTokenAmount(
        address token,
        uint256 usdcAmount,
        uint256 slippageBps
    ) internal returns (uint256) {
        if (token == address(usdcToken)) {
            return usdcAmount;
        } else if (token == address(0)) { // ETH
            uint256 ethAmount = priceOracle.getETHPrice(usdcAmount);
            return priceOracle.applySlippage(ethAmount, slippageBps);
        } else {
            uint256 tokenAmount = priceOracle.getTokenAmountForUSDC(token, usdcAmount, 0);
            return priceOracle.applySlippage(tokenAmount, slippageBps);
        }
    }
    
    /**
     * @dev Generates unique intent ID
     */
    function _generateIntentId(address user, uint256 contentId) internal view returns (bytes16) {
        return bytes16(keccak256(abi.encodePacked(
            user,
            contentId,
            block.timestamp,
            block.number
        )));
    }
    
    /**
     * @dev Handles failed purchase and prepares refund
     */
    function _handleFailedPurchase(
        bytes16 intentId,
        PendingPurchase memory pending,
        string memory reason
    ) internal {
        failedPurchases[intentId] = FailedPurchase({
            contentId: pending.contentId,
            user: pending.user,
            usdcAmount: pending.usdcPrice,
            paymentToken: pending.paymentToken,
            paidAmount: 0, // No payment was made
            failureTime: block.timestamp,
            reason: reason,
            refunded: false
        });
        
        emit PurchaseFailed(intentId, pending.contentId, pending.user, reason);
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Resume operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency token recovery (only non-USDC tokens)
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        require(token != address(usdcToken), "Cannot recover USDC");
        IERC20(token).safeTransfer(owner(), amount);
    }
}