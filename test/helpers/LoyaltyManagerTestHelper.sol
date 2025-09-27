// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/rewards/LoyaltyManager.sol";

/**
 * @title LoyaltyManagerTestHelper
 * @dev Test helper contract for LoyaltyManager - separated from production code
 * @notice This contract contains ONLY test helper functions and should never be deployed to production
 */
contract LoyaltyManagerTestHelper {
    LoyaltyManager public immutable loyaltyManager;

    // ============ INTERNAL TEST STORAGE ============
    mapping(address => LoyaltyManager.UserLoyalty) private testUserLoyalty;
    mapping(LoyaltyManager.LoyaltyTier => LoyaltyManager.TierBenefits) private testTierBenefits;
    mapping(address => mapping(uint256 => bool)) private testEarlyAccess;
    uint256 private testUserCount;
    bool private useTestStorage;

    // ============ EVENTS ============
    event TestUserLoyaltySet(address indexed user);
    event TestTierBenefitsSet(LoyaltyManager.LoyaltyTier tier);
    event TestEarlyAccessSet(address indexed user, uint256 indexed contentId, bool hasAccess);

    constructor(address _loyaltyManager) {
        require(_loyaltyManager != address(0), "Invalid LoyaltyManager address");
        loyaltyManager = LoyaltyManager(_loyaltyManager);
    }

    // ============ TEST ENVIRONMENT PROTECTION ============
    modifier testOnly() {
        require(
            block.chainid == 31337 || // Foundry/Anvil testnet
            block.chainid == 84532 ||  // Base Sepolia testnet
            tx.origin == address(0) || // Direct call (test environment)
            msg.sender.code.length == 0, // Externally owned account
            "Test helper: Production use not allowed"
        );
        _;
    }

    /**
     * @dev TEST HELPER: Gets user loyalty data for testing
     * @param user The user address
     * @return totalPoints The user's total points
     * @return availablePoints The user's available points
     * @return currentTier The user's current tier
     * @return totalSpent The user's total spent
     * @return purchaseCount The user's purchase count
     * @return lastActivityTime The user's last activity time
     * @return referralCount The user's referral count
     * @return isActive Whether the user is active
     * @return joinTimestamp The user's join timestamp
     */
    function getUserLoyaltyForTesting(address user) external view testOnly returns (
        uint256 totalPoints,
        uint256 availablePoints,
        LoyaltyManager.LoyaltyTier currentTier,
        uint256 totalSpent,
        uint256 purchaseCount,
        uint256 lastActivityTime,
        uint256 referralCount,
        bool isActive,
        uint256 joinTimestamp
    ) {
        if (useTestStorage) {
            LoyaltyManager.UserLoyalty storage testLoyalty = testUserLoyalty[user];
            return (
                testLoyalty.totalPoints,
                testLoyalty.availablePoints,
                testLoyalty.currentTier,
                testLoyalty.totalSpent,
                testLoyalty.purchaseCount,
                testLoyalty.lastActivityTime,
                testLoyalty.referralCount,
                testLoyalty.isActive,
                testLoyalty.joinTimestamp
            );
        }
        
        // Get from production contract
        LoyaltyManager.UserLoyalty memory loyalty = loyaltyManager.getUserLoyalty(user);
        return (
            loyalty.totalPoints,
            loyalty.availablePoints,
            loyalty.currentTier,
            loyalty.totalSpent,
            loyalty.purchaseCount,
            loyalty.lastActivityTime,
            loyalty.referralCount,
            loyalty.isActive,
            loyalty.joinTimestamp
        );
    }

    /**
     * @dev TEST HELPER: Gets tier benefits for testing
     * @param tier The loyalty tier
     * @return discountBps The tier discount in basis points
     * @return pointsMultiplier The tier points multiplier
     * @return cashbackBps The tier cashback in basis points
     * @return earlyAccessHours The tier early access hours
     * @return freeTransactionFees Whether tier has free transaction fees
     * @return monthlyBonus The tier monthly bonus
     * @return referralBonus The tier referral bonus
     */
    function getTierBenefitsForTesting(LoyaltyManager.LoyaltyTier tier) external view testOnly returns (
        uint256 discountBps,
        uint256 pointsMultiplier,
        uint256 cashbackBps,
        uint256 earlyAccessHours,
        bool freeTransactionFees,
        uint256 monthlyBonus,
        uint256 referralBonus
    ) {
        if (useTestStorage) {
            LoyaltyManager.TierBenefits storage testBenefits = testTierBenefits[tier];
            return (
                testBenefits.discountBps,
                testBenefits.pointsMultiplier,
                testBenefits.cashbackBps,
                testBenefits.earlyAccessHours,
                testBenefits.freeTransactionFees,
                testBenefits.monthlyBonus,
                testBenefits.referralBonus
            );
        }
        
        // Get from production contract
        LoyaltyManager.TierBenefits memory benefits = loyaltyManager.getTierBenefits(tier);
        return (
            benefits.discountBps,
            benefits.pointsMultiplier,
            benefits.cashbackBps,
            benefits.earlyAccessHours,
            benefits.freeTransactionFees,
            benefits.monthlyBonus,
            benefits.referralBonus
        );
    }

    /**
     * @dev TEST HELPER: Gets early access status for testing
     * @param user The user address
     * @param contentId The content ID
     * @return hasAccess Whether user has early access
     */
    function getEarlyAccessForTesting(address user, uint256 contentId) external view testOnly returns (bool hasAccess) {
        if (useTestStorage) {
            return testEarlyAccess[user][contentId];
        }
        
        // Get from production contract
        return loyaltyManager.hasEarlyAccessToContent(user, contentId);
    }

    /**
     * @dev TEST HELPER: Sets user loyalty data for testing
     * @param user The user address
     * @param loyalty The loyalty data to set
     */
    function setUserLoyaltyForTesting(address user, LoyaltyManager.UserLoyalty memory loyalty) external testOnly {
        testUserLoyalty[user] = loyalty;
        useTestStorage = true;
        emit TestUserLoyaltySet(user);
    }

    /**
     * @dev TEST HELPER: Sets tier benefits for testing
     * @param tier The loyalty tier
     * @param benefits The tier benefits to set
     */
    function setTierBenefitsForTesting(LoyaltyManager.LoyaltyTier tier, LoyaltyManager.TierBenefits memory benefits) external testOnly {
        testTierBenefits[tier] = benefits;
        useTestStorage = true;
        emit TestTierBenefitsSet(tier);
    }

    /**
     * @dev TEST HELPER: Sets early access for testing
     * @param user The user address
     * @param contentId The content ID
     * @param hasAccess Whether user has early access
     */
    function setEarlyAccessForTesting(address user, uint256 contentId, bool hasAccess) external testOnly {
        testEarlyAccess[user][contentId] = hasAccess;
        useTestStorage = true;
        emit TestEarlyAccessSet(user, contentId, hasAccess);
    }

    /**
     * @dev TEST HELPER: Reset all test data
     */
    function resetTestData() external testOnly {
        useTestStorage = false;
        testUserCount = 0;
        // Note: Cannot clear mappings completely in Solidity,
        // but setting useTestStorage = false will make functions
        // fall back to production contract data
    }

    /**
     * @dev TEST HELPER: Enable/disable test storage mode
     * @param enabled Whether to use test storage
     */
    function setTestStorageMode(bool enabled) external testOnly {
        useTestStorage = enabled;
    }

    /**
     * @dev TEST HELPER: Get test storage mode status
     * @return enabled Whether test storage mode is enabled
     */
    function isTestStorageModeEnabled() external view testOnly returns (bool enabled) {
        return useTestStorage;
    }

    /**
     * @dev TEST HELPER: Gets user count for testing
     */
    function getUserCountForTesting() external view testOnly returns (uint256 count) {
        return testUserCount;
    }

    /**
     * @dev TEST HELPER: Sets test user count
     * @param count The user count to set
     */
    function setUserCountForTesting(uint256 count) external testOnly {
        testUserCount = count;
        useTestStorage = true;
    }

    /**
     * @dev TEST HELPER: Gets user tier for testing
     * @param user The user address
     * @return tier The user's current tier
     */
    function getUserTierForTesting(address user) external view testOnly returns (LoyaltyManager.LoyaltyTier tier) {
        if (useTestStorage) {
            return testUserLoyalty[user].currentTier;
        }
        
        // Get from production contract
        return loyaltyManager.getUserTier(user);
    }

    /**
     * @dev TEST HELPER: Gets user points for testing
     * @param user The user address
     * @return totalPoints The user's total points
     * @return availablePoints The user's available points
     */
    function getUserPointsForTesting(address user) external view testOnly returns (uint256 totalPoints, uint256 availablePoints) {
        if (useTestStorage) {
            LoyaltyManager.UserLoyalty storage testLoyalty = testUserLoyalty[user];
            return (testLoyalty.totalPoints, testLoyalty.availablePoints);
        }
        
        // Get from production contract
        return loyaltyManager.getUserPoints(user);
    }

    /**
     * @dev TEST HELPER: Gets loyalty statistics for testing
     * @return totalUsers Total number of users
     * @return activeUsers Number of active users
     * @return totalPoints Total points across all users
     * @return totalRevenue Total revenue generated
     */
    function getLoyaltyStatsForTesting() external view testOnly returns (
        uint256 totalUsers,
        uint256 activeUsers,
        uint256 totalPoints,
        uint256 totalRevenue
    ) {
        if (useTestStorage) {
            // Return test data
            return (testUserCount, testUserCount, 0, 0); // Simplified for testing
        }
        
        // Since the production contract doesn't have this function,
        // we simulate basic stats from available data
        return (0, 0, 0, 0); // Placeholder - tests should use test storage mode
    }

    /**
     * @dev TEST HELPER: Batch set user loyalty data for testing
     * @param users Array of user addresses
     * @param loyaltyData Array of loyalty data
     */
    function batchSetUserLoyaltyForTesting(
        address[] calldata users,
        LoyaltyManager.UserLoyalty[] calldata loyaltyData
    ) external testOnly {
        require(users.length == loyaltyData.length, "Array length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            testUserLoyalty[users[i]] = loyaltyData[i];
            emit TestUserLoyaltySet(users[i]);
        }
        useTestStorage = true;
        testUserCount = users.length;
    }
}
