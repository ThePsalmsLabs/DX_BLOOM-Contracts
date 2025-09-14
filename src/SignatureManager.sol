// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import { ICommercePaymentsProtocol } from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title SignatureManager
 * @dev Manages signatures for payment intents and authorized signers
 */
contract SignatureManager is Ownable, EIP712 {
    // Mapping to store intent signatures
    mapping(bytes16 => bytes) private intentSignatures;

    // Mapping to store intent hashes
    mapping(bytes16 => bytes32) private intentHashStorage;

    // Mapping to track authorized signers
    mapping(address => bool) private authorizedSigners;

    // EIP712 type hash for TransferIntent
    bytes32 private constant TRANSFER_INTENT_TYPEHASH = keccak256(
        "TransferIntent(uint256 recipientAmount,uint256 deadline,address recipient,address recipientCurrency,address refundDestination,uint256 feeAmount,bytes16 id,address operator)"
    );

    event AuthorizedSignerAdded(address indexed signer);
    event AuthorizedSignerRemoved(address indexed signer);
    event IntentSignatureProvided(bytes16 indexed intentId, address indexed signer);

    constructor(address initialOwner) EIP712("BloomCommerceProtocol", "1") Ownable(initialOwner) {}

    /**
     * @dev Adds an authorized signer
     * @param signer The address to authorize as a signer
     */
    function addAuthorizedSigner(address signer) external onlyOwner {
        require(signer != address(0), "Invalid signer address");
        authorizedSigners[signer] = true;
        emit AuthorizedSignerAdded(signer);
    }

    /**
     * @dev Removes an authorized signer
     * @param signer The address to remove from authorized signers
     */
    function removeAuthorizedSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = false;
        emit AuthorizedSignerRemoved(signer);
    }

    /**
     * @dev Checks if an address is an authorized signer
     * @param signer The address to check
     * @return True if the address is authorized
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }

    /**
     * @dev Prepares an intent for signing by computing its hash
     * @param intent The transfer intent to prepare
     * @return The hash of the intent
     */
    function prepareIntentForSigning(
        ICommercePaymentsProtocol.TransferIntent memory intent
    ) external returns (bytes32) {
        bytes32 intentHash = _hashTransferIntent(intent);
        intentHashStorage[intent.id] = intentHash;
        return intentHash;
    }

    /**
     * @dev Provides a signature for an intent
     * @param intentId The ID of the intent
     * @param signature The signature bytes
     * @param signer The address that provided the signature
     */
    function provideIntentSignature(
        bytes16 intentId,
        bytes memory signature,
        address signer
    ) external {
        require(authorizedSigners[signer], "Unauthorized signer");
        require(signature.length > 0, "Invalid signature");

        intentSignatures[intentId] = signature;
        emit IntentSignatureProvided(intentId, signer);
    }

    /**
     * @dev Gets the signature for an intent
     * @param intentId The ID of the intent
     * @return The signature bytes
     */
    function getIntentSignature(bytes16 intentId) external view returns (bytes memory) {
        return intentSignatures[intentId];
    }

    /**
     * @dev Checks if an intent has a signature
     * @param intentId The ID of the intent
     * @return True if the intent has a signature
     */
    function hasSignature(bytes16 intentId) external view returns (bool) {
        return intentSignatures[intentId].length > 0;
    }

    /**
     * @dev Gets the hash for an intent
     * @param intentId The ID of the intent
     * @return The intent hash
     */
    function intentHashes(bytes16 intentId) external view returns (bytes32) {
        return intentHashStorage[intentId];
    }

    /**
     * @dev Internal function to hash a transfer intent
     * @param intent The transfer intent to hash
     * @return The hash of the intent
     */
    function _hashTransferIntent(
        ICommercePaymentsProtocol.TransferIntent memory intent
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
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
            )
        );
    }

    /**
     * @dev Verifies a signature for an intent
     * @param intentId The ID of the intent
     * @param signature The signature to verify
     * @param signer The expected signer
     * @return True if the signature is valid
     */
    function verifyIntentSignature(
        bytes16 intentId,
        bytes memory signature,
        address signer
    ) external view returns (bool) {
        bytes32 intentHash = intentHashStorage[intentId];
        require(intentHash != bytes32(0), "Intent not prepared for signing");

        bytes32 digest = _hashTypedDataV4(intentHash);
        address recoveredSigner = ECDSA.recover(digest, signature);
        return recoveredSigner == signer;
    }
}
