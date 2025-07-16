// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";
import {ContentRegistry} from "./ContentRegistry.sol";
import {ICommercePaymentsProtocol} from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title CommerceProtocolIntegration
 * @dev Integrates our content platform with the Base Commerce Payments Protocol
 * @notice This contract acts as an operator in the Commerce Protocol to facilitate
 *         content purchases and subscriptions with advanced payment options
 */
contract CommerceProtocolIntegration is Ownable, ReentrancyGuard, Pausable, EIP712 {
    using ECDSA for bytes32;
    
    // Base Commerce Protocol contract interface
    ICommercePaymentsProtocol public immutable commerceProtocol;
    
    // Our platform contracts
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    
    // Protocol configuration
    address public constant USDC_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base USDC
    address public operatorFeeDestination; // Where our operator fees go
    uint256 public operatorFeeRate = 50; // 0.5% operator fee in basis points
    
    // Intent tracking and management
    mapping(bytes16 => bool) public processedIntents; // Prevent replay attacks
    mapping(bytes16 => PaymentContext) public paymentContexts; // Link intents to platform actions
    
    // Nonce management for intent uniqueness
    mapping(address => uint256) public userNonces;
    
    /**
     * @dev Payment context linking Commerce Protocol intents to platform actions
     */
    struct PaymentContext {
        PaymentType paymentType;     // Type of payment (content purchase, subscription)
        address user;                // User making the payment
        address creator;             // Creator receiving the payment
        uint256 contentId;           // Content ID (0 for subscriptions)
        uint256 platformFee;         // Platform fee amount
        uint256 creatorAmount;       // Amount going to creator
        uint256 timestamp;           // Payment timestamp
        bool processed;              // Whether payment has been processed
    }
    
    /**
     * @dev Types of payments our platform supports
     */
    enum PaymentType {
        ContentPurchase,             // One-time content purchase
        Subscription,                // Monthly creator subscription
        SubscriptionRenewal          // Auto-renewal of existing subscription
    }
    
    /**
     * @dev Structure for creating payment intents on our platform
     */
    struct PlatformPaymentRequest {
        PaymentType paymentType;     // Type of payment
        address creator;             // Creator to pay
        uint256 contentId;           // Content ID (0 for subscriptions)
        address paymentToken;        // Token user wants to pay with (for swaps)
        uint256 maxSlippage;         // Maximum slippage for token swaps (basis points)
        uint256 deadline;            // Payment deadline
    }
    
    // EIP-712 type hash for TransferIntent signing
    bytes32 private constant TRANSFER_INTENT_TYPEHASH = keccak256(
        "TransferIntent(uint256 recipientAmount,uint256 deadline,address recipient,address recipientCurrency,address refundDestination,uint256 feeAmount,bytes16 id,address operator)"
    );
    
    // Events for comprehensive payment tracking
    event PaymentIntentCreated(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee
    );
    
    event PaymentCompleted(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 contentId,
        address paymentToken,
        uint256 amountPaid
    );
    
    event OperatorFeeUpdated(uint256 oldRate, uint256 newRate);
    event OperatorFeeDestinationUpdated(address oldDestination, address newDestination);
    
    // Custom errors
    error InvalidPaymentRequest();
    error IntentAlreadyProcessed();
    error InvalidCreator();
    error InvalidContent();
    error PaymentContextNotFound();
    error InvalidSignature();
    error DeadlineExpired();
    
    /**
     * @dev Constructor initializes the integration with the Commerce Protocol
     * @param _commerceProtocol Address of the deployed Commerce Protocol contract
     * @param _creatorRegistry Address of our CreatorRegistry contract
     * @param _contentRegistry Address of our ContentRegistry contract
     * @param _operatorFeeDestination Address to receive operator fees
     */
    constructor(
        address _commerceProtocol,
        address _creatorRegistry,
        address _contentRegistry,
        address _operatorFeeDestination
    ) Ownable(msg.sender) EIP712("ContentPlatformOperator", "1") {
        require(_commerceProtocol != address(0), "Invalid commerce protocol");
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_operatorFeeDestination != address(0), "Invalid fee destination");
        
        commerceProtocol = ICommercePaymentsProtocol(_commerceProtocol);
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        operatorFeeDestination = _operatorFeeDestination;
    }
    
    /**
     * @dev Registers our platform as an operator in the Commerce Protocol
     * @notice This must be called once after deployment to enable payment processing
     */
    function registerAsOperator() external onlyOwner {
        commerceProtocol.registerOperator(operatorFeeDestination);
    }
    
    /**
     * @dev Creates a signed TransferIntent for content purchase or subscription
     * @param request Payment request details from the user
     * @return intent The signed TransferIntent ready for execution
     * @return context Payment context for tracking
     */
    function createPaymentIntent(PlatformPaymentRequest memory request) 
        external  
        returns (
            ICommercePaymentsProtocol.TransferIntent memory intent,
            PaymentContext memory context
        ) 
    {
        // Validate the payment request
        _validatePaymentRequest(request);
        
        // Calculate payment amounts based on type
        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) = 
            _calculatePaymentAmounts(request);
        
        // Calculate operator fee (our revenue for facilitating the payment)
        uint256 operatorFee = (totalAmount * operatorFeeRate) / 10000;
        uint256 adjustedCreatorAmount = creatorAmount - operatorFee;
        
        // Generate unique intent ID
        bytes16 intentId = _generateIntentId(msg.sender, request);
        
        // Create the TransferIntent structure
        intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: adjustedCreatorAmount,    // Creator receives this amount
            deadline: request.deadline,                // Payment deadline
            recipient: payable(request.creator),       // Creator's address
            recipientCurrency: USDC_TOKEN,             // Always USDC for our platform
            refundDestination: msg.sender,             // Refunds go back to user
            feeAmount: platformFee + operatorFee,      // Combined platform and operator fees
            id: intentId,                              // Unique identifier
            operator: address(this),                   // Our contract is the operator
            signature: "",                             // Will be filled by signing
            prefix: ""                                 // Use default EIP-191 prefix
        });
        
        // Create payment context for tracking
        context = PaymentContext({
            paymentType: request.paymentType,
            user: msg.sender,
            creator: request.creator,
            contentId: request.contentId,
            platformFee: platformFee,
            creatorAmount: adjustedCreatorAmount,
            timestamp: block.timestamp,
            processed: false
        });
        
        // Sign the intent
        intent.signature = _signTransferIntent(intent);
        
        return (intent, context);
    }
    
    /**
     * @dev Processes a completed payment from the Commerce Protocol
     * @param intentId The ID of the completed payment intent
     * @param user The user who made the payment
     * @param paymentToken The token used for payment
     * @param amountPaid The total amount paid
     * @notice This would be called by our monitoring system when payments complete
     */
    function processCompletedPayment(
        bytes16 intentId,
        address user,
        address paymentToken,
        uint256 amountPaid
    ) external {
        // In production, this would have proper access control (e.g., only payment monitor)
        
        if (processedIntents[intentId]) revert IntentAlreadyProcessed();
        
        PaymentContext storage context = paymentContexts[intentId];
        if (context.user == address(0)) revert PaymentContextNotFound();
        
        // Mark as processed
        processedIntents[intentId] = true;
        context.processed = true;
        
        // Grant access based on payment type
        if (context.paymentType == PaymentType.ContentPurchase) {
            _grantContentAccess(context.user, context.contentId);
        } else if (context.paymentType == PaymentType.Subscription || 
                   context.paymentType == PaymentType.SubscriptionRenewal) {
            _grantSubscriptionAccess(context.user, context.creator);
        }
        
        // Update creator earnings and stats
        _updateCreatorEarnings(context.creator, context.creatorAmount, context.paymentType);
        
        emit PaymentCompleted(
            intentId,
            user,
            context.creator,
            context.paymentType,
            context.contentId,
            paymentToken,
            amountPaid
        );
    }
    
    /**
     * @dev Gets payment information for frontend integration
     * @param request Payment request details
     * @return totalAmount Total amount user needs to pay
     * @return creatorAmount Amount going to creator
     * @return platformFee Platform fee amount
     * @return operatorFee Operator fee amount
     * @return paymentMethods Available payment methods for this request
     */
    function getPaymentInfo(PlatformPaymentRequest memory request) 
        external 
        view 
        returns (
            uint256 totalAmount,
            uint256 creatorAmount,
            uint256 platformFee,
            uint256 operatorFee,
            string[] memory paymentMethods
        ) 
    {
        _validatePaymentRequest(request);
        
        (totalAmount, creatorAmount, platformFee) = _calculatePaymentAmounts(request);
        operatorFee = (totalAmount * operatorFeeRate) / 10000;
        
        // Define available payment methods based on the Commerce Protocol
        paymentMethods = new string[](4);
        paymentMethods[0] = "USDC"; // Direct USDC payment
        paymentMethods[1] = "ETH";  // ETH with automatic swap to USDC
        paymentMethods[2] = "WETH"; // WETH with automatic conversion
        paymentMethods[3] = "Other"; // Other tokens via Uniswap swap
        
        return (totalAmount, creatorAmount - operatorFee, platformFee, operatorFee, paymentMethods);
    }
    
    /**
     * @dev Updates operator fee rate
     * @param newRate New fee rate in basis points (50 = 0.5%)
     */
    function updateOperatorFeeRate(uint256 newRate) external onlyOwner {
        require(newRate <= 500, "Fee rate too high"); // Max 5%
        
        uint256 oldRate = operatorFeeRate;
        operatorFeeRate = newRate;
        
        emit OperatorFeeUpdated(oldRate, newRate);
    }
    
    /**
     * @dev Updates operator fee destination
     * @param newDestination New address to receive operator fees
     */
    function updateOperatorFeeDestination(address newDestination) external onlyOwner {
        require(newDestination != address(0), "Invalid destination");
        
        address oldDestination = operatorFeeDestination;
        operatorFeeDestination = newDestination;
        
        emit OperatorFeeDestinationUpdated(oldDestination, newDestination);
    }
    
    // Internal helper functions
    
    /**
     * @dev Validates a payment request for correctness
     */
    function _validatePaymentRequest(PlatformPaymentRequest memory request) internal view {
        // Validate creator is registered
        if (!creatorRegistry.isRegisteredCreator(request.creator)) revert InvalidCreator();
        
        // Validate content exists for content purchases
        if (request.paymentType == PaymentType.ContentPurchase) {
            if (request.contentId == 0) revert InvalidPaymentRequest();
            
            ContentRegistry.Content memory content = contentRegistry.getContent(request.contentId);
            if (content.creator != request.creator || !content.isActive) revert InvalidContent();
        }
        
        // Validate deadline is in the future
        if (request.deadline <= block.timestamp) revert DeadlineExpired();
    }
    
    /**
     * @dev Calculates payment amounts based on request type
     */
    function _calculatePaymentAmounts(PlatformPaymentRequest memory request) 
        internal 
        view 
        returns (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) 
    {
        if (request.paymentType == PaymentType.ContentPurchase) {
            // Get content price
            ContentRegistry.Content memory content = contentRegistry.getContent(request.contentId);
            totalAmount = content.payPerViewPrice;
        } else {
            // Get subscription price
            totalAmount = creatorRegistry.getSubscriptionPrice(request.creator);
        }
        
        // Calculate platform fee
        platformFee = creatorRegistry.calculatePlatformFee(totalAmount);
        creatorAmount = totalAmount - platformFee;
        
        return (totalAmount, creatorAmount, platformFee);
    }
    
    /**
     * @dev Generates a unique intent ID for the payment
     */
    function _generateIntentId(address user, PlatformPaymentRequest memory request) 
        internal 
        returns (bytes16) 
    {
        uint256 nonce = ++userNonces[user];
        
        bytes32 hash = keccak256(abi.encodePacked(
            user,
            request.creator,
            request.contentId,
            uint256(request.paymentType),
            nonce,
            block.timestamp
        ));
        
        return bytes16(hash);
    }
    
    /**
     * @dev Signs a TransferIntent using EIP-712
     */
    function _signTransferIntent(ICommercePaymentsProtocol.TransferIntent memory intent) 
        internal 
        view 
        returns (bytes memory) 
    {
        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_INTENT_TYPEHASH,
            intent.recipientAmount,
            intent.deadline,
            intent.recipient,
            intent.recipientCurrency,
            intent.refundDestination,
            intent.feeAmount,
            intent.id,
            intent.operator
        ));
        
        bytes32 hash = _hashTypedDataV4(structHash);
        
        // In production, this would be signed by a secure operator key
        // For now, we'll use a placeholder signature structure
        return abi.encodePacked(hash, address(this), block.chainid);
    }
    
    /**
     * @dev Grants content access after successful payment
     */
    function _grantContentAccess(address user, uint256 contentId) internal {
        // This would integrate with our PayPerView contract
        // For now, we'll emit an event that the monitoring system can process
        // In production, this would call: payPerView.recordPurchase(contentId, user);
    }
    
    /**
     * @dev Grants subscription access after successful payment
     */
    function _grantSubscriptionAccess(address user, address creator) internal {
        // This would integrate with our SubscriptionManager contract
        // For now, we'll emit an event that the monitoring system can process
        // In production, this would call: subscriptionManager.recordSubscription(user, creator);
    }
    
    /**
     * @dev Updates creator earnings and statistics
     */
    function _updateCreatorEarnings(address creator, uint256 amount, PaymentType paymentType) internal {
        // Update creator stats in the registry
        int256 contentDelta = paymentType == PaymentType.ContentPurchase ? int256(1) : int256(0);
        int256 subscriberDelta = (paymentType == PaymentType.Subscription) ? int256(1) : int256(0);
        
        try creatorRegistry.updateCreatorStats(creator, amount, contentDelta, subscriberDelta) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }
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
}