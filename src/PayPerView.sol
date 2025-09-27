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
import { PriceOracle } from "./PriceOracle.sol";
// Removed ICommercePaymentsProtocol import - no longer needed with new Base Commerce Protocol architecture
import { IntentIdManager } from "./IntentIdManager.sol";

/**
 * @title PayPerView
 * @dev Enhanced PayPerView contract integrated with Base Commerce Protocol and Uniswap pricing
 * @notice This contract handles content purchases using the Commerce Protocol for
 *         advanced payment options including ETH payments, token swaps, and multi-currency support
 */
contract PayPerView is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using IntentIdManager for *;

    // Role definitions
    bytes32 public constant PAYMENT_PROCESSOR_ROLE = keccak256("PAYMENT_PROCESSOR_ROLE");
    bytes32 public constant REFUND_MANAGER_ROLE = keccak256("REFUND_MANAGER_ROLE");

    // Contract references
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    PriceOracle public immutable priceOracle;
    IERC20 public immutable usdcToken;

    // WETH address - configurable per chain
    address public wethToken;

    // Payment timeout and refund settings
    uint256 public constant PAYMENT_TIMEOUT = 1 hours; // Payment intent expiry
    uint256 public constant REFUND_WINDOW = 24 hours; // Refund eligibility window

    // Access and purchase tracking
    mapping(uint256 => mapping(address => PurchaseRecord)) public purchases;
    mapping(address => uint256[]) public userPurchases;
    mapping(address => uint256) public userTotalSpent;
    mapping(bytes16 => PendingPurchase) public pendingPurchases; // Intent -> Purchase details
    mapping(address => uint256) public userNonces;

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
        bool hasPurchased; // Purchase status
        uint256 purchasePrice; // Amount paid in USDC
        uint256 purchaseTime; // Purchase timestamp
        bytes16 intentId; // Commerce Protocol intent ID
        address paymentToken; // Token used for payment (ETH, USDC, etc.)
        uint256 actualAmountPaid; // Actual amount paid in payment token
        bool refundEligible; // Whether purchase can be refunded
        uint256 refundDeadline; // Refund deadline timestamp
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
        USDC, // Direct USDC payment
        ETH, // ETH payment (swapped to USDC)
        WETH, // WETH payment (converted to USDC)
        OTHER_TOKEN // Other ERC-20 token (swapped to USDC)

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

    event PurchaseFailed(bytes16 indexed intentId, uint256 indexed contentId, address indexed user, string reason);

    event RefundProcessed(bytes16 indexed intentId, address indexed user, uint256 amount, string reason);

    event CreatorEarningsWithdrawn(address indexed creator, uint256 amount, uint256 timestamp);

    event ExternalPurchaseRecorded(
        uint256 indexed contentId,
        address indexed buyer,
        bytes16 intentId,
        uint256 usdcPrice,
        address paymentToken,
        uint256 actualAmountPaid
    );
    event ExternalRefundProcessed(
        bytes16 indexed intentId, address indexed user, uint256 indexed contentId, uint256 amount
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
        address _usdcToken,
        address _wethToken
    )
        Ownable(msg.sender)
    {
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_wethToken != address(0), "Invalid WETH token");

        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
        wethToken = _wethToken;

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
    ) external nonReentrant whenNotPaused returns (bytes16 intentId, uint256 expectedAmount, uint256 deadline) {
        // Fetch content
        ContentRegistry.Content memory content;
        try contentRegistry.getContent(contentId) returns (ContentRegistry.Content memory c) {
            content = c;
        } catch {
            revert("Content not found");
        }
        require(content.creator != address(0), "Content not found");
        require(content.isActive, "Content not active");
        require(!purchases[contentId][msg.sender].hasPurchased, "Already purchased");
        // Use standardized intent ID
        intentId = _generateStandardIntentId(msg.sender, content.creator, contentId);
        deadline = block.timestamp + PAYMENT_TIMEOUT;
        address tokenAddress = _getPaymentTokenAddress(paymentMethod, paymentToken);
        expectedAmount = _getAccurateTokenAmount(tokenAddress, content.payPerViewPrice, maxSlippage);
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
            contentId, msg.sender, content.creator, intentId, paymentMethod, content.payPerViewPrice, expectedAmount
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
    function completePurchase(bytes16 intentId, uint256 actualAmountPaid, bool success, string memory failureReason)
        external
        onlyRole(PAYMENT_PROCESSOR_ROLE)
        nonReentrant
    {
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
        require(actualAmountPaid >= pending.expectedAmount - variance, "Insufficient payment");

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
    function purchaseContentDirect(uint256 contentId) external nonReentrant whenNotPaused {
        // Validate content and access
        ContentRegistry.Content memory content;
        try contentRegistry.getContent(contentId) returns (ContentRegistry.Content memory c2) {
            content = c2;
        } catch {
            revert("Content not found");
        }
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
        bytes16 intentId = _generateStandardIntentId(msg.sender, content.creator, contentId);
        purchases[contentId][msg.sender] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: contentPrice,
            purchaseTime: block.timestamp,
            intentId: intentId,
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
        try contentRegistry.recordPurchase(contentId, msg.sender) { } catch { }

        emit DirectPurchaseCompleted(contentId, msg.sender, content.creator, contentPrice, platformFee, creatorEarning);
    }

    /**
     * @dev Requests refund for a purchase within the refund window
     * @param contentId Content to refund
     * @param reason Reason for refund request
     */
    function requestRefund(uint256 contentId, string memory reason) external nonReentrant whenNotPaused {
        PurchaseRecord storage purchase = purchases[contentId][msg.sender];
        require(purchase.hasPurchased, "No purchase found");
        require(purchase.refundEligible, "Not refund eligible");
        require(block.timestamp <= purchase.refundDeadline, "Refund window expired");
        purchase.refundEligible = false;
        pendingRefunds[msg.sender] += purchase.purchasePrice;
        // Use standardized refund intent ID
        bytes16 refundIntentId =
            IntentIdManager.generateRefundIntentId(purchase.intentId, msg.sender, reason, address(this));
        failedPurchases[refundIntentId] = FailedPurchase({
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
        emit RefundProcessed(refundIntentId, msg.sender, purchase.purchasePrice, reason);
    }

    /**
     * @dev Processes refund payout to user
     * @param user User to refund
     */
    function processRefundPayout(address user) external onlyRole(REFUND_MANAGER_ROLE) nonReentrant {
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
        returns (PaymentMethod[] memory methods, uint256[] memory prices)
    {
        ContentRegistry.Content memory content;
        try contentRegistry.getContent(contentId) returns (ContentRegistry.Content memory c3) {
            content = c3;
        } catch {
            revert("Content not found");
        }

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
    function getPurchaseDetails(uint256 contentId, address user) external view returns (PurchaseRecord memory) {
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
    function getCreatorEarnings(address creator) external view returns (uint256 total, uint256 withdrawable) {
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

    /**
     * @dev COMPLETE: Records purchase from external contract
     */
    function recordExternalPurchase(
        uint256 contentId,
        address buyer,
        bytes16 intentId,
        uint256 usdcPrice,
        address paymentToken,
        uint256 actualAmountPaid
    ) external onlyRole(PAYMENT_PROCESSOR_ROLE) nonReentrant {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        require(content.isActive, "Content not active");
        require(IntentIdManager.isValidIntentId(intentId), "Invalid intent ID format");
        require(_canPurchaseContent(contentId, buyer), "Cannot purchase content");
        purchases[contentId][buyer] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: usdcPrice,
            purchaseTime: block.timestamp,
            intentId: intentId,
            paymentToken: paymentToken,
            actualAmountPaid: actualAmountPaid,
            refundEligible: true,
            refundDeadline: block.timestamp + REFUND_WINDOW
        });

        userPurchases[buyer].push(contentId);
        userTotalSpent[buyer] += usdcPrice;

        uint256 platformFee = creatorRegistry.calculatePlatformFee(usdcPrice);
        uint256 creatorEarning = usdcPrice - platformFee;

        creatorEarnings[content.creator] += creatorEarning;
        withdrawableEarnings[content.creator] += creatorEarning;

        totalPlatformFees += platformFee;
        totalVolume += usdcPrice;
        totalPurchases++;

        contentRegistry.recordPurchase(contentId, buyer);

        creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 1, 0);

        emit ExternalPurchaseRecorded(contentId, buyer, intentId, usdcPrice, paymentToken, actualAmountPaid);
    }

    /**
     * @dev COMPLETE: Handles refund from external contract
     */
    function handleExternalRefund(bytes16 intentId, address user, uint256 contentId)
        external
        onlyRole(PAYMENT_PROCESSOR_ROLE)
        nonReentrant
    {
        PurchaseRecord storage purchase = purchases[contentId][user];
        require(purchase.hasPurchased, "No purchase found");
        require(purchase.intentId == intentId, "Intent ID mismatch");
        require(purchase.refundEligible, "Not eligible for refund");

        purchase.refundEligible = false;

        uint256 refundAmount = purchase.purchasePrice;
        uint256 platformFee = creatorRegistry.calculatePlatformFee(refundAmount);
        uint256 creatorAmount = refundAmount - platformFee;

        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);

        if (withdrawableEarnings[content.creator] >= creatorAmount) {
            withdrawableEarnings[content.creator] -= creatorAmount;
        } else {
            withdrawableEarnings[content.creator] = 0;
        }

        if (creatorEarnings[content.creator] >= creatorAmount) {
            creatorEarnings[content.creator] -= creatorAmount;
        } else {
            creatorEarnings[content.creator] = 0;
        }

        if (totalPlatformFees >= platformFee) {
            totalPlatformFees -= platformFee;
        }
        if (totalVolume >= refundAmount) {
            totalVolume -= refundAmount;
        }
        if (totalPurchases > 0) {
            totalPurchases--;
        }

        totalRefunds += refundAmount;

        creatorRegistry.updateCreatorStats(content.creator, 0, -1, 0);

        emit ExternalRefundProcessed(intentId, user, contentId, refundAmount);
    }

    /**
     * @dev COMPLETE: Check if user can purchase content (handles refunds)
     */
    function _canPurchaseContent(uint256 contentId, address user) internal view returns (bool) {
        PurchaseRecord memory purchase = purchases[contentId][user];

        if (!purchase.hasPurchased) return true;
        if (purchase.hasPurchased && !purchase.refundEligible) return true;

        return false;
    }

    function canPurchaseContent(uint256 contentId, address user) external view returns (bool) {
        return _canPurchaseContent(contentId, user);
    }

    // Internal helper functions

    /**
     * @dev Gets the appropriate token address for payment method
     */
    function _getPaymentTokenAddress(PaymentMethod method, address providedToken) internal view returns (address) {
        if (method == PaymentMethod.USDC) return address(usdcToken);
        if (method == PaymentMethod.ETH) return address(0); // ETH is address(0)
        if (method == PaymentMethod.WETH) return wethToken; // Configurable WETH address
        if (method == PaymentMethod.OTHER_TOKEN) return providedToken;

        revert InvalidPaymentMethod();
    }

    /**
     * @dev Gets accurate token amount using Uniswap oracle
     */
    function _getAccurateTokenAmount(address token, uint256 usdcAmount, uint256 slippageBps)
        internal
        returns (uint256)
    {
        if (token == address(usdcToken)) {
            return usdcAmount;
        } else if (token == address(0)) {
            // ETH
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
    function _generateStandardIntentId(address user, address creator, uint256 contentId) internal returns (bytes16) {
        uint256 nonce = ++userNonces[user];
        return IntentIdManager.generateIntentId(
            user, creator, contentId, IntentIdManager.IntentType.CONTENT_PURCHASE, nonce, address(this)
        );
    }

    /**
     * @dev Handles failed purchase and prepares refund
     */
    function _handleFailedPurchase(bytes16 intentId, PendingPurchase memory pending, string memory reason) internal {
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
