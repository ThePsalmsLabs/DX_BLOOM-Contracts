// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { CreatorRegistry } from "./CreatorRegistry.sol";
import { ContentRegistry } from "./ContentRegistry.sol";
import { PayPerView } from "./PayPerView.sol";
import { SubscriptionManager } from "./SubscriptionManager.sol";
import { PriceOracle } from "./PriceOracle.sol";
import { ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { BaseCommerceIntegration } from "./BaseCommerceIntegration.sol";
import { IntentIdManager } from "./IntentIdManager.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";

// Import libraries for shared functionality
import { PaymentValidatorLib } from "./libraries/PaymentValidatorLib.sol";
import { PaymentUtilsLib } from "./libraries/PaymentUtilsLib.sol";

// Import manager contracts for shared references
import { AdminManager } from "./AdminManager.sol";
import { ViewManager } from "./ViewManager.sol";
import { AccessManager } from "./AccessManager.sol";
import { SignatureManager } from "./SignatureManager.sol";
import { RefundManager } from "./RefundManager.sol";
import { PermitPaymentManager } from "./PermitPaymentManager.sol";

// Rewards system imports (optional - can be zero address if not deployed)
import { RewardsIntegration } from "./rewards/RewardsIntegration.sol";

/**
 * @title CommerceProtocolBase
 * @dev Abstract base contract containing shared state and functionality for Commerce Protocol integration
 * @notice This contract provides the foundation for both CommerceProtocolCore and CommerceProtocolPermit
 */
abstract contract CommerceProtocolBase is Ownable, AccessControl, ReentrancyGuard, Pausable, EIP712, ISharedTypes {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using IntentIdManager for *;

    // Library using statements for shared functionality
    using PaymentValidatorLib for *;
    using PaymentUtilsLib for *;

    // ============ SHARED ROLE DEFINITIONS ============
    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // ============ SHARED CONTRACT REFERENCES ============
    
    // Real Base Commerce Protocol integration
    BaseCommerceIntegration public immutable baseCommerceIntegration;

    // Uniswap Permit2 contract for gasless approvals
    ISignatureTransfer public immutable permit2;

    // Our platform contracts
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    PriceOracle public immutable priceOracle;

    // Manager contracts (shared references)
    AdminManager public adminManager;
    ViewManager public viewManager;
    AccessManager public accessManager;
    SignatureManager public signatureManager;
    RefundManager public refundManager;
    PermitPaymentManager public permitPaymentManager;

    // Rewards system (optional - can be zero address)
    RewardsIntegration public rewardsIntegration;

    // Token references
    IERC20 public immutable usdcToken;

    // ============ SHARED PROTOCOL CONFIGURATION ============
    address public operatorFeeDestination; // Where our operator fees go
    uint256 public operatorFeeRate = 50; // 0.5% operator fee in basis points

    // Signing configuration
    address public operatorSigner; // Address authorized to sign intents

    // ============ SHARED STATE VARIABLES ============
    
    // Intent tracking and management
    mapping(bytes16 => bool) public processedIntents; // Prevent replay attacks
    mapping(bytes16 => ISharedTypes.PaymentContext) public paymentContexts; // Link intents to platform actions
    mapping(bytes16 => uint256) public intentDeadlines; // Track intent expiration

    // Nonce management for intent uniqueness
    mapping(address => uint256) public userNonces;

    // Platform metrics
    uint256 public totalIntentsCreated;
    uint256 public totalPaymentsProcessed;
    uint256 public totalOperatorFees;
    uint256 public totalRefundsProcessed;

    // ============ SHARED STRUCTS ============
    
    // PaymentContext moved to ISharedTypes for consistency

    /**
     * @dev Payment calculation result
     */
    struct PaymentAmounts {
        uint256 totalAmount;
        uint256 creatorAmount;
        uint256 platformFee;
        uint256 operatorFee;
        uint256 adjustedCreatorAmount;
        uint256 expectedAmount;
    }

    // ============ SHARED EVENTS ============
    
    // Events for comprehensive payment tracking
    event PaymentIntentCreated(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        address paymentToken,
        uint256 expectedAmount
    );

    event PaymentCompleted(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 contentId,
        address paymentToken,
        uint256 amountPaid,
        bool success
    );

    event RefundRequested(bytes16 indexed intentId, address indexed user, uint256 amount, string reason);
    event RefundProcessed(bytes16 indexed intentId, address indexed user, uint256 amount);
    event OperatorFeeUpdated(uint256 oldRate, uint256 newRate);
    event OperatorFeeDestinationUpdated(address oldDestination, address newDestination);
    event SignerUpdated(address oldSigner, address newSigner);
    event ContractAddressUpdated(string contractName, address oldAddress, address newAddress);

    // Additional events for complete implementation
    event IntentFinalized(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 amount,
        uint256 deadline
    );

    event IntentAuditRecord(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        address paymentToken,
        uint256 deadline,
        uint256 createdAt
    );

    // ============ SHARED ERRORS ============
    
    // Custom errors
    error InvalidPaymentRequest();
    error IntentAlreadyProcessed();
    error InvalidCreator();
    error InvalidContent();
    error PaymentContextNotFound();
    error InvalidSignature();
    error DeadlineExpired();
    error IntentExpired();
    error UnauthorizedSigner();
    error RefundAlreadyProcessed();
    error NoRefundAvailable();
    error InvalidRefundAmount();

    // Additional errors for complete implementation
    error IntentAlreadyExists();
    error DeadlineInPast();
    error DeadlineTooFar();
    error ZeroAmount();
    error FeeExceedsAmount();
    error InvalidRecipient();
    error InvalidRefundDestination();
    error ContextIntentMismatch();
    error AmountMismatch();
    error InvalidPaymentType();

    // ============ SHARED TYPEHASHES ============
    
    // EIP-712 type hashes
    bytes32 internal constant TRANSFER_INTENT_TYPEHASH = keccak256(
        "TransferIntent(uint256 recipientAmount,uint256 deadline,address recipient,address recipientCurrency,address refundDestination,uint256 feeAmount,bytes16 id,address operator)"
    );

    /**
     * @dev Base constructor initializes shared state and contracts
     * @notice Manager contracts should be deployed separately to avoid initcode size limits
     */
    constructor(
        address _baseCommerceIntegration,
        address _permit2,
        address _creatorRegistry,
        address _contentRegistry,
        address _priceOracle,
        address _usdcToken,
        address _operatorFeeDestination,
        address _operatorSigner,
        // Manager contract addresses (deploy separately to avoid initcode size limits)
        address _adminManager,
        address _viewManager,
        address _accessManager,
        address _signatureManager,
        address _refundManager,
        address _permitPaymentManager,
        address _rewardsIntegration
    ) Ownable(msg.sender) EIP712("ContentPlatformOperator", "1") {
        require(_baseCommerceIntegration != address(0), "Invalid base commerce integration");
        require(_permit2 != address(0), "Invalid permit2 contract");
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_operatorFeeDestination != address(0), "Invalid fee destination");
        require(_operatorSigner != address(0), "Invalid operator signer");

        // Validate manager contract addresses
        require(_adminManager != address(0), "Invalid admin manager");
        require(_viewManager != address(0), "Invalid view manager");
        require(_accessManager != address(0), "Invalid access manager");
        require(_signatureManager != address(0), "Invalid signature manager");
        require(_refundManager != address(0), "Invalid refund manager");
        require(_permitPaymentManager != address(0), "Invalid permit payment manager");

        baseCommerceIntegration = BaseCommerceIntegration(_baseCommerceIntegration);
        permit2 = ISignatureTransfer(_permit2);
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
        operatorFeeDestination = _operatorFeeDestination;
        operatorSigner = _operatorSigner;

        // Initialize manager contracts (deployed separately)
        adminManager = AdminManager(_adminManager);
        viewManager = ViewManager(_viewManager);
        accessManager = AccessManager(_accessManager);
        signatureManager = SignatureManager(_signatureManager);
        refundManager = RefundManager(_refundManager);
        permitPaymentManager = PermitPaymentManager(_permitPaymentManager);
        
        // Rewards integration is optional during deployment to avoid circular dependency
        if (_rewardsIntegration != address(0)) {
            rewardsIntegration = RewardsIntegration(_rewardsIntegration);
        }

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_MONITOR_ROLE, msg.sender);
        _grantRole(SIGNER_ROLE, _operatorSigner);
    }

    // ============ SHARED VALIDATION FUNCTIONS ============
    
    /**
     * @dev Validates a payment request for correctness
     */
    function _validatePaymentRequest(PlatformPaymentRequest memory request) internal view virtual {
        // Basic deadline validation using library
        if (!PaymentUtilsLib.validateDeadline(request.deadline, PaymentUtilsLib.MAX_DEADLINE_FUTURE)) {
            revert DeadlineExpired();
        }

        // Payment type validation using library
        if (!PaymentUtilsLib.validatePaymentType(PaymentUtilsLib.PaymentType(uint8(request.paymentType)))) {
            revert InvalidPaymentRequest();
        }

        // Storage-dependent validations remain in main contract
        if (!creatorRegistry.isRegisteredCreator(request.creator)) revert InvalidCreator();

        if (request.paymentType == PaymentType.PayPerView) {
            if (request.contentId == 0) revert InvalidPaymentRequest();

            ContentRegistry.Content memory content = contentRegistry.getContent(request.contentId);
            if (content.creator != request.creator || !content.isActive) revert InvalidContent();
        }

        if (request.paymentToken == address(0) && request.paymentType != PaymentType.PayPerView) {
            revert InvalidPaymentRequest();
        }
    }

    /**
     * @dev Calculates payment amounts based on request type
     */
    function _calculatePaymentAmounts(PlatformPaymentRequest memory request)
        internal
        view
        virtual
        returns (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee)
    {
        // Gather data from storage
        uint256 contentPrice = 0;
        uint256 subscriptionPrice = 0;

        if (request.paymentType == PaymentType.PayPerView) {
            ContentRegistry.Content memory content = contentRegistry.getContent(request.contentId);
            contentPrice = content.payPerViewPrice;
        } else {
            subscriptionPrice = creatorRegistry.getSubscriptionPrice(request.creator);
        }

        // Get platform fee rate from CreatorRegistry (stored as basis points)
        uint256 platformFeeRate = 250; // 2.5% platform fee in basis points

        // Use library for calculation
        (totalAmount, creatorAmount, platformFee) = PaymentUtilsLib.calculateBasicPaymentAmounts(
            ISharedTypes.PaymentType(uint8(request.paymentType)),
            contentPrice,
            subscriptionPrice,
            platformFeeRate
        );

        return (totalAmount, creatorAmount, platformFee);
    }

    /**
     * @dev Calculates all payment amounts in one go with loyalty discounts applied
     */
    function _calculateAllPaymentAmounts(PlatformPaymentRequest memory request)
        internal
        virtual
        returns (PaymentAmounts memory amounts)
    {
        // Calculate base amounts
        (amounts.totalAmount, amounts.creatorAmount, amounts.platformFee) = _calculatePaymentAmounts(request);
        
        // Apply loyalty discounts if rewards integration is available
        if (address(rewardsIntegration) != address(0)) {
            try rewardsIntegration.calculateDiscountedPrice(msg.sender, amounts.totalAmount) returns (uint256 discountedTotal) {
                if (discountedTotal < amounts.totalAmount) {
                    // Apply discount proportionally across amounts
                    uint256 discountRatio = (discountedTotal * 10000) / amounts.totalAmount;
                    amounts.totalAmount = discountedTotal;
                    amounts.creatorAmount = (amounts.creatorAmount * discountRatio) / 10000;
                    amounts.platformFee = (amounts.platformFee * discountRatio) / 10000;
                }
            } catch {
                // If discount calculation fails, continue with original amounts
            }
        }
        
        amounts.operatorFee = (amounts.totalAmount * operatorFeeRate) / 10000;
        amounts.adjustedCreatorAmount = amounts.creatorAmount - amounts.operatorFee;

        // Use library for expected payment amount calculation
        amounts.expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            request.paymentToken,
            amounts.totalAmount,
            request.maxSlippage,
            address(priceOracle)
        );

        return amounts;
    }



    /**
     * @dev Marks an intent as processed (shared functionality)
     */
    function _markIntentAsProcessed(bytes16 intentId) internal virtual {
        processedIntents[intentId] = true;
        paymentContexts[intentId].processed = true;
        totalPaymentsProcessed++;
    }

    /**
     * @dev Distributes platform revenue to rewards treasury and triggers rewards
     * @param context Payment context containing fee information
     * @param intentId Intent ID for the payment
     * @param paymentToken Token used for payment
     * @param amountPaid Actual amount paid by user
     * @param operatorFee Operator fee amount
     */
    function _distributeFunds(
        ISharedTypes.PaymentContext memory context,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid,
        uint256 operatorFee
    ) internal virtual {
        // 1. Distribute platform revenue to rewards treasury
        if (address(rewardsIntegration) != address(0) && context.platformFee > 0) {
            // Approve USDC transfer to rewards integration
            IERC20(address(usdcToken)).forceApprove(address(rewardsIntegration), context.platformFee);
            
            try rewardsIntegration.onPaymentSuccess(intentId, context) {
                // Revenue distribution successful
            } catch {
                // If rewards integration fails, continue with payment
                // Platform fee stays in contract for manual handling
            }
        }

        // 2. Track operator fees
        totalOperatorFees += operatorFee;

        // 3. Creator amount is handled by the respective manager contracts (PayPerView, SubscriptionManager)
        // The actual creator payment is processed through BaseCommerceIntegration escrow
    }

    /**
     * @dev Generates standardized intent ID using IntentIdManager
     */
    function _generateStandardIntentId(address user, PlatformPaymentRequest memory request)
        internal
        virtual
        returns (bytes16)
    {
        uint256 nonce = ++userNonces[user];
        IntentIdManager.IntentType intentType;
        if (request.paymentType == PaymentType.PayPerView) {
            intentType = IntentIdManager.IntentType.CONTENT_PURCHASE;
        } else if (request.paymentType == PaymentType.Subscription) {
            intentType = IntentIdManager.IntentType.SUBSCRIPTION;
        }
        return
            IntentIdManager.generateIntentId(user, request.creator, request.contentId, intentType, nonce, address(this));
    }

    // ============ SHARED VIEW FUNCTIONS ============
    
    /**
     * @dev Gets payment context for an intent
     */
    function getPaymentContext(bytes16 intentId) external view virtual returns (ISharedTypes.PaymentContext memory) {
        return paymentContexts[intentId];
    }

    /**
     * @dev Gets platform operator metrics
     */
    function getOperatorMetrics()
        external
        view
        virtual
        returns (uint256 intentsCreated, uint256 paymentsProcessed, uint256 operatorFees, uint256 refunds)
    {
        return (totalIntentsCreated, totalPaymentsProcessed, totalOperatorFees, totalRefundsProcessed);
    }

    /**
     * @dev Check if we're registered and get our fee destination
     * @notice Now uses BaseCommerceIntegration which handles real Base Commerce Protocol
     */
    function getOperatorStatus() external view virtual returns (bool registered, address feeDestination) {
        // With BaseCommerceIntegration, we're always "registered" since it handles the real protocol
        registered = address(baseCommerceIntegration) != address(0);
        if (registered) {
            feeDestination = baseCommerceIntegration.operatorFeeDestination();
        }
    }

    // ============ ABSTRACT FUNCTIONS (TO BE IMPLEMENTED BY CHILDREN) ============
    
    /**
     * @dev Returns the contract type - must be implemented by child contracts
     */
    function getContractType() external pure virtual returns (string memory);

    /**
     * @dev Returns the contract version - must be implemented by child contracts
     */
    function getContractVersion() external pure virtual returns (string memory);

    /**
     * @dev Sets the rewards integration contract (admin only)
     * @param _rewardsIntegration Address of the RewardsIntegration contract
     */
    function setRewardsIntegration(address _rewardsIntegration) external onlyOwner {
        require(_rewardsIntegration != address(0), "Invalid rewards integration address");
        address oldAddress = address(rewardsIntegration);
        rewardsIntegration = RewardsIntegration(_rewardsIntegration);
        emit ContractAddressUpdated("RewardsIntegration", oldAddress, _rewardsIntegration);
    }
}