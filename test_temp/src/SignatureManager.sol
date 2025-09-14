// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { EIP712 } from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import { ICommercePaymentsProtocol } from "./interfaces/IPlatformInterfaces.sol";
import { PaymentUtilsLib } from "./libraries/PaymentUtilsLib.sol";

/**
 * @title SignatureManager
 * @dev Manages signature operations for payment intents
 * @notice This contract handles all signature-related operations to reduce main contract size
 */
contract SignatureManager is Ownable, EIP712 {
    // EIP-712 type hashes
    bytes32 private constant TRANSFER_INTENT_TYPEHASH = keccak256(
        "TransferIntent(uint256 recipientAmount,uint256 deadline,address recipient,address recipientCurrency,address refundDestination,uint256 feeAmount,bytes16 id,address operator)"
    );

    // Authorized signers mapping
    mapping(address => bool) public authorizedSigners;

    // Signature state
    mapping(bytes16 => bytes32) public intentHashes; // intentId => hash to be signed
    mapping(bytes16 => bytes) public intentSignatures; // intentId => actual signature
    mapping(bytes16 => bool) public intentReadyForExecution; // intentId => ready status

    // Events
    event IntentReadyForSigning(bytes16 indexed intentId, bytes32 intentHash, uint256 deadline);
    event IntentSigned(bytes16 indexed intentId, bytes signature);
    event IntentReadyForExecution(bytes16 indexed intentId, bytes signature);
    event AuthorizedSignerAdded(address signer);
    event AuthorizedSignerRemoved(address signer);

    constructor(address _operatorSigner) Ownable(msg.sender) EIP712("ContentPlatformOperator", "1") {
        require(_operatorSigner != address(0), "Invalid operator signer");
        authorizedSigners[_operatorSigner] = true;
    }

    /**
     * @dev Adds an authorized signer
     */
    function addAuthorizedSigner(address signer) external onlyOwner {
        require(signer != address(0), "Invalid signer");
        authorizedSigners[signer] = true;
        emit AuthorizedSignerAdded(signer);
    }

    /**
     * @dev Removes an authorized signer
     */
    function removeAuthorizedSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = false;
        emit AuthorizedSignerRemoved(signer);
    }

    /**
     * @dev Prepares intent for backend signing
     */
    function prepareIntentForSigning(ICommercePaymentsProtocol.TransferIntent memory intent)
        external
        returns (bytes32 intentHash)
    {
        bytes32 structHash = keccak256(
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
        );

        intentHash = _hashTypedDataV4(structHash);
        intentHashes[intent.id] = intentHash;
        intentReadyForExecution[intent.id] = false;

        emit IntentReadyForSigning(intent.id, intentHash, intent.deadline);
        return intentHash;
    }

    /**
     * @dev Backend provides the actual signature
     */
    function provideIntentSignature(bytes16 intentId, bytes memory signature, address operatorSigner) external {
        require(intentHashes[intentId] != bytes32(0), "Intent not found");

        // Signature length sanity
        if (signature.length != 65) revert("Invalid signature length");

        bytes32 intentHash = intentHashes[intentId];
        address recoveredSigner = _recoverSigner(intentHash, signature);

        // Authorization matrix
        if (!authorizedSigners[recoveredSigner]) {
            revert("Unauthorized signer");
        }
        if (msg.sender != operatorSigner) {
            revert("Only operator can provide signature");
        }

        // Already signed check
        if (intentSignatures[intentId].length != 0) revert("Intent already signed");

        // Store the signature
        intentSignatures[intentId] = signature;
        intentReadyForExecution[intentId] = true;

        emit IntentSigned(intentId, signature);
    }

    /**
     * @dev Get the signature for an intent
     */
    function getIntentSignature(bytes16 intentId) external view returns (bytes memory) {
        require(intentReadyForExecution[intentId], "Intent not ready");
        return intentSignatures[intentId];
    }

    /**
     * @dev Returns true if a signature has been provided for the given intentId
     */
    function hasSignature(bytes16 intentId) external view returns (bool) {
        return intentReadyForExecution[intentId];
    }

    /**
     * @dev Recover signer from signature
     */
    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return PaymentUtilsLib.recoverSigner(hash, signature);
    }

    /**
     * @dev Check if an address is an authorized signer
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }
}


