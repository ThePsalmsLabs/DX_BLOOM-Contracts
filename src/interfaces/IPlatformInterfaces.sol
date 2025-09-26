// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IPlatformInterfaces
 * @dev Collection of interfaces for the Onchain Content Subscription Platform
 * @notice These interfaces define the core functionality and enable better integration
 */

// Uniswap V3 Quoter Interface for price estimation
interface IQuoterV2 {
    /**
     * @dev Parameters for exact input single pool quote
     */
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;    
        uint24 fee;           
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @dev Parameters for exact output single pool quote
     */
    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;      
        uint24 fee;          
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @dev Returns quote for exact input single pool swap
     */
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);

    /**
     * @dev Returns quote for exact output single pool swap
     */
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);

    /**
     * @dev Returns quote for exact input multi-hop swap
     */
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    /**
     * @dev Returns quote for exact output multi-hop swap
     */
    function quoteExactOutput(bytes memory path, uint256 amountOut)
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );
}

// Permit2 interfaces
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    /// @notice Permit and transfer tokens in a single transaction
    /// @param permit The permit data signed by the owner
    /// @param transferDetails The transfer details
    /// @param owner The owner of the tokens
    /// @param signature The signature from the owner
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    /// @notice Nonce for a given owner
    function nonce(address owner) external view returns (uint256);

    /// @notice The domain separator used in the permit signature
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface ICommercePaymentsProtocol {
    /**
     * @dev TransferIntent structure from the actual Base Commerce Protocol
     */
    struct TransferIntent {
        uint256 recipientAmount; // Amount merchant will receive (in recipientCurrency)
        uint256 deadline; // Unix timestamp - payment must complete before this
        address payable recipient; // Merchant's receiving address
        address recipientCurrency; // Token address merchant wants to receive (USDC for our platform)
        address refundDestination; // Address for refunds (usually payer address)
        uint256 feeAmount; // Operator fee (in recipientCurrency)
        bytes16 id; // Unique payment identifier
        address operator; // Operator facilitating the payment
        bytes signature; // Operator's signature over the intent data
        bytes prefix; // Custom signature prefix (optional)
        address sender; // The user who initiated the payment intent
        address token; // The token the user is paying with
    }

    struct Permit2SignatureTransferData {
        ISignatureTransfer.PermitTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails transferDetails;
        bytes signature;
    }

    struct EIP2612SignatureTransferData {
        address owner; // Token owner
        bytes signature; // Permit signature
    }

    // ✅ CORRECTED FUNCTION SIGNATURES
    function registerOperator() external;
    function registerOperatorWithFeeDestination(address _feeDestination) external;
    function unregisterOperator() external;
    
    // View functions for checking registration status
    function operators(address operator) external view returns (bool);
    function operatorFeeDestinations(address operator) external view returns (address);
    
    function transferNative(TransferIntent calldata _intent) external payable;
    function transferToken(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;
    function transferTokenPreApproved(TransferIntent calldata _intent) external;
    function swapAndTransferUniswapV3Native(TransferIntent calldata _intent, uint24 poolFeesTier) external payable;
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData,
        uint24 poolFeesTier
    ) external;
    function swapAndTransferUniswapV3TokenPreApproved(TransferIntent calldata _intent, uint24 poolFeesTier) external;
    function wrapAndTransfer(TransferIntent calldata _intent) external payable;
    function unwrapAndTransfer(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;
    function unwrapAndTransferPreApproved(TransferIntent calldata _intent) external;
    function isOperatorRegistered(address operator) external view returns (bool);
    function getOperatorFeeDestination(address operator) external view returns (address);

    event Transferred(
        address indexed operator,
        bytes16 id,
        address recipient,
        address sender,
        uint256 spentAmount,
        address spentCurrency
    );
    event OperatorRegistered(address operator, address feeDestination);

    error InvalidSignature();
    error ExpiredIntent();
    error NullRecipient();
    error AlreadyProcessed();
    error InexactTransfer();
    error OperatorNotRegistered();
    error InvalidNativeAmount(int256 delta);
    error SwapFailedString(string reason);
    error SwapFailedBytes(bytes reason);
}

/**
 * @dev Interface for creator management and validation
 */
interface ICreatorRegistry {
    struct Creator {
        bool isRegistered;
        uint256 subscriptionPrice;
        bool isVerified;
        uint256 totalEarnings;
        uint256 contentCount;
        uint256 subscriberCount;
    }

    function registerCreator(uint256 subscriptionPrice) external;
    function updateSubscriptionPrice(uint256 newPrice) external;
    function withdrawCreatorEarnings() external;
    function isRegisteredCreator(address creator) external view returns (bool);
    function getSubscriptionPrice(address creator) external view returns (uint256);
    function calculatePlatformFee(uint256 amount) external view returns (uint256);
    function updateCreatorStats(address creator, uint256 earnings, int256 contentDelta, int256 subscriberDelta)
        external;

    event CreatorRegistered(address indexed creator, uint256 subscriptionPrice, uint256 timestamp);
    event SubscriptionPriceUpdated(address indexed creator, uint256 oldPrice, uint256 newPrice);
    event CreatorVerified(address indexed creator, bool verified);
    event CreatorEarningsWithdrawn(address indexed creator, uint256 amount);
}

/**
 * @dev Interface for content management and discovery
 */
interface IContentRegistry {
    enum ContentCategory {
        Article,
        Video,
        Audio,
        Image,
        Document,
        Course,
        Other
    }

    struct Content {
        address creator;
        string ipfsHash;
        string title;
        string description;
        ContentCategory category;
        uint256 payPerViewPrice;
        bool isActive;
        uint256 createdAt;
        uint256 purchaseCount;
        string[] tags;
    }

    function registerContent(
        string memory ipfsHash,
        string memory title,
        string memory description,
        ContentCategory category,
        uint256 payPerViewPrice,
        string[] memory tags
    ) external returns (uint256 contentId);

    function getContent(uint256 contentId) external view returns (Content memory);
    function getCreatorContent(address creator) external view returns (uint256[] memory);
    function recordPurchase(uint256 contentId, address buyer) external;

    event ContentRegistered(
        uint256 indexed contentId,
        address indexed creator,
        string ipfsHash,
        string title,
        ContentCategory category,
        uint256 payPerViewPrice,
        uint256 timestamp
    );
}

/**
 * @dev Interface for pay-per-view content purchases
 */
interface IPayPerView {
    struct PurchaseRecord {
        bool hasPurchased;
        uint256 purchasePrice;
        uint256 purchaseTime;
        bytes16 intentId;
        address paymentToken;
        uint256 actualAmountPaid;
    }

    function purchaseContentDirect(uint256 contentId) external;
    function completePurchase(bytes16 intentId, uint256 actualAmountPaid, bool success, string memory failureReason)
        external;
    function hasAccess(uint256 contentId, address user) external view returns (bool);
    function withdrawEarnings() external;
    function getPurchaseDetails(uint256 contentId, address user) external view returns (PurchaseRecord memory);
    function recordExternalPurchase(
        uint256 contentId,
        address buyer,
        bytes16 intentId,
        uint256 usdcPrice,
        address paymentToken,
        uint256 actualAmountPaid
    ) external;
    function handleExternalRefund(bytes16 intentId, address user, uint256 contentId) external;
    function canPurchaseContent(uint256 contentId, address user) external view returns (bool);

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
}

/**
 * @dev Interface for subscription management
 */
interface ISubscriptionManager {
    struct SubscriptionRecord {
        bool isActive;
        uint256 startTime;
        uint256 endTime;
        uint256 renewalCount;
        uint256 totalPaid;
        uint256 lastPayment;
    }

    struct AutoRenewal {
        bool enabled;
        uint256 maxPrice;
        uint256 balance;
    }

    function subscribeToCreator(address creator) external;
    function executeAutoRenewal(address user, address creator) external;
    function cancelSubscription(address creator, bool immediate) external;
    function withdrawSubscriptionEarnings() external;
    function isSubscribed(address user, address creator) external view returns (bool);
    function getSubscriptionDetails(address user, address creator) external view returns (SubscriptionRecord memory);
    function recordSubscriptionPayment(
        address user,
        address creator,
        bytes16 intentId,
        uint256 usdcAmount,
        address paymentToken,
        uint256 actualAmountPaid
    ) external;
    function handleExternalRefund(bytes16 intentId, address user, address creator) external;

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
}

/**
 * @dev Enhanced interface for price estimation using Uniswap with coordination features
 */
interface IPriceOracle {
    // Legacy functions
    function getTokenPrice(address tokenIn, address tokenOut, uint256 amountIn, uint24 poolFee)
        external
        view
        returns (uint256 amountOut);

    function getETHPrice(uint256 usdcAmount) external view returns (uint256 ethAmount);
    function getTokenAmountForUSDC(address token, uint256 usdcAmount, uint24 poolFee)
        external
        view
        returns (uint256 tokenAmount);
        
    // Enhanced coordination functions
    function getOptimalPoolFeeForSwap(address tokenIn, address tokenOut) external view returns (uint24 fee);
    function getQuoteWithRecommendedFee(address tokenIn, address tokenOut, uint256 amountIn) 
        external 
        view 
        returns (uint256 amountOut, uint24 recommendedFee);
        
    // Validation and protection functions
    function validateQuoteBeforeSwap(
        address tokenIn,
        address tokenOut, 
        uint256 amountIn,
        uint256 expectedAmountOut,
        uint256 toleranceBps,
        uint24 poolFee
    ) external view returns (bool isValid, uint256 currentAmountOut);
    
    function checkPriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 maxPriceImpactBps
    ) external view returns (uint256 priceImpactBps, bool isAcceptable);
    
    // Access to token addresses for validation
    function USDC() external view returns (address);
    function WETH() external view returns (address);
}

