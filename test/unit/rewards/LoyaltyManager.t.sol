// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { LoyaltyManager } from "../../../src/rewards/LoyaltyManager.sol";
import { RewardsTreasury } from "../../../src/rewards/RewardsTreasury.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

/**
 * @title LoyaltyManagerTest
 * @dev Unit tests for LoyaltyManager contract - Loyalty point system tests
 * @notice Tests loyalty points, tier progression, referrals, and discount functionality
 */
contract LoyaltyManagerTest is TestSetup {
    // Test contracts
    LoyaltyManager public testLoyaltyManager;
    RewardsTreasury public testRewardsTreasury;
    MockERC20 public testUSDC;

    // Test data
    address testUser = address(0x1234);
    address testUser2 = address(0x5678);
    address testUser3 = address(0x9ABC);
    address testPointsManager = address(0xDEF0);
    address testDiscountManager = address(0x1111);

    // Test amounts
    uint256 constant SPEND_100_USDC = 100e6;
    uint256 constant SPEND_1000_USDC = 1000e6;
    uint256 constant SPEND_10000_USDC = 10000e6;

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testUSDC = new MockERC20("USD Coin", "USDC", 6);
        testRewardsTreasury = new RewardsTreasury(address(testUSDC));
        testLoyaltyManager = new LoyaltyManager(address(testRewardsTreasury));

        // Grant roles
        vm.prank(admin);
        testLoyaltyManager.grantRole(testLoyaltyManager.POINTS_MANAGER_ROLE(), testPointsManager);

        vm.prank(admin);
        testLoyaltyManager.grantRole(testLoyaltyManager.DISCOUNT_MANAGER_ROLE(), testDiscountManager);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(testLoyaltyManager.rewardsTreasury()), address(testRewardsTreasury));
        assertTrue(testLoyaltyManager.hasRole(testLoyaltyManager.DEFAULT_ADMIN_ROLE(), admin));

        // Test role setup
        assertTrue(testLoyaltyManager.hasRole(testLoyaltyManager.DEFAULT_ADMIN_ROLE(), admin));

        // Test tier benefits are set up
        LoyaltyManager.TierBenefits memory benefits = testLoyaltyManager.getTierBenefits(LoyaltyManager.LoyaltyTier.Bronze);
        assertEq(benefits.discountBps, 100);
        assertEq(benefits.pointsMultiplier, 100);

        // Test tier thresholds
        assertEq(testLoyaltyManager.tierThresholds(LoyaltyManager.LoyaltyTier.Silver), 1000);
        assertEq(testLoyaltyManager.tierThresholds(LoyaltyManager.LoyaltyTier.Gold), 5000);
    }

    // ============ POINTS AWARD TESTS ============

    function test_AwardPurchasePoints_NewUser() public {
        // Award points to new user
        vm.prank(testPointsManager);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.PointsEarned(testUser, 10000, "Purchase"); // 100 USDC * 100 points per dollar
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Verify user loyalty data
        (
            uint256 totalPoints,
            uint256 availablePoints,
            LoyaltyManager.LoyaltyTier currentTier,
            uint256 totalSpent,
            uint256 purchaseCount,
            ,
        ) = testLoyaltyManager.getUserStats(testUser);

        assertEq(totalPoints, 10000);
        assertEq(availablePoints, 10000);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Bronze));
        assertEq(totalSpent, SPEND_100_USDC);
        assertEq(purchaseCount, 1);
    }

    function test_AwardPurchasePoints_ExistingUser() public {
        // Award points to existing user multiple times
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Verify accumulated points
        (uint256 totalPoints, , , uint256 totalSpent, uint256 purchaseCount, , ) = testLoyaltyManager.getUserStats(testUser);

        assertEq(totalPoints, 20000); // 200 USDC * 100 points per dollar
        assertEq(totalSpent, 200e6);
        assertEq(purchaseCount, 2);
    }

    function test_AwardPurchasePoints_SubscriptionBonus() public {
        // Award points for subscription (should get bonus multiplier)
        vm.prank(testPointsManager);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.PointsEarned(testUser, 12000, "Purchase"); // 100 USDC * 100 * 1.2 (subscription bonus)
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.Subscription);

        (uint256 totalPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(totalPoints, 12000);
    }

    function test_AwardPurchasePoints_TierMultiplier() public {
        // First reach Silver tier
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView); // 100,000 points

        // Award more points with Silver tier multiplier (1.1x)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView); // Should be 11,000 points with multiplier

        (uint256 totalPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(totalPoints, 111000); // 1000 USDC * 100 + 100 USDC * 100 * 1.1
    }

    // ============ REFERRAL POINTS TESTS ============

    function test_AwardReferralPoints_NewUsers() public {
        // Award referral points to new users
        vm.prank(testPointsManager);
        vm.expectEmit(true, true, true, false);
        emit LoyaltyManager.ReferralBonus(testUser, testUser2, 500);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.PointsEarned(testUser, 500, "Referral");
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.PointsEarned(testUser2, 250, "Referral Welcome");
        testLoyaltyManager.awardReferralPoints(testUser, testUser2);

        // Check referrer points
        (uint256 referrerPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(referrerPoints, 500);

        // Check referee points
        (uint256 refereePoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser2);
        assertEq(refereePoints, 250);
    }

    function test_AwardReferralPoints_ExistingUsers() public {
        // Set up existing users
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Award referral points
        vm.prank(testPointsManager);
        testLoyaltyManager.awardReferralPoints(testUser, testUser2);

        (uint256 referrerPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(referrerPoints, 10500); // 10000 base + 500 referral

        (uint256 refereePoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser2);
        assertEq(refereePoints, 250);
    }

    // ============ DISCOUNT CALCULATION TESTS ============

    function test_CalculateDiscount_BronzeTier() public {
        // Set up user in Bronze tier
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Calculate discount
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 1e6); // 1% discount = 1 USDC
        assertEq(finalPrice, 99e6); // 99 USDC
    }

    function test_CalculateDiscount_SilverTier() public {
        // Set up user in Silver tier (1000+ points)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Calculate discount
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 2.5e6); // 2.5% discount = 2.5 USDC
        assertEq(finalPrice, 97.5e6); // 97.5 USDC
    }

    function test_CalculateDiscount_GoldTier() public {
        // Set up user in Gold tier (5000+ points)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_10000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Calculate discount
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 5e6); // 5% discount = 5 USDC
        assertEq(finalPrice, 95e6); // 95 USDC
    }

    function test_CalculateDiscount_PlatinumTier() public {
        // Set up user in Platinum tier (20000+ points)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 30000e6, ISharedTypes.PaymentType.PayPerView);

        // Calculate discount
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 7.5e6); // 7.5% discount = 7.5 USDC
        assertEq(finalPrice, 92.5e6); // 92.5 USDC
    }

    function test_CalculateDiscount_DiamondTier() public {
        // Set up user in Diamond tier (50000+ points)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 60000e6, ISharedTypes.PaymentType.PayPerView);

        // Calculate discount
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 10e6); // 10% discount = 10 USDC
        assertEq(finalPrice, 90e6); // 90 USDC
    }

    function test_CalculateDiscount_InactiveUser() public {
        // Test discount calculation for inactive user
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);

        assertEq(discountAmount, 0);
        assertEq(finalPrice, 100e6); // No discount
    }

    // ============ DISCOUNT APPLICATION TESTS ============

    function test_ApplyDiscount_TierOnly() public {
        // Set up user in Silver tier
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Apply discount without points
        vm.prank(testDiscountManager);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.DiscountApplied(testUser, 2.5e6, 100e6);
        uint256 finalPrice = testLoyaltyManager.applyDiscount(testUser, 100e6, false, 0);

        assertEq(finalPrice, 97.5e6); // 2.5% discount applied

        // Check points unchanged
        (, uint256 availablePoints, , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(availablePoints, 100000); // 1000 USDC * 100 points per dollar
    }

    function test_ApplyDiscount_WithPoints() public {
        // Set up user with points
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Apply discount with points (1000 points = 1 USDC discount)
        vm.prank(testDiscountManager);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.PointsSpent(testUser, 1000, "Discount");
        uint256 finalPrice = testLoyaltyManager.applyDiscount(testUser, 100e6, true, 1000);

        assertEq(finalPrice, 99e6); // 1 USDC discount from points

        // Check points reduced
        (, uint256 availablePoints, , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(availablePoints, 9000); // 10000 - 1000
    }

    function test_ApplyDiscount_InsufficientPoints() public {
        // Set up user with minimal points
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 5e6, ISharedTypes.PaymentType.PayPerView); // 500 points

        // Try to use more points than available
        vm.prank(testDiscountManager);
        vm.expectRevert("Insufficient points");
        testLoyaltyManager.applyDiscount(testUser, 100e6, true, 1000); // Try to use 1000 points
    }

    function test_ApplyDiscount_PointsDiscountCap() public {
        // Set up user in Bronze tier
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Try to use points that would exceed the price after tier discount
        vm.prank(testDiscountManager);
        uint256 finalPrice = testLoyaltyManager.applyDiscount(testUser, 100e6, true, 5000); // Try to use 5000 points (5 USDC)

        assertEq(finalPrice, 99e6); // Capped at 1 USDC discount from points (1000 points)

        // Check only 1000 points were used
        (, uint256 availablePoints, , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(availablePoints, 9000); // 10000 - 1000
    }

    // ============ TIER UPGRADE TESTS ============

    function test_TierUpgrade_Silver() public {
        // Reach Silver tier threshold
        vm.prank(testPointsManager);
        vm.expectEmit(true, true, false, false);
        emit LoyaltyManager.TierUpgraded(testUser, LoyaltyManager.LoyaltyTier.Bronze, LoyaltyManager.LoyaltyTier.Silver);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Check tier upgrade
        (, , LoyaltyManager.LoyaltyTier currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Silver));
    }

    function test_TierUpgrade_Gold() public {
        // Reach Gold tier threshold
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_10000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Check tier upgrade
        (, , LoyaltyManager.LoyaltyTier currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Gold));
    }

    function test_TierUpgrade_Platinum() public {
        // Reach Platinum tier threshold
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 30000e6, ISharedTypes.PaymentType.PayPerView);

        // Check tier upgrade
        (, , LoyaltyManager.LoyaltyTier currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Platinum));
    }

    function test_TierUpgrade_Diamond() public {
        // Reach Diamond tier threshold
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 60000e6, ISharedTypes.PaymentType.PayPerView);

        // Check tier upgrade
        (, , LoyaltyManager.LoyaltyTier currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Diamond));
    }

    function test_TierUpgradeBonus_Points() public {
        // Test tier upgrade bonus points
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Check that upgrade bonus was awarded
        (uint256 totalPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(totalPoints, 100200); // 100000 base + 200 Silver tier bonus
    }

    // ============ EARLY ACCESS TESTS ============

    function test_GrantEarlyAccess_EligibleUser() public {
        // Set up user in Gold tier (eligible for early access)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_10000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Grant early access
        vm.prank(testDiscountManager);
        vm.expectEmit(true, true, true, false);
        emit LoyaltyManager.EarlyAccessGranted(testUser, 123, 24); // 24 hours for Gold tier
        testLoyaltyManager.grantEarlyAccess(testUser, 123);

        // Verify early access granted
        assertTrue(testLoyaltyManager.hasEarlyAccess(testUser, 123));
    }

    function test_GrantEarlyAccess_IneligibleUser() public {
        // Try to grant early access to Bronze tier user (not eligible)
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        vm.prank(testDiscountManager);
        vm.expectRevert("User not eligible for early access");
        testLoyaltyManager.grantEarlyAccess(testUser, 123);
    }

    // ============ USER STATS TESTS ============

    function test_GetUserStats_NewUser() public {
        // Test stats for new user
        (uint256 totalPoints, uint256 availablePoints, LoyaltyManager.LoyaltyTier currentTier, uint256 totalSpent, uint256 purchaseCount, uint256 tierDiscountBps, bool freeFees) = testLoyaltyManager.getUserStats(testUser);

        assertEq(totalPoints, 0);
        assertEq(availablePoints, 0);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Bronze));
        assertEq(totalSpent, 0);
        assertEq(purchaseCount, 0);
        assertEq(tierDiscountBps, 100); // Bronze tier discount
        assertFalse(freeFees);
    }

    function test_GetUserStats_ActiveUser() public {
        // Set up active user
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Test stats for active user
        (uint256 totalPoints, uint256 availablePoints, LoyaltyManager.LoyaltyTier currentTier, uint256 totalSpent, uint256 purchaseCount, uint256 tierDiscountBps, bool freeFees) = testLoyaltyManager.getUserStats(testUser);

        assertEq(totalPoints, 100200); // Including tier upgrade bonus
        assertEq(availablePoints, 100200);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Silver));
        assertEq(totalSpent, 1000e6);
        assertEq(purchaseCount, 1);
        assertEq(tierDiscountBps, 250); // Silver tier discount
        assertFalse(freeFees);
    }

    function test_GetUserStats_GoldTier() public {
        // Set up Gold tier user
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_10000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Test stats for Gold tier user
        (, , , , , uint256 tierDiscountBps, bool freeFees) = testLoyaltyManager.getUserStats(testUser);

        assertEq(tierDiscountBps, 500); // Gold tier discount
        assertTrue(freeFees); // Gold tier has free transaction fees
    }

    // ============ INTEGRATION TESTS ============

    function test_FullLoyaltyWorkflow() public {
        // 1. New user makes first purchase
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        (uint256 totalPoints, , LoyaltyManager.LoyaltyTier currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(totalPoints, 10000);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Bronze));

        // 2. User makes more purchases to reach Silver tier
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_1000_USDC, ISharedTypes.PaymentType.PayPerView);

        (, , currentTier, , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(uint256(currentTier), uint256(LoyaltyManager.LoyaltyTier.Silver));

        // Verify user loyalty data using test helper
        LoyaltyManager.UserLoyalty memory loyalty = testLoyaltyManager.getUserLoyalty(testUser);
        uint256 userTotalPoints = loyalty.totalPoints;
        uint256 userAvailablePoints = loyalty.availablePoints;
        LoyaltyManager.LoyaltyTier verifiedTier = loyalty.currentTier;
        uint256 userTotalSpent = loyalty.totalSpent;
        uint256 userPurchaseCount = loyalty.purchaseCount;
        bool userIsActive = loyalty.isActive;
        assertEq(userTotalPoints, 100200); // Including tier upgrade bonus
        assertEq(userAvailablePoints, 100200);
        assertEq(uint256(verifiedTier), uint256(LoyaltyManager.LoyaltyTier.Silver));
        assertEq(userTotalSpent, 1000e6);
        assertEq(userPurchaseCount, 1);
        assertTrue(userIsActive);

        // 3. Test discount calculation
        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(testUser, 100e6);
        assertEq(discountAmount, 2.5e6); // 2.5% discount

        // 4. Apply discount with points
        vm.prank(testDiscountManager);
        uint256 discountedPrice = testLoyaltyManager.applyDiscount(testUser, 100e6, true, 1000); // Use 1000 points

        assertEq(discountedPrice, 97.5e6); // 2.5% tier discount + 1 USDC from points

        // 5. Test referral system
        vm.prank(testPointsManager);
        testLoyaltyManager.awardReferralPoints(testUser, testUser2);

        (uint256 referrerPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(referrerPoints, 100200 + 500); // Previous points + referral bonus

        (uint256 refereePoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser2);
        assertEq(refereePoints, 250); // Referral welcome bonus
    }

    // ============ EDGE CASE TESTS ============

    function test_AwardPurchasePoints_ZeroAmount() public {
        // Test awarding points for zero amount
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, 0, ISharedTypes.PaymentType.PayPerView);

        (uint256 totalPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertEq(totalPoints, 0); // No points for zero spend
    }

    function test_ApplyDiscount_ZeroPrice() public {
        // Set up user
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        // Apply discount to zero price
        vm.prank(testDiscountManager);
        uint256 finalPrice = testLoyaltyManager.applyDiscount(testUser, 0, true, 1000);

        assertEq(finalPrice, 0); // Price remains zero
    }

    function test_GrantEarlyAccess_MultipleTimes() public {
        // Set up eligible user
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_10000_USDC, ISharedTypes.PaymentType.PayPerView);

        // Grant early access multiple times for same content
        vm.prank(testDiscountManager);
        testLoyaltyManager.grantEarlyAccess(testUser, 123);

        // Second grant should not revert (idempotent)
        vm.prank(testDiscountManager);
        testLoyaltyManager.grantEarlyAccess(testUser, 123);

        assertTrue(testLoyaltyManager.hasEarlyAccess(testUser, 123));
    }

    // ============ FUZZING TESTS ============

    function testFuzz_AwardPurchasePoints_ValidAmounts(
        uint256 amountSpent,
        uint8 paymentTypeValue
    ) public {
        // Assume valid inputs
        vm.assume(amountSpent > 0 && amountSpent <= 10000e6); // Max $10,000
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType(paymentTypeValue % 4);

        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, amountSpent, paymentType);

        // Should not revert and should update points
        (uint256 totalPoints, , , , , ,) = testLoyaltyManager.getUserStats(testUser);
        assertTrue(totalPoints > 0);
    }

    function testFuzz_CalculateDiscount_ValidPrices(
        address user,
        uint256 originalPrice
    ) public {
        vm.assume(user != address(0));
        vm.assume(originalPrice <= 10000e6); // Max $10,000

        // Set up user with some points first
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(user, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        (uint256 discountAmount, uint256 finalPrice) = testLoyaltyManager.calculateDiscount(user, originalPrice);

        // Discount should be reasonable
        assertTrue(discountAmount <= originalPrice);
        assertTrue(finalPrice <= originalPrice);
        assertTrue(finalPrice >= 0);
    }

    function testFuzz_ApplyDiscount_ValidInputs(
        uint256 originalPrice,
        bool usePoints,
        uint256 pointsToUse
    ) public {
        // Set up user
        vm.prank(testPointsManager);
        testLoyaltyManager.awardPurchasePoints(testUser, SPEND_100_USDC, ISharedTypes.PaymentType.PayPerView);

        vm.assume(originalPrice <= 1000e6); // Max $1,000
        vm.assume(pointsToUse <= 10000); // Max 10,000 points

        vm.prank(testDiscountManager);
        uint256 finalPrice = testLoyaltyManager.applyDiscount(testUser, originalPrice, usePoints, pointsToUse);

        // Should not revert and return valid price
        assertTrue(finalPrice <= originalPrice);
        assertTrue(finalPrice >= 0);
    }
}
