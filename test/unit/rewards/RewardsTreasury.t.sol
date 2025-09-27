// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { RewardsTreasury } from "../../../src/rewards/RewardsTreasury.sol";
import { RewardsTreasuryTestHelper } from "../../helpers/RewardsTreasuryTestHelper.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

/**
 * @title RewardsTreasuryTest
 * @dev Unit tests for RewardsTreasury contract - Treasury management tests
 * @notice Tests revenue collection, pool allocation, reward distribution, and treasury operations
 */
contract RewardsTreasuryTest is TestSetup {
    // Test contracts
    RewardsTreasury public testTreasury;
    RewardsTreasuryTestHelper public testHelper;
    MockERC20 public testUSDC;

    // Test data
    address testUser = address(0x1234);
    address testSource = address(0x5678);
    address testRevenueCollector = address(0x9ABC);
    address testRewardsDistributor = address(0xDEF0);
    address testTreasuryManager = address(0x1111);
    address testRecipient = address(0x2222);

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC
    uint256 constant REWARD_AMOUNT = 100e6; // 100 USDC
    uint256 constant CAMPAIGN_AMOUNT = 50e6; // 50 USDC

    bytes32 testCampaignId = keccak256("test-campaign");

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testUSDC = new MockERC20("USD Coin", "USDC", 6);
        testTreasury = new RewardsTreasury(address(testUSDC));

        // Create test helper
        testHelper = new RewardsTreasuryTestHelper(address(testTreasury));

        // Grant roles
        vm.prank(admin);
        testTreasury.grantRole(testTreasury.REVENUE_COLLECTOR_ROLE(), testRevenueCollector);

        vm.prank(admin);
        testTreasury.grantRole(testTreasury.REWARDS_DISTRIBUTOR_ROLE(), testRewardsDistributor);

        vm.prank(admin);
        testTreasury.grantRole(testTreasury.TREASURY_MANAGER_ROLE(), testTreasuryManager);

        // Mint tokens for testing
        testUSDC.mint(testSource, 2000e6);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(testTreasury.usdcToken()), address(testUSDC));
        assertEq(testTreasury.owner(), admin);

        // Test role setup
        assertTrue(testTreasury.hasRole(testTreasury.DEFAULT_ADMIN_ROLE(), admin));

        // Test initial allocation percentages
        assertEq(testTreasury.customerRewardsAllocation(), 4000); // 40%
        assertEq(testTreasury.creatorIncentivesAllocation(), 3500); // 35%
        assertEq(testTreasury.operationalAllocation(), 1500); // 15%
        assertEq(testTreasury.reserveAllocation(), 1000); // 10%

        // Test initial pool balances are zero
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, 0);
        assertEq(customerPool, 0);
        assertEq(creatorPool, 0);
        assertEq(operationalPool, 0);
        assertEq(reservePool, 0);
    }

    // ============ REVENUE DEPOSIT TESTS ============

    function test_DepositPlatformRevenue_ValidDeposit() public {
        // Approve treasury to spend tokens
        vm.prank(testSource);
        testUSDC.approve(address(testTreasury), DEPOSIT_AMOUNT);

        // Deposit revenue
        vm.prank(testRevenueCollector);
        vm.expectEmit(true, true, false, false);
        emit RewardsTreasury.RevenueDeposited(testSource, DEPOSIT_AMOUNT, block.timestamp);
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT, testSource);

        // Verify pool allocations
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, DEPOSIT_AMOUNT);

        // Check allocation calculations (1000 USDC)
        uint256 expectedCustomer = (DEPOSIT_AMOUNT * 4000) / 10000; // 400 USDC
        uint256 expectedCreator = (DEPOSIT_AMOUNT * 3500) / 10000; // 350 USDC
        uint256 expectedOperational = (DEPOSIT_AMOUNT * 1500) / 10000; // 150 USDC
        uint256 expectedReserve = DEPOSIT_AMOUNT - expectedCustomer - expectedCreator - expectedOperational; // 100 USDC

        assertEq(customerPool, expectedCustomer);
        assertEq(creatorPool, expectedCreator);
        assertEq(operationalPool, expectedOperational);
        assertEq(reservePool, expectedReserve);

        // Verify total revenue contribution
        assertEq(testTreasury.totalRevenueContributed(testSource), DEPOSIT_AMOUNT);
    }

    function test_DepositPlatformRevenue_MultipleDeposits() public {
        // First deposit
        vm.prank(testSource);
        testUSDC.approve(address(testTreasury), DEPOSIT_AMOUNT);

        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT, testSource);

        // Second deposit from different source
        address secondSource = address(0x3333);
        vm.prank(secondSource);
        testUSDC.approve(address(testTreasury), DEPOSIT_AMOUNT / 2);

        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT / 2, secondSource);

        // Verify accumulations
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, DEPOSIT_AMOUNT + DEPOSIT_AMOUNT / 2);

        // Verify separate revenue tracking
        assertEq(testTreasury.totalRevenueContributed(testSource), DEPOSIT_AMOUNT);
        assertEq(testTreasury.totalRevenueContributed(secondSource), DEPOSIT_AMOUNT / 2);
    }

    function test_DepositPlatformRevenue_UnauthorizedCaller() public {
        // Try to deposit with unauthorized caller
        vm.prank(testUser);
        vm.expectRevert("AccessControl: account 0x5000 is missing role");
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT, testSource);
    }

    function test_DepositPlatformRevenue_ZeroAmount() public {
        // Try to deposit zero amount
        vm.prank(testRevenueCollector);
        vm.expectRevert("Invalid amount");
        testTreasury.depositPlatformRevenue(0, testSource);
    }

    // ============ REWARD ALLOCATION TESTS ============

    function test_AllocateRewards_CustomerPool() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Allocate rewards from customer pool
        vm.prank(testRewardsDistributor);
        vm.expectEmit(true, true, false, false);
        emit RewardsTreasury.RewardsAllocated(testRecipient, REWARD_AMOUNT, "Customer Reward");
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 0, "Customer Reward"); // poolType = 0

        // Verify pool reduction
        (, uint256 customerPool, , , ) = testTreasury.getTreasuryStats();
        assertEq(customerPool, 400e6 - REWARD_AMOUNT); // 400 - 100 = 300 USDC

        // Verify pending rewards
        assertEq(testTreasury.pendingRewards(testRecipient), REWARD_AMOUNT);
    }

    function test_AllocateRewards_CreatorPool() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Allocate rewards from creator pool
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 1, "Creator Incentive"); // poolType = 1

        // Verify pool reduction
        (, , uint256 creatorPool, , ) = testTreasury.getTreasuryStats();
        assertEq(creatorPool, 350e6 - REWARD_AMOUNT); // 350 - 100 = 250 USDC

        // Verify pending rewards
        assertEq(testTreasury.pendingRewards(testRecipient), REWARD_AMOUNT);
    }

    function test_AllocateRewards_OperationalPool() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Allocate rewards from operational pool
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 2, "Operational Expense"); // poolType = 2

        // Verify pool reduction
        (, , , uint256 operationalPool, ) = testTreasury.getTreasuryStats();
        assertEq(operationalPool, 150e6 - REWARD_AMOUNT); // 150 - 100 = 50 USDC

        // Verify pending rewards
        assertEq(testTreasury.pendingRewards(testRecipient), REWARD_AMOUNT);
    }

    function test_AllocateRewards_UnauthorizedCaller() public {
        // Try to allocate rewards with unauthorized caller
        vm.prank(testUser);
        vm.expectRevert("AccessControl: account 0x5000 is missing role");
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 0, "Test");
    }

    function test_AllocateRewards_InvalidPoolType() public {
        // Try to allocate from invalid pool type
        vm.prank(testRewardsDistributor);
        vm.expectRevert("Invalid pool type");
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 3, "Test"); // Invalid pool type
    }

    function test_AllocateRewards_InsufficientPoolBalance() public {
        // Try to allocate more than available in pool
        vm.prank(testRewardsDistributor);
        vm.expectRevert("Insufficient customer rewards pool");
        testTreasury.allocateRewards(testRecipient, 500e6, 0, "Test"); // Try to allocate 500 USDC from 400 USDC pool
    }

    function test_AllocateRewards_ZeroAmount() public {
        // Try to allocate zero amount
        vm.prank(testRewardsDistributor);
        vm.expectRevert("Invalid amount");
        testTreasury.allocateRewards(testRecipient, 0, 0, "Test");
    }

    function test_AllocateRewards_ZeroAddressRecipient() public {
        // Try to allocate to zero address
        vm.prank(testRewardsDistributor);
        vm.expectRevert("Invalid recipient");
        testTreasury.allocateRewards(address(0), REWARD_AMOUNT, 0, "Test");
    }

    // ============ REWARDS CLAIMING TESTS ============

    function test_ClaimRewards_ValidClaim() public {
        // First allocate rewards
        _setupTreasuryWithFunds();
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, REWARD_AMOUNT, 0, "Test Reward");

        // Claim rewards
        vm.prank(testRecipient);
        vm.expectEmit(true, true, false, false);
        emit RewardsTreasury.RewardsClaimed(testRecipient, REWARD_AMOUNT);
        testTreasury.claimRewards();

        // Verify rewards cleared
        assertEq(testTreasury.pendingRewards(testRecipient), 0);

        // Verify balance transfer (would need to check recipient balance)
    }

    function test_ClaimRewards_NoPendingRewards() public {
        // Try to claim with no pending rewards
        vm.prank(testRecipient);
        vm.expectRevert("No rewards to claim");
        testTreasury.claimRewards();
    }

    function test_ClaimRewards_MultipleAllocations() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Allocate multiple rewards
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, 50e6, 0, "Reward 1");

        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, 30e6, 1, "Reward 2");

        // Claim all rewards
        vm.prank(testRecipient);
        testTreasury.claimRewards();

        // Verify all rewards claimed
        assertEq(testTreasury.pendingRewards(testRecipient), 0);
    }

    // ============ CAMPAIGN FUNDING TESTS ============

    function test_FundCampaign_CustomerPool() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Fund campaign from customer pool
        vm.prank(testTreasuryManager);
        vm.expectEmit(true, true, false, false);
        emit RewardsTreasury.CampaignFunded(testCampaignId, CAMPAIGN_AMOUNT);
        testTreasury.fundCampaign(testCampaignId, CAMPAIGN_AMOUNT, 0); // poolType = 0

        // Verify pool reduction
        (, uint256 customerPool, , , ) = testTreasury.getTreasuryStats();
        assertEq(customerPool, 400e6 - CAMPAIGN_AMOUNT);

        // Verify campaign budget
        assertEq(testTreasury.campaignBudgets(testCampaignId), CAMPAIGN_AMOUNT);
    }

    function test_FundCampaign_CreatorPool() public {
        // First deposit revenue
        _setupTreasuryWithFunds();

        // Fund campaign from creator pool
        vm.prank(testTreasuryManager);
        testTreasury.fundCampaign(testCampaignId, CAMPAIGN_AMOUNT, 1); // poolType = 1

        // Verify pool reduction
        (, , uint256 creatorPool, , ) = testTreasury.getTreasuryStats();
        assertEq(creatorPool, 350e6 - CAMPAIGN_AMOUNT);

        // Verify campaign budget
        assertEq(testTreasury.campaignBudgets(testCampaignId), CAMPAIGN_AMOUNT);
    }

    function test_FundCampaign_UnauthorizedCaller() public {
        // Try to fund campaign with unauthorized caller
        vm.prank(testUser);
        vm.expectRevert("AccessControl: account 0x5000 is missing role");
        testTreasury.fundCampaign(testCampaignId, CAMPAIGN_AMOUNT, 0);
    }

    function test_FundCampaign_ZeroAmount() public {
        // Try to fund campaign with zero amount
        vm.prank(testTreasuryManager);
        vm.expectRevert("Invalid amount");
        testTreasury.fundCampaign(testCampaignId, 0, 0);
    }

    function test_FundCampaign_InsufficientPoolBalance() public {
        // Try to fund more than available in pool
        vm.prank(testTreasuryManager);
        vm.expectRevert("Insufficient customer rewards pool");
        testTreasury.fundCampaign(testCampaignId, 500e6, 0); // Try to fund 500 USDC from 400 USDC pool
    }

    // ============ ALLOCATION UPDATE TESTS ============

    function test_UpdateAllocations_ValidPercentages() public {
        // Update allocations with new percentages
        vm.prank(testTreasuryManager);
        testTreasury.updateAllocations(3000, 4000, 2000, 1000); // 30%, 40%, 20%, 10%

        // Verify updated allocations
        assertEq(testTreasury.customerRewardsAllocation(), 3000);
        assertEq(testTreasury.creatorIncentivesAllocation(), 4000);
        assertEq(testTreasury.operationalAllocation(), 2000);
        assertEq(testTreasury.reserveAllocation(), 1000);
    }

    function test_UpdateAllocations_UnauthorizedCaller() public {
        // Try to update allocations with unauthorized caller
        vm.prank(testUser);
        vm.expectRevert("AccessControl: account 0x5000 is missing role");
        testTreasury.updateAllocations(3000, 4000, 2000, 1000);
    }

    function test_UpdateAllocations_InvalidPercentages() public {
        // Try to update with percentages that don't sum to 100%
        vm.prank(testTreasuryManager);
        vm.expectRevert("Must total 100%");
        testTreasury.updateAllocations(3000, 4000, 2000, 500); // Only 95%
    }

    // ============ EMERGENCY WITHDRAWAL TESTS ============

    function test_EmergencyWithdraw_ValidWithdrawal() public {
        // First deposit revenue to build reserve pool
        _setupTreasuryWithFunds();

        // Get initial pool balances for verification
        ( , uint256 initialCustomer, uint256 initialCreator, uint256 initialOperational, uint256 initialReserve) = testTreasury.getTreasuryStats();
        uint256 withdrawAmount = 50e6; // 50 USDC

        // Emergency withdraw
        vm.prank(admin);
        testTreasury.emergencyWithdraw(withdrawAmount);

        // Verify reserve pool reduction
        ( , uint256 finalCustomer, uint256 finalCreator, uint256 finalOperational, uint256 finalReserve) = testTreasury.getTreasuryStats();
        assertEq(finalReserve, initialReserve - withdrawAmount);
    }

    function test_EmergencyWithdraw_UnauthorizedCaller() public {
        // Try emergency withdraw with unauthorized caller
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testTreasury.emergencyWithdraw(50e6);
    }

    function test_EmergencyWithdraw_InsufficientReserve() public {
        // Try to withdraw more than reserve pool has
        vm.prank(admin);
        vm.expectRevert("Insufficient reserve funds");
        testTreasury.emergencyWithdraw(200e6); // Try to withdraw 200 USDC from 100 USDC reserve
    }

    // ============ TREASURY STATISTICS TESTS ============

    function test_GetTreasuryStats_InitialState() public {
        // Get initial treasury stats
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, 0);
        assertEq(customerPool, 0);
        assertEq(creatorPool, 0);
        assertEq(operationalPool, 0);
        assertEq(reservePool, 0);
    }

    function test_GetTreasuryStats_AfterDeposits() public {
        // Deposit revenue
        _setupTreasuryWithFunds();

        // Get treasury stats
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, 1000e6);
        assertEq(customerPool, 400e6);
        assertEq(creatorPool, 350e6);
        assertEq(operationalPool, 150e6);
        assertEq(reservePool, 100e6);
    }

    function test_GetTreasuryStats_AfterAllocations() public {
        // Deposit and allocate
        _setupTreasuryWithFunds();

        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, 50e6, 0, "Test"); // Allocate from customer pool

        // Get updated treasury stats
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, 950e6); // 1000 - 50 = 950 USDC
        assertEq(customerPool, 350e6); // 400 - 50 = 350 USDC
        assertEq(creatorPool, 350e6); // unchanged
        assertEq(operationalPool, 150e6); // unchanged
        assertEq(reservePool, 100e6); // unchanged
    }

    // ============ INTEGRATION TESTS ============

    function test_FullTreasuryWorkflow() public {
        // 1. Deposit platform revenue
        vm.prank(testSource);
        testUSDC.approve(address(testTreasury), DEPOSIT_AMOUNT);

        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT, testSource);

        // 2. Verify initial allocation
        (
            uint256 totalBalance,
            uint256 customerPool,
            uint256 creatorPool,
            uint256 operationalPool,
            uint256 reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, DEPOSIT_AMOUNT);
        assertEq(customerPool, 400e6); // 40%
        assertEq(creatorPool, 350e6); // 35%
        assertEq(operationalPool, 150e6); // 15%
        assertEq(reservePool, 100e6); // 10%

        // 3. Allocate rewards from different pools
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, 50e6, 0, "Customer Reward"); // From customer pool

        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(testRecipient, 30e6, 1, "Creator Incentive"); // From creator pool

        // 4. Fund a campaign
        vm.prank(testTreasuryManager);
        testTreasury.fundCampaign(testCampaignId, 25e6, 2); // From operational pool

        // 5. Verify updated balances
        (
            totalBalance,
            customerPool,
            creatorPool,
            operationalPool,
            reservePool
        ) = testTreasury.getTreasuryStats();

        assertEq(totalBalance, 845e6); // 1000 - 50 - 30 - 25 = 845 USDC
        assertEq(customerPool, 350e6); // 400 - 50 = 350 USDC
        assertEq(creatorPool, 320e6); // 350 - 30 = 320 USDC
        assertEq(operationalPool, 125e6); // 150 - 25 = 125 USDC
        assertEq(reservePool, 100e6); // unchanged

        // 6. Claim rewards
        vm.prank(testRecipient);
        testTreasury.claimRewards();

        assertEq(testTreasury.pendingRewards(testRecipient), 0);
    }

    function test_MultipleSourceRevenueTracking() public {
        // Track revenue from multiple sources
        address source1 = address(0x1111);
        address source2 = address(0x2222);
        address source3 = address(0x3333);

        // Deposit from multiple sources
        vm.prank(source1);
        testUSDC.approve(address(testTreasury), 500e6);
        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(500e6, source1);

        vm.prank(source2);
        testUSDC.approve(address(testTreasury), 300e6);
        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(300e6, source2);

        vm.prank(source3);
        testUSDC.approve(address(testTreasury), 200e6);
        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(200e6, source3);

        // Verify separate tracking
        assertEq(testTreasury.totalRevenueContributed(source1), 500e6);
        assertEq(testTreasury.totalRevenueContributed(source2), 300e6);
        assertEq(testTreasury.totalRevenueContributed(source3), 200e6);

        // Verify total balance
        (uint256 totalBalance, , , , ) = testTreasury.getTreasuryStats();
        assertEq(totalBalance, 1000e6); // 500 + 300 + 200 = 1000 USDC
    }

    // ============ EDGE CASE TESTS ============

    function test_AllocateRewards_ToSelf() public {
        // Allocate rewards to treasury contract itself
        _setupTreasuryWithFunds();

        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(address(testTreasury), REWARD_AMOUNT, 0, "Self Allocation");

        assertEq(testTreasury.pendingRewards(address(testTreasury)), REWARD_AMOUNT);
    }

    function test_FundCampaign_MultipleTimes() public {
        // Fund same campaign multiple times
        _setupTreasuryWithFunds();

        vm.prank(testTreasuryManager);
        testTreasury.fundCampaign(testCampaignId, 25e6, 0);

        vm.prank(testTreasuryManager);
        testTreasury.fundCampaign(testCampaignId, 15e6, 0);

        // Verify accumulated budget
        assertEq(testTreasury.campaignBudgets(testCampaignId), 40e6); // 25 + 15 = 40 USDC

        // Verify pool reduction
        (, uint256 customerPool, , , ) = testTreasury.getTreasuryStats();
        assertEq(customerPool, 400e6 - 40e6); // 400 - 40 = 360 USDC
    }

    function test_EmergencyWithdraw_AllReserve() public {
        // Withdraw entire reserve pool
        _setupTreasuryWithFunds();

        // Get initial pool balances
        ( , uint256 initialCustomer, uint256 initialCreator, uint256 initialOperational, uint256 initialReserve) = testTreasury.getTreasuryStats();

        vm.prank(admin);
        testTreasury.emergencyWithdraw(50e6); // Withdraw fixed amount

        // Verify reserve pool reduction
        ( , uint256 finalCustomer, uint256 finalCreator, uint256 finalOperational, uint256 finalReserve) = testTreasury.getTreasuryStats();
        assertEq(finalReserve, 0); // Should be zero if we withdrew all
    }

    // ============ HELPER FUNCTIONS ============

    function _setupTreasuryWithFunds() internal {
        vm.prank(testSource);
        testUSDC.approve(address(testTreasury), DEPOSIT_AMOUNT);

        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(DEPOSIT_AMOUNT, testSource);
    }

    // ============ FUZZING TESTS ============

    function testFuzz_DepositPlatformRevenue_ValidAmounts(
        uint256 amount,
        address source
    ) public {
        // Assume valid inputs
        vm.assume(amount > 0 && amount <= 10000e6); // Max $10,000
        vm.assume(source != address(0));

        // Mint tokens for source
        testUSDC.mint(source, amount);

        // Approve and deposit
        vm.prank(source);
        testUSDC.approve(address(testTreasury), amount);

        vm.prank(testRevenueCollector);
        testTreasury.depositPlatformRevenue(amount, source);

        // Verify deposit was recorded
        assertEq(testTreasury.totalRevenueContributed(source), amount);
    }

    function testFuzz_AllocateRewards_ValidInputs(
        address recipient,
        uint256 amount,
        uint8 poolType
    ) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0 && amount <= 1000e6); // Max $1,000
        vm.assume(poolType <= 2); // Valid pool types: 0, 1, 2

        // Set up treasury with funds
        _setupTreasuryWithFunds();

        // Allocate rewards
        vm.prank(testRewardsDistributor);
        testTreasury.allocateRewards(recipient, amount, poolType, "Test Reward");

        // Verify allocation
        assertEq(testTreasury.pendingRewards(recipient), amount);
    }

    function testFuzz_UpdateAllocations_ValidPercentages(
        uint256 customerPct,
        uint256 creatorPct,
        uint256 operationalPct,
        uint256 reservePct
    ) public {
        // Assume valid percentage combinations that sum to 100%
        vm.assume(customerPct + creatorPct + operationalPct + reservePct == 10000);

        // Update allocations
        vm.prank(testTreasuryManager);
        testTreasury.updateAllocations(customerPct, creatorPct, operationalPct, reservePct);

        // Verify updated allocations
        assertEq(testTreasury.customerRewardsAllocation(), customerPct);
        assertEq(testTreasury.creatorIncentivesAllocation(), creatorPct);
        assertEq(testTreasury.operationalAllocation(), operationalPct);
        assertEq(testTreasury.reserveAllocation(), reservePct);
    }

    function testFuzz_FundCampaign_ValidInputs(
        bytes32 campaignId,
        uint256 amount,
        uint8 poolType
    ) public {
        vm.assume(amount > 0 && amount <= 500e6); // Max $500
        vm.assume(poolType <= 2); // Valid pool types: 0, 1, 2

        // Set up treasury with funds
        _setupTreasuryWithFunds();

        // Fund campaign
        vm.prank(testTreasuryManager);
        testTreasury.fundCampaign(campaignId, amount, poolType);

        // Verify campaign funding
        assertEq(testTreasury.campaignBudgets(campaignId), amount);
    }
}
