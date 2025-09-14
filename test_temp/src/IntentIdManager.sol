// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IntentIdManager
 * @dev Centralized intent ID generation to ensure uniqueness across all platform contracts
 * @notice This library provides a standardized way to generate unique intent IDs
 *         that are compatible with the Base Commerce Protocol requirements
 */
library IntentIdManager {
    /**
     * @dev Intent types for different platform operations
     */
    enum IntentType {
        CONTENT_PURCHASE, // Pay-per-view content purchase
        SUBSCRIPTION, // Creator subscription
        SUBSCRIPTION_RENEWAL, // Auto-renewal of subscription
        REFUND // Refund operation

    }

    /**
     * @dev Generates a unique intent ID for commerce protocol operations
     * @param user Address of the user initiating the action
     * @param target Target address (creator for subscriptions, content creator for purchases)
     * @param identifier Unique identifier (contentId for purchases, 0 for subscriptions)
     * @param intentType Type of intent being created
     * @param nonce User's current nonce (must be managed by calling contract)
     * @param contractAddress Address of the calling contract for additional uniqueness
     * @return bytes16 Unique intent ID
     */
    function generateIntentId(
        address user,
        address target,
        uint256 identifier,
        IntentType intentType,
        uint256 nonce,
        address contractAddress
    ) internal view returns (bytes16) {
        // Create a comprehensive hash that includes all relevant context
        bytes32 hash = keccak256(
            abi.encodePacked(
                user, // Who is making the transaction
                target, // Who is receiving (creator address)
                identifier, // What is being purchased (contentId or 0)
                uint256(intentType), // Type of operation
                nonce, // User's transaction nonce
                contractAddress, // Which contract is generating this
                block.timestamp, // When the intent was created
                block.chainid // Which chain (prevents cross-chain collisions)
            )
        );

        return bytes16(hash);
    }

    /**
     * @dev Generates a unique refund intent ID
     * @param originalIntentId The original intent ID being refunded
     * @param user User requesting the refund
     * @param reason Refund reason (hashed for uniqueness)
     * @param contractAddress Address of the calling contract
     * @return bytes16 Unique refund intent ID
     */
    function generateRefundIntentId(
        bytes16 originalIntentId,
        address user,
        string memory reason,
        address contractAddress
    ) internal view returns (bytes16) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                originalIntentId,
                user,
                keccak256(bytes(reason)),
                contractAddress,
                block.timestamp,
                "REFUND" // Additional string for refund uniqueness
            )
        );

        return bytes16(hash);
    }

    /**
     * @dev Validates that an intent ID follows the expected format
     * @param intentId Intent ID to validate
     * @return bool True if the intent ID is non-zero (basic validation)
     */
    function isValidIntentId(bytes16 intentId) internal pure returns (bool) {
        return intentId != bytes16(0);
    }

    /**
     * @dev Creates a deterministic but unique nonce for emergency situations
     * @param user User address
     * @param contractAddress Contract address
     * @param fallbackSeed Additional seed for uniqueness
     * @return uint256 Emergency nonce
     */
    function generateEmergencyNonce(address user, address contractAddress, uint256 fallbackSeed)
        internal
        view
        returns (uint256)
    {
        return
            uint256(keccak256(abi.encodePacked(user, contractAddress, fallbackSeed, block.timestamp, block.prevrandao)));
    }
}
