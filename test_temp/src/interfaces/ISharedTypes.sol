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
        Podcast // 4

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
}
