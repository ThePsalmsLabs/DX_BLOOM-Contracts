// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ICommercePaymentsProtocol, ISignatureTransfer } from "./interfaces/IPlatformInterfaces.sol";
import { PermitHandlerLib } from "./libraries/PermitHandlerLib.sol";
import { PaymentValidatorLib } from "./libraries/PaymentValidatorLib.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";

/**
 * @title PermitPaymentManager
 * @dev Manages permit-based payment operations
 * @notice This contract handles all permit-based payment operations to reduce main contract size
 */
contract PermitPaymentManager is Ownable, AccessControl, ReentrancyGuard, Pausable {
    using PermitHandlerLib for *;
    using PaymentValidatorLib for *;

    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");

    // Contract references
    ICommercePaymentsProtocol public commerceProtocol;
    ISignatureTransfer public permit2;
    address public usdcToken;

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
        address _commerceProtocol,
        address _permit2,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_commerceProtocol != address(0), "Invalid commerce protocol");
        require(_permit2 != address(0), "Invalid permit2 contract");
        require(_usdcToken != address(0), "Invalid USDC token");

        commerceProtocol = ICommercePaymentsProtocol(_commerceProtocol);
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
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        uint256 deadline,
        ISharedTypes.PaymentType paymentType,
        bytes memory signature,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) external nonReentrant whenNotPaused returns (bool success) {
        require(user == msg.sender, "Not intent creator");

        // Reconstruct the transfer intent with operator signature
        ICommercePaymentsProtocol.TransferIntent memory intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: creatorAmount,
            deadline: deadline,
            recipient: payable(creator),
            recipientCurrency: usdcToken, // Use configured USDC token
            refundDestination: user,
            feeAmount: platformFee + operatorFee,
            id: intentId,
            operator: address(this),
            signature: signature,
            prefix: "",
            sender: user,
            token: paymentToken
        });

        // Execute permit payment using library
        bool paymentSuccess = PermitHandlerLib.executePermitTransfer(
            commerceProtocol, intent, permitData
        );

        if (paymentSuccess) {
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
        } else {
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
        uint256 contentId,
        ISharedTypes.PaymentType paymentType,
        address paymentToken,
        uint256 expectedAmount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        uint256 deadline,
        bytes16 intentId,
        bytes memory signature,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData
    ) external nonReentrant whenNotPaused returns (bytes16, bool) {
        require(user == msg.sender, "Not intent creator");

        // Reconstruct the transfer intent with operator signature
        ICommercePaymentsProtocol.TransferIntent memory intent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: creatorAmount,
            deadline: deadline,
            recipient: payable(creator),
            recipientCurrency: usdcToken,
            refundDestination: user,
            feeAmount: platformFee + operatorFee,
            id: intentId,
            operator: address(this),
            signature: signature,
            prefix: "",
            sender: user,
            token: paymentToken
        });

        // Execute with permit
        bool success = this.executePaymentWithPermit(
            intentId,
            user,
            paymentToken,
            expectedAmount,
            creator,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            paymentType,
            signature,
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
        return PermitHandlerLib.getPermitNonce(permit2, user);
    }

    /**
     * @dev Validates permit signature data before execution
     */
    function validatePermitData(
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        address user
    ) external view returns (bool isValid) {
        return PermitHandlerLib.validatePermitData(permit2, permitData, user);
    }

    /**
     * @dev Validates that permit data matches the payment context
     */
    function validatePermitContext(
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
        address paymentToken,
        uint256 expectedAmount,
        address commerceProtocolAddress
    ) external view returns (bool isValid) {
        return PermitHandlerLib.validatePermitContext(permitData, paymentToken, expectedAmount, commerceProtocolAddress);
    }

    /**
     * @dev Gets the EIP-712 domain separator for permit signatures
     */
    function getPermitDomainSeparator() external view returns (bytes32 domainSeparator) {
        return PermitHandlerLib.getPermitDomainSeparator(permit2);
    }

    /**
     * @dev Validates that a payment intent can be executed with permit
     */
    function canExecuteWithPermit(
        bytes16 intentId,
        address user,
        uint256 deadline,
        bool hasSignature,
        ICommercePaymentsProtocol.Permit2SignatureTransferData calldata permitData,
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

        // Validate permit data using library
        if (!PermitHandlerLib.validatePermitData(permit2, permitData, user)) {
            return (false, "Invalid permit data");
        }

        // Validate permit context using library
        if (!PermitHandlerLib.validatePermitContext(permitData, paymentToken, expectedAmount, address(commerceProtocol))) {
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
}
