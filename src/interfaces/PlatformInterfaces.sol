// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IPlatformInterfaces
 * @dev Collection of interfaces for the Onchain Content Subscription Platform
 * @notice These interfaces define the core functionality and enable better integration
 */

/**
 * @dev Interface for the actual Base Commerce Payments Protocol integration
 * Based on the deployed Transfers.sol contract by Coinbase and Shopify
 * Contract addresses:
 * - Base Mainnet: 0xeADE6bE02d043b3550bE19E960504dbA14A14971
 * - Base Sepolia: 0x96A08D8e8631b6dB52Ea0cbd7232d9A85d239147
 */

// Import the actual protocol interfaces
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
     * This is the exact structure used by the deployed protocol
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

    /**
     * @dev Permit2-based token transfer data structure
     */
    struct Permit2SignatureTransferData {
        ISignatureTransfer.PermitTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails transferDetails;
        bytes signature;
    }

    /**
     * @dev EIP-2612 permit-based transfer data structure
     */
    struct EIP2612SignatureTransferData {
        address owner;     // Token owner
        bytes signature;   // Permit signature
    }

    /**
     * @dev Register as an operator to facilitate payments
     * @param _feeDestination Address to receive operator fees
     */
    function registerOperator(address _feeDestination) external;

    /**
     * @dev Transfer native currency (ETH) from sender to recipient
     * @param _intent The transfer intent describing the payment
     */
    function transferNative(TransferIntent calldata _intent) external payable;

    /**
     * @dev Transfer ERC-20 tokens using Permit2 signatures
     * @param _intent The transfer intent describing the payment
     * @param _signatureTransferData Permit2 signature data for token transfer
     */
    function transferToken(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;

    /**
     * @dev Transfer ERC-20 tokens with pre-approved allowance
     * @param _intent The transfer intent describing the payment
     */
    function transferTokenPreApproved(TransferIntent calldata _intent) external;

    /**
     * @dev Swap ETH for target token via Uniswap V3 and transfer to recipient
     * @param _intent The transfer intent describing the payment
     * @param poolFeesTier Uniswap V3 pool fee tier (500, 3000, 10000)
     */
    function swapAndTransferUniswapV3Native(
        TransferIntent calldata _intent,
        uint24 poolFeesTier
    ) external payable;

    /**
     * @dev Swap any token for target token via Uniswap V3 using Permit2
     * @param _intent The transfer intent describing the payment
     * @param _signatureTransferData Permit2 signature data
     * @param poolFeesTier Uniswap V3 pool fee tier
     */
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData,
        uint24 poolFeesTier
    ) external;

    /**
     * @dev Swap any token for target token via Uniswap V3 with pre-approved allowance
     * @param _intent The transfer intent describing the payment
     * @param poolFeesTier Uniswap V3 pool fee tier
     */
    function swapAndTransferUniswapV3TokenPreApproved(
        TransferIntent calldata _intent,
        uint24 poolFeesTier
    ) external;

    /**
     * @dev Convert ETH to WETH and transfer to recipient
     * @param _intent The transfer intent describing the payment
     */
    function wrapAndTransfer(TransferIntent calldata _intent) external payable;

    /**
     * @dev Convert WETH to ETH and transfer to recipient using Permit2
     * @param _intent The transfer intent describing the payment
     * @param _signatureTransferData Permit2 signature data for WETH
     */
    function unwrapAndTransfer(
        TransferIntent calldata _intent,
        Permit2SignatureTransferData calldata _signatureTransferData
    ) external;

    /**
     * @dev Convert WETH to ETH and transfer to recipient with pre-approved allowance
     * @param _intent The transfer intent describing the payment
     */
    function unwrapAndTransferPreApproved(TransferIntent calldata _intent) external;

    /**
     * @dev Check if an operator is registered
     * @param operator Operator address to check
     * @return bool True if operator is registered
     */
    function isOperatorRegistered(address operator) external view returns (bool);

    /**
     * @dev Get operator's fee destination address
     * @param operator Operator address
     * @return address Fee destination for the operator
     */
    function getOperatorFeeDestination(address operator) external view returns (address);

    // Events emitted by the protocol
    event Transferred(
        address indexed operator,
        bytes16 id,
        address recipient,
        address sender,
        uint256 spentAmount,
        address spentCurrency
    );

    event OperatorRegistered(address operator, address feeDestination);

    // Custom errors
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
 * Defines core creator registry functionality
 */
