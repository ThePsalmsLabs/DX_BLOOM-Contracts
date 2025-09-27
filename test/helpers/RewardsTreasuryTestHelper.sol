// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/rewards/RewardsTreasury.sol";

/**
 * @title RewardsTreasuryTestHelper
 * @dev Test utilities for RewardsTreasury - NOT FOR PRODUCTION DEPLOYMENT
 * @notice This contract provides testing-specific functionality
 */
contract RewardsTreasuryTestHelper {
    RewardsTreasury public immutable rewardsTreasury;

    // ============ INTERNAL TEST STORAGE ============
    struct TestTreasuryPools {
        uint256 customerRewardsPool;
        uint256 creatorIncentivesPool;
        uint256 operationalPool;
        uint256 reservePool;
    }
    
    TestTreasuryPools private testPools;
    mapping(address => uint256) private testPendingRewards;
    mapping(bytes32 => uint256) private testCampaignBudgets;
    mapping(address => uint256) private testTotalRevenue;
    bool private useTestStorage;

    // ============ EVENTS ============
    event TestPoolsSet(uint256 customerRewards, uint256 creatorIncentives, uint256 operational, uint256 reserve);
    event TestPendingRewardsSet(address indexed user, uint256 amount);
    event TestCampaignBudgetSet(bytes32 indexed campaignId, uint256 amount);
    event TestRevenueSet(address indexed source, uint256 amount);

    // Test environment check
    modifier testOnly() {
        require(
            block.chainid == 31337 || // Foundry local
            block.chainid == 84532,   // Base Sepolia testnet
            "Test helper: Production use not allowed"
        );
        _;
    }

    constructor(address _rewardsTreasury) {
        require(_rewardsTreasury != address(0), "Invalid contract address");
        rewardsTreasury = RewardsTreasury(_rewardsTreasury);
    }

    /**
     * @dev TEST ONLY: Gets pool balances for testing
     * @return customerRewards Customer rewards pool balance
     * @return creatorIncentives Creator incentives pool balance
     * @return operational Operational pool balance
     * @return reserve Reserve pool balance
     */
    function getPoolBalancesForTesting() external view testOnly returns (
        uint256 customerRewards,
        uint256 creatorIncentives,
        uint256 operational,
        uint256 reserve
    ) {
        if (useTestStorage) {
            return (
                testPools.customerRewardsPool,
                testPools.creatorIncentivesPool,
                testPools.operationalPool,
                testPools.reservePool
            );
        }
        // Access through public interface only
        (, customerRewards, creatorIncentives, operational, reserve) = rewardsTreasury.getTreasuryStats();
    }

    /**
     * @dev TEST ONLY: Gets pending rewards for testing
     * @param user The user address
     * @return rewards Pending rewards amount
     */
    function getPendingRewardsForTesting(address user) external view testOnly returns (uint256 rewards) {
        return testPendingRewards[user];
    }

    /**
     * @dev TEST ONLY: Gets campaign budget for testing
     * @param campaignId The campaign ID
     * @return budget Campaign budget amount
     */
    function getCampaignBudgetForTesting(bytes32 campaignId) external view testOnly returns (uint256 budget) {
        return testCampaignBudgets[campaignId];
    }

    /**
     * @dev TEST ONLY: Gets total revenue contributed by source for testing
     * @param source The source address
     * @return revenue Total revenue contributed
     */
    function getTotalRevenueForTesting(address source) external view testOnly returns (uint256 revenue) {
        return testTotalRevenue[source];
    }

    /**
     * @dev TEST ONLY: Sets up test treasury scenario
     * @param customerRewards Customer rewards pool balance
     * @param creatorIncentives Creator incentives pool balance
     * @param operational Operational pool balance
     * @param reserve Reserve pool balance
     */
    function setupTestTreasuryScenario(
        uint256 customerRewards,
        uint256 creatorIncentives,
        uint256 operational,
        uint256 reserve
    ) external testOnly {
        testPools = TestTreasuryPools({
            customerRewardsPool: customerRewards,
            creatorIncentivesPool: creatorIncentives,
            operationalPool: operational,
            reservePool: reserve
        });
        useTestStorage = true;
        emit TestPoolsSet(customerRewards, creatorIncentives, operational, reserve);
    }

    /**
     * @dev TEST ONLY: Sets pending rewards for testing
     * @param user The user address
     * @param amount The pending rewards amount
     */
    function setPendingRewardsForTesting(address user, uint256 amount) external testOnly {
        testPendingRewards[user] = amount;
        emit TestPendingRewardsSet(user, amount);
    }

    /**
     * @dev TEST ONLY: Gets treasury statistics for testing
     * @return totalBalance Total treasury balance
     * @return customerPool Customer rewards pool
     * @return creatorPool Creator incentives pool
     * @return operationalPool Operational pool
     * @return reservePool Reserve pool
     */
    function getTreasuryStatsForTesting() external view testOnly returns (
        uint256 totalBalance,
        uint256 customerPool,
        uint256 creatorPool,
        uint256 operationalPool,
        uint256 reservePool
    ) {
        // Access through public interface only
        return rewardsTreasury.getTreasuryStats();
    }

    /**
     * @dev TEST ONLY: Sets campaign budget for testing
     * @param campaignId The campaign ID
     * @param amount The budget amount
     */
    function setCampaignBudgetForTesting(bytes32 campaignId, uint256 amount) external testOnly {
        testCampaignBudgets[campaignId] = amount;
        emit TestCampaignBudgetSet(campaignId, amount);
    }

    /**
     * @dev TEST ONLY: Sets total revenue for testing
     * @param source The source address
     * @param amount The revenue amount
     */
    function setTotalRevenueForTesting(address source, uint256 amount) external testOnly {
        testTotalRevenue[source] = amount;
        emit TestRevenueSet(source, amount);
    }

    /**
     * @dev TEST ONLY: Batch set pool balances for testing
     * @param balances Array of balances [customerRewards, creatorIncentives, operational, reserve]
     */
    function batchSetPoolBalancesForTesting(uint256[4] calldata balances) external testOnly {
        testPools = TestTreasuryPools({
            customerRewardsPool: balances[0],
            creatorIncentivesPool: balances[1],
            operationalPool: balances[2],
            reservePool: balances[3]
        });
        useTestStorage = true;
        emit TestPoolsSet(balances[0], balances[1], balances[2], balances[3]);
    }

    /**
     * @dev TEST ONLY: Setup test rewards allocation
     * @param recipient Address to receive rewards
     * @param amount Amount to allocate
     * @param poolType Pool type (0=customer, 1=creator, 2=operational)
     * @param rewardType Description of reward type
     */
    function setupTestRewardsAllocation(
        address recipient,
        uint256 amount,
        uint8 poolType,
        string memory rewardType
    ) external testOnly {
        // Simulate reward allocation by setting pending rewards
        testPendingRewards[recipient] += amount;
        
        // Deduct from appropriate test pool
        if (useTestStorage) {
            if (poolType == 0 && testPools.customerRewardsPool >= amount) {
                testPools.customerRewardsPool -= amount;
            } else if (poolType == 1 && testPools.creatorIncentivesPool >= amount) {
                testPools.creatorIncentivesPool -= amount;
            } else if (poolType == 2 && testPools.operationalPool >= amount) {
                testPools.operationalPool -= amount;
            }
        }
        
        emit TestPendingRewardsSet(recipient, testPendingRewards[recipient]);
    }

    /**
     * @dev TEST ONLY: Setup test campaign funding
     * @param campaignId Campaign ID
     * @param amount Amount to fund
     * @param poolType Pool type to draw from
     */
    function setupTestCampaignFunding(
        bytes32 campaignId,
        uint256 amount,
        uint8 poolType
    ) external testOnly {
        // Set campaign budget
        testCampaignBudgets[campaignId] = amount;
        
        // Deduct from appropriate test pool if using test storage
        if (useTestStorage) {
            if (poolType == 0 && testPools.customerRewardsPool >= amount) {
                testPools.customerRewardsPool -= amount;
            } else if (poolType == 1 && testPools.creatorIncentivesPool >= amount) {
                testPools.creatorIncentivesPool -= amount;
            } else if (poolType == 2 && testPools.operationalPool >= amount) {
                testPools.operationalPool -= amount;
            }
        }
        
        emit TestCampaignBudgetSet(campaignId, amount);
    }

    /**
     * @dev TEST ONLY: Setup test revenue deposit
     * @param amount Revenue amount
     * @param source Source contract
     */
    function setupTestRevenueDeposit(
        uint256 amount,
        address source
    ) external testOnly {
        // Add to total revenue tracking
        testTotalRevenue[source] += amount;
        
        // Distribute to pools if using test storage
        if (useTestStorage) {
            // Use same allocation percentages as production: 40%, 35%, 15%, 10%
            uint256 customerAllocation = (amount * 4000) / 10000;
            uint256 creatorAllocation = (amount * 3500) / 10000;
            uint256 operationalAllocation = (amount * 1500) / 10000;
            uint256 reserveAllocation = amount - customerAllocation - creatorAllocation - operationalAllocation;
            
            testPools.customerRewardsPool += customerAllocation;
            testPools.creatorIncentivesPool += creatorAllocation;
            testPools.operationalPool += operationalAllocation;
            testPools.reservePool += reserveAllocation;
        }
        
        emit TestRevenueSet(source, testTotalRevenue[source]);
    }

    /**
     * @dev TEST ONLY: Reset all test data
     */
    function resetTestData() external testOnly {
        testPools = TestTreasuryPools(0, 0, 0, 0);
        useTestStorage = false;
        // Note: Cannot clear mappings completely, but setting useTestStorage = false
        // will make functions fall back to production data
    }

    /**
     * @dev TEST ONLY: Enable/disable test storage mode
     * @param enabled Whether to use test storage
     */
    function setTestStorageMode(bool enabled) external testOnly {
        useTestStorage = enabled;
    }

    /**
     * @dev TEST ONLY: Get test storage mode status
     * @return enabled Whether test storage mode is enabled
     */
    function isTestStorageModeEnabled() external view testOnly returns (bool enabled) {
        return useTestStorage;
    }
}