// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CommerceProtocolBase } from "./CommerceProtocolBase.sol";
import { BaseCommerceIntegration } from "./BaseCommerceIntegration.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";
import { AccessManager } from "./AccessManager.sol";
import { RefundManager } from "./RefundManager.sol";

/**
 * @title CommerceProtocolCore
 * @dev Core Commerce Protocol integration contract handling standard payment flows
 * @notice This contract handles intent creation, signature-based payments, and admin functions
 */
contract CommerceProtocolCore is CommerceProtocolBase {

    // ============ CONSTRUCTOR ============
    
    /**
     * @dev Constructor initializes the core contract with shared base functionality
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

    // ============ CORE PAYMENT FUNCTIONS ============
    
    /**
     * @dev Creates payment intent with signature preparation
     */
    function createPaymentIntent(PlatformPaymentRequest memory request)
        external
        nonReentrant
        whenNotPaused
        returns (bytes16 intentId, ISharedTypes.PaymentContext memory context)
    {
        // Validate payment request (includes payment type validation)
        _validatePaymentRequest(request);

        PaymentAmounts memory amounts = _calculateAllPaymentAmounts(request);
        // Use standardized intent ID
        intentId = _generateStandardIntentId(msg.sender, request);

        // Create payment context (simplified for new flow)
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

        return (intentId, context);
    }

    /**
     * @dev Execute payment with signature - calls Base Commerce Protocol
     */
    function executePaymentWithSignature(bytes16 intentId)
        external
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        require(signatureManager.hasSignature(intentId), "No signature provided");
        ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
        require(context.user == msg.sender, "Not intent creator");
        require(block.timestamp <= intentDeadlines[intentId], "Intent expired");
        require(!processedIntents[intentId], "Intent already processed");


        // Execute the payment through Base Commerce Protocol with enhanced validation
        if (context.paymentToken == address(usdcToken) || context.paymentToken == address(0)) {
            // Validate quote freshness before executing swap (for non-USDC payments)
            if (context.paymentToken != address(usdcToken)) {
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
            
            // Use new BaseCommerceIntegration escrow flow
            try baseCommerceIntegration.executeEscrowPayment(
                BaseCommerceIntegration.EscrowPaymentParams({
                    payer: context.user,
                    receiver: context.creator,
                    amount: context.expectedAmount,
                    paymentType: context.paymentType,
                    permit2Data: "", // Empty for signature-based payments (non-permit)
                    instantCapture: true // Authorize + capture in one transaction
                })
            ) returns (bytes32 paymentHash) {
                // Mark as processed and handle success
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

                // Log successful payment
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

                return true;
            } catch Error(string memory reason) {
                refundManager.handleFailedPayment(
                    intentId,
                    context.user,
                    context.creator,
                    context.creatorAmount,
                    context.platformFee,
                    context.operatorFee,
                    context.paymentType,
                    reason
                );
                
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
                refundManager.handleFailedPayment(
                    intentId,
                    context.user,
                    context.creator,
                    context.creatorAmount,
                    context.platformFee,
                    context.operatorFee,
                    context.paymentType,
                    reason
                );
                
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
            // For other tokens, require permit data
            revert("Non-USDC payments require permit data. Use CommerceProtocolPermit contract instead.");
        }
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

        // Check if intent has expired
        if (block.timestamp > intentDeadlines[intentId]) revert IntentExpired();

        // Mark as processed
        _markIntentAsProcessed(intentId);

        if (success) {
            accessManager.handleSuccessfulPayment(
                _convertToAccessManagerContext(context),
                intentId,
                paymentToken,
                amountPaid,
                context.operatorFee
            );
        } else {
            refundManager.handleFailedPayment(
                intentId,
                context.user,
                context.creator,
                context.creatorAmount,
                context.platformFee,
                context.operatorFee,
                context.paymentType,
                failureReason
            );
        }

        emit PaymentCompleted(
            intentId, user, context.creator, context.paymentType, context.contentId, paymentToken, amountPaid, success
        );
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
        operatorFeeRate = newRate;
        emit OperatorFeeUpdated(operatorFeeRate, newRate);
    }

    /**
     * @dev Updates operator fee destination (delegated to AdminManager)
     */
    function updateOperatorFeeDestination(address newDestination) external onlyOwner {
        adminManager.updateOperatorFeeDestination(newDestination);
        address oldDestination = operatorFeeDestination;
        operatorFeeDestination = newDestination;
        emit OperatorFeeDestinationUpdated(oldDestination, newDestination);
    }

    /**
     * @dev Updates the operator signer address (delegated to AdminManager)
     */
    function updateOperatorSigner(address newSigner) external onlyOwner {
        adminManager.updateOperatorSigner(newSigner);
        address oldSigner = operatorSigner;
        operatorSigner = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    /**
     * @dev Grants payment monitor role (delegated to AdminManager)
     */
    function grantPaymentMonitorRole(address monitor) external onlyOwner {
        adminManager.grantPaymentMonitorRole(monitor);
        _grantRole(PAYMENT_MONITOR_ROLE, monitor);
    }

    /**
     * @dev Withdraws operator fees (delegated to AdminManager)
     */
    function withdrawOperatorFees(address token, uint256 amount) external onlyOwner {
        adminManager.withdrawOperatorFees(token, amount);
    }

    // ============ EMERGENCY CONTROLS (DELEGATED TO ADMIN MANAGER) ============

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        adminManager.pause();
        _pause();
    }

    /**
     * @dev Resume operations after pause
     */
    function unpause() external onlyOwner {
        adminManager.unpause();
        _unpause();
    }

    /**
     * @dev Emergency token recovery
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        adminManager.emergencyTokenRecovery(token, amount);
    }

    // ============ SIGNATURE MANAGEMENT FUNCTIONS (DELEGATED) ============

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
     * @dev Gets intent hash for an intent (delegates to SignatureManager)
     */
    function intentHashes(bytes16 intentId) external view returns (bytes32) {
        return signatureManager.intentHashes(intentId);
    }

    // ============ REFUND MANAGEMENT FUNCTIONS (DELEGATED) ============

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
        ISharedTypes.PaymentContext memory context = paymentContexts[intentId];
        refundManager.processRefundWithCoordination(intentId, context.paymentType, context.contentId, context.creator);
    }

    // ============ UTILITY FUNCTIONS ============

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

    // ============ INTERNAL HELPER FUNCTIONS ============

    /**
     * @dev Converts PaymentContext to AccessManager format
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

    // ============ ABSTRACT FUNCTION IMPLEMENTATIONS ============

    /**
     * @dev Returns the contract type
     */
    function getContractType() external pure override returns (string memory) {
        return "CommerceProtocolCore";
    }

    /**
     * @dev Returns the contract version
     */
    function getContractVersion() external pure override returns (string memory) {
        return "2.0.0";
    }
}