interface ICreatorRegistry {
    /**
     * @dev Creator profile structure
     */
    struct Creator {
        bool isRegistered;
        uint256 subscriptionPrice;
        bool isVerified;
        uint256 totalEarnings;
        uint256 contentCount;
        uint256 subscriberCount;
    }
    
    /**
     * @dev Registers a new creator with subscription pricing
     * @param subscriptionPrice Monthly subscription price in USDC
     */
    function registerCreator(uint256 subscriptionPrice) external;
    
    /**
     * @dev Updates creator's subscription price
     * @param newPrice New subscription price
     */
    function updateSubscriptionPrice(uint256 newPrice) external;
    
    /**
     * @dev Checks if an address is a registered creator
     * @param creator Address to check
     * @return bool Registration status
     */
    function isRegisteredCreator(address creator) external view returns (bool);
    
    /**
     * @dev Gets creator's subscription price
     * @param creator Creator address
     * @return uint256 Subscription price in USDC
     */
    function getSubscriptionPrice(address creator) external view returns (uint256);
    
    /**
     * @dev Calculates platform fee for a given amount
     * @param amount Amount to calculate fee for
     * @return uint256 Platform fee amount
     */
    function calculatePlatformFee(uint256 amount) external view returns (uint256);
    
    // Events
    event CreatorRegistered(address indexed creator, uint256 subscriptionPrice, uint256 timestamp);
    event SubscriptionPriceUpdated(address indexed creator, uint256 oldPrice, uint256 newPrice);
    event CreatorVerified(address indexed creator, bool verified);
}

/**
 * @dev Interface for content management and discovery
 * Defines content registry functionality
 */
interface IContentRegistry {
    /**
     * @dev Content categories for organization
     */
    enum ContentCategory {
        Article,
        Video,
        Audio,
        Image,
        Document,
        Course,
        Other
    }
    
    /**
     * @dev Content metadata structure
     */
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
    
    /**
     * @dev Registers new content with metadata
     * @param ipfsHash IPFS content hash
     * @param title Content title
     * @param description Content description
     * @param category Content category
     * @param payPerViewPrice Price for one-time access
     * @param tags Searchable tags
     * @return contentId Assigned content ID
     */
    function registerContent(
        string memory ipfsHash,
        string memory title,
        string memory description,
        ContentCategory category,
        uint256 payPerViewPrice,
        string[] memory tags
    ) external returns (uint256 contentId);
    
    /**
     * @dev Gets content information by ID
     * @param contentId Content identifier
     * @return Content Content details
     */
    function getContent(uint256 contentId) external view returns (Content memory);
    
    /**
     * @dev Gets content IDs for a creator
     * @param creator Creator address
     * @return uint256[] Array of content IDs
     */
    function getCreatorContent(address creator) external view returns (uint256[] memory);
    
    // Events
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
 * Defines one-time purchase functionality
 */
interface IPayPerView {
    /**
     * @dev Purchase record structure
     */
    struct PurchaseRecord {
        bool hasPurchased;
        uint256 purchasePrice;
        uint256 purchaseTime;
        bytes32 transactionHash;
    }
    
    /**
     * @dev Purchases content with USDC payment
     * @param contentId Content to purchase
     */
    function purchaseContent(uint256 contentId) external;
    
    /**
     * @dev Checks if user has access to content
     * @param contentId Content ID
     * @param user User address
     * @return bool Access status
     */
    function hasAccess(uint256 contentId, address user) external view returns (bool);
    
    /**
     * @dev Allows creators to withdraw earnings
     */
    function withdrawEarnings() external;
    
