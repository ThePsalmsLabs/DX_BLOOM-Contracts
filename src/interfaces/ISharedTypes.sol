// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ISharedTypes
 * @dev Central interface for all shared types across the platform
 * @notice This prevents enum conversion errors by ensuring all contracts
 *         use the exact same type definitions
 */
interface ISharedTypes {
    /**
     * @dev Payment types supported by the platform
     * @notice CRITICAL: All contracts must use this single definition
     */
    enum PaymentType {
        PayPerView, // 0
        Subscription, // 1
        Tip, // 2
        Donation // 3

    }

    /**
     * @dev Content categories for classification
     * @notice Ensure consistent ordering across all contracts
     */
    enum ContentCategory {
        Article, // 0
        Video, // 1
        Course, // 2
        Music, // 3
        Podcast, // 4
        Image // 5

    }

    /**
     * @dev Subscription status tracking
     */
    enum SubscriptionStatus {
        Inactive, // 0
        Active, // 1
        Paused, // 2
        Cancelled // 3

    }

    /**
     * @dev Platform payment request structure
     * @notice Used for creating payment intents across the platform
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
     * @dev Payment context linking Commerce Protocol intents to platform actions
     * @notice Used for tracking payment state across manager contracts
     */
    struct PaymentContext {
        PaymentType paymentType; // Type of payment
        address user; // User making the payment
        address creator; // Creator receiving the payment
        uint256 contentId; // Content ID (0 for subscriptions)
        uint256 platformFee; // Platform fee amount
        uint256 creatorAmount; // Amount going to creator
        uint256 operatorFee; // Operator fee amount
        uint256 timestamp; // Payment timestamp
        bool processed; // Whether payment has been processed
        address paymentToken; // Token used for payment
        uint256 expectedAmount; // Expected payment amount
        bytes16 intentId; // The original intent ID from the Commerce Protocol
    }
}
