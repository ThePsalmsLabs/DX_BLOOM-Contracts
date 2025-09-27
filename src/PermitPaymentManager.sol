// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { PaymentValidatorLib } from "./libraries/PaymentValidatorLib.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";
import { BaseCommerceIntegration } from "./BaseCommerceIntegration.sol";

/**
 * @title PermitPaymentManager
 * @dev Manages permit-based payment operations
 * @notice This contract handles all permit-based payment operations to reduce main contract size
 */
contract PermitPaymentManager is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using PaymentValidatorLib for *;

    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");

    // Contract references  
    BaseCommerceIntegration public immutable baseCommerceIntegration;
    ISignatureTransfer public immutable permit2;
    address public immutable usdcToken;

    // Permit data structure for BaseCommerceIntegration
    struct Permit2Data {
        ISignatureTransfer.PermitTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails transferDetails;
        bytes signature;
    }

    // Events
    event PaymentExecutedWithPermit(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        ISharedTypes.PaymentType paymentType,
        uint256 amount,
        address paymentToken,
        bool success
    );

    event PermitPaymentCreated(
        bytes16 indexed intentId,
        address indexed user,
        address indexed creator,
        ISharedTypes.PaymentType paymentType,
        uint256 amount,
        address paymentToken,
        uint256 nonce
    );

    constructor(
        address _baseCommerceIntegration,
        address _permit2,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_baseCommerceIntegration != address(0), "Invalid base commerce integration");
        require(_permit2 != address(0), "Invalid permit2 contract");
        require(_usdcToken != address(0), "Invalid USDC token");

        baseCommerceIntegration = BaseCommerceIntegration(_baseCommerceIntegration);
        permit2 = ISignatureTransfer(_permit2);
        usdcToken = _usdcToken;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_MONITOR_ROLE, msg.sender);
    }

    /**
     * @dev Executes payment using Permit2 for gasless approvals
     */
    function executePaymentWithPermit(
        bytes16 intentId,
        address user,
        address paymentToken,
        uint256 expectedAmount,
        address creator,
        ISharedTypes.PaymentType paymentType,
        Permit2Data calldata permitData
    ) external nonReentrant whenNotPaused returns (bool success) {
        require(user == msg.sender, "Not intent creator");

        // Validate permit data
        require(_validatePermitData(permitData, user), "Invalid permit data");
        require(_validatePermitContext(permitData, paymentToken, expectedAmount), "Permit context mismatch");

        // Encode permit data for BaseCommerceIntegration
        bytes memory permit2DataEncoded = abi.encode(permitData);

        // Execute payment through BaseCommerceIntegration
        try baseCommerceIntegration.executeEscrowPayment(
            BaseCommerceIntegration.EscrowPaymentParams({
                payer: user,
                receiver: creator,
                amount: expectedAmount,
                paymentType: paymentType,
                permit2Data: permit2DataEncoded,
                instantCapture: true // Single transaction: authorize + capture
            })
        ) returns (bytes32 paymentHash) {
            emit PaymentExecutedWithPermit(
                intentId,
                user,
                creator,
                paymentType,
                expectedAmount,
                paymentToken,
                true
            );

            return true;
        } catch Error(string memory reason) {
            emit PaymentExecutedWithPermit(
                intentId,
                user,
                creator,
                paymentType,
                0,
                paymentToken,
                false
            );

            return false;
        } catch (bytes memory) {
            emit PaymentExecutedWithPermit(
                intentId,
                user,
                creator,
                paymentType,
                0,
                paymentToken,
                false
            );

            return false;
        }
    }

    /**
     * @dev Creates payment intent and executes with permit in one transaction
     */
    function createAndExecuteWithPermit(
        address user,
        address creator,
        ISharedTypes.PaymentType paymentType,
        address paymentToken,
        uint256 expectedAmount,
        bytes16 intentId,
        Permit2Data calldata permitData
    ) external nonReentrant whenNotPaused returns (bytes16, bool) {
        require(user == msg.sender, "Not intent creator");

        // Execute with permit directly (no need for double call)
        bool success = this.executePaymentWithPermit(
            intentId,
            user,
            paymentToken,
            expectedAmount,
            creator,
            paymentType,
            permitData
        );

        // Emit permit payment creation event
        emit PermitPaymentCreated(
            intentId,
            user,
            creator,
            paymentType,
            expectedAmount,
            paymentToken,
            permit2.nonce(user)
        );

        return (intentId, success);
    }

    /**
     * @dev Gets permit nonce for a user
     */
    function getPermitNonce(address user) external view returns (uint256 nonce) {
        return permit2.nonce(user);
    }

    /**
     * @dev Validates permit signature data before execution
     */
    function validatePermitData(
        Permit2Data calldata permitData,
        address user
    ) external view returns (bool isValid) {
        return _validatePermitData(permitData, user);
    }

    /**
     * @dev Validates that permit data matches the payment context
     */
    function validatePermitContext(
        Permit2Data calldata permitData,
        address paymentToken,
        uint256 expectedAmount,
        address commerceProtocolAddress
    ) external view returns (bool isValid) {
        return _validatePermitContext(permitData, paymentToken, expectedAmount);
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures
     */
    function getPermitDomainSeparator() external view returns (bytes32 domainSeparator) {
        return permit2.DOMAIN_SEPARATOR();
    }

    /**
     * @dev Validates that a payment intent can be executed with permit
     */
    function canExecuteWithPermit(
        bytes16 /* intentId */,
        address user,
        uint256 deadline,
        bool hasSignature,
        Permit2Data calldata permitData,
        address paymentToken,
        uint256 expectedAmount
    ) external view returns (bool canExecute, string memory reason) {
        // Check if intent exists
        if (user == address(0)) {
            return (false, "Intent not found");
        }

        // Check if expired
        if (block.timestamp > deadline) {
            return (false, "Intent expired");
        }

        // Check if operator signature exists
        if (!hasSignature) {
            return (false, "No operator signature");
        }

        // Validate permit data
        if (!_validatePermitData(permitData, user)) {
            return (false, "Invalid permit data");
        }

        // Validate permit context
        if (!_validatePermitContext(permitData, paymentToken, expectedAmount)) {
            return (false, "Permit data doesn't match payment context");
        }

        return (true, "");
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resume operations after pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ INTERNAL VALIDATION FUNCTIONS ============

    /**
     * @dev Internal function to validate permit data
     */
    function _validatePermitData(
        Permit2Data calldata permitData,
        address user
    ) internal view returns (bool) {
        // Check permit deadline
        if (permitData.permit.deadline < block.timestamp) {
            return false;
        }

        // Check permit nonce matches current user nonce
        if (permitData.permit.nonce != permit2.nonce(user)) {
            return false;
        }

        // Additional validations can be added here
        return true;
    }

    /**
     * @dev Internal function to validate permit context matches payment
     */
    function _validatePermitContext(
        Permit2Data calldata permitData,
        address paymentToken,
        uint256 expectedAmount
    ) internal view returns (bool) {
        // Check token matches
        if (permitData.permit.permitted.token != paymentToken) {
            return false;
        }

        // Check amount is sufficient
        if (permitData.permit.permitted.amount < expectedAmount) {
            return false;
        }

        // Check transfer details
        if (permitData.transferDetails.to != address(baseCommerceIntegration)) {
            return false;
        }

        if (permitData.transferDetails.requestedAmount != expectedAmount) {
            return false;
        }

        return true;
    }
}