    /**
     * @dev Gets creator's earnings information
     * @param creator Creator address
     * @return total Total lifetime earnings
     * @return withdrawable Current withdrawable amount
     */
    function getCreatorEarnings(address creator) 
        external 
        view 
        returns (uint256 total, uint256 withdrawable);
    
    // Events
    event ContentPurchased(
        uint256 indexed contentId,
        address indexed buyer,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning,
        uint256 timestamp
    );
}

/**
 * @dev Interface for subscription management
 * Defines recurring subscription functionality
 */
interface ISubscriptionManager {
    /**
     * @dev Subscription record structure
     */
    struct SubscriptionRecord {
        bool isActive;
        uint256 startTime;
        uint256 endTime;
        uint256 renewalCount;
        uint256 totalPaid;
        uint256 lastPayment;
    }
    
    /**
     * @dev Auto-renewal configuration
     */
    struct AutoRenewal {
        bool enabled;
        uint256 maxPrice;
        uint256 balance;
    }
    
    /**
     * @dev Subscribes to a creator for 30 days
     * @param creator Creator to subscribe to
     */
    function subscribeToCreator(address creator) external;
    
    /**
     * @dev Checks if user has active subscription
     * @param user User address
     * @param creator Creator address
     * @return bool Subscription status
     */
    function isSubscribed(address user, address creator) external view returns (bool);
    
    /**
     * @dev Configures auto-renewal for subscriptions
     * @param creator Creator address
     * @param enabled Enable auto-renewal
     * @param maxPrice Maximum price for auto-renewal
     * @param depositAmount USDC to deposit for renewals
     */
    function configureAutoRenewal(
        address creator,
        bool enabled,
        uint256 maxPrice,
        uint256 depositAmount
    ) external;
    
    /**
     * @dev Cancels subscription
     * @param creator Creator to cancel subscription for
     * @param immediate Whether to cancel immediately
     */
    function cancelSubscription(address creator, bool immediate) external;
    
    // Events
    event Subscribed(
        address indexed user,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning,
        uint256 startTime,
        uint256 endTime
    );
}

/**
 * @dev Interface for platform analytics and metrics
 * Provides comprehensive platform data for dashboards and monitoring
 */
interface IPlatformAnalytics {
    /**
     * @dev Platform-wide metrics structure
     */
    struct PlatformMetrics {
        uint256 totalCreators;           // Number of registered creators
        uint256 totalContent;            // Number of published content pieces
        uint256 totalSubscriptions;     // Number of active subscriptions
        uint256 totalRevenue;            // Total platform revenue
        uint256 totalVolume;             // Total transaction volume
        uint256 averageContentPrice;    // Average content pricing
        uint256 averageSubscriptionPrice; // Average subscription pricing
    }
    
    /**
     * @dev Creator-specific analytics
     */
    struct CreatorAnalytics {
        uint256 totalEarnings;          // Lifetime earnings
        uint256 monthlyRevenue;         // Current month revenue
        uint256 subscriberCount;        // Active subscribers
        uint256 contentCount;           // Published content count
        uint256 averageRating;          // Content quality rating
        uint256 engagementScore;        // User engagement metrics
    }
    
    /**
     * @dev Gets platform-wide metrics
     * @return PlatformMetrics Comprehensive platform data
     */
    function getPlatformMetrics() external view returns (PlatformMetrics memory);
    
    /**
     * @dev Gets creator-specific analytics
     * @param creator Creator address
     * @return CreatorAnalytics Creator performance data
     */
    function getCreatorAnalytics(address creator) external view returns (CreatorAnalytics memory);
    
    /**
     * @dev Gets trending content based on purchase velocity
     * @param limit Number of trending items to return
     * @return uint256[] Content IDs sorted by popularity
     */
    function getTrendingContent(uint256 limit) external view returns (uint256[] memory);
    
