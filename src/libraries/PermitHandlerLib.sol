// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ICommercePaymentsProtocol, ISignatureTransfer } from "../interfaces/IPlatformInterfaces.sol";
import { ISharedTypes } from "../interfaces/ISharedTypes.sol";

/**
 * @title PermitHandlerLib
 * @dev Library for handling Uniswap Permit2 operations and validations
 * @notice This library provides stateless functions for permit-related operations
 *         to help reduce contract size while maintaining functionality
 */
library PermitHandlerLib {

    // ============ STRUCTS ============

    /**
     * @dev Context data needed for permit operations
     */
    struct PermitContext {
        ISignatureTransfer permit2;
        ICommercePaymentsProtocol commerceProtocol;
        address contractAddress;
    }

    /**
     * @dev Intent execution data
     */
    struct IntentExecutionData {
        bytes16 intentId;
        ICommercePaymentsProtocol.TransferIntent intent;
        ICommercePaymentsProtocol.Permit2SignatureTransferData permitData;
        bytes operatorSignature;
    }

    // ============ PERMIT VALIDATION FUNCTIONS ============

    /**
     * @dev Validates permit signature data before execution
     * @param permit2 The Permit2 contract
     * @param permitData The permit data to validate
     * @param user The user who should have signed the permit
     * @return isValid Whether the permit data is valid
     */
    function validatePermitData(
        ISignatureTransfer permit2,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        address user
    ) internal view returns (bool isValid) {
        // Basic validation checks
        if (permitData.permit.deadline < block.timestamp) return false;
        if (permitData.permit.nonce != permit2.nonce(user)) return false;

        return true;
    }

    /**
     * @dev Validates that permit data matches the payment context
     * @param permitData The permit data
     * @param paymentToken The expected payment token
     * @param expectedAmount The expected payment amount
     * @param commerceProtocol The commerce protocol contract
     * @return isValid Whether permit data matches context
     */
    function validatePermitContext(
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        address paymentToken,
        uint256 expectedAmount,
        address commerceProtocol
    ) internal pure returns (bool isValid) {
        // Check that token matches
        if (permitData.permit.permitted.token != paymentToken) return false;

        // Check that amount is sufficient
        if (permitData.permit.permitted.amount < expectedAmount) return false;

        // Check that transfer destination is correct
        if (permitData.transferDetails.to != commerceProtocol) return false;

        // Check that requested amount matches expected
        if (permitData.transferDetails.requestedAmount != expectedAmount) return false;

        return true;
    }

    /**
     * @dev Validates if a payment intent can be executed with permit
     * @param permit2 The Permit2 contract
     * @param commerceProtocol The commerce protocol contract
     * @param permitData The permit data to validate
     * @param contextData Context data for validation
     * @return canExecute Whether the payment can be executed
     * @return reason If cannot execute, the reason why
     */
    function canExecuteWithPermit(
        ISignatureTransfer permit2,
        ICommercePaymentsProtocol commerceProtocol,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        PermitValidationContext memory contextData
    ) internal view returns (bool canExecute, string memory reason) {
        // Check permit data validity
        if (!validatePermitData(permit2, permitData, contextData.user)) {
            return (false, "Invalid permit data");
        }

        // Check permit context validity
        if (!validatePermitContext(permitData, contextData.paymentToken, contextData.expectedAmount, address(commerceProtocol))) {
            return (false, "Permit data doesn't match payment context");
        }

        return (true, "");
    }

    // ============ PERMIT EXECUTION HELPERS ============

    /**
     * @dev Executes a permit-based payment through the commerce protocol
     * @param context Permit context
     * @param executionData Intent execution data
     * @return success Whether the payment was successful
     */
    function executePermitPayment(
        PermitContext memory context,
        IntentExecutionData memory executionData
    ) internal returns (bool success) {
        // Execute the payment through Base Commerce Protocol with Permit2
        try context.commerceProtocol.transferToken(executionData.intent, executionData.permitData) {
            return true;
        } catch Error(string memory reason) {
            // Log the failure reason (would emit event in main contract)
            revert(reason);
        } catch (bytes memory lowLevelData) {
            string memory reason = lowLevelData.length > 0 ? string(lowLevelData) : "Unknown error";
            revert(reason);
        }
    }

    /**
     * @dev Simple permit payment execution - just the core transfer
     * @param commerceProtocol The commerce protocol contract
     * @param intent The transfer intent
     * @param permitData The permit data
     * @return success Whether the payment was successful
     */
    function executePermitTransfer(
        ICommercePaymentsProtocol commerceProtocol,
        ICommercePaymentsProtocol.TransferIntent memory intent,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) internal returns (bool success) {
        try commerceProtocol.transferToken(intent, permitData) {
            return true;
        } catch {
            return false;
        }
    }



    /**
     * @dev Gets permit nonce for a user
     * @param permit2 The Permit2 contract
     * @param user The user address
     * @return nonce The current nonce for the user
     */
    function getPermitNonce(ISignatureTransfer permit2, address user) internal view returns (uint256 nonce) {
        return permit2.nonce(user);
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures
     * @param permit2 The Permit2 contract
     * @return domainSeparator The domain separator hash
     */
    function getPermitDomainSeparator(ISignatureTransfer permit2) internal view returns (bytes32 domainSeparator) {
        return permit2.DOMAIN_SEPARATOR();
    }

    // ============ UTILITY STRUCTS ============

    /**
     * @dev Context data for permit validation
     */
    struct PermitValidationContext {
        address user;
        address paymentToken;
        uint256 expectedAmount;
        uint256 deadline;
        bool hasOperatorSignature;
        bool isProcessed;
    }

    // ============ CONSTANTS ============

    /// @notice Error messages
    string internal constant INVALID_PERMIT_DATA = "Invalid permit data";
    string internal constant PERMIT_EXPIRED = "Permit expired";
    string internal constant INVALID_NONCE = "Invalid nonce";
    string internal constant INVALID_DESTINATION = "Invalid transfer destination";
    string internal constant INSUFFICIENT_AMOUNT = "Insufficient permit amount";
}
