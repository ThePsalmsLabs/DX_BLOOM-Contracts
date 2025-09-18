// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISignatureTransfer } from "./IPlatformInterfaces.sol";

/**
 * @title IBaseCommerceProtocol
 * @dev Real Base Commerce Protocol interfaces based on actual deployed contracts
 * @notice These interfaces match the actual AuthCaptureEscrow and TokenCollector contracts
 */

/**
 * @title IAuthCaptureEscrow
 * @dev Main escrow contract interface - Address: 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff
 * @notice Handles two-phase payments: authorize (lock funds) → capture (release funds)
 */
interface IAuthCaptureEscrow {
    /**
     * @dev Payment information structure for escrow operations
     * @notice All payment operations use this struct to identify and configure payments
     */
    struct PaymentInfo {
        address operator;           // The platform/operator facilitating the payment (us)
        address payer;             // User making the payment
        address receiver;          // Creator/merchant receiving the payment
        address token;             // Token being paid (USDC in our case)
        uint120 maxAmount;         // Maximum amount that can be charged
        uint48 preApprovalExpiry;  // When pre-approval expires (if applicable)
        uint48 authorizationExpiry; // When the authorization expires
        uint48 refundExpiry;       // When the refund window closes
        uint16 minFeeBps;          // Minimum fee in basis points (100 = 1%)
        uint16 maxFeeBps;          // Maximum fee in basis points (1000 = 10%)
        address feeReceiver;       // Where operator fees are sent
        uint256 salt;              // Unique identifier/nonce for this payment
    }

    /**
     * @dev Current state of a payment in the escrow system
     */
    struct PaymentState {
        bool hasCollectedPayment;   // Whether payment tokens have been collected
        uint120 capturableAmount;   // Amount available for capture
        uint120 refundableAmount;   // Amount available for refund
    }

