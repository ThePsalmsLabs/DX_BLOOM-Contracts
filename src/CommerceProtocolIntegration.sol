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
import {CreatorRegistry} from "./CreatorRegistry.sol";
import {ContentRegistry} from "./ContentRegistry.sol";
import {PayPerView} from "./PayPerView.sol";
import {SubscriptionManager} from "./SubscriptionManager.sol";
import {PriceOracle} from "./PriceOracle.sol";
import {ICommercePaymentsProtocol} from "./interfaces/IPlatformInterfaces.sol";
import {IntentIdManager} from "./IntentIdManager.sol";
import {ISharedTypes} from "./interfaces/ISharedTypes.sol";

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

    // Role definitions
    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    // Base Commerce Protocol contract interface
    ICommercePaymentsProtocol public immutable commerceProtocol;

    // Our platform contracts
    CreatorRegistry public immutable creatorRegistry;
    ContentRegistry public immutable contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    PriceOracle public immutable priceOracle;

    // Token references
    IERC20 public immutable usdcToken;

    // Protocol configuration
    address public operatorFeeDestination; // Where our operator fees go
    uint256 public operatorFeeRate = 50; // 0.5% operator fee in basis points

    // Signing configuration
    address public operatorSigner; // Address authorized to sign intents
    mapping(address => bool) public authorizedSigners; // Multiple signers support

    // Intent tracking and management
    mapping(bytes16 => bool) public processedIntents; // Prevent replay attacks
    mapping(bytes16 => PaymentContext) public paymentContexts; // Link intents to platform actions
    mapping(bytes16 => uint256) public intentDeadlines; // Track intent expiration

    // Nonce management for intent uniqueness
    mapping(address => uint256) public userNonces;

    // Refund tracking
    mapping(bytes16 => RefundRequest) public refundRequests;
    mapping(address => uint256) public pendingRefunds; // User -> USDC amount

    // Platform metrics
    uint256 public totalIntentsCreated;
    uint256 public totalPaymentsProcessed;
    uint256 public totalOperatorFees;
    uint256 public totalRefundsProcessed;

    // === REAL SIGNATURE IMPLEMENTATION STATE ===
    mapping(bytes16 => bytes32) public intentHashes; // intentId => hash to be signed
    mapping(bytes16 => bytes) public intentSignatures; // intentId => actual signature
    mapping(bytes16 => bool) public intentReadyForExecution; // intentId => ready status

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
     * @dev Refund request structure
     */
    struct RefundRequest {
        bytes16 originalIntentId;
        address user;
        uint256 amount;
        string reason;
        uint256 requestTime;
        bool processed;
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

    /**
     * @dev Structure for creating payment intents on our platform
     */
    struct PlatformPaymentRequest {
        PaymentType paymentType; // Type of payment
        address creator; // Creator to pay
        uint256 contentId; // Content ID (0 for subscriptions)
        address paymentToken; // Token user wants to pay with
        uint256 maxSlippage; // Maximum slippage for token swaps (basis points)
        uint256 deadline; // Payment deadline
    }

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
     */
    constructor(
        address _commerceProtocol,
        address _creatorRegistry,
        address _contentRegistry,
        address _priceOracle,
        address _usdcToken,
        address _operatorFeeDestination,
        address _operatorSigner
    ) Ownable(msg.sender) EIP712("ContentPlatformOperator", "1") {
        require(_commerceProtocol != address(0), "Invalid commerce protocol");
        require(_creatorRegistry != address(0), "Invalid creator registry");
        require(_contentRegistry != address(0), "Invalid content registry");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_operatorFeeDestination != address(0), "Invalid fee destination");
        require(_operatorSigner != address(0), "Invalid operator signer");

        commerceProtocol = ICommercePaymentsProtocol(_commerceProtocol);
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        contentRegistry = ContentRegistry(_contentRegistry);
        priceOracle = PriceOracle(_priceOracle);
        usdcToken = IERC20(_usdcToken);
        operatorFeeDestination = _operatorFeeDestination;
        operatorSigner = _operatorSigner;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_MONITOR_ROLE, msg.sender);
        _grantRole(SIGNER_ROLE, _operatorSigner);

        // Add operator signer to authorized signers
        authorizedSigners[_operatorSigner] = true;
    }

    /**
     * @dev Sets the PayPerView contract address after deployment
     */
    function setPayPerView(address _payPerView) external onlyOwner {
        require(_payPerView != address(0), "Invalid address");
        address oldAddress = address(payPerView);
        payPerView = PayPerView(_payPerView);
        emit ContractAddressUpdated("PayPerView", oldAddress, _payPerView);
    }

    /**
     * @dev Sets the SubscriptionManager contract address after deployment
     */
    function setSubscriptionManager(address _subscriptionManager) external onlyOwner {
        require(_subscriptionManager != address(0), "Invalid address");
        address oldAddress = address(subscriptionManager);
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        emit ContractAddressUpdated("SubscriptionManager", oldAddress, _subscriptionManager);
    }

    /**
     * @dev Registers our platform as an operator in the Commerce Protocol
     */
    function registerAsOperator() external onlyOwner {
        commerceProtocol.registerOperator(operatorFeeDestination);
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
        // Validate payment type is within enum range
        if (uint8(request.paymentType) > 2) revert InvalidPaymentType();
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        // Use standardized intent ID
        bytes16 intentId = _generateStandardIntentId(msg.sender, request);

        intent = _createTransferIntent(request, amounts, intentId);
        context = _createPaymentContext(request, amounts, intentId);

        _finalizeIntent(intentId, intent, context, request.deadline);
        _prepareIntentForSigning(intent);
        _emitIntentCreatedEvent(intentId, request, amounts);

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

        // Validate payment type is within enum range
        if (uint8(context.paymentType) > 2) revert InvalidPaymentType();

        // Check if intent has expired
        if (block.timestamp > intentDeadlines[intentId]) revert IntentExpired();

        // Mark as processed
        processedIntents[intentId] = true;
        context.processed = true;

        if (success) {
            _handleSuccessfulPayment(context, intentId, paymentToken, amountPaid);
        } else {
            _handleFailedPayment(intentId, context, failureReason);
        }

        emit PaymentCompleted(
            intentId, user, context.creator, context.paymentType, context.contentId, paymentToken, amountPaid, success
        );
    }

    /**
     * @dev Requests a refund for a failed or disputed payment
     */
    function requestRefund(bytes16 intentId, string memory reason) external nonReentrant whenNotPaused {
        PaymentContext storage context = paymentContexts[intentId];
        require(context.user == msg.sender, "Not payment creator");
        require(context.processed, "Payment not processed");

        // Check if refund already requested
        if (refundRequests[intentId].requestTime != 0) revert RefundAlreadyProcessed();

        // Use standardized refund intent ID
        bytes16 refundIntentId = IntentIdManager.generateRefundIntentId(intentId, msg.sender, reason, address(this));
        // Calculate and process refund request
        _processRefundRequest(refundIntentId, context, reason);
    }

    /**
     * @dev Processes a refund payout to user
     */
    function processRefund(bytes16 intentId) external onlyRole(PAYMENT_MONITOR_ROLE) nonReentrant {
        RefundRequest storage refund = refundRequests[intentId];
        require(refund.requestTime != 0, "Refund not requested");
        require(!refund.processed, "Already processed");

        refund.processed = true;

        // Update pending refunds
        if (pendingRefunds[refund.user] >= refund.amount) {
            pendingRefunds[refund.user] -= refund.amount;
        } else {
            pendingRefunds[refund.user] = 0;
        }

        // Transfer USDC refund
        usdcToken.safeTransfer(refund.user, refund.amount);

        totalRefundsProcessed += refund.amount;

        emit RefundProcessed(intentId, refund.user, refund.amount);
    }

    /**
     * @dev Processes refund with coordination between contracts
     */
    function processRefundWithCoordination(bytes16 intentId) external onlyRole(PAYMENT_MONITOR_ROLE) nonReentrant {
        RefundRequest storage refund = refundRequests[intentId];
        require(refund.requestTime != 0, "Refund not requested");
        require(!refund.processed, "Already processed");

        PaymentContext memory context = paymentContexts[intentId];
        // Validate payment type is within enum range
        if (uint8(context.paymentType) > 2) revert InvalidPaymentType();
        refund.processed = true;

        if (context.paymentType == PaymentType.PayPerView && address(payPerView) != address(0)) {
            try payPerView.handleExternalRefund(intentId, refund.user, context.contentId) {} catch {}
        } else if ((context.paymentType == PaymentType.Subscription) && address(subscriptionManager) != address(0)) {
            try subscriptionManager.handleExternalRefund(intentId, refund.user, context.creator) {} catch {}
        }

        if (pendingRefunds[refund.user] >= refund.amount) {
            pendingRefunds[refund.user] -= refund.amount;
        } else {
            pendingRefunds[refund.user] = 0;
        }

        usdcToken.safeTransfer(refund.user, refund.amount);
        totalRefundsProcessed += refund.amount;

        emit RefundProcessed(intentId, refund.user, refund.amount);
    }

    /**
     * @dev COMPLETE: Execute payment with real signature
     */
    function executePaymentWithSignature(bytes16 intentId)
        external
        nonReentrant
        whenNotPaused
        returns (ICommercePaymentsProtocol.TransferIntent memory intent)
    {
        require(intentReadyForExecution[intentId], "Intent not ready for execution");
        PaymentContext memory context = paymentContexts[intentId];
        // Validate payment type is within enum range
        if (uint8(context.paymentType) > 2) revert InvalidPaymentType();
        require(context.user == msg.sender, "Not intent creator");
        require(block.timestamp <= intentDeadlines[intentId], "Intent expired");
        // Reconstruct intent with real signature
        intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: context.creatorAmount,
            deadline: intentDeadlines[intentId],
            recipient: payable(context.creator),
            recipientCurrency: address(usdcToken), // Use the configured USDC token
            refundDestination: context.user,
            feeAmount: context.platformFee + context.operatorFee,
            id: intentId,
            operator: address(this),
            signature: intentSignatures[intentId], // REAL SIGNATURE
            prefix: "",
            sender: context.user,
            token: context.paymentToken
        });
        emit IntentReadyForExecution(intentId, intent.signature);
        return intent;
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
    function updateOperatorFeeRate(uint256 newRate) external onlyOwner {
        require(newRate <= 500, "Fee rate too high"); // Max 5%

        uint256 oldRate = operatorFeeRate;
        operatorFeeRate = newRate;

        emit OperatorFeeUpdated(oldRate, newRate);
    }

    /**
     * @dev Updates operator fee destination
     */
    function updateOperatorFeeDestination(address newDestination) external onlyOwner {
        require(newDestination != address(0), "Invalid destination");

        address oldDestination = operatorFeeDestination;
        operatorFeeDestination = newDestination;

        emit OperatorFeeDestinationUpdated(oldDestination, newDestination);
    }

    /**
     * @dev Updates the operator signer address
     */
    function updateOperatorSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid signer");

        address oldSigner = operatorSigner;

        // Remove old signer from authorized signers
        authorizedSigners[oldSigner] = false;
        _revokeRole(SIGNER_ROLE, oldSigner);

        // Add new signer
        operatorSigner = newSigner;
        authorizedSigners[newSigner] = true;
        _grantRole(SIGNER_ROLE, newSigner);

        emit SignerUpdated(oldSigner, newSigner);
    }

    /**
     * @dev Adds an authorized signer
     */
    function addAuthorizedSigner(address signer) external onlyOwner {
        require(signer != address(0), "Invalid signer");
        authorizedSigners[signer] = true;
        _grantRole(SIGNER_ROLE, signer);
    }

    /**
     * @dev Removes an authorized signer
     */
    function removeAuthorizedSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = false;
        _revokeRole(SIGNER_ROLE, signer);
    }

    /**
     * @dev Grants payment monitor role to authorized backend services
     */
    function grantPaymentMonitorRole(address monitor) external onlyOwner {
        _grantRole(PAYMENT_MONITOR_ROLE, monitor);
    }

    /**
     * @dev Withdraws operator fees
     */
    function withdrawOperatorFees(uint256 amount) external onlyOwner {
        uint256 balance = usdcToken.balanceOf(address(this));
        if (amount == 0) {
            amount = balance;
        }

        require(amount <= balance, "Insufficient balance");
        usdcToken.safeTransfer(operatorFeeDestination, amount);
    }

    // Internal helper functions - broken down to avoid stack too deep

    /**
     * @dev Calculates all payment amounts in one go
     */
    function _calculateAllPaymentAmounts(PlatformPaymentRequest memory request)
        internal
        returns (PaymentAmounts memory amounts)
    {
        (amounts.totalAmount, amounts.creatorAmount, amounts.platformFee) = _calculatePaymentAmounts(request);
        amounts.operatorFee = (amounts.totalAmount * operatorFeeRate) / 10000;
        amounts.adjustedCreatorAmount = amounts.creatorAmount - amounts.operatorFee;
        amounts.expectedAmount =
            _getExpectedPaymentAmount(request.paymentToken, amounts.totalAmount, request.maxSlippage);

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
     * @dev Creates the payment context for tracking
     */
    function _createPaymentContext(
        PlatformPaymentRequest memory request,
        PaymentAmounts memory amounts,
        bytes16 intentId
    ) internal view returns (PaymentContext memory context) {
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
            intentId: intentId // Store the original intent ID
        });

        return context;
    }

    /**
     * @dev COMPLETE: Finalizes intent creation with proper validation and state initialization
     * @param intentId Unique identifier for the payment intent
     * @param intent The transfer intent structure for the Commerce Protocol
     * @param context Payment context containing business logic details
     * @param deadline When the payment intent expires
     */
    function _finalizeIntent(
        bytes16 intentId,
        ICommercePaymentsProtocol.TransferIntent memory intent,
        PaymentContext memory context,
        uint256 deadline
    ) internal {
        // VALIDATION: Ensure intent ID is unique and not already processed
        if (processedIntents[intentId]) revert IntentAlreadyProcessed();
        if (paymentContexts[intentId].user != address(0)) revert IntentAlreadyExists();
        // VALIDATION: Ensure deadline is reasonable (not in the past, not too far in future)
        if (deadline <= block.timestamp) revert DeadlineInPast();
        if (deadline > block.timestamp + 7 days) revert DeadlineTooFar(); // Max 7 days
        // VALIDATION: Ensure intent amounts are reasonable and consistent
        if (intent.recipientAmount == 0) revert ZeroAmount();
        if (intent.feeAmount > intent.recipientAmount) revert FeeExceedsAmount();
        // VALIDATION: Ensure recipient and refund destinations are valid
        if (intent.recipient == address(0)) revert InvalidRecipient();
        if (intent.refundDestination == address(0)) revert InvalidRefundDestination();
        // VALIDATION: Ensure context data is consistent with intent
        if (context.user != intent.refundDestination) revert ContextIntentMismatch();
        if (context.creatorAmount != intent.recipientAmount) revert AmountMismatch();
        // STORAGE: Store the validated context and deadline
        paymentContexts[intentId] = context;
        intentDeadlines[intentId] = deadline;
        // INITIALIZATION: Initialize signing-related state
        intentReadyForExecution[intentId] = false; // Will be set to true when signed
        // INITIALIZATION: Mark intent as created but not processed
        processedIntents[intentId] = false; // Will be set to true when payment completes
        // METRICS: Update counters for monitoring and analytics
        totalIntentsCreated++;
        // LOGGING: Emit event for off-chain monitoring and debugging
        emit IntentFinalized(
            intentId, context.user, context.creator, context.paymentType, intent.recipientAmount, deadline
        );
        // AUDIT: Record intent creation in our audit log
        _recordIntentCreation(intentId, context, deadline);
    }

    /**
     * @dev Records intent creation for audit purposes
     * @param intentId The intent identifier
     * @param context Payment context
     * @param deadline Intent deadline
     */
    function _recordIntentCreation(bytes16 intentId, PaymentContext memory context, uint256 deadline) private {
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
     * @dev Emits the payment intent created event
     */
    function _emitIntentCreatedEvent(
        bytes16 intentId,
        PlatformPaymentRequest memory request,
        PaymentAmounts memory amounts
    ) internal {
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
    }

    /**
     * @dev Handles successful payment processing
     */
    function _handleSuccessfulPayment(
        PaymentContext storage context,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid
    ) internal {
        // Grant access based on payment type
        if (context.paymentType == PaymentType.PayPerView) {
            _grantContentAccess(context.user, context.contentId, intentId, paymentToken, amountPaid);
        } else if (context.paymentType == PaymentType.Subscription) {
            _grantSubscriptionAccess(context.user, context.creator, intentId, paymentToken, amountPaid);
        }

        // Update creator earnings through registry
        _updateCreatorStats(context);

        // Update operator metrics
        totalOperatorFees += context.operatorFee;
        totalPaymentsProcessed++;
    }

    /**
     * @dev Updates creator stats safely
     */
    function _updateCreatorStats(PaymentContext storage context) internal {
        try creatorRegistry.updateCreatorStats(
            context.creator,
            context.creatorAmount,
            context.paymentType == PaymentType.PayPerView ? int256(1) : int256(0),
            context.paymentType == PaymentType.Subscription ? int256(1) : int256(0)
        ) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }
    }

    /**
     * @dev Processes refund request creation
     */
    function _processRefundRequest(bytes16 refundIntentId, PaymentContext storage context, string memory reason)
        internal
    {
        // Calculate refund amount (full payment including fees)
        uint256 refundAmount = context.creatorAmount + context.platformFee + context.operatorFee;

        // Create refund request
        refundRequests[refundIntentId] = RefundRequest({
            originalIntentId: context.intentId, // Reference to original
            user: msg.sender,
            amount: refundAmount,
            reason: reason,
            requestTime: block.timestamp,
            processed: false
        });

        // Add to pending refunds
        pendingRefunds[msg.sender] += refundAmount;

        emit RefundRequested(refundIntentId, msg.sender, refundAmount, reason);
    }

    /**
     * @dev Validates a payment request for correctness
     */
    function _validatePaymentRequest(PlatformPaymentRequest memory request) internal view {
        // Validate creator is registered
        if (!creatorRegistry.isRegisteredCreator(request.creator)) revert InvalidCreator();

        // Validate content exists for content purchases
        if (request.paymentType == PaymentType.PayPerView) {
            if (request.contentId == 0) revert InvalidPaymentRequest();

            ContentRegistry.Content memory content = contentRegistry.getContent(request.contentId);
            if (content.creator != request.creator || !content.isActive) revert InvalidContent();
        }

        // Validate deadline is in the future
        if (request.deadline <= block.timestamp) revert DeadlineExpired();

        // Validate payment token
        if (request.paymentToken == address(0) && request.paymentType != PaymentType.PayPerView) {
            revert InvalidPaymentRequest(); // ETH payments only for content purchases
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
        if (request.paymentType == PaymentType.PayPerView) {
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
     * @dev Gets expected payment amount using price oracle
     */
    function _getExpectedPaymentAmount(address paymentToken, uint256 usdcAmount, uint256 slippageBps)
        internal
        returns (uint256)
    {
        if (paymentToken == address(usdcToken)) {
            return usdcAmount;
        } else if (paymentToken == address(0)) {
            // ETH
            uint256 ethAmount = priceOracle.getETHPrice(usdcAmount);
            return priceOracle.applySlippage(ethAmount, slippageBps);
        } else {
            uint256 tokenAmount = priceOracle.getTokenAmountForUSDC(paymentToken, usdcAmount, 0);
            return priceOracle.applySlippage(tokenAmount, slippageBps);
        }
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
     * @dev COMPLETE: Prepares intent for backend signing (REAL implementation)
     */
    function _prepareIntentForSigning(ICommercePaymentsProtocol.TransferIntent memory intent)
        internal
        returns (bytes32 intentHash)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_INTENT_TYPEHASH,
                intent.recipientAmount,
                intent.deadline,
                intent.recipient,
                intent.recipientCurrency,
                intent.refundDestination,
                intent.feeAmount,
                intent.id,
                intent.operator
            )
        );

        intentHash = _hashTypedDataV4(structHash);
        intentHashes[intent.id] = intentHash;
        intentReadyForExecution[intent.id] = false;

        // Emit event for backend to pick up and sign
        emit IntentReadyForSigning(intent.id, intentHash, intent.deadline);

        return intentHash;
    }

    /**
     * @dev COMPLETE: Backend provides the actual signature (REAL implementation)
     */
    function provideIntentSignature(bytes16 intentId, bytes memory signature) external onlyRole(SIGNER_ROLE) {
        require(intentHashes[intentId] != bytes32(0), "Intent not found");
        require(!intentReadyForExecution[intentId], "Already signed");

        // Verify the signature is valid for this intent
        bytes32 intentHash = intentHashes[intentId];
        address recoveredSigner = _recoverSigner(intentHash, signature);
        require(authorizedSigners[recoveredSigner], "Invalid signer");

        // Store the real signature
        intentSignatures[intentId] = signature;
        intentReadyForExecution[intentId] = true;

        emit IntentSigned(intentId, signature);
    }

    /**
     * @dev COMPLETE: Get the real signature for an intent
     */
    function getIntentSignature(bytes16 intentId) external view returns (bytes memory) {
        require(intentReadyForExecution[intentId], "Intent not ready");
        return intentSignatures[intentId];
    }

    /**
     * @dev COMPLETE: Recover signer from signature (REAL implementation)
     */
    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature v");

        return ecrecover(hash, v, r, s);
    }

    /**
     * @dev Grants content access after successful payment
     */
    function _grantContentAccess(
        address user,
        uint256 contentId,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid
    ) internal returns (bool success) {
        PaymentContext memory context = paymentContexts[intentId];

        if (address(payPerView) != address(0)) {
            try payPerView.completePurchase(intentId, amountPaid, true, "") {
                emit ContentAccessGranted(user, contentId, intentId, paymentToken, amountPaid);
                return true;
            } catch {
                uint256 totalUsdcAmount = context.creatorAmount + context.platformFee;
                try payPerView.recordExternalPurchase(
                    contentId, user, intentId, totalUsdcAmount, paymentToken, amountPaid
                ) {
                    emit ContentAccessGranted(user, contentId, intentId, paymentToken, amountPaid);
                    return true;
                } catch Error(string memory reason) {
                    _handleFailedPayment(intentId, context, string.concat("Content access failed: ", reason));
                    return false;
                } catch (bytes memory lowLevelData) {
                    string memory reason = lowLevelData.length > 0 ? string(lowLevelData) : "Unknown error";
                    _handleFailedPayment(intentId, context, string.concat("Content access failed: ", reason));
                    return false;
                }
            }
        } else {
            _handleFailedPayment(intentId, context, "PayPerView not set");
            return false;
        }
    }

    /**
     * @dev Grants subscription access after successful payment
     */
    function _grantSubscriptionAccess(
        address user,
        address creator,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid
    ) internal returns (bool success) {
        PaymentContext memory context = paymentContexts[intentId];
        uint256 totalUsdcAmount = context.creatorAmount + context.platformFee;

        if (address(subscriptionManager) != address(0)) {
            try subscriptionManager.recordSubscriptionPayment(
                user, creator, intentId, totalUsdcAmount, paymentToken, amountPaid
            ) {
                emit SubscriptionAccessGranted(user, creator, intentId, paymentToken, amountPaid);
                return true;
            } catch Error(string memory reason) {
                _handleFailedPayment(intentId, context, string.concat("Subscription failed: ", reason));
                return false;
            } catch (bytes memory lowLevelData) {
                string memory reason = lowLevelData.length > 0 ? string(lowLevelData) : "Unknown error";
                _handleFailedPayment(intentId, context, string.concat("Subscription failed: ", reason));
                return false;
            }
        } else {
            _handleFailedPayment(intentId, context, "SubscriptionManager not set");
            return false;
        }
    }

    /**
     * @dev Handles failed payment and prepares for refund
     */
    function _handleFailedPayment(bytes16 intentId, PaymentContext memory context, string memory reason) internal {
        // Calculate refund amount
        uint256 refundAmount = context.creatorAmount + context.platformFee + context.operatorFee;

        // Use standardized refund intent ID
        bytes16 refundIntentId = IntentIdManager.generateRefundIntentId(intentId, context.user, reason, address(this));

        refundRequests[refundIntentId] = RefundRequest({
            originalIntentId: context.intentId, // Reference to original
            user: context.user,
            amount: refundAmount,
            reason: reason,
            requestTime: block.timestamp,
            processed: false
        });

        pendingRefunds[context.user] += refundAmount;

        emit RefundRequested(refundIntentId, context.user, refundAmount, reason);
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

    /**
     * @dev Emergency token recovery
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Returns true if a signature has been provided for the given intentId
     */
    function hasSignature(bytes16 intentId) public view returns (bool) {
        return intentReadyForExecution[intentId];
    }

    /**
     * @dev Returns true if the intent is still active (not processed)
     */
    function hasActiveIntent(bytes16 intentId) public view returns (bool) {
        return !processedIntents[intentId];
    }
}
