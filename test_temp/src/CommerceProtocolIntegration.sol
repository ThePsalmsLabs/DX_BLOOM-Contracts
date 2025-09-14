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
import { ICommercePaymentsProtocol, ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { IntentIdManager } from "./IntentIdManager.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";

// Import libraries for size reduction
import { PermitHandlerLib } from "./libraries/PermitHandlerLib.sol";
import { PaymentValidatorLib } from "./libraries/PaymentValidatorLib.sol";
import { PaymentUtilsLib } from "./libraries/PaymentUtilsLib.sol";

// Import split contracts for size reduction
import { AdminManager } from "./AdminManager.sol";
import { ViewManager } from "./ViewManager.sol";
import { AccessManager } from "./AccessManager.sol";
import { SignatureManager } from "./SignatureManager.sol";
import { RefundManager } from "./RefundManager.sol";
import { PermitPaymentManager } from "./PermitPaymentManager.sol";

// Define AccessManager interface for calling its functions
interface IAccessManager {
    struct PaymentContext {
        ISharedTypes.PaymentType paymentType;
        address user;
        address creator;
        uint256 contentId;
        uint256 platformFee;
        uint256 creatorAmount;
        uint256 operatorFee;
        uint256 timestamp;
        bool processed;
        address paymentToken;
        uint256 expectedAmount;
        bytes16 intentId;
    }

    function handleSuccessfulPayment(
        PaymentContext memory context,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid,
        uint256 operatorFee
    ) external;
}

/**
 * @title CommerceProtocolIntegration
 * @dev Integration with Base Commerce Payments Protocol
 * @notice This contract acts as an operator in the Commerce Protocol to facilitate
 *         content purchases and subscriptions with advanced payment options
 */
contract CommerceProtocolIntegration is Ownable, AccessControl, ReentrancyGuard, Pausable, EIP712, ISharedTypes {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using IntentIdManager for *;

    // Library using statements for size reduction
    using PermitHandlerLib for *;
    using PaymentValidatorLib for *;
    using PaymentUtilsLib for *;

    // Role definitions
    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // Base Commerce Protocol contract interface
    ICommercePaymentsProtocol public immutable commerceProtocol;

    // Uniswap Permit2 contract for gasless approvals
    ISignatureTransfer public immutable permit2;

    // Our platform contracts
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    PriceOracle public immutable priceOracle;

    // Split contracts for size reduction
    AdminManager public adminManager;
    ViewManager public viewManager;
    IAccessManager public accessManager;
    SignatureManager public signatureManager;
    RefundManager public refundManager;
    PermitPaymentManager public permitPaymentManager;

    // Token references
    IERC20 public immutable usdcToken;

    // Protocol configuration
    address public operatorFeeDestination; // Where our operator fees go
    uint256 public operatorFeeRate = 50; // 0.5% operator fee in basis points

    // Signing configuration
    address public operatorSigner; // Address authorized to sign intents

    // Intent tracking and management
    mapping(bytes16 => bool) public processedIntents; // Prevent replay attacks
    mapping(bytes16 => PaymentContext) public paymentContexts; // Link intents to platform actions
    mapping(bytes16 => uint256) public intentDeadlines; // Track intent expiration

    // Nonce management for intent uniqueness
    mapping(address => uint256) public userNonces;

    // Platform metrics
    uint256 public totalIntentsCreated;
    uint256 public totalPaymentsProcessed;
    uint256 public totalOperatorFees;
    uint256 public totalRefundsProcessed;

    /**
     * @dev Payment context linking Commerce Protocol intents to platform actions
     */
    struct PaymentContext {
        PaymentType paymentType; // Type of payment
        address user; // User making the payment
        address creator; // Creator receiving the payment
        uint256 contentId; // Content ID (0 for subscriptions)
        uint256 platformFee; // Platform fee amount
        uint256 creatorAmount; // Amount going to creator
        uint256 operatorFee; // Operator fee amount
        uint256 timestamp; // Payment timestamp
        bool processed; // Whether payment has been processed
        address paymentToken; // Token used for payment
        uint256 expectedAmount; // Expected payment amount
        bytes16 intentId; // The original intent ID from the Commerce Protocol
    }



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

    /**
     * @dev Types of payments our platform supports
     */
    // All usages of PaymentType remain the same, as the type is now inherited from ISharedTypes.

    // PlatformPaymentRequest struct moved to ISharedTypes

    // EIP-712 type hashes
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

    // === EVENTS FOR SIGNATURE FLOW ===
    event IntentReadyForSigning(bytes16 indexed intentId, bytes32 intentHash, uint256 deadline);
    event IntentSigned(bytes16 indexed intentId, bytes signature);
    event IntentReadyForExecution(bytes16 indexed intentId, bytes signature);
    event SubscriptionAccessGranted(
        address indexed user, address indexed creator, bytes16 intentId, address paymentToken, uint256 amountPaid
    );
    event ContentAccessGranted(
        address indexed user, uint256 indexed contentId, bytes16 intentId, address paymentToken, uint256 amountPaid
    );

    // Additional events needed for the complete implementation

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

    // ============ PERMIT EVENTS ============
    event PaymentExecutedWithPermit(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 amount,
        address paymentToken,
        bool success
    );

    event PermitPaymentCreated(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        PaymentType paymentType,
        uint256 amount,
        address paymentToken,
        uint256 nonce
    );

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

    // Additional errors needed for the complete implementation
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

    /**
     * @dev Constructor initializes the integration with the Commerce Protocol
     * @notice Manager contracts should be deployed separately to avoid initcode size limits
     */
    constructor(
        address _commerceProtocol,
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
        address _permitPaymentManager
    ) Ownable(msg.sender) EIP712("ContentPlatformOperator", "1") {
        require(_commerceProtocol != address(0), "Invalid commerce protocol");
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

        commerceProtocol = ICommercePaymentsProtocol(_commerceProtocol);
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
        accessManager = IAccessManager(_accessManager);
        signatureManager = SignatureManager(_signatureManager);
        refundManager = RefundManager(_refundManager);
        permitPaymentManager = PermitPaymentManager(_permitPaymentManager);

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_MONITOR_ROLE, msg.sender);
        _grantRole(SIGNER_ROLE, _operatorSigner);
    }

    // Admin functions moved to AdminManager contract for size reduction


    
    /**
     * @dev Check if we're registered and get our fee destination
     */
    function getOperatorStatus() external view returns (bool registered, address feeDestination) {
        registered = commerceProtocol.operators(address(this));
        if (registered) {
            feeDestination = commerceProtocol.operatorFeeDestinations(address(this));
        }
    }

    // ============ ADMIN FUNCTIONS (DELEGATED TO ADMIN MANAGER) ============

    /**
     * @dev Sets the PayPerView contract address (delegated to AdminManager)
     */
    function setPayPerView(address _payPerView) external onlyOwner {
        adminManager.setPayPerView(_payPerView);
    }

    /**
     * @dev Sets the SubscriptionManager contract address (delegated to AdminManager)
     */
    function setSubscriptionManager(address _subscriptionManager) external onlyOwner {
        adminManager.setSubscriptionManager(_subscriptionManager);
    }

    /**
     * @dev Registers our platform as an operator (delegated to AdminManager)
     */
    function registerAsOperator() external onlyOwner {
        adminManager.registerAsOperator();
    }

    /**
     * @dev Alternative registration method (delegated to AdminManager)
     */
    function registerAsOperatorSimple() external onlyOwner {
        adminManager.registerAsOperatorSimple();
    }

    /**
     * @dev Updates operator fee rate (delegated to AdminManager)
     */
    function updateOperatorFeeRate(uint256 newRate) external onlyOwner {
        adminManager.updateOperatorFeeRate(newRate);
    }

    /**
     * @dev Updates operator fee destination (delegated to AdminManager)
     */
    function updateOperatorFeeDestination(address newDestination) external onlyOwner {
        adminManager.updateOperatorFeeDestination(newDestination);
    }

    /**
     * @dev Updates the operator signer address (delegated to AdminManager)
     */
    function updateOperatorSigner(address newSigner) external onlyOwner {
        adminManager.updateOperatorSigner(newSigner);
    }

    /**
     * @dev Adds an authorized signer (delegated to SignatureManager)
     */
    function addAuthorizedSigner(address signer) external onlyOwner {
        signatureManager.addAuthorizedSigner(signer);
    }

    /**
     * @dev Removes an authorized signer (delegated to SignatureManager)
     */
    function removeAuthorizedSigner(address signer) external onlyOwner {
        signatureManager.removeAuthorizedSigner(signer);
    }

    /**
     * @dev Grants payment monitor role (delegated to AdminManager)
     */
    function grantPaymentMonitorRole(address monitor) external onlyOwner {
        adminManager.grantPaymentMonitorRole(monitor);
    }

    /**
     * @dev Withdraws operator fees (delegated to AdminManager)
     */
    function withdrawOperatorFees(address token, uint256 amount) external onlyOwner {
        adminManager.withdrawOperatorFees(token, amount);
    }

    // ============ EMERGENCY CONTROLS ============

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        adminManager.pause();
    }

    /**
     * @dev Resume operations after pause
     */
    function unpause() external onlyOwner {
        adminManager.unpause();
    }

    /**
     * @dev Emergency token recovery
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        adminManager.emergencyTokenRecovery(token, amount);
    }

    /**
     * @dev COMPLETE: Updated createPaymentIntent with REAL signing
     */
    function createPaymentIntent(PlatformPaymentRequest memory request)
        external
        nonReentrant
        whenNotPaused
        returns (ICommercePaymentsProtocol.TransferIntent memory intent, PaymentContext memory context)
    {
        // Validate payment request (includes payment type validation)
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        // Use standardized intent ID
        bytes16 intentId = _generateStandardIntentId(msg.sender, request);

        intent = _createTransferIntent(request, amounts, intentId);

        // Inline _createPaymentContext
        context = PaymentContext({
            paymentType: request.paymentType,
            user: msg.sender,
            creator: request.creator,
            contentId: request.contentId,
            platformFee: amounts.platformFee,
            creatorAmount: amounts.adjustedCreatorAmount,
            operatorFee: amounts.operatorFee,
            timestamp: block.timestamp,
            processed: false,
            paymentToken: request.paymentToken,
            expectedAmount: amounts.expectedAmount,
            intentId: intentId
        });

        _finalizeIntent(intentId, intent, context, request.deadline);
        signatureManager.prepareIntentForSigning(intent);

        // Inline _emitIntentCreatedEvent
        emit PaymentIntentCreated(
            intentId,
            msg.sender,
            request.creator,
            request.paymentType,
            amounts.totalAmount,
            amounts.adjustedCreatorAmount,
            amounts.platformFee,
            amounts.operatorFee,
            request.paymentToken,
            amounts.expectedAmount
        );

        return (intent, context);
    }

    /**
     * @dev Processes a completed payment from the Commerce Protocol
     */
    function processCompletedPayment(
        bytes16 intentId,
        address user,
        address paymentToken,
        uint256 amountPaid,
        bool success,
        string memory failureReason
    ) external onlyRole(PAYMENT_MONITOR_ROLE) nonReentrant {
        if (processedIntents[intentId]) revert IntentAlreadyProcessed();

        PaymentContext storage context = paymentContexts[intentId];
        if (context.user == address(0)) revert PaymentContextNotFound();

        // Validate payment type using library
        if (!PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType(uint8(context.paymentType)))) revert InvalidPaymentType();

        // Check if intent has expired
        if (block.timestamp > intentDeadlines[intentId]) revert IntentExpired();

        // Mark as processed
        processedIntents[intentId] = true;
        context.processed = true;

        if (success) {
            // Convert context to IAccessManager format
            IAccessManager.PaymentContext memory sharedContext = IAccessManager.PaymentContext({
                paymentType: ISharedTypes.PaymentType(uint8(context.paymentType)),
                user: context.user,
                creator: context.creator,
                contentId: context.contentId,
                platformFee: context.platformFee,
                creatorAmount: context.creatorAmount,
                operatorFee: context.operatorFee,
                timestamp: context.timestamp,
                processed: context.processed,
                paymentToken: context.paymentToken,
                expectedAmount: context.expectedAmount,
                intentId: context.intentId
            });

            accessManager.handleSuccessfulPayment(sharedContext, intentId, paymentToken, amountPaid, context.operatorFee);
        } else {
            refundManager.handleFailedPayment(intentId, context.user, context.creator, context.creatorAmount, context.platformFee, context.operatorFee, context.paymentType, failureReason);
        }

        emit PaymentCompleted(
            intentId, user, context.creator, context.paymentType, context.contentId, paymentToken, amountPaid, success
        );
    }



    /**
     * @dev Execute payment with signature - NOW CALLS BASE COMMERCE PROTOCOL!
     * @notice CRITICAL FIX: This function now actually executes payments on Base Commerce Protocol
     */
    function executePaymentWithSignature(bytes16 intentId)
        external
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        require(signatureManager.hasSignature(intentId), "No signature provided");
        PaymentContext memory context = paymentContexts[intentId];
        // Validate payment type using library
        if (!PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType(uint8(context.paymentType)))) revert InvalidPaymentType();
        require(context.user == msg.sender, "Not intent creator");
        require(block.timestamp <= intentDeadlines[intentId], "Intent expired");
        require(!processedIntents[intentId], "Intent already processed");

        // Reconstruct the transfer intent with operator signature
        ICommercePaymentsProtocol.TransferIntent memory intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: context.creatorAmount,
            deadline: intentDeadlines[intentId],
            recipient: payable(context.creator),
            recipientCurrency: address(usdcToken),
            refundDestination: context.user,
            feeAmount: context.platformFee + context.operatorFee,
            id: intentId,
            operator: address(this),
            signature: signatureManager.getIntentSignature(intentId),
            prefix: "",
            sender: context.user,
            token: context.paymentToken
        });

        // CRITICAL FIX: Actually execute the payment through Base Commerce Protocol
        if (context.paymentToken == address(usdcToken) || context.paymentToken == address(0)) {
            // For USDC or ETH payments, use transferNative or transferTokenPreApproved
            try commerceProtocol.transferTokenPreApproved(intent) {
                // Mark as processed and handle success
                processedIntents[intentId] = true;

                // Update context in storage
                PaymentContext storage storedContext = paymentContexts[intentId];
                storedContext.processed = true;

                // Convert context to IAccessManager format
                IAccessManager.PaymentContext memory sharedContext = IAccessManager.PaymentContext({
                    paymentType: ISharedTypes.PaymentType(uint8(storedContext.paymentType)),
                    user: storedContext.user,
                    creator: storedContext.creator,
                    contentId: storedContext.contentId,
                    platformFee: storedContext.platformFee,
                    creatorAmount: storedContext.creatorAmount,
                    operatorFee: storedContext.operatorFee,
                    timestamp: storedContext.timestamp,
                    processed: storedContext.processed,
                    paymentToken: storedContext.paymentToken,
                    expectedAmount: storedContext.expectedAmount,
                    intentId: storedContext.intentId
                });

                accessManager.handleSuccessfulPayment(sharedContext, intentId, storedContext.paymentToken, storedContext.expectedAmount, storedContext.operatorFee);

                emit PaymentCompleted(
                    intentId,
                    context.user,
                    context.creator,
                    context.paymentType,
                    context.contentId,
                    context.paymentToken,
                    context.expectedAmount,
                    true
                );

        emit IntentReadyForExecution(intentId, intent.signature);
                return true;
            } catch Error(string memory reason) {
                refundManager.handleFailedPayment(intentId, context.user, context.creator, context.creatorAmount, context.platformFee, context.operatorFee, context.paymentType, reason);
                emit PaymentCompleted(
                    intentId,
                    context.user,
                    context.creator,
                    context.paymentType,
                    context.contentId,
                    context.paymentToken,
                    0,
                    false
                );
                return false;
            } catch (bytes memory lowLevelData) {
                string memory reason = lowLevelData.length > 0 ? string(lowLevelData) : "Unknown error";
                refundManager.handleFailedPayment(intentId, context.user, context.creator, context.creatorAmount, context.platformFee, context.operatorFee, context.paymentType, reason);
                emit PaymentCompleted(
                    intentId,
                    context.user,
                    context.creator,
                    context.paymentType,
                    context.contentId,
                    context.paymentToken,
                    0,
                    false
                );
                return false;
            }
        } else {
            // For other tokens, we need permit data - this path requires permit integration
            revert("Non-USDC payments require permit data. Use executePaymentWithPermit instead.");
        }
    }

    /**
     * @dev Gets payment information for frontend integration
     */
    function getPaymentInfo(PlatformPaymentRequest memory request)
        external
        returns (
            uint256 totalAmount,
            uint256 creatorAmount,
            uint256 platformFee,
            uint256 operatorFee,
            uint256 expectedAmount
        )
    {
        _validatePaymentRequest(request);
        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);

        return (
            amounts.totalAmount,
            amounts.adjustedCreatorAmount,
            amounts.platformFee,
            amounts.operatorFee,
            amounts.expectedAmount
        );
    }

    /**
     * @dev Gets payment context for an intent
     */
    function getPaymentContext(bytes16 intentId) external view returns (PaymentContext memory) {
        return paymentContexts[intentId];
    }

    /**
     * @dev Gets platform operator metrics
     */
    function getOperatorMetrics()
        external
        view
        returns (uint256 intentsCreated, uint256 paymentsProcessed, uint256 operatorFees, uint256 refunds)
    {
        return (totalIntentsCreated, totalPaymentsProcessed, totalOperatorFees, totalRefundsProcessed);
    }







    /**
     * @dev Updates operator fee rate
     */






    // Internal helper functions - broken down to avoid stack too deep

    /**
     * @dev Calculates all payment amounts in one go
     */
    function _calculateAllPaymentAmounts(PlatformPaymentRequest memory request)
        internal
        returns (PaymentAmounts memory amounts)
    {
        // Use library for expected amount calculation only
        (amounts.totalAmount, amounts.creatorAmount, amounts.platformFee) = _calculatePaymentAmounts(request);
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
     * @dev Creates the TransferIntent structure
     */
    function _createTransferIntent(
        PlatformPaymentRequest memory request,
        PaymentAmounts memory amounts,
        bytes16 intentId
    ) internal view returns (ICommercePaymentsProtocol.TransferIntent memory intent) {
        intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: amounts.adjustedCreatorAmount,
            deadline: request.deadline,
            recipient: payable(request.creator),
            recipientCurrency: address(usdcToken), // Use the configured USDC token
            refundDestination: msg.sender,
            feeAmount: amounts.platformFee + amounts.operatorFee,
            id: intentId,
            operator: address(this),
            signature: "",
            prefix: "",
            sender: msg.sender,
            token: request.paymentToken
        });
        return intent;
    }



    /**
     * @dev Finalizes intent creation with validation and state initialization
     */
    function _finalizeIntent(
        bytes16 intentId,
        ICommercePaymentsProtocol.TransferIntent memory intent,
        PaymentContext memory context,
        uint256 deadline
    ) internal {
        // Validate intent uniqueness
        if (processedIntents[intentId]) revert IntentAlreadyProcessed();
        if (paymentContexts[intentId].user != address(0)) revert IntentAlreadyExists();

        // Validate deadline
        if (deadline <= block.timestamp) revert DeadlineInPast();
        if (deadline > block.timestamp + 7 days) revert DeadlineTooFar();

        // Validate amounts
        if (intent.recipientAmount == 0) revert ZeroAmount();
        if (intent.feeAmount > intent.recipientAmount) revert FeeExceedsAmount();

        // Validate addresses
        if (intent.recipient == address(0)) revert InvalidRecipient();
        if (intent.refundDestination == address(0)) revert InvalidRefundDestination();

        // Validate consistency
        if (context.user != intent.refundDestination) revert ContextIntentMismatch();
        if (context.creatorAmount != intent.recipientAmount) revert AmountMismatch();

        // Store data
        paymentContexts[intentId] = context;
        intentDeadlines[intentId] = deadline;
        processedIntents[intentId] = false;
        totalIntentsCreated++;
        emit IntentFinalized(intentId, context.user, context.creator, context.paymentType, intent.recipientAmount, deadline);

        // Inline _recordIntentCreation
        emit IntentAuditRecord(
            intentId,
            context.user,
            context.creator,
            context.paymentType,
            context.creatorAmount,
            context.platformFee,
            context.operatorFee,
            context.paymentToken,
            deadline,
            block.timestamp
        );
    }











    /**
     * @dev Validates a payment request for correctness
     */
    function _validatePaymentRequest(PlatformPaymentRequest memory request) internal view {
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
        // We can't directly access the private platformFee variable, so we calculate it
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
     * @dev Gets expected payment amount using price oracle
     */
    function _getExpectedPaymentAmount(address paymentToken, uint256 usdcAmount, uint256 slippageBps)
        internal
        returns (uint256)
    {
        return PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            usdcAmount,
            slippageBps,
            address(priceOracle)
        );
    }

    /**
     * @dev UPDATED: Standardized intent ID generation using IntentIdManager
     * @param user User making the payment
     * @param request Payment request details
     * @return bytes16 Unique intent ID
     */
    function _generateStandardIntentId(address user, PlatformPaymentRequest memory request)
        internal
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





    /**
     * @dev Grants content access after successful payment
     */




    /**
     * @dev Emergency pause function
     */




    /**
     * @dev Returns true if the intent is still active (not processed)
     */
    function hasActiveIntent(bytes16 intentId) public view returns (bool) {
        return !processedIntents[intentId] && signatureManager.hasSignature(intentId);
    }

    /**
     * @dev Returns true if an intent has been signed and is ready for execution
     */
    function intentReadyForExecution(bytes16 intentId) public view returns (bool) {
        return signatureManager.hasSignature(intentId);
    }

    /**
     * @dev Provides signature for an intent (delegates to SignatureManager)
     */
    function provideIntentSignature(bytes16 intentId, bytes memory signature) external {
        signatureManager.provideIntentSignature(intentId, signature, operatorSigner);
    }

    /**
     * @dev Gets signature for an intent (delegates to SignatureManager)
     */
    function getIntentSignature(bytes16 intentId) external view returns (bytes memory) {
        return signatureManager.getIntentSignature(intentId);
    }

    /**
     * @dev Checks if an intent has a signature (delegates to SignatureManager)
     */
    function hasSignature(bytes16 intentId) external view returns (bool) {
        return signatureManager.hasSignature(intentId);
    }

    /**
     * @dev Executes payment with permit (delegates to PermitPaymentManager)
     */
    function executePaymentWithPermit(
        bytes16 intentId,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) external nonReentrant whenNotPaused returns (bool success) {
        PaymentContext memory context = paymentContexts[intentId];
        require(context.user == msg.sender, "Not intent creator");

        return permitPaymentManager.executePaymentWithPermit(
            intentId,
            msg.sender,
            context.paymentToken,
            context.expectedAmount,
            context.creator,
            context.creatorAmount,
            context.platformFee,
            context.operatorFee,
            intentDeadlines[intentId],
            context.paymentType,
            signatureManager.getIntentSignature(intentId),
            permitData
        );
    }

    /**
     * @dev Creates and executes payment with permit (delegates to PermitPaymentManager)
     */
    function createAndExecuteWithPermit(
        PlatformPaymentRequest memory request,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) external nonReentrant whenNotPaused returns (bytes16 intentId, bool success) {
        // Validate payment request (includes payment type validation)
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        intentId = _generateStandardIntentId(msg.sender, request);

        // Create transfer intent
        ICommercePaymentsProtocol.TransferIntent memory intent = _createTransferIntent(request, amounts, intentId);

        // Inline _createPaymentContext
        PaymentContext memory context = PaymentContext({
            paymentType: request.paymentType,
            user: msg.sender,
            creator: request.creator,
            contentId: request.contentId,
            platformFee: amounts.platformFee,
            creatorAmount: amounts.adjustedCreatorAmount,
            operatorFee: amounts.operatorFee,
            timestamp: block.timestamp,
            processed: false,
            paymentToken: request.paymentToken,
            expectedAmount: amounts.expectedAmount,
            intentId: intentId
        });

        // Prepare and sign intent with operator signature
        signatureManager.prepareIntentForSigning(intent);
        _finalizeIntent(intentId, intent, context, request.deadline);

        // Inline _emitIntentCreatedEvent
        emit PaymentIntentCreated(
            intentId,
            msg.sender,
            request.creator,
            request.paymentType,
            amounts.totalAmount,
            amounts.adjustedCreatorAmount,
            amounts.platformFee,
            amounts.operatorFee,
            request.paymentToken,
            amounts.expectedAmount
        );

        // Execute with permit
        success = permitPaymentManager.executePaymentWithPermit(
            intentId,
            msg.sender,
            request.paymentToken,
            amounts.expectedAmount,
            request.creator,
            amounts.adjustedCreatorAmount,
            amounts.platformFee,
            amounts.operatorFee,
            request.deadline,
            request.paymentType,
            signatureManager.getIntentSignature(intentId),
            permitData
        );

        return (intentId, success);
    }

    /**
     * @dev Checks if payment can be executed with permit (delegates to PermitPaymentManager)
     */
    function canExecuteWithPermit(
        bytes16 intentId,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) external view returns (bool canExecute, string memory reason) {
        PaymentContext memory context = paymentContexts[intentId];
        return permitPaymentManager.canExecuteWithPermit(
            intentId,
            context.user,
            intentDeadlines[intentId],
            signatureManager.hasSignature(intentId),
            permitData,
            context.paymentToken,
            context.expectedAmount
        );
    }

    /**
     * @dev Gets permit nonce for a user (delegates to PermitPaymentManager)
     */
    function getPermitNonce(address user) external view returns (uint256 nonce) {
        return permitPaymentManager.getPermitNonce(user);
    }

    // ============ PERMIT VALIDATION FUNCTIONS (DELEGATED TO PERMIT MANAGER) ============

    /**
     * @dev Validates permit signature data (delegated to PermitPaymentManager)
     */
    function validatePermitData(
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        address user
    ) external view returns (bool isValid) {
        return permitPaymentManager.validatePermitData(permitData, user);
    }

    /**
     * @dev Validates that permit data matches the payment context (delegated to PermitPaymentManager)
     */
    function validatePermitContext(
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        PaymentContext memory context
    ) external view returns (bool isValid) {
        return permitPaymentManager.validatePermitContext(permitData, context.paymentToken, context.expectedAmount, address(commerceProtocol));
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures (delegated to PermitPaymentManager)
     */
    function getPermitDomainSeparator() external view returns (bytes32 domainSeparator) {
        return permitPaymentManager.getPermitDomainSeparator();
    }

    // ============ ADDITIONAL SIGNATURE MANAGEMENT FUNCTIONS ============

    /**
     * @dev Prepares an intent for signing (delegated to SignatureManager)
     */
    function prepareIntentForSigning(ICommercePaymentsProtocol.TransferIntent memory intent) external returns (bytes32) {
        return signatureManager.prepareIntentForSigning(intent);
    }

    /**
     * @dev Provides an intent signature (delegated to SignatureManager)
     */
    function provideIntentSignature(bytes16 intentId, bytes memory signature, address signer) external {
        signatureManager.provideIntentSignature(intentId, signature, signer);
    }

    /**
     * @dev Gets intent hash for an intent (delegates to SignatureManager)
     */
    function intentHashes(bytes16 intentId) external view returns (bytes32) {
        return signatureManager.intentHashes(intentId);
    }

    /**
     * @dev Requests a refund (delegates to RefundManager)
     */
    function requestRefund(bytes16 intentId, string memory reason) external nonReentrant whenNotPaused {
        PaymentContext storage context = paymentContexts[intentId];
        require(context.user == msg.sender, "Not payment creator");
        require(context.processed, "Payment not processed");

        refundManager.requestRefund(
            intentId,
            msg.sender,
            context.creatorAmount,
            context.platformFee,
            context.operatorFee,
            context.paymentType,
            reason
        );
    }

    /**
     * @dev Gets refund request details (delegates to RefundManager)
     */
    function refundRequests(bytes16 intentId) external view returns (
        bytes16 originalIntentId,
        address user,
        uint256 amount,
        string memory reason,
        uint256 requestTime,
        bool processed
    ) {
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(intentId);
        return (
            refund.originalIntentId,
            refund.user,
            refund.amount,
            refund.reason,
            refund.requestTime,
            refund.processed
        );
    }

    // ============ REFUND PROCESSING FUNCTIONS (DELEGATED TO REFUND MANAGER) ============

    /**
     * @dev Processes a refund payout to user (delegated to RefundManager)
     */
    function processRefund(bytes16 intentId) external onlyRole(PAYMENT_MONITOR_ROLE) nonReentrant {
        refundManager.processRefund(intentId);
    }

    /**
     * @dev Processes refund with coordination between contracts (delegated to RefundManager)
     */
    function processRefundWithCoordination(bytes16 intentId) external onlyRole(PAYMENT_MONITOR_ROLE) nonReentrant {
        PaymentContext memory context = paymentContexts[intentId];
        refundManager.processRefundWithCoordination(intentId, context.paymentType, context.contentId, context.creator);
    }
}
