// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IPlatformInterfaces
 * @dev Collection of interfaces for the Onchain Content Subscription Platform
 * @notice These interfaces define the core functionality and enable better integration
 */

// Uniswap V3 Quoter Interface for price estimation
interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
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
}

interface ICommercePaymentsProtocol {
    /**
     * @dev TransferIntent structure from the actual Base Commerce Protocol
     */
    struct TransferIntent {
        uint256 recipientAmount;      // Amount merchant will receive (in recipientCurrency)
        uint256 deadline;             // Unix timestamp - payment must complete before this
        address payable recipient;    // Merchant's receiving address
        address recipientCurrency;    // Token address merchant wants to receive (USDC for our platform)
        address refundDestination;    // Address for refunds (usually payer address)
        uint256 feeAmount;           // Operator fee (in recipientCurrency)
        bytes16 id;                  // Unique payment identifier
        address operator;            // Operator facilitating the payment
        bytes signature;             // Operator's signature over the intent data
        bytes prefix;                // Custom signature prefix (optional)
    }

    struct Permit2SignatureTransferData {
        ISignatureTransfer.PermitTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails transferDetails;
        bytes signature;
    }

    struct EIP2612SignatureTransferData {
        address owner;     // Token owner
        bytes signature;   // Permit signature
    }

    function registerOperator(address _feeDestination) external;
    function transferNative(TransferIntent calldata _intent) external payable;
    function transferToken(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;
    function transferTokenPreApproved(TransferIntent calldata _intent) external;
    function swapAndTransferUniswapV3Native(
        TransferIntent calldata _intent,
        uint24 poolFeesTier
    ) external payable;
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData,
        uint24 poolFeesTier
    ) external;
    function swapAndTransferUniswapV3TokenPreApproved(
        TransferIntent calldata _intent,
        uint24 poolFeesTier
    ) external;
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
    function updateCreatorStats(
        address creator,
        uint256 earnings,
        int256 contentDelta,
        int256 subscriberDelta
    ) external;
    
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
    function completePurchase(
        bytes16 intentId,
        address paymentToken,
        uint256 actualAmountPaid
    ) external;
    function hasAccess(uint256 contentId, address user) external view returns (bool);
    function withdrawEarnings() external;
    function getPurchaseDetails(uint256 contentId, address user) 
        external 
        view 
        returns (PurchaseRecord memory);
    
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
    function getSubscriptionDetails(address user, address creator) 
        external 
        view 
        returns (SubscriptionRecord memory);
    
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
}

/**
 * @dev Interface for price estimation using Uniswap
 */
interface IPriceOracle {
    function getTokenPrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 poolFee
    ) external view returns (uint256 amountOut);
    
    function getETHPrice(uint256 usdcAmount) external view returns (uint256 ethAmount);
    function getTokenAmountForUSDC(
        address token,
        uint256 usdcAmount,
        uint24 poolFee
    ) external view returns (uint256 tokenAmount);
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