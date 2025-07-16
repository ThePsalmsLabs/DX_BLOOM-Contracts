// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";
import {ContentRegistry} from "./ContentRegistry.sol";
import {CommerceProtocolIntegration} from "./CommerceProtocolIntegration.sol";
import {ICommercePaymentsProtocol} from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title PayPerViewWithCommerce
 * @dev  PayPerView contract integrated with Base Commerce Protocol
 * @notice This contract handles content purchases using the Commerce Protocol for
 *         advanced payment options including ETH payments, token swaps, and multi-currency support
 */
contract PayPerView is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    // Contract references
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    CommerceProtocolIntegration public immutable commerceIntegration;
    ICommercePaymentsProtocol public immutable commerceProtocol;
    IERC20 public immutable usdcToken;
    
    // Access and purchase tracking
    mapping(uint256 => mapping(address => PurchaseRecord)) public purchases;
    mapping(address => uint256[]) public userPurchases;
    mapping(address => uint256) public userTotalSpent;
    
    // Creator earnings and platform metrics
    mapping(address => uint256) public creatorEarnings;
    mapping(address => uint256) public withdrawableEarnings;
    uint256 public totalPlatformFees;
    uint256 public totalVolume;
    uint256 public totalPurchases;
    
    // Commerce Protocol integration tracking
    mapping(bytes16 => uint256) public intentToContentId; // Link payment intents to content
    mapping(bytes16 => address) public intentToUser;      // Link payment intents to users
    
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
    
    // Custom errors
    error InvalidPaymentMethod();
    error PurchaseAlreadyCompleted();
    error IntentNotFound();
    error CommerceProtocolError(string reason);
    
    /**
     * @dev Constructor initializes the enhanced PayPerView system
     * @param _creatorRegistry Address of CreatorRegistry contract
     * @param _contentRegistry Address of ContentRegistry contract
     * @param _commerceIntegration Address of our Commerce Protocol integration
     * @param _commerceProtocol Address of the deployed Commerce Protocol
     * @param _usdcToken Address of USDC token contract
     */
    constructor(
        address _creatorRegistry,
        address _contentRegistry,
        address _commerceIntegration,
        address _commerceProtocol,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_commerceIntegration != address(0), "Invalid commerce integration");
        require(_commerceProtocol != address(0), "Invalid commerce protocol");
        require(_usdcToken != address(0), "Invalid USDC token");
        
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        commerceIntegration = CommerceProtocolIntegration(_commerceIntegration);
        commerceProtocol = ICommercePaymentsProtocol(_commerceProtocol);
        usdcToken = IERC20(_usdcToken);
    }
    
    /**
     * @dev Initiates content purchase using Commerce Protocol for advanced payment options
     * @param contentId Content to purchase
     * @param paymentMethod How user wants to pay (USDC, ETH, WETH, other token)
     * @param paymentToken Token address for OTHER_TOKEN method
     * @param maxSlippage Maximum slippage for token swaps (basis points)
     * @param deadline Payment deadline timestamp
     * @return intent TransferIntent for user to execute
     * @return expectedAmount Expected payment amount in the chosen token
     */
    function initiatePurchaseWithCommerce(
        uint256 contentId,
        PaymentMethod paymentMethod,
        address paymentToken,
        uint256 maxSlippage,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (
        ICommercePaymentsProtocol.TransferIntent memory intent,
        uint256 expectedAmount
    ) {
        // Validate content and access
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        require(content.isActive, "Content not active");
        require(!purchases[contentId][msg.sender].hasPurchased, "Already purchased");
        
        // Create payment request for Commerce Integration
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = 
            CommerceProtocolIntegration.PlatformPaymentRequest({
                paymentType: CommerceProtocolIntegration.PaymentType.ContentPurchase,
                creator: content.creator,
                contentId: contentId,
                paymentToken: _getPaymentTokenAddress(paymentMethod, paymentToken),
                maxSlippage: maxSlippage,
                deadline: deadline
            });
        
        // Get signed intent from our integration contract
        (intent, ) = commerceIntegration.createPaymentIntent(request);
        
        // Track the intent for completion processing
        intentToContentId[intent.id] = contentId;
        intentToUser[intent.id] = msg.sender;
        
        // Calculate expected payment amount based on method
        expectedAmount = _calculateExpectedPaymentAmount(
            content.payPerViewPrice,
            paymentMethod,
            paymentToken
        );
        
        emit ContentPurchaseInitiated(
            contentId,
            msg.sender,
            content.creator,
            intent.id,
            paymentMethod,
            content.payPerViewPrice,
            expectedAmount
        );
        
        return (intent, expectedAmount);
    }
    
    /**
     * @dev Completes content purchase after Commerce Protocol payment
     * @param intentId Payment intent ID that was executed
     * @param paymentToken Token used for payment
     * @param actualAmountPaid Actual amount paid in payment token
     * @notice This is called by our monitoring system when payments complete
     */
    function completePurchase(
        bytes16 intentId,
        address paymentToken,
        uint256 actualAmountPaid
    ) external nonReentrant {
        // In production, this would have proper access control (payment monitor only)
        
        uint256 contentId = intentToContentId[intentId];
        address user = intentToUser[intentId];
        
        require(contentId != 0, "Intent not found");
        require(user != address(0), "User not found");
        require(!purchases[contentId][user].hasPurchased, "Already completed");
        
        // Get content and creator details
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        uint256 contentPrice = content.payPerViewPrice;
        
        // Calculate fees and earnings
        uint256 platformFee = creatorRegistry.calculatePlatformFee(contentPrice);
        uint256 creatorEarning = contentPrice - platformFee;
        
        // Record the purchase
        purchases[contentId][user] = PurchaseRecord({
            hasPurchased: true,
            purchasePrice: contentPrice,
            purchaseTime: block.timestamp,
            intentId: intentId,
            paymentToken: paymentToken,
            actualAmountPaid: actualAmountPaid
        });
        
        // Update user purchase history
        userPurchases[user].push(contentId);
        userTotalSpent[user] += contentPrice;
        
        // Update creator earnings
        creatorEarnings[content.creator] += creatorEarning;
        withdrawableEarnings[content.creator] += creatorEarning;
        
        // Update platform metrics
        totalPlatformFees += platformFee;
        totalVolume += contentPrice;
        totalPurchases++;
        
        // Update creator stats
        try creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 0, 0) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails
        }
        
        // Record purchase in content registry
        try contentRegistry.recordPurchase(contentId, user) {
            // Purchase recorded successfully
        } catch {
            // Continue if recording fails
        }
        
        // Clean up tracking
        delete intentToContentId[intentId];
        delete intentToUser[intentId];
        
        emit ContentPurchaseCompleted(
            contentId,
            user,
            content.creator,
            intentId,
            contentPrice,
            actualAmountPaid,
            paymentToken
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
            actualAmountPaid: contentPrice
        });
        
        // Update tracking
        userPurchases[msg.sender].push(contentId);
        userTotalSpent[msg.sender] += contentPrice;
        creatorEarnings[content.creator] += creatorEarning;
        withdrawableEarnings[content.creator] += creatorEarning;
        totalPlatformFees += platformFee;
        totalVolume += contentPrice;
        totalPurchases++;
        
        // Update stats and registry
        try creatorRegistry.updateCreatorStats(content.creator, creatorEarning, 0, 0) {} catch {}
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
     * @dev Gets available payment methods and their expected costs for content
     * @param contentId Content to check pricing for
     * @return methods Array of available payment methods
     * @return expectedCosts Expected payment amounts for each method
     */
    function getPaymentOptions(uint256 contentId) 
        external 
        view 
        returns (
            PaymentMethod[] memory methods,
            uint256[] memory expectedCosts
        ) 
    {
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        require(content.creator != address(0), "Content not found");
        
        methods = new PaymentMethod[](4);
        expectedCosts = new uint256[](4);
        
        methods[0] = PaymentMethod.USDC;
        expectedCosts[0] = content.payPerViewPrice;
        
        methods[1] = PaymentMethod.ETH;
        expectedCosts[1] = _estimateETHCost(content.payPerViewPrice);
        
        methods[2] = PaymentMethod.WETH;
        expectedCosts[2] = _estimateETHCost(content.payPerViewPrice); // Same as ETH
        
        methods[3] = PaymentMethod.OTHER_TOKEN;
        expectedCosts[3] = 0; // Depends on specific token chosen
        
        return (methods, expectedCosts);
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
     * @dev Creator earnings withdrawal (unchanged from original)
     */
    function withdrawEarnings() external nonReentrant {
        uint256 amount = withdrawableEarnings[msg.sender];
        require(amount > 0, "No earnings to withdraw");
        
        withdrawableEarnings[msg.sender] = 0;
        usdcToken.safeTransfer(msg.sender, amount);
    }
    
    // Internal helper functions
    
    /**
     * @dev Gets the appropriate token address for payment method
     */
    function _getPaymentTokenAddress(PaymentMethod method, address providedToken) 
        internal 
        view 
        returns (address) 
    {
        if (method == PaymentMethod.USDC) return address(usdcToken);
        if (method == PaymentMethod.ETH) return address(0); // ETH is address(0)
        if (method == PaymentMethod.WETH) return 0x4200000000000000000000000000000000000006; // WETH on Base
        if (method == PaymentMethod.OTHER_TOKEN) return providedToken;
        
        revert InvalidPaymentMethod();
    }
    
    /**
     * @dev Calculates expected payment amount for different methods
     */
    function _calculateExpectedPaymentAmount(
        uint256 usdcPrice,
        PaymentMethod method,
        address paymentToken
    ) internal pure returns (uint256) {
        if (method == PaymentMethod.USDC) {
            return usdcPrice;
        } else if (method == PaymentMethod.ETH || method == PaymentMethod.WETH) {
            return _estimateETHCost(usdcPrice);
        } else if (method == PaymentMethod.OTHER_TOKEN) {
            // This would use a price oracle or Uniswap quoter in production
            return _estimateTokenCost(paymentToken, usdcPrice);
        }
        
        return 0;
    }
    
    /**
     * @dev Estimates ETH cost for USDC amount (placeholder for price oracle)
     */
    function _estimateETHCost(uint256 usdcAmount) internal pure returns (uint256) {
        // Placeholder: In production, use Chainlink oracle or Uniswap quoter
        // Assuming 1 ETH = $3000, this is a rough estimate
        return (usdcAmount * 1e18) / (3000 * 1e6); // Convert USDC to ETH
    }
    
    /**
     * @dev Estimates cost in other tokens (placeholder for price oracle)
     */
    function _estimateTokenCost(address token, uint256 usdcAmount) internal pure returns (uint256) {
        // Placeholder: In production, use price oracles or Uniswap quoter
        return usdcAmount; // 1:1 ratio as placeholder
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
}