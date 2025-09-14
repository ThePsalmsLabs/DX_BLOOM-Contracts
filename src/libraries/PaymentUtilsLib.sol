// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedTypes } from "../interfaces/ISharedTypes.sol";
import { ICommercePaymentsProtocol, ISignatureTransfer, IPriceOracle } from "../interfaces/IPlatformInterfaces.sol";

/**
 * @title PaymentUtilsLib
 * @dev Library for payment utility functions and calculations
 * @notice This library provides stateless utility functions to reduce
 *         contract size while maintaining calculation accuracy
 */
library PaymentUtilsLib {

    // ============ ENUMS ============

    /**
     * @dev Payment types (mirrored from ISharedTypes)
     */
    enum PaymentType {
        PayPerView, // 0
        Subscription, // 1
        Tip, // 2
        Donation // 3
    }

    // ============ STRUCTS ============

    /**
     * @dev Platform payment request structure (mirrored from ISharedTypes)
     */
    struct PlatformPaymentRequest {
        PaymentType paymentType; // Type of payment
        address creator; // Creator to pay
        uint256 contentId; // Content ID (0 for subscriptions)
        address paymentToken; // Token user wants to pay with
        uint256 maxSlippage; // Maximum slippage for token swaps (basis points)
        uint256 deadline; // Payment deadline
    }

    /**
     * @dev Payment amount calculation result
     */
    struct PaymentAmounts {
        uint256 totalAmount;
        uint256 creatorAmount;
        uint256 platformFee;
        uint256 operatorFee;
        uint256 adjustedCreatorAmount;
        uint256 expectedAmount;
    }

    /**
     * @dev Context for amount calculations
     */
    struct AmountCalculationContext {
        address paymentToken;
        uint256 totalAmount;
        uint256 platformFeeRate;
        uint256 operatorFeeRate;
        uint256 maxSlippage;
    }

    /**
     * @dev Intent creation context
     */
    struct IntentCreationContext {
        address user;
        address creator;
        uint256 contentId;
        PaymentType paymentType;
        uint256 deadline;
        address paymentToken;
    }

    // ============ AMOUNT CALCULATIONS ============

    /**
     * @dev Calculates all payment amounts in a single operation
     * @param context Amount calculation context
     * @param priceOracle Price oracle contract (passed to avoid storage access)
     * @return amounts Complete payment amount breakdown
     */
    function calculateAllPaymentAmounts(
        AmountCalculationContext memory context,
        address priceOracle
    ) internal returns (PaymentAmounts memory amounts) {
        // Get total amount based on payment type (would need to be passed or calculated externally)
        amounts.totalAmount = context.totalAmount;

        // Calculate platform fee
        amounts.platformFee = (amounts.totalAmount * context.platformFeeRate) / 10000;

        // Calculate creator amount before operator fee
        amounts.creatorAmount = amounts.totalAmount - amounts.platformFee;

        // Calculate operator fee
        amounts.operatorFee = (amounts.totalAmount * context.operatorFeeRate) / 10000;

        // Calculate adjusted creator amount (after all fees)
        amounts.adjustedCreatorAmount = amounts.creatorAmount - amounts.operatorFee;

        // Calculate expected payment amount with slippage
        amounts.expectedAmount = calculateExpectedPaymentAmount(
            context.paymentToken,
            amounts.totalAmount,
            context.maxSlippage,
            priceOracle
        );

        return amounts;
    }

    /**
     * @dev Calculates expected payment amount with real price oracle integration
     * @param paymentToken Token user wants to pay with (address(0) for ETH)
     * @param usdcAmount Amount of USDC the payment represents
     * @param maxSlippage Maximum slippage tolerance in basis points  
     * @param priceOracle Address of price oracle contract
     * @return expectedAmount Expected amount to pay including slippage
     */
    function calculateExpectedPaymentAmount(
        address paymentToken,
        uint256 usdcAmount,
        uint256 maxSlippage,
        address priceOracle
    ) internal returns (uint256 expectedAmount) {
        // Import the price oracle interface
        IPriceOracle oracle = IPriceOracle(priceOracle);
        
        if (paymentToken == address(0)) {
            // ETH payment - get real ETH price from oracle
            try oracle.getETHPrice(usdcAmount) returns (uint256 ethAmount) {
                return applySlippage(ethAmount, maxSlippage);
            } catch {
                // Fallback: revert if we can't get price (safer than placeholder)
                revert("ETH price oracle failed");
            }
        } else {
            // Get USDC address from oracle to check for 1:1 case
            try oracle.USDC() returns (address usdcAddr) {
                if (paymentToken == usdcAddr) {
                    // USDC-to-USDC is 1:1, just apply slippage for gas variance
                    return applySlippage(usdcAmount, maxSlippage);
                }
            } catch {
                // Continue with token price lookup if USDC check fails
            }
            
            // Token payment - get real token price from oracle
            try oracle.getTokenAmountForUSDC(paymentToken, usdcAmount, 0) returns (uint256 tokenAmount) {
                return applySlippage(tokenAmount, maxSlippage);
            } catch {
                // Fallback: revert if we can't get price (safer than placeholder)
                revert("Token price oracle failed");
            }
        }
    }

    /**
     * @dev Applies slippage tolerance to an amount
     * @param amount Base amount
     * @param slippageBps Slippage in basis points
     * @return adjustedAmount Amount with slippage applied
     */
    function applySlippage(uint256 amount, uint256 slippageBps) internal pure returns (uint256 adjustedAmount) {
        if (slippageBps > 10000) revert("Invalid slippage");
        return amount + (amount * slippageBps) / 10000;
    }

    // ============ INTENT CREATION HELPERS ============

    /**
     * @dev Generates a standardized intent ID
     * @param context Intent creation context
     * @param nonce User nonce for uniqueness
     * @param contractAddress Contract address for uniqueness
     * @return intentId Generated intent ID
     */
    function generateStandardIntentId(
        IntentCreationContext memory context,
        uint256 nonce,
        address contractAddress
    ) internal view returns (bytes16 intentId) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                context.user,
                context.creator,
                context.contentId,
                uint256(context.paymentType),
                nonce,
                contractAddress,
                block.timestamp,
                block.chainid
            )
        );
        return bytes16(hash);
    }

    /**
     * @dev Prepares intent for operator signing
     * @param intent The transfer intent
     * @param signer The EIP-712 signer contract
     * @return intentHash Hash for operator to sign
     */
    function prepareIntentForSigning(
        ICommercePaymentsProtocol.TransferIntent memory intent,
        address signer
    ) internal view returns (bytes32 intentHash) {
        // This would prepare the intent hash for EIP-712 signing
        // Implementation would depend on the specific signing scheme used
        return keccak256(abi.encodePacked(
            intent.recipientAmount,
            intent.deadline,
            intent.recipient,
            intent.recipientCurrency,
            intent.refundDestination,
            intent.feeAmount,
            intent.id,
            intent.operator
        ));
    }

    // ============ SIGNATURE RECOVERY ============

    /**
     * @dev Recovers signer from signature
     * @param hash Hash that was signed
     * @param signature Signature to recover from
     * @return signer Recovered signer address
     */
    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            if (v == 0 || v == 1) v += 27;
            else return address(0);
        }

        if (v != 27 && v != 28) return address(0);

        return ecrecover(hash, v, r, s);
    }

    // ============ PAYMENT TYPE HELPERS ============

    /**
     * @dev Validates payment type enum value
     * @param paymentType The payment type to validate
     * @return isValid Whether the payment type is valid
     */
    function validatePaymentType(PaymentType paymentType) internal pure returns (bool isValid) {
        return uint8(paymentType) <= uint8(PaymentType.Donation);
    }

    /**
     * @dev Gets payment type name for logging
     * @param paymentType The payment type
     * @return name Human-readable name
     */
    function getPaymentTypeName(PaymentType paymentType) internal pure returns (string memory name) {
        if (paymentType == PaymentType.PayPerView) return "PayPerView";
        if (paymentType == PaymentType.Subscription) return "Subscription";
        if (paymentType == PaymentType.Tip) return "Tip";
        if (paymentType == PaymentType.Donation) return "Donation";
        return "Unknown";
    }

    // ============ DEADLINE VALIDATION ============

    /**
     * @dev Validates deadline is reasonable
     * @param deadline The deadline to validate
     * @param maxFutureTime Maximum allowed future time (e.g., 7 days)
     * @return isValid Whether deadline is valid
     */
    function validateDeadline(uint256 deadline, uint256 maxFutureTime) internal view returns (bool isValid) {
        if (deadline <= block.timestamp) return false;
        if (deadline > block.timestamp + maxFutureTime) return false;
        return true;
    }

    /**
     * @dev Checks if deadline has expired
     * @param deadline The deadline to check
     * @return isExpired Whether the deadline has expired
     */
    function isDeadlineExpired(uint256 deadline) internal view returns (bool isExpired) {
        return block.timestamp > deadline;
    }

    // ============ AMOUNT ROUNDING ============

    /**
     * @dev Safely rounds down amount to prevent dust
     * @param amount Amount to round
     * @param decimals Target decimals
     * @return roundedAmount Rounded amount
     */
    function roundDown(uint256 amount, uint8 decimals) internal pure returns (uint256 roundedAmount) {
        uint256 divisor = 10 ** decimals;
        return (amount / divisor) * divisor;
    }

    /**
     * @dev Safely rounds up amount to ensure sufficient payment
     * @param amount Amount to round
     * @param decimals Target decimals
     * @return roundedAmount Rounded amount
     */
    function roundUp(uint256 amount, uint8 decimals) internal pure returns (uint256 roundedAmount) {
        uint256 divisor = 10 ** decimals;
        uint256 remainder = amount % divisor;
        if (remainder == 0) {
            return amount;
        }
        return amount + (divisor - remainder);
    }

    /**
     * @dev Calculates basic payment amounts when given the required data
     * @param paymentType The type of payment
     * @param contentPrice Price for PayPerView content (0 for subscriptions)
     * @param subscriptionPrice Price for subscription (0 for content)
     * @param platformFeeRate The platform fee rate in basis points
     * @return totalAmount Total amount to pay
     * @return creatorAmount Amount going to creator
     * @return platformFee Platform fee amount
     */
    function calculateBasicPaymentAmounts(
        ISharedTypes.PaymentType paymentType,
        uint256 contentPrice,
        uint256 subscriptionPrice,
        uint256 platformFeeRate
    ) external pure returns (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) {
        if (paymentType == ISharedTypes.PaymentType.PayPerView) {
            totalAmount = contentPrice;
        } else {
            totalAmount = subscriptionPrice;
        }

        // Calculate platform fee
        platformFee = (totalAmount * platformFeeRate) / 10000;
        creatorAmount = totalAmount - platformFee;

        return (totalAmount, creatorAmount, platformFee);
    }

    // ============ CONSTANTS ============

    /// @notice Maximum allowed future deadline (7 days)
    uint256 internal constant MAX_DEADLINE_FUTURE = 7 days;

    /// @notice Maximum slippage allowed (10%)
    uint256 internal constant MAX_SLIPPAGE = 1000; // 10% in basis points

    /// @notice Platform fee denominator (10000 = 100%)
    uint256 internal constant FEE_DENOMINATOR = 10000;
}