    /**
     * @dev Gets top performing creators by revenue
     * @param limit Number of creators to return
     * @return address[] Creator addresses sorted by earnings
     */
    function getTopCreators(uint256 limit) external view returns (address[] memory);
}

/**
 * @dev Interface for content moderation and governance
 * Enables community-driven content quality control
 */
interface IContentModeration {
    /**
     * @dev Content report structure
     */
    struct ContentReport {
        uint256 contentId;              // Reported content ID
        address reporter;               // User reporting content
        string reason;                  // Reason for report
        uint256 timestamp;              // Report timestamp
        bool resolved;                  // Resolution status
    }
    
    /**
     * @dev Reports content for moderation review
     * @param contentId Content to report
     * @param reason Reason for reporting
     */
    function reportContent(uint256 contentId, string memory reason) external;
    
    /**
     * @dev Resolves a content report (admin function)
     * @param reportId Report to resolve
     * @param action Action taken (remove, warn, ignore)
     */
    function resolveReport(uint256 reportId, string memory action) external;
    
    /**
     * @dev Gets pending reports for moderation
     * @return ContentReport[] Array of unresolved reports
     */
    function getPendingReports() external view returns (ContentReport[] memory);
    
    // Events
    event ContentReported(uint256 indexed contentId, address indexed reporter, string reason);
    event ReportResolved(uint256 indexed reportId, string action);
}

/**
 * @dev Interface for IPFS content management
 * Abstracts IPFS operations for the platform
 */
interface IIPFSManager {
    /**
     * @dev Content metadata for IPFS storage
     */
    struct ContentMetadata {
        string title;                   // Content title
        string description;             // Content description
        string contentType;             // MIME type
        uint256 fileSize;               // File size in bytes
        string[] tags;                  // Content tags
        uint256 timestamp;              // Upload timestamp
    }
    
    /**
     * @dev Uploads content to IPFS with metadata
     * @param content Content data
     * @param metadata Content metadata
     * @return ipfsHash IPFS hash of uploaded content
     */
    function uploadContent(bytes memory content, ContentMetadata memory metadata) 
        external 
        returns (string memory ipfsHash);
    
    /**
     * @dev Retrieves content from IPFS
     * @param ipfsHash IPFS hash of content
     * @return content Content data
     * @return metadata Content metadata
     */
    function getContent(string memory ipfsHash) 
        external 
        view 
        returns (bytes memory content, ContentMetadata memory metadata);
    
    /**
     * @dev Pins content to ensure availability
     * @param ipfsHash IPFS hash to pin
     * @return success Whether pinning was successful
     */
    function pinContent(string memory ipfsHash) external returns (bool success);
    
    // Events
    event ContentUploaded(string indexed ipfsHash, address indexed uploader, uint256 fileSize);
    event ContentPinned(string indexed ipfsHash, address indexed pinner);
}

/**
 * @dev Interface for platform governance and DAO functionality
 * Enables decentralized decision making for platform evolution
 */
interface IPlatformGovernance {
    /**
     * @dev Proposal structure for governance decisions
     */
    struct Proposal {
        uint256 id;                     // Proposal ID
        address proposer;               // Proposal creator
        string title;                   // Proposal title
        string description;             // Detailed description
        bytes proposalData;             // Encoded proposal actions
        uint256 startTime;              // Voting start time
        uint256 endTime;                // Voting end time
        uint256 forVotes;               // Votes in favor
        uint256 againstVotes;           // Votes against
        bool executed;                  // Execution status
    }
    
    /**
     * @dev Creates a new governance proposal
     * @param title Proposal title
     * @param description Proposal description
     * @param proposalData Encoded proposal actions
     * @return proposalId Created proposal ID
     */
    function createProposal(
        string memory title,
        string memory description,
        bytes memory proposalData
    ) external returns (uint256 proposalId);
    
    /**
     * @dev Votes on a governance proposal
     * @param proposalId Proposal to vote on
     * @param support True for yes, false for no
     * @param votingPower Amount of voting power to use
     */
    function vote(uint256 proposalId, bool support, uint256 votingPower) external;
    
    /**
     * @dev Executes a passed proposal
     * @param proposalId Proposal to execute
     * @return success Whether execution was successful
     */
    function executeProposal(uint256 proposalId) external returns (bool success);
    
    // Events
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId, bool success);
}