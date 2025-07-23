// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";

/**
 * @title CreatorRegistryTest - FIXED VERSION
 * @dev Comprehensive test suite for the CreatorRegistry contract - all previously failing tests are now fixed
 * @notice This test suite covers all aspects of creator registration, profile management,
 *         subscription pricing, earnings tracking, and platform administration. We test both
 *         happy path scenarios and edge cases to ensure the contract behaves correctly
 *         under all conditions.
 */
contract CreatorRegistryTest is TestSetup {
    // We'll use these events to verify that our contract emits them correctly
    event SubscriptionPriceUpdated(address indexed creator, uint256 oldPrice, uint256 newPrice);
    event CreatorVerified(address indexed creator, bool verified);
    event CreatorEarningsUpdated(address indexed creator, uint256 amount, string source);
    event CreatorEarningsWithdrawn(address indexed creator, uint256 amount, uint256 timestamp);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    /**
     * @dev Test setup specific to CreatorRegistry tests
     * @notice This function runs before each test to ensure we start with a clean state
     */
    function setUp() public override {
        super.setUp();
        // Any additional setup specific to CreatorRegistry tests can go here
    }

    // Helper for string equality
    function stringEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ============ CREATOR REGISTRATION TESTS ============

    /**
     * @dev Tests successful creator registration with valid parameters
     * @notice This is our happy path test - everything should work perfectly
     */
    function test_RegisterCreator_Success() public {
        // Arrange: Set up the test conditions
        uint256 subscriptionPrice = DEFAULT_SUBSCRIPTION_PRICE;
        string memory profileData = SAMPLE_PROFILE_DATA;

        // Act: Execute the function we're testing
        vm.startPrank(creator1);

        // We expect the CreatorRegistered event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CreatorRegistered(creator1, subscriptionPrice, block.timestamp, profileData);

        creatorRegistry.registerCreator(subscriptionPrice, profileData);
        vm.stopPrank();

        // Assert: Verify the results
        // Check that the creator is now registered
        assertTrue(creatorRegistry.isRegisteredCreator(creator1));

        // Check that the subscription price is set correctly
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), subscriptionPrice);

        // Check that the creator profile contains the correct data
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(creator.isRegistered);
        assertEq(creator.subscriptionPrice, subscriptionPrice);
        assertFalse(creator.isVerified); // Should not be verified initially
        assertEq(creator.totalEarnings, 0); // Should start with zero earnings
        assertEq(creator.contentCount, 0); // Should start with zero content
        assertEq(creator.subscriberCount, 0); // Should start with zero subscribers
        assertTrue(stringEqual(creator.profileData, profileData));

        // Check that the creator was added to the total count
        assertEq(creatorRegistry.getTotalCreators(), 1);

        // Check that the creator can be retrieved by index
        assertEq(creatorRegistry.getCreatorByIndex(0), creator1);
    }

    /**
     * @dev Tests that registration fails when subscription price is too low
     * @notice This tests our price validation logic
     */
    function test_RegisterCreator_PriceTooLow() public {
        // Arrange: Set up a price that's below the minimum
        uint256 invalidPrice = MIN_SUBSCRIPTION_PRICE - 1;
        string memory profileData = SAMPLE_PROFILE_DATA;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.registerCreator(invalidPrice, profileData);
        vm.stopPrank();

        // Verify that the creator was NOT registered
        assertFalse(creatorRegistry.isRegisteredCreator(creator1));
        assertEq(creatorRegistry.getTotalCreators(), 0);
    }

    /**
     * @dev Tests that registration fails when subscription price is too high
     * @notice This tests the upper bound of our price validation
     */
    function test_RegisterCreator_PriceTooHigh() public {
        // Arrange: Set up a price that's above the maximum
        uint256 invalidPrice = MAX_SUBSCRIPTION_PRICE + 1;
        string memory profileData = SAMPLE_PROFILE_DATA;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.registerCreator(invalidPrice, profileData);
        vm.stopPrank();

        // Verify that the creator was NOT registered
        assertFalse(creatorRegistry.isRegisteredCreator(creator1));
    }

    /**
     * @dev Tests that registration fails with empty profile data
     * @notice This tests our profile data validation
     */
    function test_RegisterCreator_EmptyProfileData() public {
        // Arrange: Set up empty profile data
        uint256 subscriptionPrice = DEFAULT_SUBSCRIPTION_PRICE;
        string memory emptyProfileData = "";

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidProfileData.selector);
        creatorRegistry.registerCreator(subscriptionPrice, emptyProfileData);
        vm.stopPrank();

        // Verify that the creator was NOT registered
        assertFalse(creatorRegistry.isRegisteredCreator(creator1));
    }

    /**
     * @dev Tests that a creator cannot register twice
     * @notice This tests our duplicate registration prevention
     */
    function test_RegisterCreator_AlreadyRegistered() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act & Assert: Try to register the same creator again
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorAlreadyRegistered.selector);
        creatorRegistry.registerCreator(DEFAULT_SUBSCRIPTION_PRICE, SAMPLE_PROFILE_DATA);
        vm.stopPrank();

        // Verify that the total count didn't increase
        assertEq(creatorRegistry.getTotalCreators(), 1);
    }

    /**
     * @dev Tests registration with minimum valid price
     * @notice This tests the exact boundary condition
     */
    function test_RegisterCreator_MinimumPrice() public {
        // Arrange: Use the minimum allowed price
        uint256 minPrice = MIN_SUBSCRIPTION_PRICE;
        string memory profileData = SAMPLE_PROFILE_DATA;

        // Act: Register with minimum price
        vm.startPrank(creator1);
        creatorRegistry.registerCreator(minPrice, profileData);
        vm.stopPrank();

        // Assert: Verify registration succeeded
        assertTrue(creatorRegistry.isRegisteredCreator(creator1));
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), minPrice);
    }

    /**
     * @dev Tests registration with maximum valid price
     * @notice This tests the other boundary condition
     */
    function test_RegisterCreator_MaximumPrice() public {
        // Arrange: Use the maximum allowed price
        uint256 maxPrice = MAX_SUBSCRIPTION_PRICE;
        string memory profileData = SAMPLE_PROFILE_DATA;

        // Act: Register with maximum price
        vm.startPrank(creator1);
        creatorRegistry.registerCreator(maxPrice, profileData);
        vm.stopPrank();

        // Assert: Verify registration succeeded
        assertTrue(creatorRegistry.isRegisteredCreator(creator1));
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), maxPrice);
    }

    // ============ SUBSCRIPTION PRICE UPDATE TESTS ============

    /**
     * @dev Tests successful subscription price update
     * @notice This tests the happy path for price updates
     */
    function test_UpdateSubscriptionPrice_Success() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        uint256 oldPrice = DEFAULT_SUBSCRIPTION_PRICE;
        uint256 newPrice = 2e6; // $2 USDC

        // Act: Update the subscription price
        vm.startPrank(creator1);

        // Expect the price update event
        vm.expectEmit(true, false, false, true);
        emit SubscriptionPriceUpdated(creator1, oldPrice, newPrice);

        creatorRegistry.updateSubscriptionPrice(newPrice);
        vm.stopPrank();

        // Assert: Verify the price was updated
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), newPrice);

        // Verify the creator profile reflects the change
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(creator.subscriptionPrice, newPrice);
    }

    /**
     * @dev Tests that non-registered creators cannot update prices
     * @notice This tests our access control
     */
    function test_UpdateSubscriptionPrice_NotRegistered() public {
        // Arrange: Use a creator that hasn't registered
        uint256 newPrice = 2e6; // $2 USDC

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.CreatorNotRegistered.selector);
        creatorRegistry.updateSubscriptionPrice(newPrice);
        vm.stopPrank();
    }

    /**
     * @dev Tests that subscription price update fails with invalid price
     * @notice This tests price validation during updates
     */
    function test_UpdateSubscriptionPrice_InvalidPrice() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        uint256 invalidPrice = MIN_SUBSCRIPTION_PRICE - 1;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidSubscriptionPrice.selector);
        creatorRegistry.updateSubscriptionPrice(invalidPrice);
        vm.stopPrank();

        // Verify the price wasn't changed
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), DEFAULT_SUBSCRIPTION_PRICE);
    }

    // ============ PROFILE DATA UPDATE TESTS ============

    /**
     * @dev Tests successful profile data update
     * @notice This tests updating creator metadata
     */
    function test_UpdateProfileData_Success() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        string memory oldProfileData = SAMPLE_PROFILE_DATA;
        string memory newProfileData = SAMPLE_PROFILE_DATA_2;

        // Act: Update the profile data
        vm.startPrank(creator1);
        creatorRegistry.updateProfileData(newProfileData);
        vm.stopPrank();

        // Assert: Verify the profile data was updated
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(stringEqual(creator.profileData, newProfileData));
        assertFalse(stringEqual(creator.profileData, oldProfileData));
    }

    /**
     * @dev Tests that profile data update fails with empty data - FIXED
     * @notice This tests our profile data validation
     */
    function test_UpdateProfileData_EmptyData() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        string memory emptyData = "";

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.InvalidProfileData.selector);
        creatorRegistry.updateProfileData(emptyData);
        vm.stopPrank();

        // FIXED: Verify the profile data wasn't changed (should still be "Test Profile 1", not SAMPLE_PROFILE_DATA)
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(stringEqual(creator.profileData, "Test Profile 1"));
    }

    // ============ CREATOR VERIFICATION TESTS ============

    /**
     * @dev Tests successful creator verification by admin
     * @notice This tests our verification system
     */
    function test_SetCreatorVerification_Success() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act: Verify the creator as admin
        vm.startPrank(admin);

        // Expect the verification event
        vm.expectEmit(true, false, false, true);
        emit CreatorVerified(creator1, true);

        creatorRegistry.setCreatorVerification(creator1, true);
        vm.stopPrank();

        // Assert: Verify the creator is now verified
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(creator.isVerified);

        // Verify they're in the verified creators list
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 1);
        assertEq(creatorRegistry.getVerifiedCreatorByIndex(0), creator1);
    }

    /**
     * @dev Tests removing verification from a creator
     * @notice This tests the unverification process
     */
    function test_SetCreatorVerification_RemoveVerification() public {
        // Arrange: Register and verify a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        // Verify they're verified
        assertTrue(creatorRegistry.getCreatorProfile(creator1).isVerified);
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 1);

        // Act: Remove verification
        vm.startPrank(admin);

        // Expect the verification removal event
        vm.expectEmit(true, false, false, true);
        emit CreatorVerified(creator1, false);

        creatorRegistry.setCreatorVerification(creator1, false);
        vm.stopPrank();

        // Assert: Verify the creator is no longer verified
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertFalse(creator.isVerified);

        // Verify they're removed from the verified creators list
        assertEq(creatorRegistry.getVerifiedCreatorCount(), 0);
    }

    /**
     * @dev Tests that only moderators can verify creators
     * @notice This tests our access control for verification
     */
    function test_SetCreatorVerification_OnlyModerator() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act & Assert: Try to verify as a regular user
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to missing MODERATOR_ROLE
        creatorRegistry.setCreatorVerification(creator1, true);
        vm.stopPrank();

        // Verify the creator is still not verified
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertFalse(creator.isVerified);
    }

    // ============ EARNINGS MANAGEMENT TESTS ============

    /**
     * @dev Tests updating creator stats (earnings, content count, subscriber count)
     * @notice This tests the core function that other contracts use to update creator data
     */
    function test_UpdateCreatorStats_Success() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Give the test contract platform role to update stats
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));

        uint256 earnings = 1e6; // $1 USDC
        int256 contentDelta = 1; // Add 1 content
        int256 subscriberDelta = 1; // Add 1 subscriber

        // Act: Update creator stats
        vm.expectEmit(true, false, false, true);
        emit CreatorEarningsUpdated(creator1, earnings, "platform_activity");

        creatorRegistry.updateCreatorStats(creator1, earnings, contentDelta, subscriberDelta);

        // Assert: Verify the stats were updated
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(creator.totalEarnings, earnings);
        assertEq(creator.contentCount, 1);
        assertEq(creator.subscriberCount, 1);

        // Verify earnings are available for withdrawal
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, earnings);
        assertEq(total, earnings);
        assertEq(withdrawn, 0);
    }

    /**
     * @dev Tests that only platform contracts can update creator stats
     * @notice This tests our access control for stats updates
     */
    function test_UpdateCreatorStats_OnlyPlatformContract() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act & Assert: Try to update stats without platform role
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to missing PLATFORM_CONTRACT_ROLE
        creatorRegistry.updateCreatorStats(creator1, 1e6, 1, 1);
        vm.stopPrank();
    }

    /**
     * @dev Tests creator earnings withdrawal - FIXED
     * @notice This tests the withdrawal mechanism for creator earnings
     */
    function test_WithdrawCreatorEarnings_Success() public {
        // Arrange: Register a creator and give them earnings
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Give the test contract platform role to update stats
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));

        uint256 earnings = 1e6; // $1 USDC
        creatorRegistry.updateCreatorStats(creator1, earnings, 0, 0);

        // Get initial balances
        uint256 initialCreatorBalance = mockUSDC.balanceOf(creator1);

        // FIXED: Fund the contract using admin permissions (not the test contract directly)
        vm.startPrank(admin);
        mockUSDC.mint(address(creatorRegistry), earnings);
        vm.stopPrank();

        // Act: Withdraw earnings as the creator
        vm.startPrank(creator1);

        // Expect the withdrawal event
        vm.expectEmit(true, false, false, true);
        emit CreatorEarningsWithdrawn(creator1, earnings, block.timestamp);

        creatorRegistry.withdrawCreatorEarnings();
        vm.stopPrank();

        // Assert: Verify the withdrawal was successful
        assertEq(mockUSDC.balanceOf(creator1), initialCreatorBalance + earnings);

        // Verify earnings were reset
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, 0);
        assertEq(total, earnings);
        assertEq(withdrawn, earnings);
    }

    /**
     * @dev Tests that withdrawal fails when there are no earnings
     * @notice This tests the error handling for empty withdrawals
     */
    function test_WithdrawCreatorEarnings_NoEarnings() public {
        // Arrange: Register a creator with no earnings
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act & Assert: Try to withdraw with no earnings
        vm.startPrank(creator1);
        vm.expectRevert(CreatorRegistry.NoEarningsToWithdraw.selector);
        creatorRegistry.withdrawCreatorEarnings();
        vm.stopPrank();
    }

    // ============ PLATFORM FEE MANAGEMENT TESTS ============

    /**
     * @dev Tests updating platform fee
     * @notice This tests the admin function to change platform fees
     */
    function test_UpdatePlatformFee_Success() public {
        // Arrange: Set up a new fee rate
        uint256 oldFee = PLATFORM_FEE_BPS;
        uint256 newFee = 300; // 3%

        // Act: Update platform fee as admin
        vm.startPrank(admin);

        // Expect the fee update event
        vm.expectEmit(false, false, false, true);
        emit PlatformFeeUpdated(oldFee, newFee);

        creatorRegistry.updatePlatformFee(newFee);
        vm.stopPrank();

        // Assert: Verify the fee was updated
        assertEq(creatorRegistry.platformFee(), newFee);

        // Verify the fee calculation works with the new rate
        uint256 testAmount = 1e6; // $1 USDC
        uint256 expectedFee = (testAmount * newFee) / 10000;
        assertEq(creatorRegistry.calculatePlatformFee(testAmount), expectedFee);
    }

    /**
     * @dev Tests that platform fee cannot be set too high
     * @notice This tests our fee validation
     */
    function test_UpdatePlatformFee_TooHigh() public {
        // Arrange: Set up a fee that's too high
        uint256 invalidFee = 1001; // 10.01% (over 10% limit)

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(admin);
        vm.expectRevert(CreatorRegistry.InvalidFeePercentage.selector);
        creatorRegistry.updatePlatformFee(invalidFee);
        vm.stopPrank();

        // Verify the fee wasn't changed
        assertEq(creatorRegistry.platformFee(), PLATFORM_FEE_BPS);
    }

    /**
     * @dev Tests that only owner can update platform fee
     * @notice This tests our access control for fee updates
     */
    function test_UpdatePlatformFee_OnlyOwner() public {
        // Arrange: Set up a new fee rate
        uint256 newFee = 300; // 3%

        // Act & Assert: Try to update fee as non-owner
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to Ownable restrictions
        creatorRegistry.updatePlatformFee(newFee);
        vm.stopPrank();

        // Verify the fee wasn't changed
        assertEq(creatorRegistry.platformFee(), PLATFORM_FEE_BPS);
    }

    /**
     * @dev Tests updating fee recipient
     * @notice This tests changing where platform fees are sent
     */
    function test_UpdateFeeRecipient_Success() public {
        // Arrange: Set up a new fee recipient
        address newRecipient = address(0x9999);

        // Act: Update fee recipient as admin
        vm.startPrank(admin);

        // Expect the fee recipient update event
        vm.expectEmit(false, false, false, true);
        emit FeeRecipientUpdated(feeRecipient, newRecipient);

        creatorRegistry.updateFeeRecipient(newRecipient);
        vm.stopPrank();

        // Assert: Verify the recipient was updated
        assertEq(creatorRegistry.feeRecipient(), newRecipient);
    }

    /**
     * @dev Tests that fee recipient cannot be set to zero address
     * @notice This tests our address validation
     */
    function test_UpdateFeeRecipient_ZeroAddress() public {
        // Act & Assert: Try to set zero address as recipient
        vm.startPrank(admin);
        vm.expectRevert(CreatorRegistry.InvalidFeeRecipient.selector);
        creatorRegistry.updateFeeRecipient(address(0));
        vm.stopPrank();

        // Verify the recipient wasn't changed
        assertEq(creatorRegistry.feeRecipient(), feeRecipient);
    }

    /**
     * @dev Tests that only owner can update fee recipient
     * @notice This tests our access control for fee recipient updates
     */
    function test_UpdateFeeRecipient_OnlyOwner() public {
        // Arrange: Set up a new fee recipient
        address newRecipient = address(0x9999);

        // Act & Assert: Try to update recipient as non-owner
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to Ownable restrictions
        creatorRegistry.updateFeeRecipient(newRecipient);
        vm.stopPrank();

        // Verify the recipient wasn't changed
        assertEq(creatorRegistry.feeRecipient(), feeRecipient);
    }

    // ============ PLATFORM ANALYTICS TESTS ============

    /**
     * @dev Tests getting platform statistics
     * @notice This tests our analytics functions
     */
    function test_GetPlatformStats_Success() public {
        // Arrange: Create some test data
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));

        // Verify creator1 to have some verified creators
        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        // Add some earnings to creators
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));
        creatorRegistry.updateCreatorStats(creator1, 1e6, 1, 1);
        creatorRegistry.updateCreatorStats(creator2, 2e6, 2, 1);

        // Act: Get platform statistics
        (
            uint256 totalCreators,
            uint256 verifiedCreators,
            uint256 totalPlatformEarnings,
            uint256 totalCreatorEarnings,
            uint256 totalWithdrawnEarnings
        ) = creatorRegistry.getPlatformStats();

        // Assert: Verify the statistics are correct
        assertEq(totalCreators, 2);
        assertEq(verifiedCreators, 1);
        assertEq(totalCreatorEarnings, 3e6); // $1 + $2 USDC
        assertEq(totalWithdrawnEarnings, 0); // No withdrawals yet
    }

    /**
     * @dev Tests getting creator earnings information
     * @notice This tests the earnings tracking system
     */
    function test_GetCreatorEarnings_Success() public {
        // Arrange: Register a creator and give them earnings
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));

        uint256 initialEarnings = 1e6; // $1 USDC
        creatorRegistry.updateCreatorStats(creator1, initialEarnings, 0, 0);

        // Act: Get creator earnings info
        (uint256 pending, uint256 total, uint256 withdrawn) = creatorRegistry.getCreatorEarnings(creator1);

        // Assert: Verify the earnings information
        assertEq(pending, initialEarnings);
        assertEq(total, initialEarnings);
        assertEq(withdrawn, 0);

        // Add more earnings and verify cumulative tracking
        uint256 additionalEarnings = 0.5e6; // $0.50 USDC
        creatorRegistry.updateCreatorStats(creator1, additionalEarnings, 0, 0);

        (pending, total, withdrawn) = creatorRegistry.getCreatorEarnings(creator1);
        assertEq(pending, initialEarnings + additionalEarnings);
        assertEq(total, initialEarnings + additionalEarnings);
        assertEq(withdrawn, 0);
    }
}
