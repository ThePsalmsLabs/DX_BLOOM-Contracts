// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";

/**
 * @title CreatorRegistryTest
 * @dev Comprehensive unit tests for the CreatorRegistry contract
 * @notice This test suite covers all aspects of creator management including registration,
 *         pricing updates, earnings tracking, and administrative functions. We test both
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
     * @dev Tests that profile data update fails with empty data
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

        // Verify the profile data wasn't changed
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertTrue(stringEqual(creator.profileData, SAMPLE_PROFILE_DATA));
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
     * @dev Tests creator earnings withdrawal
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
        uint256 initialContractBalance = mockUSDC.balanceOf(address(creatorRegistry));

        // Fund the contract so it can pay out earnings
        mockUSDC.mint(address(creatorRegistry), earnings);

        // Act: Withdraw earnings
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
        vm.expectRevert(); // Should revert due to Ownable restriction
        creatorRegistry.updatePlatformFee(newFee);
        vm.stopPrank();

        // Verify the fee wasn't changed
        assertEq(creatorRegistry.platformFee(), PLATFORM_FEE_BPS);
    }

    // ============ PLATFORM ANALYTICS TESTS ============

    /**
     * @dev Tests getting platform statistics
     * @notice This tests our analytics functionality
     */
    function test_GetPlatformStats_Success() public {
        // Arrange: Register multiple creators with different verification status
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));

        // Verify one creator
        vm.prank(admin);
        creatorRegistry.setCreatorVerification(creator1, true);

        // Give them some earnings
        vm.prank(admin);
        creatorRegistry.grantPlatformRole(address(this));

        creatorRegistry.updateCreatorStats(creator1, 1e6, 1, 1);
        creatorRegistry.updateCreatorStats(creator2, 2e6, 2, 2);

        // Act: Get platform stats
        (
            uint256 totalCreators,
            uint256 verifiedCount,
            uint256 totalEarnings,
            uint256 creatorEarnings,
            uint256 withdrawnAmount
        ) = creatorRegistry.getPlatformStats();

        // Assert: Verify the stats are correct
        assertEq(totalCreators, 2);
        assertEq(verifiedCount, 1);
        assertEq(totalEarnings, 0); // No platform fees withdrawn yet
        assertEq(creatorEarnings, 3e6); // $3 total creator earnings
        assertEq(withdrawnAmount, 0); // No withdrawals yet
    }

    /**
     * @dev Tests multiple creators registration and retrieval
     * @notice This tests our creator management at scale
     */
    function test_MultipleCreators_Success() public {
        // Arrange: Register multiple creators
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));

        // Act & Assert: Verify both creators are registered
        assertEq(creatorRegistry.getTotalCreators(), 2);

        // Verify we can retrieve both creators by index
        assertEq(creatorRegistry.getCreatorByIndex(0), creator1);
        assertEq(creatorRegistry.getCreatorByIndex(1), creator2);

        // Verify their individual settings
        assertEq(creatorRegistry.getSubscriptionPrice(creator1), DEFAULT_SUBSCRIPTION_PRICE);
        assertEq(creatorRegistry.getSubscriptionPrice(creator2), DEFAULT_SUBSCRIPTION_PRICE);

        // Verify their profiles are correct
        CreatorRegistry.Creator memory c1 = creatorRegistry.getCreatorProfile(creator1);
        CreatorRegistry.Creator memory c2 = creatorRegistry.getCreatorProfile(creator2);

        assertTrue(stringEqual(c1.profileData, "Test Profile 1"));
        assertTrue(stringEqual(c2.profileData, "Test Profile 2"));
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @dev Tests that contract can be paused and unpaused
     * @notice This tests our emergency pause functionality
     */
    function test_PauseUnpause_Success() public {
        // Arrange: Register a creator first
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));

        // Act: Pause the contract
        vm.prank(admin);
        creatorRegistry.pause();

        // Assert: Registration should fail when paused
        vm.startPrank(creator2);
        vm.expectRevert(); // Should revert due to whenNotPaused modifier
        creatorRegistry.registerCreator(DEFAULT_SUBSCRIPTION_PRICE, SAMPLE_PROFILE_DATA);
        vm.stopPrank();

        // Act: Unpause the contract
        vm.prank(admin);
        creatorRegistry.unpause();

        // Assert: Registration should work again
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));
        assertEq(creatorRegistry.getTotalCreators(), 2);
    }

    /**
     * @dev Tests fee calculation with various amounts
     * @notice This tests our fee calculation logic thoroughly
     */
    function test_FeeCalculation_Various() public {
        // Test with different amounts
        uint256[] memory testAmounts = new uint256[](4);
        testAmounts[0] = 1e6; // $1
        testAmounts[1] = 10e6; // $10
        testAmounts[2] = 100e6; // $100
        testAmounts[3] = 1000e6; // $1000

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            uint256 expectedFee = (amount * PLATFORM_FEE_BPS) / 10000;
            uint256 actualFee = creatorRegistry.calculatePlatformFee(amount);
            assertEq(actualFee, expectedFee);
        }
    }

    /**
     * @dev Tests that invalid creator addresses are handled correctly
     * @notice This tests our error handling for invalid inputs
     */
    function test_InvalidCreatorAddress_Handling() public {
        // Test with zero address
        assertFalse(creatorRegistry.isRegisteredCreator(address(0)));
        assertEq(creatorRegistry.getSubscriptionPrice(address(0)), 0);

        // Test with unregistered address
        assertFalse(creatorRegistry.isRegisteredCreator(address(0x9999)));
        assertEq(creatorRegistry.getSubscriptionPrice(address(0x9999)), 0);
    }
}