    /**
     * @dev Authorizes a payment by locking funds in escrow
     * @param paymentInfo Payment details and configuration
     * @param amount Amount to authorize (must be <= maxAmount)
     * @param tokenCollector Address of the token collector contract
     * @param collectorData Encoded data for the token collector
     * @notice This is Phase 1 of the two-phase payment flow
     */
    function authorize(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external;

    /**
     * @dev Captures (releases) authorized funds to the receiver
     * @param paymentInfo Same PaymentInfo used in authorize
     * @param amount Amount to capture (can be partial)
     * @param feeBps Fee basis points for this capture
     * @param feeReceiver Address to receive the fee
     * @notice This is Phase 2 of the two-phase payment flow
     */
    function capture(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        uint16 feeBps,
        address feeReceiver
    ) external;

    /**
     * @dev Voids (cancels) an authorized payment
     * @param paymentInfo Payment to void
     * @notice Can only be called by the operator before capture
     */
    function void(PaymentInfo calldata paymentInfo) external;

    /**
     * @dev Refunds authorized funds back to the payer
     * @param paymentInfo Payment to refund
     * @param amount Amount to refund
     * @param tokenCollector Token collector for the refund transfer
     * @param collectorData Data for the token collector
     */
    function refund(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external;

    /**
     * @dev Single-transaction authorize + capture
     * @param paymentInfo Payment details
     * @param amount Amount to charge
     * @param tokenCollector Token collector address
     * @param collectorData Collector data
     * @param feeBps Fee basis points
     * @param feeReceiver Fee recipient
     * @notice Convenience function that combines authorize and capture
     */
    function charge(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        uint16 feeBps,
        address feeReceiver
    ) external;

    /**
     * @dev Gets the current state of a payment
     * @param paymentInfo Payment to query
     * @return state Current payment state
     */
    function getPaymentState(PaymentInfo calldata paymentInfo) 
        external view returns (PaymentState memory state);

    /**
     * @dev Generates a unique hash for a payment
     * @param paymentInfo Payment to hash
     * @return hash Unique payment identifier
     */
    function getPaymentHash(PaymentInfo calldata paymentInfo) 
        external pure returns (bytes32 hash);

    /**
     * @dev Checks if a payment exists and is valid
     * @param paymentInfo Payment to validate
     * @return isValid Whether the payment is valid
     */
    function isValidPayment(PaymentInfo calldata paymentInfo) 
        external view returns (bool isValid);

    // Events
    event PaymentAuthorized(
        bytes32 indexed paymentHash,
        address indexed operator,
        address indexed payer,
        address receiver,
        uint256 amount
    );

    event PaymentCaptured(
        bytes32 indexed paymentHash,
        address indexed operator,
        uint256 amount,
        uint256 fee
    );

    event PaymentVoided(
        bytes32 indexed paymentHash,
        address indexed operator
    );

    event PaymentRefunded(
        bytes32 indexed paymentHash,
        address indexed operator,
        uint256 amount
    );
}

/**
 * @title ITokenCollector
 * @dev Base interface for all token collectors
 * @notice Token collectors handle different authorization methods (Permit2, ERC-3009, etc.)
 */
interface ITokenCollector {
    /**
     * @dev Collects tokens from payer to escrow
     * @param paymentInfo Payment details
     * @param tokenStore Where to store the collected tokens (escrow contract)
     * @param amount Amount to collect
     * @param collectorData Collector-specific data (signatures, permits, etc.)
     */
    function collectTokens(
        IAuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata collectorData
    ) external;

    /**
     * @dev Returns the type identifier for this collector
     * @return collectorType Unique identifier string
     */
    function collectorType() external pure returns (string memory collectorType);
}

/**
 * @title IPermit2PaymentCollector  
 * @dev Permit2-based token collector - Address: 0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26
 * @notice Uses Uniswap Permit2 for gasless token approvals
 */
interface IPermit2PaymentCollector is ITokenCollector {
    /**
     * @dev Data structure for Permit2-based collection
     * @notice This gets encoded as collectorData for collectTokens()
     */
    struct Permit2CollectorData {
        ISignatureTransfer.PermitTransferFrom permit;        // Permit2 permit structure
        ISignatureTransfer.SignatureTransferDetails transferDetails; // Transfer details
        bytes signature;                                      // User's signature
    }

    /**
     * @dev Validates Permit2 data before collection
     * @param permit2Data The permit2 data to validate
     * @return isValid Whether the data is valid
     */
    function validatePermit2Data(Permit2CollectorData calldata permit2Data) 
        external view returns (bool isValid);
}

/**
 * @title IERC3009PaymentCollector
 * @dev ERC-3009 based token collector - Address: 0x0E3dF9510de65469C4518D7843919c0b8C7A7757
 * @notice Uses ERC-3009 transferWithAuthorization for gasless transfers
 */
interface IERC3009PaymentCollector is ITokenCollector {
    /**
     * @dev Data structure for ERC-3009 collection
     */
    struct ERC3009CollectorData {
        address from;           // Token holder
        address to;             // Token recipient (escrow)
        uint256 value;          // Amount to transfer
        uint256 validAfter;     // Valid after timestamp
        uint256 validBefore;    // Valid before timestamp
        bytes32 nonce;          // Unique nonce
        bytes signature;        // Authorization signature
    }
}

/**
 * @title IPreApprovalPaymentCollector
 * @dev Pre-approval based collector - Address: 0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6
 * @notice Uses traditional ERC-20 approvals
 */
interface IPreApprovalPaymentCollector is ITokenCollector {
    /**
     * @dev Data for pre-approved token collection
     * @notice Minimal data needed since approval is already on-chain
     */
    struct PreApprovalCollectorData {
        address spender;        // Who is approved to spend (should be collector)
        uint256 amount;         // Amount to collect
    }
}

/**
 * @title ISpendPermissionPaymentCollector
 * @dev Coinbase spend permission collector - Address: 0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa
 * @notice Uses Coinbase's spend permission system
 */
interface ISpendPermissionPaymentCollector is ITokenCollector {
    /**
     * @dev Data for spend permission collection
     */
    struct SpendPermissionData {
        bytes32 permissionHash;  // Spend permission identifier
        bytes signature;         // Permission signature
        uint256 amount;          // Amount to spend
    }
}

/**
 * @title BaseCommerceProtocolAddresses
 * @dev Contract addresses for Base Commerce Protocol (same on mainnet and testnet)
 */
library BaseCommerceProtocolAddresses {
    // Main escrow contract
    address public constant AUTH_CAPTURE_ESCROW = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;
    
    // Token collectors
    address public constant PERMIT2_COLLECTOR = 0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26;
    address public constant ERC3009_COLLECTOR = 0x0E3dF9510de65469C4518D7843919c0b8C7A7757;
    address public constant PRE_APPROVAL_COLLECTOR = 0x1b77ABd71FCD21fbe2398AE821Aa27D1E6B94bC6;
    address public constant SPEND_PERMISSION_COLLECTOR = 0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa;
}