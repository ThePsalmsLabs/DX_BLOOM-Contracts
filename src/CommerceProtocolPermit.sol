// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CommerceProtocolBase } from "./CommerceProtocolBase.sol";
import { BaseCommerceIntegration } from "./BaseCommerceIntegration.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";
import { ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { AccessManager } from "./AccessManager.sol";
import { RefundManager } from "./RefundManager.sol";
import { PermitPaymentManager } from "./PermitPaymentManager.sol";

/**
 * @title CommerceProtocolPermit
 * @dev Permit-based Commerce Protocol integration contract handling gasless payments
 * @notice This contract handles permit-based payments, validation, and advanced permit functionality
 */
contract CommerceProtocolPermit is CommerceProtocolBase {

    // ============ PERMIT-SPECIFIC EVENTS ============
    
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

    // ============ CONSTRUCTOR ============
    
    /**
     * @dev Constructor initializes the permit contract with shared base functionality
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
        // Manager contract addresses
        address _adminManager,
        address _viewManager,
        address _accessManager,
        address _signatureManager,
        address _refundManager,
        address _permitPaymentManager,
        address _rewardsIntegration
    ) CommerceProtocolBase(
        _baseCommerceIntegration,
        _permit2,
        _creatorRegistry,
        _contentRegistry,
        _priceOracle,
        _usdcToken,
        _operatorFeeDestination,
        _operatorSigner,
        _adminManager,
        _viewManager,
        _accessManager,
        _signatureManager,
        _refundManager,
        _permitPaymentManager,
        _rewardsIntegration
    ) {}

    // ============ PERMIT PAYMENT FUNCTIONS ============
    
    /**
     * @dev Executes payment with permit (delegates to PermitPaymentManager)
     */
    function executePaymentWithPermit(
        bytes16 intentId,
        PermitPaymentManager.Permit2Data calldata permitData
    ) external nonReentrant whenNotPaused returns (bool success) {
        ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
        require(context.user == msg.sender, "Not intent creator");
        require(!processedIntents[intentId], "Intent already processed");
        require(block.timestamp <= intentDeadlines[intentId], "Intent expired");

        // Enhanced validation before permit execution
        if (context.paymentToken != address(usdcToken)) {
            // Validate quote freshness before executing
            (bool isValid, uint256 currentQuote) = priceOracle.validateQuoteBeforeSwap(
                context.paymentToken,
                address(usdcToken),
                context.expectedAmount,
                context.expectedAmount, // Expected from original quote
                500, // 5% tolerance
                priceOracle.getOptimalPoolFeeForSwap(context.paymentToken, address(usdcToken))
            );
            
            require(isValid, "Quote validation failed - price moved beyond tolerance");
            
            // Check price impact for large trades
            (uint256 priceImpactBps, bool impactAcceptable) = priceOracle.checkPriceImpact(
                context.paymentToken,
                address(usdcToken), 
                context.expectedAmount,
                1000 // Max 10% price impact
            );
            
            require(impactAcceptable, "Price impact too high");
        }

        success = permitPaymentManager.executePaymentWithPermit(
            intentId,
            msg.sender,
            context.paymentToken,
            context.expectedAmount,
            context.creator,
            context.paymentType,
            permitData
        );

        if (success) {
            // Mark intent as processed
            _markIntentAsProcessed(intentId);

            // Handle successful payment through AccessManager
            accessManager.handleSuccessfulPayment(
                _convertToAccessManagerContext(context),
                intentId,
                context.paymentToken,
                context.expectedAmount,
                context.operatorFee
            );

            // Distribute funds to rewards treasury and trigger loyalty points
            _distributeFunds(context, intentId, context.paymentToken, context.expectedAmount, context.operatorFee);

            emit PaymentExecutedWithPermit(
                intentId,
                msg.sender,
                context.creator,
                context.paymentType,
                context.expectedAmount,
                context.paymentToken,
                true
            );
        } else {
            // Handle failed payment
            refundManager.handleFailedPayment(
                intentId,
                context.user,
                context.creatorAmount,
                context.platformFee,
                context.operatorFee,
                "Permit payment execution failed"
            );

            emit PaymentExecutedWithPermit(
                intentId,
                msg.sender,
                context.creator,
                context.paymentType,
                0,
                context.paymentToken,
                false
            );
        }

        return success;
    }

    /**
     * @dev Creates and executes payment with permit in one transaction
     */
    function createAndExecuteWithPermit(
        PlatformPaymentRequest memory request,
        PermitPaymentManager.Permit2Data calldata permitData
    ) external nonReentrant whenNotPaused returns (bytes16 intentId, bool success) {
        // Validate payment request
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        intentId = _generateStandardIntentId(msg.sender, request);
        
        // Create payment context
        ISharedTypes.PaymentContext memory context = ISharedTypes.PaymentContext({
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

        // Store the payment context
        paymentContexts[intentId] = context;
        intentDeadlines[intentId] = request.deadline;
        totalIntentsCreated++;

        // Emit intent created event
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

        emit PermitPaymentCreated(
            intentId,
            msg.sender,
            request.creator,
            request.paymentType,
            amounts.expectedAmount,
            request.paymentToken,
            userNonces[msg.sender]
        );

        // Execute with permit
        success = permitPaymentManager.executePaymentWithPermit(
            intentId,
            msg.sender,
            request.paymentToken,
            amounts.expectedAmount,
            request.creator,
            request.paymentType,
            permitData
        );

        if (success) {
            // Mark intent as processed
            _markIntentAsProcessed(intentId);

            // Handle successful payment
            accessManager.handleSuccessfulPayment(
                _convertToAccessManagerContext(context),
                intentId,
                request.paymentToken,
                amounts.expectedAmount,
                amounts.operatorFee
            );

            emit PaymentExecutedWithPermit(
                intentId,
                msg.sender,
                request.creator,
                request.paymentType,
                amounts.expectedAmount,
                request.paymentToken,
                true
            );
        } else {
            // Handle failed payment
            refundManager.handleFailedPayment(
                intentId,
                msg.sender,
                amounts.adjustedCreatorAmount,
                amounts.platformFee,
                amounts.operatorFee,
                "Permit payment creation and execution failed"
            );

            emit PaymentExecutedWithPermit(
                intentId,
                msg.sender,
                request.creator,
                request.paymentType,
                0,
                request.paymentToken,
                false
            );
        }

        return (intentId, success);
    }

    // ============ PERMIT VALIDATION FUNCTIONS (DELEGATED) ============

    /**
     * @dev Checks if payment can be executed with permit (delegates to PermitPaymentManager)
     */
    function canExecuteWithPermit(
        bytes16 intentId,
        PermitPaymentManager.Permit2Data calldata permitData
    ) external view returns (bool canExecute, string memory reason) {
        ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
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

    /**
     * @dev Validates permit signature data (delegated to PermitPaymentManager)
     */
    function validatePermitData(
        PermitPaymentManager.Permit2Data calldata permitData,
        address user
    ) external view returns (bool isValid) {
        return permitPaymentManager.validatePermitData(permitData, user);
    }

    /**
     * @dev Validates that permit data matches the payment context (delegated to PermitPaymentManager)
     */
    function validatePermitContext(
        PermitPaymentManager.Permit2Data calldata permitData,
        ISharedTypes.PaymentContext memory context
    ) external view returns (bool isValid) {
        return permitPaymentManager.validatePermitContext(
            permitData, 
            context.paymentToken, 
            context.expectedAmount, 
            address(baseCommerceIntegration)
        );
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures (delegated to PermitPaymentManager)
     */
    function getPermitDomainSeparator() external view returns (bytes32 domainSeparator) {
        return permitPaymentManager.getPermitDomainSeparator();
    }

    // ============ PERMIT CREATION HELPERS ============

    /**
     * @dev Creates a permit payment intent for gasless transactions
     */
    function createPermitIntent(PlatformPaymentRequest memory request)
        external
        nonReentrant
        whenNotPaused
        returns (bytes16 intentId, ISharedTypes.PaymentContext memory context)
    {
        // Validate payment request
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        intentId = _generateStandardIntentId(msg.sender, request);

        // Create payment context
        context = ISharedTypes.PaymentContext({
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

        // Store the payment context
        paymentContexts[intentId] = context;
        intentDeadlines[intentId] = request.deadline;
        totalIntentsCreated++;

        // Emit events
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

        emit PermitPaymentCreated(
            intentId,
            msg.sender,
            request.creator,
            request.paymentType,
            amounts.expectedAmount,
            request.paymentToken,
            userNonces[msg.sender]
        );

        return (intentId, context);
    }

    // ============ BATCH PERMIT OPERATIONS ============

    /**
     * @dev Executes multiple permit payments in a single transaction
     */
    function batchExecuteWithPermit(
        bytes16[] calldata intentIds,
        PermitPaymentManager.Permit2Data[] calldata permitDataArray
    ) external nonReentrant whenNotPaused returns (bool[] memory results) {
        require(intentIds.length == permitDataArray.length, "Array length mismatch");
        require(intentIds.length > 0, "Empty arrays");
        require(intentIds.length <= 10, "Too many operations"); // Limit batch size

        results = new bool[](intentIds.length);

        for (uint256 i = 0; i < intentIds.length; i++) {
            bytes16 intentId = intentIds[i];
            ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
            
            // Basic validation for each intent
            if (context.user == msg.sender && 
                !processedIntents[intentId] && 
                block.timestamp <= intentDeadlines[intentId]) {
                
                results[i] = permitPaymentManager.executePaymentWithPermit(
                    intentId,
                    msg.sender,
                    context.paymentToken,
                    context.expectedAmount,
                    context.creator,
                    context.paymentType,
                    permitDataArray[i]
                );

                if (results[i]) {
                    _markIntentAsProcessed(intentId);
                    
                    accessManager.handleSuccessfulPayment(
                        _convertToAccessManagerContext(context),
                        intentId,
                        context.paymentToken,
                        context.expectedAmount,
                        context.operatorFee
                    );

                    emit PaymentExecutedWithPermit(
                        intentId,
                        msg.sender,
                        context.creator,
                        context.paymentType,
                        context.expectedAmount,
                        context.paymentToken,
                        true
                    );
                } else {
                    emit PaymentExecutedWithPermit(
                        intentId,
                        msg.sender,
                        context.creator,
                        context.paymentType,
                        0,
                        context.paymentToken,
                        false
                    );
                }
            } else {
                results[i] = false;
                emit PaymentExecutedWithPermit(
                    intentId,
                    msg.sender,
                    address(0),
                    PaymentType.PayPerView,
                    0,
                    address(0),
                    false
                );
            }
        }

        return results;
    }

    // ============ PERMIT QUERY FUNCTIONS ============

    /**
     * @dev Gets permit payment status for an intent
     */
    function getPermitPaymentStatus(bytes16 intentId) 
        external 
        view 
        returns (
            bool exists,
            bool processed,
            bool expired,
            bool hasSignature,
            uint256 deadline,
            address paymentToken,
            uint256 expectedAmount
        ) 
    {
        ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
        exists = context.user != address(0);
        
        if (exists) {
            processed = processedIntents[intentId];
            deadline = intentDeadlines[intentId];
            expired = block.timestamp > deadline;
            hasSignature = signatureManager.hasSignature(intentId);
            paymentToken = context.paymentToken;
            expectedAmount = context.expectedAmount;
        }
    }

    /**
     * @dev Gets permit requirements for a payment request
     */
    function getPermitRequirements(PlatformPaymentRequest memory request)
        external
        returns (
            address token,
            uint256 amount,
            address spender,
            uint256 deadline,
            bytes32 domainSeparator
        )
    {
        _validatePaymentRequest(request);
        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);

        token = request.paymentToken;
        amount = amounts.expectedAmount;
        spender = address(baseCommerceIntegration);
        deadline = request.deadline;
        domainSeparator = permitPaymentManager.getPermitDomainSeparator();
    }

    // ============ INTERNAL HELPER FUNCTIONS ============

    /**
     * @dev Converts ISharedTypes.PaymentContext to AccessManager format
     */
    function _convertToAccessManagerContext(ISharedTypes.PaymentContext memory context) 
        internal 
        pure 
        returns (AccessManager.PaymentContext memory) 
    {
        return AccessManager.PaymentContext({
            paymentType: context.paymentType,
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
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @dev Emergency pause for permit operations only
     */
    function pausePermitOperations() external onlyOwner {
        permitPaymentManager.pause();
    }

    /**
     * @dev Resume permit operations
     */
    function unpausePermitOperations() external onlyOwner {
        permitPaymentManager.unpause();
    }

    // ============ ABSTRACT FUNCTION IMPLEMENTATIONS ============

    /**
     * @dev Returns the contract type
     */
    function getContractType() external pure override returns (string memory) {
        return "CommerceProtocolPermit";
    }

    /**
     * @dev Returns the contract version
     */
    function getContractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }
}
