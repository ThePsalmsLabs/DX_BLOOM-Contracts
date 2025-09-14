// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedTypes } from "../interfaces/ISharedTypes.sol";
import { ICommercePaymentsProtocol } from "../interfaces/IPlatformInterfaces.sol";

/**
 * @title PaymentValidatorLib
 * @dev Library for payment validation logic
 * @notice This library provides stateless validation functions to reduce
 *         contract size while maintaining validation integrity
 */
library PaymentValidatorLib {

    // ============ ENUMS ============

    /**
     * @dev Payment types (mirrored from ISharedTypes)
     */
    enum PaymentType {
        PayPerView, // 0
        Subscription, // 1
        Tip, // 2
        Donation // 3
    }

    // ============ STRUCTS ============

    /**
     * @dev Platform payment request structure (mirrored from ISharedTypes)
     */
    struct PlatformPaymentRequest {
        PaymentType paymentType; // Type of payment
        address creator; // Creator to pay
        uint256 contentId; // Content ID (0 for subscriptions)
        address paymentToken; // Token user wants to pay with
        uint256 maxSlippage; // Maximum slippage for token swaps (basis points)
        uint256 deadline; // Payment deadline
    }

    /**
     * @dev Validation context for payment requests
     */
    struct PaymentValidationContext {
        address user;
        address creator;
        uint256 contentId;
        address paymentToken;
        uint256 deadline;
        PaymentType paymentType;
    }

    /**
     * @dev Creator validation data
     */
    struct CreatorValidationData {
        bool isRegistered;
        bool isActive;
        uint256 subscriptionPrice;
    }

    /**
     * @dev Content validation data
     */
    struct ContentValidationData {
        address creator;
        bool isActive;
        uint256 payPerViewPrice;
    }

    // ============ PAYMENT REQUEST VALIDATION ============

    /**
     * @dev Validates a payment request comprehensively
     * @param request The payment request to validate
     * @param creatorData Creator validation data
     * @param contentData Content validation data (if applicable)
     * @return isValid Whether the request is valid
     * @return errorCode Error code if invalid (0 = valid)
     */
    function validatePaymentRequest(
        PlatformPaymentRequest memory request,
        CreatorValidationData memory creatorData,
        ContentValidationData memory contentData
    ) internal view returns (bool isValid, uint8 errorCode) {
        // Validate payment type
        if (uint8(request.paymentType) > uint8(PaymentType.Donation)) {
            return (false, 1); // InvalidPaymentType
        }

        // Validate creator
        if (!creatorData.isRegistered || !creatorData.isActive) {
            return (false, 2); // InvalidCreator
        }

        // Validate deadline
        if (request.deadline <= block.timestamp) {
            return (false, 3); // DeadlineExpired
        }

        // Validate content for PayPerView payments
        if (request.paymentType == PaymentType.PayPerView) {
            if (request.contentId == 0) {
                return (false, 4); // InvalidPaymentRequest
            }

            if (contentData.creator != request.creator || !contentData.isActive) {
                return (false, 5); // InvalidContent
            }
        }

        // Validate payment token for non-PayPerView payments
        if (uint8(request.paymentType) != uint8(PaymentType.PayPerView) && request.paymentToken == address(0)) {
            return (false, 4); // InvalidPaymentRequest
        }

        return (true, 0);
    }

    /**
     * @dev Validates intent execution context
     * @param intentId The intent ID
     * @param user The calling user
     * @param contextUser The intent creator
     * @param deadline The intent deadline
     * @param hasSignature Whether operator signature exists
     * @param isProcessed Whether already processed
     * @return isValid Whether the execution context is valid
     * @return errorCode Error code if invalid
     */
    function validateExecutionContext(
        bytes16 intentId,
        address user,
        address contextUser,
        uint256 deadline,
        bool hasSignature,
        bool isProcessed
    ) internal view returns (bool isValid, uint8 errorCode) {
        // Validate intent exists
        if (contextUser == address(0)) {
            return (false, 6); // IntentNotFound
        }

        // Validate caller is intent creator
        if (user != contextUser) {
            return (false, 7); // NotIntentCreator
        }

        // Validate not already processed
        if (isProcessed) {
            return (false, 8); // IntentAlreadyProcessed
        }

        // Validate deadline
        if (block.timestamp > deadline) {
            return (false, 3); // IntentExpired
        }

        // Validate operator signature exists
        if (!hasSignature) {
            return (false, 9); // NoOperatorSignature
        }

        return (true, 0);
    }

    // ============ AMOUNT VALIDATION ============

    /**
     * @dev Validates payment amounts and calculations
     * @param totalAmount Total payment amount
     * @param creatorAmount Amount going to creator
     * @param platformFee Platform fee amount
     * @param operatorFee Operator fee amount
     * @return isValid Whether amounts are valid
     * @return errorCode Error code if invalid
     */
    function validatePaymentAmounts(
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee
    ) internal pure returns (bool isValid, uint8 errorCode) {
        // Validate amounts are reasonable
        if (totalAmount == 0) {
            return (false, 10); // ZeroAmount
        }

        if (creatorAmount == 0) {
            return (false, 11); // ZeroCreatorAmount
        }

        // Validate fee doesn't exceed creator amount
        if (platformFee + operatorFee >= creatorAmount) {
            return (false, 12); // FeeExceedsAmount
        }

        // Validate total calculation
        if (creatorAmount + platformFee != totalAmount - operatorFee) {
            return (false, 13); // AmountMismatch
        }

        return (true, 0);
    }

    // ============ PERMIT VALIDATION HELPERS ============

    /**
     * @dev Validates permit expiration
     * @param deadline The permit deadline
     * @return isValid Whether deadline is valid
     */
    function validatePermitDeadline(uint256 deadline) internal view returns (bool isValid) {
        return deadline >= block.timestamp;
    }

    /**
     * @dev Validates permit nonce
     * @param expectedNonce The expected nonce
     * @param actualNonce The actual nonce
     * @return isValid Whether nonce is valid
     */
    function validatePermitNonce(uint256 expectedNonce, uint256 actualNonce) internal pure returns (bool isValid) {
        return expectedNonce == actualNonce;
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @dev Gets error message for error code
     * @param errorCode The error code
     * @return message Human-readable error message
     */
    function getErrorMessage(uint8 errorCode) internal pure returns (string memory message) {
        if (errorCode == 0) return "";
        if (errorCode == 1) return "Invalid payment type";
        if (errorCode == 2) return "Invalid creator";
        if (errorCode == 3) return "Deadline expired";
        if (errorCode == 4) return "Invalid payment request";
        if (errorCode == 5) return "Invalid content";
        if (errorCode == 6) return "Intent not found";
        if (errorCode == 7) return "Not intent creator";
        if (errorCode == 8) return "Intent already processed";
        if (errorCode == 9) return "No operator signature";
        if (errorCode == 10) return "Zero amount";
        if (errorCode == 11) return "Zero creator amount";
        if (errorCode == 12) return "Fee exceeds amount";
        if (errorCode == 13) return "Amount mismatch";

        return "Unknown error";
    }

    // ============ CONSTANTS ============

    /// @notice Error codes for validation failures
    uint8 internal constant ERROR_NONE = 0;
    uint8 internal constant ERROR_INVALID_PAYMENT_TYPE = 1;
    uint8 internal constant ERROR_INVALID_CREATOR = 2;
    uint8 internal constant ERROR_DEADLINE_EXPIRED = 3;
    uint8 internal constant ERROR_INVALID_PAYMENT_REQUEST = 4;
    uint8 internal constant ERROR_INVALID_CONTENT = 5;
    uint8 internal constant ERROR_INTENT_NOT_FOUND = 6;
    uint8 internal constant ERROR_NOT_INTENT_CREATOR = 7;
    uint8 internal constant ERROR_INTENT_PROCESSED = 8;
    uint8 internal constant ERROR_NO_OPERATOR_SIGNATURE = 9;
    uint8 internal constant ERROR_ZERO_AMOUNT = 10;
    uint8 internal constant ERROR_ZERO_CREATOR_AMOUNT = 11;
    uint8 internal constant ERROR_FEE_EXCEEDS_AMOUNT = 12;
    uint8 internal constant ERROR_AMOUNT_MISMATCH = 13;

    /**
     * @dev Simple payment type enum validation
     * @param paymentType The payment type to validate
     * @return isValid Whether the payment type is within valid range
     */
    function validatePaymentTypeSimple(PaymentType paymentType) internal pure returns (bool isValid) {
        return uint8(paymentType) <= uint8(PaymentType.Donation);
    }
}
