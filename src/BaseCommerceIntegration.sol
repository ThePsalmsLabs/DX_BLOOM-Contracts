// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAuthCaptureEscrow, IPermit2PaymentCollector, BaseCommerceProtocolAddresses } from "./interfaces/IBaseCommerceProtocol.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";

/**
 * @title BaseCommerceIntegration
 * @dev Handles integration with Base Commerce Protocol's escrow system
 * @notice This contract manages the two-phase authorize→capture payment flow
 */
contract BaseCommerceIntegration is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    IAuthCaptureEscrow public immutable authCaptureEscrow;
    IPermit2PaymentCollector public immutable permit2Collector;
    IERC20 public immutable usdcToken;
    
    // Platform configuration
    address public operatorFeeDestination;
    uint16 public operatorFeeRate = 250; // 2.5% in basis points
    uint48 public defaultAuthExpiry = 30 minutes;
    uint48 public defaultRefundWindow = 7 days;

    // Payment tracking
    mapping(bytes32 => PaymentRecord) public paymentRecords;
    mapping(address => uint256) public userNonces;

    // ============ STRUCTS ============

    struct PaymentRecord {
        bytes32 paymentHash;
        address payer;
        address receiver;
        uint256 amount;
        uint256 timestamp;
        PaymentStatus status;
        ISharedTypes.PaymentType paymentType;
    }

    enum PaymentStatus {
        None,           // 0 - Payment doesn't exist
        Authorized,     // 1 - Funds locked in escrow
        Captured,       // 2 - Funds released to receiver
        Voided,         // 3 - Payment cancelled
        Refunded        // 4 - Funds returned to payer
    }

    struct EscrowPaymentParams {
        address payer;
        address receiver;
        uint256 amount;
        ISharedTypes.PaymentType paymentType;
        bytes permit2Data;
        bool instantCapture; // If true, authorize + capture in one transaction
    }

    // ============ EVENTS ============

    event EscrowPaymentInitiated(
        bytes32 indexed paymentHash,
        address indexed payer,
        address indexed receiver,
        uint256 amount,
        ISharedTypes.PaymentType paymentType
    );

    event EscrowPaymentAuthorized(
        bytes32 indexed paymentHash,
        uint256 amount
    );

    event EscrowPaymentCaptured(
        bytes32 indexed paymentHash,
        uint256 amount,
        uint256 fee
    );

    event EscrowPaymentVoided(
        bytes32 indexed paymentHash,
        address indexed operator
    );

    event EscrowPaymentRefunded(
        bytes32 indexed paymentHash,
        uint256 amount
    );

    event OperatorConfigUpdated(
        address indexed newFeeDestination,
        uint16 newFeeRate
    );

    // ============ CONSTRUCTOR ============

    constructor(
        address _usdcToken,
        address _operatorFeeDestination
    ) Ownable(msg.sender) {
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_operatorFeeDestination != address(0), "Invalid fee destination");

        // Use the real Base Commerce Protocol addresses
        authCaptureEscrow = IAuthCaptureEscrow(BaseCommerceProtocolAddresses.AUTH_CAPTURE_ESCROW);
        permit2Collector = IPermit2PaymentCollector(BaseCommerceProtocolAddresses.PERMIT2_COLLECTOR);
        usdcToken = IERC20(_usdcToken);
        operatorFeeDestination = _operatorFeeDestination;
    }

    // ============ CORE PAYMENT FUNCTIONS ============

    /**
     * @dev Execute complete escrow payment: authorize → capture
     * @param params Payment parameters including payer, receiver, amount
     * @return paymentHash Unique identifier for this payment
     */
    function executeEscrowPayment(
        EscrowPaymentParams calldata params
    ) external nonReentrant returns (bytes32 paymentHash) {
        require(params.amount > 0, "Amount must be positive");
        require(params.payer != address(0), "Invalid payer");
        require(params.receiver != address(0), "Invalid receiver");

        // Create PaymentInfo for escrow
        IAuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(
            params.payer,
            params.receiver,
            params.amount
        );

        paymentHash = authCaptureEscrow.getPaymentHash(paymentInfo);

        // Record payment
        paymentRecords[paymentHash] = PaymentRecord({
            paymentHash: paymentHash,
            payer: params.payer,
            receiver: params.receiver,
            amount: params.amount,
            timestamp: block.timestamp,
            status: PaymentStatus.None,
            paymentType: params.paymentType
        });

        emit EscrowPaymentInitiated(
            paymentHash,
            params.payer,
            params.receiver,
            params.amount,
            params.paymentType
        );

        if (params.instantCapture) {
            // Single transaction: authorize + capture
            _chargePayment(paymentInfo, params.amount, params.permit2Data);
            paymentRecords[paymentHash].status = PaymentStatus.Captured;
            
            emit EscrowPaymentCaptured(paymentHash, params.amount, _calculateFee(params.amount));
        } else {
            // Two-phase: authorize first
            _authorizePayment(paymentInfo, params.amount, params.permit2Data);
            paymentRecords[paymentHash].status = PaymentStatus.Authorized;
            
            emit EscrowPaymentAuthorized(paymentHash, params.amount);
        }

        return paymentHash;
    }

    /**
     * @dev Capture previously authorized payment
     * @param paymentHash Hash of the payment to capture
     * @param amount Amount to capture (can be partial)
     * @return success Whether capture succeeded
     */
    function capturePayment(
        bytes32 paymentHash,
        uint256 amount
    ) external onlyOwner nonReentrant returns (bool success) {
        PaymentRecord storage record = paymentRecords[paymentHash];
        require(record.status == PaymentStatus.Authorized, "Payment not authorized");
        require(amount > 0, "Invalid capture amount");

        // Recreate PaymentInfo from stored data
        IAuthCaptureEscrow.PaymentInfo memory paymentInfo = _recreatePaymentInfo(record);

        try authCaptureEscrow.capture(
            paymentInfo,
            amount,
            operatorFeeRate,
            operatorFeeDestination
        ) {
            record.status = PaymentStatus.Captured;
            emit EscrowPaymentCaptured(paymentHash, amount, _calculateFee(amount));
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Void (cancel) an authorized payment
     * @param paymentHash Payment to void
     * @return success Whether void succeeded
     */
    function voidPayment(bytes32 paymentHash) external onlyOwner nonReentrant returns (bool success) {
        PaymentRecord storage record = paymentRecords[paymentHash];
        require(record.status == PaymentStatus.Authorized, "Payment not authorized");

        IAuthCaptureEscrow.PaymentInfo memory paymentInfo = _recreatePaymentInfo(record);

        try authCaptureEscrow.void(paymentInfo) {
            record.status = PaymentStatus.Voided;
            emit EscrowPaymentVoided(paymentHash, msg.sender);
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Refund a payment back to payer
     * @param paymentHash Payment to refund
     * @param amount Amount to refund
     * @param permit2Data Permit2 data for the refund transfer
     * @return success Whether refund succeeded
     */
    function refundPayment(
        bytes32 paymentHash,
        uint256 amount,
        bytes calldata permit2Data
    ) external onlyOwner nonReentrant returns (bool success) {
        PaymentRecord storage record = paymentRecords[paymentHash];
        require(
            record.status == PaymentStatus.Authorized || 
            record.status == PaymentStatus.Captured,
            "Invalid payment status for refund"
        );

        IAuthCaptureEscrow.PaymentInfo memory paymentInfo = _recreatePaymentInfo(record);

        try authCaptureEscrow.refund(
            paymentInfo,
            amount,
            address(permit2Collector),
            permit2Data
        ) {
            record.status = PaymentStatus.Refunded;
            emit EscrowPaymentRefunded(paymentHash, amount);
            return true;
        } catch {
            return false;
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Authorize payment (Phase 1)
     */
    function _authorizePayment(
        IAuthCaptureEscrow.PaymentInfo memory paymentInfo,
        uint256 amount,
        bytes calldata permit2Data
    ) internal {
        authCaptureEscrow.authorize(
            paymentInfo,
            amount,
            address(permit2Collector),
            permit2Data
        );
    }

    /**
     * @dev Single-transaction authorize + capture
     */
    function _chargePayment(
        IAuthCaptureEscrow.PaymentInfo memory paymentInfo,
        uint256 amount,
        bytes calldata permit2Data
    ) internal {
        authCaptureEscrow.charge(
            paymentInfo,
            amount,
            address(permit2Collector),
            permit2Data,
            operatorFeeRate,
            operatorFeeDestination
        );
    }

    /**
     * @dev Create PaymentInfo struct for escrow operations
     */
    function _createPaymentInfo(
        address payer,
        address receiver,
        uint256 amount
    ) internal returns (IAuthCaptureEscrow.PaymentInfo memory) {
        // Increment user nonce for uniqueness
        userNonces[payer]++;
        
        uint256 salt = uint256(keccak256(abi.encodePacked(
            payer,
            receiver,
            amount,
            userNonces[payer],
            block.timestamp,
            address(this)
        )));

        return IAuthCaptureEscrow.PaymentInfo({
            operator: address(this),
            payer: payer,
            receiver: receiver,
            token: address(usdcToken),
            maxAmount: uint120(amount),
            preApprovalExpiry: uint48(block.timestamp + 1 hours),
            authorizationExpiry: uint48(block.timestamp + defaultAuthExpiry),
            refundExpiry: uint48(block.timestamp + defaultRefundWindow),
            minFeeBps: 0,
            maxFeeBps: 1000, // 10% max fee
            feeReceiver: operatorFeeDestination,
            salt: salt
        });
    }

    /**
     * @dev Recreate PaymentInfo from stored record (for capture/void/refund)
     */
    function _recreatePaymentInfo(
        PaymentRecord memory record
    ) internal view returns (IAuthCaptureEscrow.PaymentInfo memory) {
        // For stored payments, we need to recreate the exact same PaymentInfo
        // The salt and other fields must match exactly what was used in authorization
        uint256 salt = uint256(keccak256(abi.encodePacked(
            record.payer,
            record.receiver,
            record.amount,
            userNonces[record.payer], // This should be stored in PaymentRecord
            record.timestamp,
            address(this)
        )));

        return IAuthCaptureEscrow.PaymentInfo({
            operator: address(this),
            payer: record.payer,
            receiver: record.receiver,
            token: address(usdcToken),
            maxAmount: uint120(record.amount),
            preApprovalExpiry: uint48(record.timestamp + 1 hours),
            authorizationExpiry: uint48(record.timestamp + defaultAuthExpiry),
            refundExpiry: uint48(record.timestamp + defaultRefundWindow),
            minFeeBps: 0,
            maxFeeBps: 1000,
            feeReceiver: operatorFeeDestination,
            salt: salt
        });
    }

    /**
     * @dev Calculate operator fee for amount
     */
    function _calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * operatorFeeRate) / 10000;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get payment status from escrow
     */
    function getPaymentState(bytes32 paymentHash) 
        external view returns (IAuthCaptureEscrow.PaymentState memory) {
        PaymentRecord memory record = paymentRecords[paymentHash];
        require(record.payer != address(0), "Payment not found");
        
        IAuthCaptureEscrow.PaymentInfo memory paymentInfo = _recreatePaymentInfo(record);
        return authCaptureEscrow.getPaymentState(paymentInfo);
    }

    /**
     * @dev Get payment record
     */
    function getPaymentRecord(bytes32 paymentHash) 
        external view returns (PaymentRecord memory) {
        return paymentRecords[paymentHash];
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Update operator configuration
     */
    function updateOperatorConfig(
        address newFeeDestination,
        uint16 newFeeRate
    ) external onlyOwner {
        require(newFeeDestination != address(0), "Invalid fee destination");
        require(newFeeRate <= 1000, "Fee rate too high"); // Max 10%

        operatorFeeDestination = newFeeDestination;
        operatorFeeRate = newFeeRate;

        emit OperatorConfigUpdated(newFeeDestination, newFeeRate);
    }

    /**
     * @dev Update timing configuration
     */
    function updateTimingConfig(
        uint48 newAuthExpiry,
        uint48 newRefundWindow
    ) external onlyOwner {
        require(newAuthExpiry >= 5 minutes, "Auth expiry too short");
        require(newRefundWindow >= 1 hours, "Refund window too short");

        defaultAuthExpiry = newAuthExpiry;
        defaultRefundWindow = newRefundWindow;
    }
}