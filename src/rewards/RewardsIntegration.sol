// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RewardsTreasury.sol";
import "./LoyaltyManager.sol";
import "../interfaces/ISharedTypes.sol";
import "../CommerceProtocolCore.sol";

/**
 * @title RewardsIntegration
 * @dev Integration layer between commerce protocol and rewards system
 * @notice Handles automatic revenue collection and reward distribution
 */
contract RewardsIntegration is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant INTEGRATION_MANAGER_ROLE = keccak256("INTEGRATION_MANAGER_ROLE");
    bytes32 public constant REWARDS_TRIGGER_ROLE = keccak256("REWARDS_TRIGGER_ROLE");

    // ============ CONTRACT REFERENCES ============
    RewardsTreasury public immutable rewardsTreasury;
    LoyaltyManager public immutable loyaltyManager;
    CommerceProtocolCore public immutable commerceProtocol;

    // ============ CONFIGURATION ============
    bool public autoDistributeRevenue = true;
    bool public autoAwardLoyaltyPoints = true;
    uint256 public minPurchaseForRewards = 1e6; // $1 USDC minimum

    // ============ EVENTS ============
    event RevenueAutoDistributed(uint256 amount, uint256 timestamp);
    event LoyaltyPointsAutoAwarded(address indexed user, uint256 points, uint256 purchaseAmount);
    event IntegrationConfigured(bool autoRevenue, bool autoLoyalty);

    // ============ CONSTRUCTOR ============
    constructor(
        address _rewardsTreasury,
        address _loyaltyManager,
        address _commerceProtocol
    ) {
        rewardsTreasury = RewardsTreasury(_rewardsTreasury);
        loyaltyManager = LoyaltyManager(_loyaltyManager);
        commerceProtocol = CommerceProtocolCore(_commerceProtocol);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INTEGRATION_MANAGER_ROLE, msg.sender);
        _grantRole(REWARDS_TRIGGER_ROLE, address(_commerceProtocol));
    }

    /**
     * @dev Hook called after successful payment to distribute rewards
     * @param intentId The payment intent ID
     * @param context Payment context information
     */
    function onPaymentSuccess(
        bytes16 intentId,
        ISharedTypes.PaymentContext memory context
    ) external onlyRole(REWARDS_TRIGGER_ROLE) nonReentrant {
        require(context.processed && context.paymentToken == address(rewardsTreasury.usdcToken()),
                "Invalid payment context");

        // Distribute platform revenue to treasury
        if (autoDistributeRevenue && context.platformFee > 0) {
            _distributePlatformRevenue(context.platformFee);
        }

        // Award loyalty points for purchases
        if (autoAwardLoyaltyPoints && context.expectedAmount >= minPurchaseForRewards) {
            _awardLoyaltyPoints(context.user, context.expectedAmount, context.paymentType);
        }
    }

    /**
     * @dev Distributes platform fee to rewards treasury
     */
    function _distributePlatformRevenue(uint256 platformFee) internal {
        // Approve treasury to pull funds
        IERC20(address(rewardsTreasury.usdcToken())).forceApprove(address(rewardsTreasury), platformFee);

        // Deposit revenue (this will automatically allocate to pools)
        rewardsTreasury.depositPlatformRevenue(platformFee, address(commerceProtocol));

        emit RevenueAutoDistributed(platformFee, block.timestamp);
    }

    /**
     * @dev Awards loyalty points for successful purchases
     */
    function _awardLoyaltyPoints(
        address user,
        uint256 purchaseAmount,
        ISharedTypes.PaymentType paymentType
    ) internal {
        loyaltyManager.awardPurchasePoints(user, purchaseAmount, paymentType);

        // Calculate points awarded for event
        uint256 pointsEarned = _calculatePointsEarned(user, purchaseAmount, paymentType);

        emit LoyaltyPointsAutoAwarded(user, pointsEarned, purchaseAmount);
    }

    /**
     * @dev Calculates points that would be earned (for event logging)
     */
    function _calculatePointsEarned(
        address user,
        uint256 purchaseAmount,
        ISharedTypes.PaymentType paymentType
    ) internal view returns (uint256) {
        uint256 basePoints = (purchaseAmount * loyaltyManager.pointsPerDollarSpent()) / 1e6;

        // Get user's current tier for multiplier
        (, , LoyaltyManager.LoyaltyTier tier, , , , ) = loyaltyManager.getUserStats(user);

        uint256 multiplier = _getTierMultiplier(tier);
        uint256 finalPoints = (basePoints * multiplier) / 100;

        // Subscription bonus
        if (paymentType == ISharedTypes.PaymentType.Subscription) {
            finalPoints = (finalPoints * loyaltyManager.subscriptionBonusMultiplier()) / 100;
        }

        return finalPoints;
    }

    /**
     * @dev Gets tier multiplier for points calculation
     */
    function _getTierMultiplier(LoyaltyManager.LoyaltyTier tier) internal pure returns (uint256) {
        if (tier == LoyaltyManager.LoyaltyTier.Bronze) return 100;
        if (tier == LoyaltyManager.LoyaltyTier.Silver) return 110;
        if (tier == LoyaltyManager.LoyaltyTier.Gold) return 125;
        if (tier == LoyaltyManager.LoyaltyTier.Platinum) return 150;
        if (tier == LoyaltyManager.LoyaltyTier.Diamond) return 200;
        return 100;
    }

    /**
     * @dev Applies loyalty discount to a purchase amount
     * @param user User requesting discount
     * @param originalAmount Original purchase amount
     * @param usePoints Whether to use loyalty points for additional discount
     * @param pointsToUse Number of points to use (if usePoints is true)
     */
    function applyLoyaltyDiscount(
        address user,
        uint256 originalAmount,
        bool usePoints,
        uint256 pointsToUse
    ) external onlyRole(REWARDS_TRIGGER_ROLE) returns (uint256 discountedAmount) {
        return loyaltyManager.applyDiscount(user, originalAmount, usePoints, pointsToUse);
    }

    /**
     * @dev Gets loyalty discount preview without applying it
     */
    function getLoyaltyDiscount(
        address user,
        uint256 originalAmount
    ) external view returns (uint256 discountAmount, uint256 finalAmount) {
        return loyaltyManager.calculateDiscount(user, originalAmount);
    }

    /**
     * @dev Calculates discounted price for a user based on loyalty tier
     * @param user User address to calculate discount for
     * @param originalAmount Original payment amount
     * @return discountedAmount Final amount after applying loyalty discount
     */
    function calculateDiscountedPrice(
        address user,
        uint256 originalAmount
    ) external view returns (uint256 discountedAmount) {
        (, uint256 finalAmount) = loyaltyManager.calculateDiscount(user, originalAmount);
        return finalAmount;
    }

    /**
     * @dev Triggers referral bonus when a new user makes their first purchase
     */
    function processReferralBonus(
        address referrer,
        address newUser,
        uint256 firstPurchaseAmount
    ) external onlyRole(REWARDS_TRIGGER_ROLE) {
        loyaltyManager.awardReferralPoints(referrer, newUser);
    }

    /**
     * @dev Updates integration configuration
     */
    function updateConfiguration(
        bool _autoDistributeRevenue,
        bool _autoAwardLoyaltyPoints,
        uint256 _minPurchaseForRewards
    ) external onlyRole(INTEGRATION_MANAGER_ROLE) {
        autoDistributeRevenue = _autoDistributeRevenue;
        autoAwardLoyaltyPoints = _autoAwardLoyaltyPoints;
        minPurchaseForRewards = _minPurchaseForRewards;

        emit IntegrationConfigured(_autoDistributeRevenue, _autoAwardLoyaltyPoints);
    }

    /**
     * @dev Emergency pause of auto-distribution
     */
    function emergencyPause() external onlyRole(INTEGRATION_MANAGER_ROLE) {
        autoDistributeRevenue = false;
        autoAwardLoyaltyPoints = false;
        emit IntegrationConfigured(false, false);
    }

    /**
     * @dev Resume auto-distribution after emergency pause
     */
    function resumeIntegration() external onlyRole(INTEGRATION_MANAGER_ROLE) {
        autoDistributeRevenue = true;
        autoAwardLoyaltyPoints = true;
        emit IntegrationConfigured(true, true);
    }

    /**
     * @dev Gets integration statistics
     */
    function getIntegrationStats() external view returns (
        bool revenueAutoDistribute,
        bool loyaltyAutoAward,
        uint256 minPurchaseThreshold,
        address treasuryAddress,
        address loyaltyManagerAddress
    ) {
        return (
            autoDistributeRevenue,
            autoAwardLoyaltyPoints,
            minPurchaseForRewards,
            address(rewardsTreasury),
            address(loyaltyManager)
        );
    }
}

// Library for additional integration functionality
library RewardsIntegrationLib {
    function calculateEffectiveDiscount(
        uint256 originalAmount,
        uint256 tierDiscountBps,
        uint256 pointsDiscount
    ) internal pure returns (uint256) {
        uint256 tierDiscount = (originalAmount * tierDiscountBps) / 10000;
        return tierDiscount + pointsDiscount;
    }
}
