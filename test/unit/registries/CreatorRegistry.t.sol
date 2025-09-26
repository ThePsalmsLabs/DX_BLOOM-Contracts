// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { CreatorRegistry } from "../../../src/CreatorRegistry.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

/**
 * @title CreatorRegistryTest
 * @dev Unit tests for CreatorRegistry contract
 * @notice Tests all creator registration and management functions in isolation
 */
contract CreatorRegistryTest is TestSetup {
    // Test data
    string constant TEST_PROFILE_DATA = "QmTestProfileHash123456789012345678901234567890123456789";
    string constant TEST_PROFILE_DATA_2 = "QmTestProfileHash987654321098765432109876543210987654321";
    uint256 constant TEST_SUBSCRIPTION_PRICE = 1e6; // $1.00
    uint256 constant TEST_SUBSCRIPTION_PRICE_2 = 2e6; // $2.00

    function setUp() public override {
        super.setUp();

        // Grant platform role to test contract for updateCreatorStats
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(creatorRegistry.owner(), admin);
        assertTrue(creatorRegistry.hasRole(creatorRegistry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(creatorRegistry.hasRole(creatorRegistry.MODERATOR_ROLE(), admin));

        // Verify constants are set correctly
        assertEq(creatorRegistry.MIN_SUBSCRIPTION_PRICE(), 0.01e6);
        assertEq(creatorRegistry.MAX_SUBSCRIPTION_PRICE(), 100e6);
        assertEq(creatorRegistry.SUBSCRIPTION_DURATION(), 30 days);
    }

    // ============ CREATOR REGISTRATION TESTS ============

    function test_RegisterCreator_ValidParameters() public {
        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorRegistered(creator1, TEST_SUBSCRIPTION_PRICE, block.timestamp, TEST_PROFILE_DATA);

        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Verify creator was registered correctly
        assertTrue(creatorRegistry.isRegisteredCreator(creator1));
        assertTrue(creatorRegistry.isActive(creator1));

        CreatorRegistry.Creator memory registeredCreator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(registeredCreator.isRegistered);
        assertEq(registeredCreator.subscriptionPrice, TEST_SUBSCRIPTION_PRICE);
        assertEq(registeredCreator.profileData, TEST_PROFILE_DATA);
        assertFalse(registeredCreator.isVerified);
        assertFalse(registeredCreator.isSuspended);
        assertEq(registeredCreator.registrationTime, block.timestamp);
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), TEST_SUBSCRIPTION_PRICE);
    }

    function test_RegisterCreator_AlreadyRegistered() public {
        // Register first time
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Try to register again
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorAlreadyRegistered.selector);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);
    }

    function test_RegisterCreator_InvalidSubscriptionPrice_TooLow() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.registerCreator(creatorRegistry.MIN_SUBSCRIPTION_PRICE() - 1, TEST_PROFILE_DATA);
    }

    function test_RegisterCreator_InvalidSubscriptionPrice_TooHigh() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.registerCreator(creatorRegistry.MAX_SUBSCRIPTION_PRICE() + 1, TEST_PROFILE_DATA);
    }

    function test_RegisterCreator_InvalidProfileData_Empty() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidProfileData.selector);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, "");
    }

    function test_RegisterCreator_MinimumPrice() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(creatorRegistry.MIN_SUBSCRIPTION_PRICE(), TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), creatorRegistry.MIN_SUBSCRIPTION_PRICE());
    }

    function test_RegisterCreator_MaximumPrice() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(creatorRegistry.MAX_SUBSCRIPTION_PRICE(), TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), creatorRegistry.MAX_SUBSCRIPTION_PRICE());
    }

    function test_RegisterCreator_MultipleCreators() public {
        // Register first creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Register second creator
        vm.prank(creator2);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE_2, TEST_PROFILE_DATA_2);

        // Verify both are registered
        assertTrue(creatorRegistry.isRegisteredCreator(creator1));
        assertTrue(creatorRegistry.isRegisteredCreator(creator2));
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), TEST_SUBSCRIPTION_PRICE);
        assertEq(creatorRegistry.getSubscriptionPrice(creator2), TEST_SUBSCRIPTION_PRICE_2);

        // Verify total count
        assertEq(creatorRegistry.getTotalCreators(), 2);
    }

    // ============ SUBSCRIPTION PRICE UPDATE TESTS ============

    function test_UpdateSubscriptionPrice_ValidUpdate() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Update subscription price
        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.SubscriptionPriceUpdated(creator1, TEST_SUBSCRIPTION_PRICE, TEST_SUBSCRIPTION_PRICE_2);

        creatorRegistry.updateSubscriptionPrice(TEST_SUBSCRIPTION_PRICE_2);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), TEST_SUBSCRIPTION_PRICE_2);
    }

    function test_UpdateSubscriptionPrice_NotRegistered() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.updateSubscriptionPrice(TEST_SUBSCRIPTION_PRICE);
    }

    function test_UpdateSubscriptionPrice_InvalidPrice_TooLow() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.updateSubscriptionPrice(creatorRegistry.MIN_SUBSCRIPTION_PRICE() - 1);
    }

    function test_UpdateSubscriptionPrice_InvalidPrice_TooHigh() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.updateSubscriptionPrice(creatorRegistry.MAX_SUBSCRIPTION_PRICE() + 1);
    }

    // ============ PROFILE DATA UPDATE TESTS ============

    function test_UpdateProfileData_ValidUpdate() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Update profile data
        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.ProfileDataUpdated(creator1, TEST_PROFILE_DATA, TEST_PROFILE_DATA_2);

        creatorRegistry.updateProfileData(TEST_PROFILE_DATA_2);

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.profileData, TEST_PROFILE_DATA_2);
    }

    function test_UpdateProfileData_NotRegistered() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.updateProfileData(TEST_PROFILE_DATA);
    }

    function test_UpdateProfileData_InvalidProfileData() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidProfileData.selector);
        creatorRegistry.updateProfileData("");
    }

    // ============ CREATOR VERIFICATION TESTS ============

    function test_SetCreatorVerification_VerifyCreator() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Verify creator (admin only)
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorVerified(creator1, true);

        creatorRegistry.setCreatorVerification(creator1, true);

        CreatorRegistry.Creator memory verifiedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(verifiedCreator.isVerified);
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 1);
    }

    function test_SetCreatorVerification_UnverifyCreator() public {
        // Register and verify creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        // Unverify creator
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorVerified(creator1, false);

        creatorRegistry.setCreatorVerification(creator1, false);

        CreatorRegistry.Creator memory unverifiedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertFalse(unverifiedCreator.isVerified);
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 0);
    }

    function test_SetCreatorVerification_NotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.setCreatorVerification(creator1, true);
    }

    function test_SetCreatorVerification_Unauthorized() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(user1); // Not admin/moderator
        vm.expectRevert(); // Should revert due to access control
        creatorRegistry.setCreatorVerification(creator1, true);
    }

    // ============ CREATOR SUSPENSION TESTS ============

    function test_SuspendCreator() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Suspend creator (admin only)
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorSuspended(creator1, true);

        creatorRegistry.suspendCreator(creator1, true);

        CreatorRegistry.Creator memory suspendedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(suspendedCreator.isSuspended);
        assertFalse(creatorRegistry.isActive(creator1));
    }

    function test_UnsuspendCreator() public {
        // Register and suspend creator
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(admin);
        creatorRegistry.suspendCreator(creator1, true);

        // Unsuspend creator
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorSuspended(creator1, false);

        creatorRegistry.suspendCreator(creator1, false);

        CreatorRegistry.Creator memory activeCreator = creatorRegistry.getCreatorProfile(creator1);
        assertFalse(activeCreator.isSuspended);
        assertTrue(creatorRegistry.isActive(creator1));
    }

    function test_SuspendCreator_NotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.suspendCreator(creator1, true);
    }

    function test_SuspendCreator_Unauthorized() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(user1); // Not admin/moderator
        vm.expectRevert(); // Should revert due to access control
        creatorRegistry.suspendCreator(creator1, true);
    }

    // ============ CREATOR STATS UPDATE TESTS ============

    function test_UpdateCreatorStats_EarningsOnly() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earningsAmount = 100e6; // $100

        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorEarningsUpdated(creator1, earningsAmount, "platform_activity");

        creatorRegistry.updateCreatorStats(creator1, earningsAmount, 0, 0);

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, earningsAmount);
        assertEq(total, earningsAmount);
        assertEq(withdrawn, 0);
    }

    function test_UpdateCreatorStats_ContentIncrease() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 5, 0); // +5 content

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.contentCount, 5);
    }

    function test_UpdateCreatorStats_ContentDecrease() public {
        // First increase content count
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 5, 0); // +5 content

        // Then decrease
        creatorRegistry.updateCreatorStats(creator1, 0, -2, 0); // -2 content

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.contentCount, 3);
    }

    function test_UpdateCreatorStats_ContentDecreaseToZero() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 2, 0); // +2 content
        creatorRegistry.updateCreatorStats(creator1, 0, -2, 0); // -2 content (to zero)

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.contentCount, 0);
    }

    function test_UpdateCreatorStats_ContentDecreaseBelowZero() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 2, 0); // +2 content
        creatorRegistry.updateCreatorStats(creator1, 0, -5, 0); // -5 content (below zero)

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.contentCount, 0); // Should not go below zero
    }

    function test_UpdateCreatorStats_SubscriberIncrease() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 0, 10); // +10 subscribers

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.subscriberCount, 10);
    }

    function test_UpdateCreatorStats_SubscriberDecrease() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 0, 10); // +10 subscribers
        creatorRegistry.updateCreatorStats(creator1, 0, 0, -3); // -3 subscribers

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.subscriberCount, 7);
    }

    function test_UpdateCreatorStats_SubscriberDecreaseToZero() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 0, 5); // +5 subscribers
        creatorRegistry.updateCreatorStats(creator1, 0, 0, -5); // -5 subscribers (to zero)

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.subscriberCount, 0);
    }

    function test_UpdateCreatorStats_SubscriberDecreaseBelowZero() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, 0, 0, 5); // +5 subscribers
        creatorRegistry.updateCreatorStats(creator1, 0, 0, -10); // -10 subscribers (below zero)

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.subscriberCount, 0); // Should not go below zero
    }

    function test_UpdateCreatorStats_AllUpdates() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earnings = 100e6; // $100
        int256 contentDelta = 3;
        int256 subscriberDelta = 15;

        creatorRegistry.updateCreatorStats(creator1, earnings, contentDelta, subscriberDelta);

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.totalEarnings, earnings);
        assertEq(updatedCreator.contentCount, 3);
        assertEq(updatedCreator.subscriberCount, 15);

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, earnings);
        assertEq(total, earnings);
    }

    function test_UpdateCreatorStats_NotRegistered() public {
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.updateCreatorStats(creator1, 100e6, 0, 0);
    }

    function test_UpdateCreatorStats_Unauthorized() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(user1); // Not authorized
        vm.expectRevert(); // Should revert due to access control
        creatorRegistry.updateCreatorStats(creator1, 100e6, 0, 0);
    }

    // ============ EARNINGS WITHDRAWAL TESTS ============

    function test_WithdrawCreatorEarnings_Success() public {
        // Register creator and add earnings
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earningsAmount = 100e6; // $100
        creatorRegistry.updateCreatorStats(creator1, earningsAmount, 0, 0);

        // Mint USDC to registry for withdrawal
        mockUSDC.mint(address(creatorRegistry), earningsAmount);

        // Withdraw earnings
        vm.prank(creator1);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorEarningsWithdrawn(creator1, earningsAmount, block.timestamp);

        creatorRegistry.withdrawCreatorEarnings();

        // Verify withdrawal
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, 0);
        assertEq(total, earningsAmount);
        assertEq(withdrawn, earningsAmount);
        assertEq(mockUSDC.balanceOf(creator1), earningsAmount);
    }

    function test_WithdrawCreatorEarnings_NoEarnings() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.NoEarningsToWithdraw.selector);
        creatorRegistry.withdrawCreatorEarnings();
    }

    function test_WithdrawCreatorEarnings_NotRegistered() public {
        vm.prank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.withdrawCreatorEarnings();
    }

    function test_WithdrawCreatorEarnings_PartialWithdrawal() public {
        // Add earnings twice
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 firstEarnings = 50e6;
        uint256 secondEarnings = 30e6;
        creatorRegistry.updateCreatorStats(creator1, firstEarnings, 0, 0);
        creatorRegistry.updateCreatorStats(creator1, secondEarnings, 0, 0);

        // Mint USDC for withdrawal
        mockUSDC.mint(address(creatorRegistry), firstEarnings + secondEarnings);

        // Withdraw once
        vm.prank(creator1);
        creatorRegistry.withdrawCreatorEarnings();

        // Verify partial withdrawal
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, 0);
        assertEq(total, firstEarnings + secondEarnings);
        assertEq(withdrawn, firstEarnings + secondEarnings);
    }

    // ============ BONUS EARNINGS TESTS ============

    function test_AddBonusEarnings_Success() public {
        // Register creator first
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 bonusAmount = 10e6; // $10

        // Mint USDC to admin for transfer
        mockUSDC.mint(admin, bonusAmount);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.CreatorEarningsUpdated(creator1, bonusAmount, "bonus");

        creatorRegistry.addBonusEarnings(creator1, bonusAmount, "bonus");

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, bonusAmount);
        assertEq(total, bonusAmount);
    }

    function test_AddBonusEarnings_ZeroAmount() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(admin);
        creatorRegistry.addBonusEarnings(creator1, 0, "bonus"); // Should not revert

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, 0);
        assertEq(total, 0);
    }

    function test_AddBonusEarnings_NotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.addBonusEarnings(creator1, 10e6, "bonus");
    }

    function test_AddBonusEarnings_Unauthorized() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(user1); // Not admin/moderator
        vm.expectRevert(); // Should revert due to access control
        creatorRegistry.addBonusEarnings(creator1, 10e6, "bonus");
    }

    function test_AddBonusEarnings_InsufficientBalance() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 bonusAmount = 10e6;

        vm.prank(admin);
        vm.expectRevert(); // Should revert due to insufficient balance
        creatorRegistry.addBonusEarnings(creator1, bonusAmount, "bonus");
    }

    // ============ PLATFORM FEE MANAGEMENT TESTS ============

    function test_UpdatePlatformFee_ValidFee() public {
        uint256 newFee = 500; // 5%

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.PlatformFeeUpdated(250, 500);

        creatorRegistry.updatePlatformFee(newFee);

        assertEq(creatorRegistry.platformFee(), newFee);
    }

    function test_UpdatePlatformFee_InvalidFee_TooHigh() public {
        uint256 invalidFee = 1001; // > 10%

        vm.prank(admin);
        vm.expectRevert(CreatorRegistry.InvalidFeePercentage.selector);
        creatorRegistry.updatePlatformFee(invalidFee);
    }

    function test_UpdatePlatformFee_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.updatePlatformFee(300);
    }

    function test_CalculatePlatformFee() public {
        uint256 amount = 1000e6; // $1000
        uint256 feeRate = 250; // 2.5%

        uint256 calculatedFee = creatorRegistry.calculatePlatformFee(amount);
        uint256 expectedFee = (amount * feeRate) / 10000;

        assertEq(calculatedFee, expectedFee);
    }

    // ============ PLATFORM FEE RECIPIENT TESTS ============

    function test_UpdateFeeRecipient_ValidAddress() public {
        address newRecipient = address(0x1234);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit CreatorRegistry.FeeRecipientUpdated(address(0), newRecipient);

        creatorRegistry.updateFeeRecipient(newRecipient);

        assertEq(creatorRegistry.feeRecipient(), newRecipient);
    }

    function test_UpdateFeeRecipient_InvalidAddress() public {
        vm.prank(admin);
        vm.expectRevert(CreatorRegistry.InvalidFeeRecipient.selector);
        creatorRegistry.updateFeeRecipient(address(0));
    }

    function test_UpdateFeeRecipient_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.updateFeeRecipient(address(0x1234));
    }

    // ============ PLATFORM FEE WITHDRAWAL TESTS ============

    function test_WithdrawPlatformFees_Success() public {
        // Register creator and add earnings
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earningsAmount = 1000e6; // $1000
        creatorRegistry.updateCreatorStats(creator1, earningsAmount, 0, 0);

        // Update platform fee to test calculation
        vm.prank(admin);
        creatorRegistry.updatePlatformFee(250); // 2.5%

        // Calculate expected platform fees
        // Platform gets 2.5% of total earnings
        uint256 expectedPlatformFees = (earningsAmount * 250) / 10000; // 25e6

        // Mint USDC for withdrawal
        mockUSDC.mint(address(creatorRegistry), expectedPlatformFees);

        // Get current recipient balance
        uint256 initialRecipientBalance = mockUSDC.balanceOf(creatorRegistry.feeRecipient());

        // Withdraw platform fees
        vm.prank(admin);
        creatorRegistry.withdrawPlatformFees();

        // Verify withdrawal
        uint256 finalRecipientBalance = mockUSDC.balanceOf(creatorRegistry.feeRecipient());
        assertEq(finalRecipientBalance, initialRecipientBalance + expectedPlatformFees);
    }

    function test_WithdrawPlatformFees_NoFeesToWithdraw() public {
        vm.prank(admin);
        vm.expectRevert("No platform fees to withdraw");
        creatorRegistry.withdrawPlatformFees();
    }

    function test_WithdrawPlatformFees_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.withdrawPlatformFees();
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_IsRegisteredCreator() public {
        assertFalse(creatorRegistry.isRegisteredCreator(creator1));

        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        assertTrue(creatorRegistry.isRegisteredCreator(creator1));
    }

    function test_GetSubscriptionPrice() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), TEST_SUBSCRIPTION_PRICE);
    }

    function test_GetCreatorProfile() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        CreatorRegistry.Creator memory profile = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(profile.isRegistered);
        assertEq(profile.subscriptionPrice, TEST_SUBSCRIPTION_PRICE);
        assertEq(profile.profileData, TEST_PROFILE_DATA);
    }

    function test_GetCreatorEarnings() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earnings = 100e6;
        creatorRegistry.updateCreatorStats(creator1, earnings, 0, 0);

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, earnings);
        assertEq(total, earnings);
        assertEq(withdrawn, 0);
    }

    function test_GetTotalCreators() public {
        assertEq(creatorRegistry.getTotalCreators(), 0);

        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getTotalCreators(), 1);
    }

    function test_GetVerifiedCreatorCount() public {
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 0);

        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        assertEq(creatorRegistry.getVerifiedCreatorCount(), 1);
    }

    function test_GetCreatorByIndex() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator2);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE_2, TEST_PROFILE_DATA_2);

        assertEq(creatorRegistry.getCreatorByIndex(0), creator1);
        assertEq(creatorRegistry.getCreatorByIndex(1), creator2);

        vm.expectRevert("Index out of bounds");
        creatorRegistry.getCreatorByIndex(2);
    }

    function test_GetVerifiedCreatorByIndex() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(creator2);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE_2, TEST_PROFILE_DATA_2);

        // Verify first creator only
        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        assertEq(creatorRegistry.getVerifiedCreatorByIndex(0), creator1);

        vm.expectRevert("Index out of bounds");
        creatorRegistry.getVerifiedCreatorByIndex(1);
    }

    function test_GetPlatformStats() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earnings = 100e6;
        creatorRegistry.updateCreatorStats(creator1, earnings, 0, 0);

        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        (uint256 totalCreators, uint256 verifiedCount, uint256 totalEarnings, uint256 creatorEarnings, uint256 withdrawnAmount) =
            creatorRegistry.getPlatformStats();

        assertEq(totalCreators, 1);
        assertEq(verifiedCount, 1);
        assertEq(totalEarnings, 0); // Platform earnings not updated yet
        assertEq(creatorEarnings, earnings);
        assertEq(withdrawnAmount, 0);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_GrantPlatformRole() public {
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(user1);

        assertTrue(creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), user1));
    }

    function test_RevokePlatformRole() public {
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(user1);

        assertTrue(creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), user1));

        vm.prank(admin);
        creatorRegistry.revokePlatformRole(user1);

        assertFalse(creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), user1));
    }

    function test_GrantPlatformRole_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.grantPlatformRole(user2);
    }

    function test_RevokePlatformRole_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.revokePlatformRole(user1);
    }

    // ============ PAUSE/UNPAUSE TESTS ============

    function test_Pause_Unpause() public {
        // Test pause
        vm.prank(admin);
        creatorRegistry.pause();
        assertTrue(creatorRegistry.paused());

        // Test unpause
        vm.prank(admin);
        creatorRegistry.unpause();
        assertFalse(creatorRegistry.paused());
    }

    function test_Pause_Unauthorized() public {
        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.pause();
    }

    function test_Unpause_Unauthorized() public {
        vm.prank(admin);
        creatorRegistry.pause(); // Pause first

        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.unpause();
    }

    function test_RegisterCreator_WhenPaused() public {
        vm.prank(admin);
        creatorRegistry.pause();

        vm.prank(creator1);
        vm.expectRevert("Pausable: paused");
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);
    }

    function test_UpdateSubscriptionPrice_WhenPaused() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        vm.prank(admin);
        creatorRegistry.pause();

        vm.prank(creator1);
        vm.expectRevert("Pausable: paused");
        creatorRegistry.updateSubscriptionPrice(TEST_SUBSCRIPTION_PRICE_2);
    }

    // ============ EMERGENCY FUNCTIONS TESTS ============

    function test_EmergencyTokenRecovery_NonUSDC() public {
        // Mint some other token to registry
        address otherToken = address(0x1234);
        MockERC20 mockOtherToken = new MockERC20("Other Token", "OTHER", 18);
        mockOtherToken.mint(address(creatorRegistry), 100e18);

        uint256 initialOwnerBalance = mockOtherToken.balanceOf(admin);

        vm.prank(admin);
        creatorRegistry.emergencyTokenRecovery(otherToken, 100e18);

        uint256 finalOwnerBalance = mockOtherToken.balanceOf(admin);
        assertEq(finalOwnerBalance, initialOwnerBalance + 100e18);
    }

    function test_EmergencyTokenRecovery_USDC() public {
        // Should not allow USDC recovery
        vm.prank(admin);
        vm.expectRevert("Cannot recover USDC");
        creatorRegistry.emergencyTokenRecovery(address(mockUSDC), 100e6);
    }

    function test_EmergencyTokenRecovery_Unauthorized() public {
        address otherToken = address(0x1234);
        MockERC20 mockOtherToken = new MockERC20("Other Token", "OTHER", 18);
        mockOtherToken.mint(address(creatorRegistry), 100e18);

        vm.prank(user1); // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        creatorRegistry.emergencyTokenRecovery(otherToken, 100e18);
    }

    // ============ EDGE CASE TESTS ============

    function test_RegisterCreator_WithMaxValues() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(creatorRegistry.MAX_SUBSCRIPTION_PRICE(), TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), creatorRegistry.MAX_SUBSCRIPTION_PRICE());
    }

    function test_RegisterCreator_WithMinValues() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(creatorRegistry.MIN_SUBSCRIPTION_PRICE(), TEST_PROFILE_DATA);

        assertEq(creatorRegistry.getSubscriptionPrice(creator1), creatorRegistry.MIN_SUBSCRIPTION_PRICE());
    }

    function test_UpdateCreatorStats_MaxValues() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        creatorRegistry.updateCreatorStats(creator1, type(uint256).max, int256(type(int256).max), int256(type(int256).max));

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.totalEarnings, type(uint256).max);
        assertEq(updatedCreator.contentCount, type(uint256).max);
        assertEq(updatedCreator.subscriberCount, type(uint256).max);
    }

    function test_WithdrawCreatorEarnings_AfterSuspension() public {
        // Register and add earnings
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        uint256 earningsAmount = 100e6;
        creatorRegistry.updateCreatorStats(creator1, earningsAmount, 0, 0);
        mockUSDC.mint(address(creatorRegistry), earningsAmount);

        // Suspend creator
        vm.prank(admin);
        creatorRegistry.suspendCreator(creator1, true);

        // Should still be able to withdraw earnings even when suspended
        vm.prank(creator1);
        creatorRegistry.withdrawCreatorEarnings();

        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, 0);
        assertEq(total, earningsAmount);
        assertEq(withdrawn, earningsAmount);
    }

    function test_UpdateCreatorStats_ZeroValues() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        // Update with zero values - should not change anything
        creatorRegistry.updateCreatorStats(creator1, 0, 0, 0);

        CreatorRegistry.Creator memory updatedCreator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(updatedCreator.totalEarnings, 0);
        assertEq(updatedCreator.contentCount, 0);
        assertEq(updatedCreator.subscriberCount, 0);
    }

    function test_IsActive_AfterSuspension() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        assertTrue(creatorRegistry.isActive(creator1));

        vm.prank(admin);
        creatorRegistry.suspendCreator(creator1, true);

        assertFalse(creatorRegistry.isActive(creator1));
    }

    function test_GetCreatorWithActive() public {
        vm.prank(creator1);
        creatorRegistry.registerCreator(TEST_SUBSCRIPTION_PRICE, TEST_PROFILE_DATA);

        (CreatorRegistry.Creator memory creator, bool active) = creatorRegistry.getCreatorWithActive(creator1);
        assertTrue(creator.isRegistered);
        assertTrue(active);

        vm.prank(admin);
        creatorRegistry.suspendCreator(creator1, true);

        (CreatorRegistry.Creator memory suspendedCreator, bool suspendedActive) = creatorRegistry.getCreatorWithActive(creator1);
        assertTrue(suspendedCreator.isRegistered);
        assertFalse(suspendedActive);
    }
}
