// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";
import { BaseCommerceIntegration } from "./BaseCommerceIntegration.sol";

/**
 * @title ViewManager
 * @dev Manages view-only functions for the Commerce Protocol Integration
 * @notice This contract handles simple utility functions to reduce main contract size
 */
contract ViewManager {
    // Reference to BaseCommerceIntegration for operator status checking
    BaseCommerceIntegration public immutable baseCommerceIntegration;

    /**
     * @dev Constructor initializes the ViewManager with BaseCommerceIntegration reference
     * @param _baseCommerceIntegration Address of the BaseCommerceIntegration contract
     */
    constructor(address _baseCommerceIntegration) {
        require(_baseCommerceIntegration != address(0), "Invalid BaseCommerceIntegration address");
        baseCommerceIntegration = BaseCommerceIntegration(_baseCommerceIntegration);
    }

    // ============ PERMIT FUNCTIONS ============

    /**
     * @dev Gets permit nonce for a user
     * @param permit2 The Permit2 contract
     * @param user The user address
     * @return nonce The current nonce for the user
     */
    function getPermitNonce(ISignatureTransfer permit2, address user) external view returns (uint256 nonce) {
        return permit2.nonce(user);
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures
     * @param permit2 The Permit2 contract
     * @return domainSeparator The domain separator hash
     */
    function getPermitDomainSeparator(ISignatureTransfer permit2) external view returns (bytes32 domainSeparator) {
        return permit2.DOMAIN_SEPARATOR();
    }

    // ============ METRICS FUNCTIONS ============

    /**
     * @dev Gets operator metrics
     * @param totalIntentsCreated Total intents created
     * @param totalPaymentsProcessed Total payments processed
     * @param totalOperatorFees Total operator fees collected
     * @param totalRefundsProcessed Total refunds processed
     */
    function getOperatorMetrics(
        uint256 totalIntentsCreated,
        uint256 totalPaymentsProcessed,
        uint256 totalOperatorFees,
        uint256 totalRefundsProcessed
    ) external pure returns (
        uint256 intentsCreated,
        uint256 paymentsProcessed,
        uint256 operatorFees,
        uint256 refunds
    ) {
        return (totalIntentsCreated, totalPaymentsProcessed, totalOperatorFees, totalRefundsProcessed);
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @dev Validates payment type enum value
     * @param paymentType The payment type to validate
     * @return isValid Whether the payment type is valid
     */
    function validatePaymentType(ISharedTypes.PaymentType paymentType) external pure returns (bool isValid) {
        return uint8(paymentType) <= uint8(ISharedTypes.PaymentType.Donation);
    }

    /**
     * @dev Gets payment type name for logging
     * @param paymentType The payment type
     * @return name Human-readable name
     */
    function getPaymentTypeName(ISharedTypes.PaymentType paymentType) external pure returns (string memory name) {
        if (paymentType == ISharedTypes.PaymentType.PayPerView) return "PayPerView";
        if (paymentType == ISharedTypes.PaymentType.Subscription) return "Subscription";
        if (paymentType == ISharedTypes.PaymentType.Tip) return "Tip";
        if (paymentType == ISharedTypes.PaymentType.Donation) return "Donation";
        return "Unknown";
    }

    /**
     * @dev Gets operator status by checking BaseCommerceIntegration configuration
     * @notice Operator is considered registered if BaseCommerceIntegration has valid configuration
     */
    function getOperatorStatus() external view returns (bool registered, address feeDestination) {
        // Check if BaseCommerceIntegration has a valid fee destination configured
        address configuredFeeDestination = baseCommerceIntegration.operatorFeeDestination();
        registered = configuredFeeDestination != address(0);
        feeDestination = configuredFeeDestination;
    }
}
