// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardsTreasury
 * @dev Central revenue collection and distribution hub for the incentive ecosystem
 * @notice Manages platform revenue allocation across customer rewards, creator incentives, and operational reserves
 */
contract RewardsTreasury is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant REVENUE_COLLECTOR_ROLE = keccak256("REVENUE_COLLECTOR_ROLE");
    bytes32 public constant REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    // ============ TREASURY POOLS ============
    struct TreasuryPools {
        uint256 customerRewardsPool;      // 40% - For customer incentives
        uint256 creatorIncentivesPool;    // 35% - For creator rewards
        uint256 operationalPool;          // 15% - For platform operations
        uint256 reservePool;              // 10% - Emergency reserves
    }

    TreasuryPools public pools;
    IERC20 public immutable usdcToken;

    // ============ REVENUE TRACKING ============
    mapping(address => uint256) public totalRevenueContributed;
    mapping(bytes32 => uint256) public campaignBudgets;
    mapping(address => uint256) public pendingRewards;

    // ============ ALLOCATION CONFIGURATION ============
    uint256 public customerRewardsAllocation = 4000;  // 40% in basis points
    uint256 public creatorIncentivesAllocation = 3500; // 35% in basis points
    uint256 public operationalAllocation = 1500;       // 15% in basis points
    uint256 public reserveAllocation = 1000;           // 10% in basis points

    // ============ EVENTS ============
    event RevenueDeposited(address indexed source, uint256 amount, uint256 timestamp);
    event RewardsAllocated(address indexed recipient, uint256 amount, string rewardType);
    event PoolsRebalanced(TreasuryPools oldPools, TreasuryPools newPools);
    event CampaignFunded(bytes32 indexed campaignId, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    // ============ CONSTRUCTOR ============
    constructor(address _usdcToken) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TREASURY_MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Deposits platform revenue and distributes to pools
     * @param amount Revenue amount to deposit
     * @param source Source contract that generated the revenue
     */
    function depositPlatformRevenue(uint256 amount, address source)
        external
        onlyRole(REVENUE_COLLECTOR_ROLE)
        nonReentrant
    {
        require(amount > 0, "Invalid amount");

        // Transfer USDC from source
        usdcToken.safeTransferFrom(source, address(this), amount);

        // Allocate to pools based on percentages
        uint256 customerAllocation = (amount * customerRewardsAllocation) / 10000;
        uint256 creatorAllocation = (amount * creatorIncentivesAllocation) / 10000;
        uint256 operationalAllocationAmount = (amount * operationalAllocation) / 10000;
        uint256 reserveAllocationAmount = amount - customerAllocation - creatorAllocation - operationalAllocationAmount;

        pools.customerRewardsPool += customerAllocation;
        pools.creatorIncentivesPool += creatorAllocation;
        pools.operationalPool += operationalAllocationAmount;
        pools.reservePool += reserveAllocationAmount;

        totalRevenueContributed[source] += amount;

        emit RevenueDeposited(source, amount, block.timestamp);
    }

    /**
     * @dev Allocates rewards from appropriate pool
     * @param recipient Address to receive rewards
     * @param amount Amount to allocate
     * @param poolType Which pool to draw from (0=customer, 1=creator, 2=operational)
     * @param rewardType Description of reward type
     */
    function allocateRewards(
        address recipient,
        uint256 amount,
        uint8 poolType,
        string memory rewardType
    ) external onlyRole(REWARDS_DISTRIBUTOR_ROLE) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        if (poolType == 0) {
            require(pools.customerRewardsPool >= amount, "Insufficient customer rewards pool");
            pools.customerRewardsPool -= amount;
        } else if (poolType == 1) {
            require(pools.creatorIncentivesPool >= amount, "Insufficient creator incentives pool");
            pools.creatorIncentivesPool -= amount;
        } else if (poolType == 2) {
            require(pools.operationalPool >= amount, "Insufficient operational pool");
            pools.operationalPool -= amount;
        } else {
            revert("Invalid pool type");
        }

        pendingRewards[recipient] += amount;
        emit RewardsAllocated(recipient, amount, rewardType);
    }

    /**
     * @dev User claims their pending rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards to claim");

        pendingRewards[msg.sender] = 0;
        usdcToken.safeTransfer(msg.sender, amount);

        emit RewardsClaimed(msg.sender, amount);
    }

    /**
     * @dev Funds a campaign from treasury pools
     */
    function fundCampaign(bytes32 campaignId, uint256 amount, uint8 poolType)
        external
        onlyRole(TREASURY_MANAGER_ROLE)
        nonReentrant
    {
        require(amount > 0, "Invalid amount");

        // Deduct from appropriate pool
        if (poolType == 0) {
            require(pools.customerRewardsPool >= amount, "Insufficient customer pool");
            pools.customerRewardsPool -= amount;
        } else if (poolType == 1) {
            require(pools.creatorIncentivesPool >= amount, "Insufficient creator pool");
            pools.creatorIncentivesPool -= amount;
        } else if (poolType == 2) {
            require(pools.operationalPool >= amount, "Insufficient operational pool");
            pools.operationalPool -= amount;
        }

        campaignBudgets[campaignId] += amount;
        emit CampaignFunded(campaignId, amount);
    }

    /**
     * @dev Updates allocation percentages (only treasury manager)
     */
    function updateAllocations(
        uint256 _customerRewards,
        uint256 _creatorIncentives,
        uint256 _operational,
        uint256 _reserve
    ) external onlyRole(TREASURY_MANAGER_ROLE) {
        require(_customerRewards + _creatorIncentives + _operational + _reserve == 10000, "Must total 100%");

        customerRewardsAllocation = _customerRewards;
        creatorIncentivesAllocation = _creatorIncentives;
        operationalAllocation = _operational;
        reserveAllocation = _reserve;
    }

    /**
     * @dev Gets current treasury statistics
     */
    function getTreasuryStats() external view returns (
        uint256 totalBalance,
        uint256 customerPool,
        uint256 creatorPool,
        uint256 operationalPool,
        uint256 reservePool
    ) {
        return (
            usdcToken.balanceOf(address(this)),
            pools.customerRewardsPool,
            pools.creatorIncentivesPool,
            pools.operationalPool,
            pools.reservePool
        );
    }

    /**
     * @dev Emergency withdrawal of reserve funds (only owner)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner nonReentrant {
        require(pools.reservePool >= amount, "Insufficient reserve funds");

        pools.reservePool -= amount;
        usdcToken.safeTransfer(owner(), amount);
    }
}
