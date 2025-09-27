// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "../../src/SignatureManager.sol";

/**
 * @title SignatureManagerTestHelper
 * @dev Test helper contract for SignatureManager - separated from production code
 * @notice This contract contains ONLY test helper functions and should never be deployed to production
 */
contract SignatureManagerTestHelper is EIP712 {
    SignatureManager public immutable signatureManager;

    // ============ INTERNAL TEST STORAGE ============
    mapping(bytes16 => bytes32) private testIntentHashes;
    mapping(address => bool) private testAuthorizedSigners;
    uint256 private testSignersCount;

    // ============ EVENTS ============
    event IntentHashSetForTesting(bytes16 indexed intentId, bytes32 hash);
    event AuthorizedSignerSetForTesting(address indexed signer, bool authorized);

    constructor(address _signatureManager) EIP712("SignatureManagerTestHelper", "1") {
        require(_signatureManager != address(0), "Invalid SignatureManager address");
        signatureManager = SignatureManager(_signatureManager);
    }

    // ============ TEST ENVIRONMENT PROTECTION ============
    modifier testOnly() {
        require(
            block.chainid == 31337 || // Foundry/Anvil testnet
            block.chainid == 84532 ||  // Base Sepolia testnet
            tx.origin == address(0) || // Direct call (test environment)
            msg.sender.code.length == 0, // Externally owned account
            "Test helper: Production use not allowed"
        );
        _;
    }

    /**
     * @dev TEST HELPER: Sets an intent hash for testing purposes only
     * @param intentId The intent ID
     * @param hash The intent hash to store
     * @notice This function should ONLY be used in testing environments
     */
    function setIntentHashForTesting(bytes16 intentId, bytes32 hash) external testOnly {
        testIntentHashes[intentId] = hash;
        emit IntentHashSetForTesting(intentId, hash);
    }

    /**
     * @dev TEST HELPER: Gets intent hash for testing verification
     * @dev First checks test storage, then production contract
     */
    function getIntentHashForTesting(bytes16 intentId) external view returns (bytes32 hash) {
        // First try test storage
        bytes32 testHash = testIntentHashes[intentId];
        if (testHash != bytes32(0)) {
            return testHash;
        }
        // Fall back to production contract
        return signatureManager.getIntentHash(intentId);
    }

    /**
     * @dev TEST HELPER: Verifies signature without intent hash requirement
     * @param signature The signature to verify
     * @param messageHash The message hash that was signed
     * @param expectedSigner The expected signer address
     */
    function verifySignatureDirect(
        bytes memory signature,
        bytes32 messageHash,
        address expectedSigner
    ) external view testOnly returns (bool isValid) {
        // Use EIP712 structured data hashing
        bytes32 digest = _hashTypedDataV4(messageHash);
        address recoveredSigner = ECDSA.recover(digest, signature);
        return recoveredSigner == expectedSigner;
    }

    /**
     * @dev TEST HELPER: Verifies signature without EIP712 wrapper (raw signature)
     * @param signature The signature to verify
     * @param messageHash The raw message hash that was signed
     * @param expectedSigner The expected signer address
     */
    function verifySignatureRaw(
        bytes memory signature,
        bytes32 messageHash,
        address expectedSigner
    ) external pure testOnly returns (bool isValid) {
        address recoveredSigner = ECDSA.recover(messageHash, signature);
        return recoveredSigner == expectedSigner;
    }

    /**
     * @dev TEST HELPER: Sets authorized signer status for testing
     * @param signer The signer address
     * @param authorized Whether the signer is authorized
     */
    function setAuthorizedSignerForTesting(address signer, bool authorized) external testOnly {
        bool wasAuthorized = testAuthorizedSigners[signer];
        testAuthorizedSigners[signer] = authorized;
        
        // Update count
        if (authorized && !wasAuthorized) {
            testSignersCount++;
        } else if (!authorized && wasAuthorized) {
            testSignersCount--;
        }
        
        emit AuthorizedSignerSetForTesting(signer, authorized);
    }

    /**
     * @dev TEST HELPER: Gets all authorized signers count from test storage
     */
    function getAuthorizedSignersCount() external view testOnly returns (uint256 count) {
        return testSignersCount;
    }

    /**
     * @dev TEST HELPER: Checks if a signer is authorized in test storage
     * @param signer The signer address to check
     * @return authorized True if authorized in test storage
     */
    function isAuthorizedSignerForTesting(address signer) external view testOnly returns (bool authorized) {
        return testAuthorizedSigners[signer];
    }

    /**
     * @dev TEST HELPER: Gets intent hash directly from production contract
     * @param intentId The intent ID
     * @dev Note: getIntentHashDirect was renamed to getIntentHash in production contract
     */
    function getIntentHashDirect(bytes16 intentId) external view testOnly returns (bytes32) {
        return signatureManager.getIntentHash(intentId);
    }

    /**
     * @dev TEST HELPER: Batch set multiple intent hashes for testing
     * @param intentIds Array of intent IDs
     * @param hashes Array of hashes to set
     */
    function batchSetIntentHashesForTesting(
        bytes16[] calldata intentIds,
        bytes32[] calldata hashes
    ) external testOnly {
        require(intentIds.length == hashes.length, "Array length mismatch");
        
        for (uint256 i = 0; i < intentIds.length; i++) {
            testIntentHashes[intentIds[i]] = hashes[i];
            emit IntentHashSetForTesting(intentIds[i], hashes[i]);
        }
    }

    /**
     * @dev TEST HELPER: Gets multiple intent hashes for testing
     * @param intentIds Array of intent IDs
     */
    function batchGetIntentHashesForTesting(bytes16[] calldata intentIds) external view testOnly returns (bytes32[] memory hashes) {
        hashes = new bytes32[](intentIds.length);
        for (uint256 i = 0; i < intentIds.length; i++) {
            // First try test storage, then production
            bytes32 testHash = testIntentHashes[intentIds[i]];
            if (testHash != bytes32(0)) {
                hashes[i] = testHash;
            } else {
                hashes[i] = signatureManager.getIntentHash(intentIds[i]);
            }
        }
    }

    /**
     * @dev TEST HELPER: Clears all test data
     */
    function clearTestData() external testOnly {
        // Note: Cannot iterate through mappings, so this is a placeholder
        // Tests should track and clear specific entries they set
        testSignersCount = 0;
    }

    /**
     * @dev TEST HELPER: Gets test storage status
     * @return intentHashCount Number of intent hashes in test storage (approximation)
     * @return signersCount Number of authorized signers in test storage
     */
    function getTestStorageStatus() external view testOnly returns (uint256 intentHashCount, uint256 signersCount) {
        // Note: Cannot count mapping entries directly
        // Return signer count and 0 for intent hashes
        return (0, testSignersCount);
    }
}