/**
 * @dev Interface for payment monitoring system
 */
interface IPaymentMonitor {
    function grantPurchaseAccess(address user, uint256 contentId) external;
    function grantSubscriptionAccess(address user, address creator) external;
    function processRefund(bytes16 intentId, address user, uint256 amount) external;

    event AccessGranted(address indexed user, uint256 indexed contentId, string accessType);
    event RefundProcessed(bytes16 indexed intentId, address indexed user, uint256 amount);
}

/**
 * @dev Interface for Base Commerce Integration
 */
interface IBaseCommerceIntegration {
    struct EscrowPaymentParams {
        address payer;
        address receiver;
        uint256 amount;
        uint8 paymentType;
        bytes permit2Data;
        bool instantCapture;
    }

    function registerOperator(address feeDestination) external returns (bytes32 operatorId);
    function isOperatorRegistered(address operator) external view returns (bool);
    function operatorFeeDestination() external view returns (address);
    function executeEscrowPayment(EscrowPaymentParams memory params) external returns (bytes32 paymentHash);
    function executeBatchEscrowPayment(EscrowPaymentParams[] memory params) external returns (bytes32[] memory paymentHashes);
    function getProtocolFeeRate() external view returns (uint256 feeRate);
    function getOperatorFee(address operator) external view returns (uint256 feeAmount);
}
