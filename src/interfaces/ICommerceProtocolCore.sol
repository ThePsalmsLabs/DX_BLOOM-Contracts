// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedTypes } from "./ISharedTypes.sol";

/**
 * @title ICommerceProtocolCore
 * @dev Interface for CommerceProtocolCore to break circular dependencies
 * @notice This interface allows other contracts to reference CommerceProtocolCore without importing the implementation
 */
interface ICommerceProtocolCore {
    /**
     * @dev Processes a payment and executes any associated rewards
     * @param intentId Unique identifier for the payment intent
     * @param context Payment context information
     */
    function processPaymentWithRewards(
        bytes16 intentId,
        ISharedTypes.PaymentContext memory context
    ) external;

    /**
     * @dev Gets the current payment context for an intent
     * @param intentId The intent identifier
     * @return context Current payment context
     */
    function getPaymentContext(bytes16 intentId) 
        external view returns (ISharedTypes.PaymentContext memory context);

    /**
     * @dev Checks if a payment intent is valid and processed
     * @param intentId The intent identifier
     * @return isValid Whether the intent is valid
     * @return isProcessed Whether the intent has been processed
     */
    function getIntentStatus(bytes16 intentId) 
        external view returns (bool isValid, bool isProcessed);

    /**
     * @dev Gets the owner/admin of the protocol
     * @return owner The owner address
     */
    function owner() external view returns (address owner);

    /**
     * @dev Checks if an address has a specific role
     * @param role The role to check
     * @param account The account to check
     * @return hasRole Whether the account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool hasRole);
}