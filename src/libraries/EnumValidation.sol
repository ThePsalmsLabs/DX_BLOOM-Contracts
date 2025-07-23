// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedTypes } from "../interfaces/ISharedTypes.sol";

library EnumValidation {
    /**
     * @dev Validates PaymentType enum value
     * @param value The uint8 value to validate
     * @return isValid True if the value is a valid PaymentType
     * @notice This prevents enum conversion panics by checking ranges properly
     */
    function isValidPaymentType(uint8 value) internal pure returns (bool isValid) {
        return value <= uint8(ISharedTypes.PaymentType.Donation); // 0-3 are valid
    }

    /**
     * @dev Validates ContentCategory enum value
     * @param value The uint8 value to validate
     * @return isValid True if the value is a valid ContentCategory
     */
    function isValidContentCategory(uint8 value) internal pure returns (bool isValid) {
        return value <= uint8(ISharedTypes.ContentCategory.Podcast); // 0-4 are valid
    }

    /**
     * @dev Validates SubscriptionStatus enum value
     * @param value The uint8 value to validate
     * @return isValid True if the value is a valid SubscriptionStatus
     */
    function isValidSubscriptionStatus(uint8 value) internal pure returns (bool isValid) {
        return value <= uint8(ISharedTypes.SubscriptionStatus.Cancelled); // 0-3 are valid
    }

    /**
     * @dev Safe casting from uint8 to PaymentType with validation
     * @param value The uint8 value to cast
     * @return paymentType The safely cast PaymentType
     * @notice Reverts with descriptive error if value is invalid
     */
    function toPaymentType(uint8 value) internal pure returns (ISharedTypes.PaymentType paymentType) {
        if (!isValidPaymentType(value)) {
            revert InvalidPaymentType();
        }
        return ISharedTypes.PaymentType(value);
    }

    /**
     * @dev Safe casting from uint8 to ContentCategory with validation
     * @param value The uint8 value to cast
     * @return category The safely cast ContentCategory
     */
    function toContentCategory(uint8 value) internal pure returns (ISharedTypes.ContentCategory category) {
        if (!isValidContentCategory(value)) {
            revert InvalidContentCategory();
        }
        return ISharedTypes.ContentCategory(value);
    }

    // Custom errors for better debugging
    error InvalidPaymentType();
    error InvalidContentCategory();
    error InvalidSubscriptionStatus();
}
