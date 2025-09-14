// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedTypes } from "./interfaces/ISharedTypes.sol";
import { PayPerView } from "./PayPerView.sol";
import { SubscriptionManager } from "./SubscriptionManager.sol";
import { CreatorRegistry } from "./CreatorRegistry.sol";

/**
 * @title AccessManager
 * @dev Manages content access and subscription logic
 * @notice This contract handles access granting after successful payments
 */
contract AccessManager {

    // ============ STRUCT DEFINITIONS ============

    // PaymentContext struct (mirrored from main contract)
    struct PaymentContext {
        ISharedTypes.PaymentType paymentType;
        address user;
        address creator;
        uint256 contentId;
        uint256 platformFee;
        uint256 creatorAmount;
        uint256 operatorFee;
        uint256 timestamp;
        bool processed;
        address paymentToken;
        uint256 expectedAmount;
        bytes16 intentId;
    }

    // ============ STATE VARIABLES ============

    // Contract references
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    CreatorRegistry public creatorRegistry;

    // Metrics tracking (minimal storage for this contract)
    uint256 public totalPaymentsProcessed;
    uint256 public totalOperatorFees;

    // ============ EVENTS ============

    event ContentAccessGranted(address indexed user, uint256 indexed contentId, bytes16 indexed intentId, address paymentToken, uint256 amountPaid);
    event SubscriptionAccessGranted(address indexed user, address indexed creator, bytes16 indexed intentId, address paymentToken, uint256 amountPaid);
    event PaymentProcessingCompleted(bytes16 indexed intentId, address indexed user, address indexed creator, ISharedTypes.PaymentType paymentType);

    // ============ CONSTRUCTOR ============

    constructor(
        address _payPerView,
        address _subscriptionManager,
        address _creatorRegistry
    ) {
        payPerView = PayPerView(_payPerView);
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        creatorRegistry = CreatorRegistry(_creatorRegistry);
    }





    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets access manager metrics
     */
    function getMetrics() external view returns (
        uint256 paymentsProcessed,
        uint256 operatorFees
    ) {
        return (totalPaymentsProcessed, totalOperatorFees);
    }

    /**
     * @dev Checks if contracts are properly configured
     */
    function isConfigured() external view returns (bool) {
        return address(payPerView) != address(0) &&
               address(subscriptionManager) != address(0) &&
               address(creatorRegistry) != address(0);
    }

    /**
     * @dev Handles successful payment processing
     * @param context The payment context
     * @param intentId The intent ID
     * @param paymentToken The payment token
     * @param amountPaid The amount paid
     * @param operatorFee The operator fee amount
     */
    function handleSuccessfulPayment(
        PaymentContext memory context,
        bytes16 intentId,
        address paymentToken,
        uint256 amountPaid,
        uint256 operatorFee
    ) external {
        // Grant access based on payment type
        if (context.paymentType == ISharedTypes.PaymentType.PayPerView) {
            // Inline content access logic
            if (address(payPerView) != address(0)) {
                try payPerView.completePurchase(intentId, amountPaid, true, "") {
                    emit ContentAccessGranted(context.user, context.contentId, intentId, paymentToken, amountPaid);
                } catch {
                    uint256 totalUsdcAmount = amountPaid;
                    try payPerView.recordExternalPurchase(
                        context.contentId, context.user, intentId, totalUsdcAmount, paymentToken, amountPaid
                    ) {
                        emit ContentAccessGranted(context.user, context.contentId, intentId, paymentToken, amountPaid);
                    } catch Error(string memory reason) {
                        emit PaymentProcessingCompleted(intentId, context.user, address(0), ISharedTypes.PaymentType.PayPerView);
                    } catch (bytes memory lowLevelData) {
                        emit PaymentProcessingCompleted(intentId, context.user, address(0), ISharedTypes.PaymentType.PayPerView);
                    }
                }
            } else {
                emit PaymentProcessingCompleted(intentId, context.user, address(0), ISharedTypes.PaymentType.PayPerView);
            }
        } else if (context.paymentType == ISharedTypes.PaymentType.Subscription) {
            // Inline subscription access logic
            uint256 totalUsdcAmount = context.creatorAmount + context.platformFee;
            if (address(subscriptionManager) != address(0)) {
                try subscriptionManager.recordSubscriptionPayment(
                    context.user, context.creator, intentId, totalUsdcAmount, paymentToken, amountPaid
                ) {
                    emit SubscriptionAccessGranted(context.user, context.creator, intentId, paymentToken, amountPaid);
                } catch Error(string memory reason) {
                    emit PaymentProcessingCompleted(intentId, context.user, context.creator, ISharedTypes.PaymentType.Subscription);
                } catch (bytes memory lowLevelData) {
                    emit PaymentProcessingCompleted(intentId, context.user, context.creator, ISharedTypes.PaymentType.Subscription);
                }
            } else {
                emit PaymentProcessingCompleted(intentId, context.user, context.creator, ISharedTypes.PaymentType.Subscription);
            }
        }

        // Update creator earnings through registry
        try creatorRegistry.updateCreatorStats(
            context.creator,
            context.creatorAmount,
            context.paymentType == ISharedTypes.PaymentType.PayPerView ? int256(1) : int256(0),
            context.paymentType == ISharedTypes.PaymentType.Subscription ? int256(1) : int256(0)
        ) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }

        // Update operator metrics
        totalOperatorFees += operatorFee;
        totalPaymentsProcessed++;
    }
}
