// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./RewardsTreasury.sol";
import "../interfaces/ISharedTypes.sol";

/**
 * @title LoyaltyManager
 * @dev Manages customer loyalty program with points, tiers, and rewards
 * @notice Handles points earning, tier progression, and discount calculations
 */
contract LoyaltyManager is AccessControl, ReentrancyGuard {
    // Library dependency will be added once implemented

    // ============ ROLES ============
    bytes32 public constant POINTS_MANAGER_ROLE = keccak256("POINTS_MANAGER_ROLE");
    bytes32 public constant DISCOUNT_MANAGER_ROLE = keccak256("DISCOUNT_MANAGER_ROLE");

    // ============ LOYALTY TIERS ============
    enum LoyaltyTier {
        Bronze,   // 0-999 points
        Silver,   // 1000-4999 points
        Gold,     // 5000-19999 points
        Platinum, // 20000-49999 points
        Diamond   // 50000+ points (VIP)
    }

    // ============ USER LOYALTY DATA ============
    struct UserLoyalty {
        uint256 totalPoints;
        uint256 availablePoints;
        LoyaltyTier currentTier;
        uint256 totalSpent;
        uint256 purchaseCount;
        uint256 lastActivityTime;
        uint256 referralCount;
        bool isActive;
        uint256 joinTimestamp;
    }

    // ============ TIER BENEFITS ============
    struct TierBenefits {
        uint256 discountBps;        // Discount in basis points (e.g., 500 = 5%)
        uint256 pointsMultiplier;   // Points earned multiplier (e.g., 150 = 1.5x)
        uint256 cashbackBps;        // Cashback percentage
        uint256 earlyAccessHours;   // Early access to new content (hours)
        bool freeTransactionFees;   // Free platform fees
        uint256 monthlyBonus;       // Monthly bonus points
        uint256 referralBonus;      // Bonus points for successful referrals
    }

    // ============ STORAGE ============
    mapping(address => UserLoyalty) public userLoyalty;
    mapping(LoyaltyTier => TierBenefits) public tierBenefits;
    mapping(address => mapping(uint256 => bool)) public hasEarlyAccess;
    mapping(LoyaltyTier => uint256) public tierThresholds;

    // ============ CONFIGURATION ============
    uint256 public pointsPerDollarSpent = 100;  // 100 points per $1 USDC spent
    uint256 public referralBonusPoints = 500;   // 500 points for successful referral
    uint256 public dailyLoginPoints = 10;       // 10 points for daily login
    uint256 public subscriptionBonusMultiplier = 120; // 20% bonus for subscriptions

    RewardsTreasury public immutable rewardsTreasury;

    // ============ EVENTS ============
    event PointsEarned(address indexed user, uint256 points, string reason);
    event PointsSpent(address indexed user, uint256 points, string reason);
    event TierUpgraded(address indexed user, LoyaltyTier oldTier, LoyaltyTier newTier);
    event DiscountApplied(address indexed user, uint256 discountAmount, uint256 originalPrice);
    event ReferralBonus(address indexed referrer, address indexed referee, uint256 bonusPoints);
    event EarlyAccessGranted(address indexed user, uint256 contentId, uint256 accessHours);

    // ============ CONSTRUCTOR ============
    constructor(address _rewardsTreasury) {
        rewardsTreasury = RewardsTreasury(_rewardsTreasury);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupTierBenefits();
        _setupTierThresholds();
    }

    /**
     * @dev Awards points for purchase activity
     * @param user Address of the user
     * @param amountSpent Amount spent in USDC (6 decimals)
     * @param paymentType Type of payment made
     */
    function awardPurchasePoints(
        address user,
        uint256 amountSpent,
        ISharedTypes.PaymentType paymentType
    ) external onlyRole(POINTS_MANAGER_ROLE) {
        UserLoyalty storage loyalty = userLoyalty[user];

        // Initialize user if first time
        if (!loyalty.isActive) {
            loyalty.isActive = true;
            loyalty.joinTimestamp = block.timestamp;
        }

        // Calculate base points (amountSpent is in USDC with 6 decimals)
        uint256 basePoints = (amountSpent * pointsPerDollarSpent) / 1e6;

        // Apply tier multiplier
        TierBenefits memory benefits = tierBenefits[loyalty.currentTier];
        uint256 finalPoints = (basePoints * benefits.pointsMultiplier) / 100;

        // Bonus points for certain payment types
        if (paymentType == ISharedTypes.PaymentType.Subscription) {
            finalPoints = (finalPoints * subscriptionBonusMultiplier) / 100;
        }

        // Update user data
        loyalty.totalPoints += finalPoints;
        loyalty.availablePoints += finalPoints;
        loyalty.totalSpent += amountSpent;
        loyalty.purchaseCount += 1;
        loyalty.lastActivityTime = block.timestamp;

        // Check for tier upgrade
        _checkTierUpgrade(user);

        emit PointsEarned(user, finalPoints, "Purchase");
    }

    /**
     * @dev Awards referral bonus points
     */
    function awardReferralPoints(address referrer, address referee)
        external
        onlyRole(POINTS_MANAGER_ROLE)
    {
        UserLoyalty storage referrerLoyalty = userLoyalty[referrer];
        UserLoyalty storage refereeLoyalty = userLoyalty[referee];

        // Award bonus to referrer
        referrerLoyalty.totalPoints += referralBonusPoints;
        referrerLoyalty.availablePoints += referralBonusPoints;
        referrerLoyalty.referralCount += 1;

        // Award initial points to referee
        if (!refereeLoyalty.isActive) {
            refereeLoyalty.isActive = true;
            refereeLoyalty.joinTimestamp = block.timestamp;
        }
        refereeLoyalty.totalPoints += referralBonusPoints / 2; // Half bonus for referee
        refereeLoyalty.availablePoints += referralBonusPoints / 2;

        emit ReferralBonus(referrer, referee, referralBonusPoints);
        emit PointsEarned(referrer, referralBonusPoints, "Referral");
        emit PointsEarned(referee, referralBonusPoints / 2, "Referral Welcome");
    }

    /**
     * @dev Calculates discount for user based on tier
     */
    function calculateDiscount(address user, uint256 originalPrice)
        external
        view
        returns (uint256 discountAmount, uint256 finalPrice)
    {
        UserLoyalty storage loyalty = userLoyalty[user];
        if (!loyalty.isActive) return (0, originalPrice);

        TierBenefits memory benefits = tierBenefits[loyalty.currentTier];

        discountAmount = (originalPrice * benefits.discountBps) / 10000;
        finalPrice = originalPrice - discountAmount;

        return (discountAmount, finalPrice);
    }

    /**
     * @dev Applies discount and deducts points if used
     */
    function applyDiscount(
        address user,
        uint256 originalPrice,
        bool usePoints,
        uint256 pointsToUse
    ) external onlyRole(DISCOUNT_MANAGER_ROLE) returns (uint256 finalPrice) {
        UserLoyalty storage loyalty = userLoyalty[user];
        require(loyalty.isActive, "User not in loyalty program");

        // Apply tier discount
        (uint256 tierDiscount, uint256 priceAfterTierDiscount) =
            this.calculateDiscount(user, originalPrice);

        // Apply points discount if requested
        uint256 pointsDiscount = 0;
        if (usePoints && pointsToUse > 0) {
            require(loyalty.availablePoints >= pointsToUse, "Insufficient points");

            // 1000 points = $1 USDC discount
            pointsDiscount = pointsToUse / 1000;
            if (pointsDiscount > priceAfterTierDiscount) {
                pointsDiscount = priceAfterTierDiscount;
                pointsToUse = pointsDiscount * 1000;
            }

            loyalty.availablePoints -= pointsToUse;
            emit PointsSpent(user, pointsToUse, "Discount");
        }

        finalPrice = priceAfterTierDiscount - pointsDiscount;

        emit DiscountApplied(user, tierDiscount + pointsDiscount, originalPrice);
        return finalPrice;
    }

    /**
     * @dev Grants early access to content for eligible users
     */
    function grantEarlyAccess(address user, uint256 contentId)
        external
        onlyRole(DISCOUNT_MANAGER_ROLE)
    {
        UserLoyalty storage loyalty = userLoyalty[user];
        require(loyalty.isActive, "User not in loyalty program");

        TierBenefits memory benefits = tierBenefits[loyalty.currentTier];
        require(benefits.earlyAccessHours > 0, "User not eligible for early access");

        hasEarlyAccess[user][contentId] = true;

        emit EarlyAccessGranted(user, contentId, benefits.earlyAccessHours);
    }

    /**
     * @dev Checks and upgrades user tier if eligible
     */
    function _checkTierUpgrade(address user) internal {
        UserLoyalty storage loyalty = userLoyalty[user];
        LoyaltyTier oldTier = loyalty.currentTier;
        LoyaltyTier newTier = _calculateTier(loyalty.totalPoints);

        if (newTier != oldTier) {
            loyalty.currentTier = newTier;

            // Award tier upgrade bonus
            uint256 upgradeBonus = _getTierUpgradeBonus(newTier);
            if (upgradeBonus > 0) {
                loyalty.totalPoints += upgradeBonus;
                loyalty.availablePoints += upgradeBonus;
                emit PointsEarned(user, upgradeBonus, "Tier Upgrade Bonus");
            }

            emit TierUpgraded(user, oldTier, newTier);
        }
    }

    /**
     * @dev Calculates appropriate tier based on total points
     */
    function _calculateTier(uint256 totalPoints) internal view returns (LoyaltyTier) {
        if (totalPoints >= tierThresholds[LoyaltyTier.Diamond]) return LoyaltyTier.Diamond;
        if (totalPoints >= tierThresholds[LoyaltyTier.Platinum]) return LoyaltyTier.Platinum;
        if (totalPoints >= tierThresholds[LoyaltyTier.Gold]) return LoyaltyTier.Gold;
        if (totalPoints >= tierThresholds[LoyaltyTier.Silver]) return LoyaltyTier.Silver;
        return LoyaltyTier.Bronze;
    }

    /**
     * @dev Gets tier upgrade bonus amount
     */
    function _getTierUpgradeBonus(LoyaltyTier newTier) internal pure returns (uint256) {
        if (newTier == LoyaltyTier.Silver) return 200;
        if (newTier == LoyaltyTier.Gold) return 500;
        if (newTier == LoyaltyTier.Platinum) return 1000;
        if (newTier == LoyaltyTier.Diamond) return 2500;
        return 0;
    }

    /**
     * @dev Setup tier benefits configuration
     */
    function _setupTierBenefits() internal {
        // Bronze (0-999 points)
        tierBenefits[LoyaltyTier.Bronze] = TierBenefits({
            discountBps: 100,        // 1% discount
            pointsMultiplier: 100,   // 1x points
            cashbackBps: 50,         // 0.5% cashback
            earlyAccessHours: 0,     // No early access
            freeTransactionFees: false,
            monthlyBonus: 0,         // No monthly bonus
            referralBonus: 100       // 100 bonus referral points
        });

        // Silver (1000-4999 points)
        tierBenefits[LoyaltyTier.Silver] = TierBenefits({
            discountBps: 250,        // 2.5% discount
            pointsMultiplier: 110,   // 1.1x points
            cashbackBps: 100,        // 1% cashback
            earlyAccessHours: 6,     // 6 hours early access
            freeTransactionFees: false,
            monthlyBonus: 100,       // 100 bonus points monthly
            referralBonus: 150       // 150 bonus referral points
        });

        // Gold (5000-19999 points)
        tierBenefits[LoyaltyTier.Gold] = TierBenefits({
            discountBps: 500,        // 5% discount
            pointsMultiplier: 125,   // 1.25x points
            cashbackBps: 150,        // 1.5% cashback
            earlyAccessHours: 24,    // 24 hours early access
            freeTransactionFees: true,
            monthlyBonus: 250,       // 250 bonus points monthly
            referralBonus: 200       // 200 bonus referral points
        });

        // Platinum (20000-49999 points)
        tierBenefits[LoyaltyTier.Platinum] = TierBenefits({
            discountBps: 750,        // 7.5% discount
            pointsMultiplier: 150,   // 1.5x points
            cashbackBps: 200,        // 2% cashback
            earlyAccessHours: 72,    // 3 days early access
            freeTransactionFees: true,
            monthlyBonus: 500,       // 500 bonus points monthly
            referralBonus: 300       // 300 bonus referral points
        });

        // Diamond (50000+ points) - VIP
        tierBenefits[LoyaltyTier.Diamond] = TierBenefits({
            discountBps: 1000,       // 10% discount
            pointsMultiplier: 200,   // 2x points
            cashbackBps: 300,        // 3% cashback
            earlyAccessHours: 168,   // 1 week early access
            freeTransactionFees: true,
            monthlyBonus: 1000,      // 1000 bonus points monthly
            referralBonus: 500       // 500 bonus referral points
        });
    }

    /**
     * @dev Setup tier thresholds
     */
    function _setupTierThresholds() internal {
        tierThresholds[LoyaltyTier.Bronze] = 0;
        tierThresholds[LoyaltyTier.Silver] = 1000;
        tierThresholds[LoyaltyTier.Gold] = 5000;
        tierThresholds[LoyaltyTier.Platinum] = 20000;
        tierThresholds[LoyaltyTier.Diamond] = 50000;
    }

    /**
     * @dev Gets user loyalty statistics
     */
    function getUserStats(address user) external view returns (
        uint256 totalPoints,
        uint256 availablePoints,
        LoyaltyTier currentTier,
        uint256 totalSpent,
        uint256 purchaseCount,
        uint256 tierDiscountBps,
        bool freeFees
    ) {
        UserLoyalty storage loyalty = userLoyalty[user];
        TierBenefits storage benefits = tierBenefits[loyalty.currentTier];

        return (
            loyalty.totalPoints,
            loyalty.availablePoints,
            loyalty.currentTier,
            loyalty.totalSpent,
            loyalty.purchaseCount,
            benefits.discountBps,
            benefits.freeTransactionFees
        );
    }
}

// Library for additional loyalty functionality
library LoyaltyManagerLib {
    function getTierBenefits(LoyaltyManager.TierBenefits storage benefits)
        internal
        view
        returns (uint256 cashbackBps)
    {
        return benefits.cashbackBps;
    }
}
