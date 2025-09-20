// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/rewards/RewardsTreasury.sol";
import "../src/rewards/LoyaltyManager.sol";
import "../src/rewards/RewardsIntegration.sol";

/**
 * @title DeployRewardsSystem
 * @dev Deployment script for the complete rewards and incentives system
 * @notice Deploys treasury, loyalty manager, and integration contracts
 */
contract DeployRewardsSystem is Script {
    // Configuration
    address constant USDC_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base USDC
    address constant COMMERCE_PROTOCOL_CORE = address(0); // Set this to your deployed CommerceProtocolCore

    // Contract instances
    RewardsTreasury public rewardsTreasury;
    LoyaltyManager public loyaltyManager;
    RewardsIntegration public rewardsIntegration;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Rewards System...");

        // Phase 1: Deploy RewardsTreasury
        console.log("1. Deploying RewardsTreasury...");
        rewardsTreasury = new RewardsTreasury(USDC_TOKEN);
        console.log("RewardsTreasury deployed at:", address(rewardsTreasury));

        // Phase 2: Deploy LoyaltyManager
        console.log("2. Deploying LoyaltyManager...");
        loyaltyManager = new LoyaltyManager(address(rewardsTreasury));
        console.log("LoyaltyManager deployed at:", address(loyaltyManager));

        // Phase 3: Deploy RewardsIntegration
        console.log("3. Deploying RewardsIntegration...");
        require(COMMERCE_PROTOCOL_CORE != address(0), "Set COMMERCE_PROTOCOL_CORE address");
        rewardsIntegration = new RewardsIntegration(
            address(rewardsTreasury),
            address(loyaltyManager),
            COMMERCE_PROTOCOL_CORE
        );
        console.log("RewardsIntegration deployed at:", address(rewardsIntegration));

        // Phase 4: Configure permissions
        console.log("4. Configuring permissions...");
        _setupPermissions();

        // Phase 5: Initial funding (if needed)
        console.log("5. Setting up initial configuration...");
        _setupInitialConfiguration();

        console.log("Rewards System deployment completed!");
        console.log("===================================");
        console.log("RewardsTreasury:", address(rewardsTreasury));
        console.log("LoyaltyManager:", address(loyaltyManager));
        console.log("RewardsIntegration:", address(rewardsIntegration));
        console.log("===================================");

        vm.stopBroadcast();
    }

    function _setupPermissions() internal {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Grant roles to RewardsIntegration
        rewardsTreasury.grantRole(rewardsTreasury.REVENUE_COLLECTOR_ROLE(), address(rewardsIntegration));
        rewardsTreasury.grantRole(rewardsTreasury.REWARDS_DISTRIBUTOR_ROLE(), address(rewardsIntegration));

        // Grant roles to LoyaltyManager
        loyaltyManager.grantRole(loyaltyManager.POINTS_MANAGER_ROLE(), address(rewardsIntegration));
        loyaltyManager.grantRole(loyaltyManager.DISCOUNT_MANAGER_ROLE(), address(rewardsIntegration));

        // Grant roles to CommerceProtocol
        rewardsIntegration.grantRole(rewardsIntegration.REWARDS_TRIGGER_ROLE(), COMMERCE_PROTOCOL_CORE);

        console.log("Permissions configured for deployer:", deployer);
    }

    function _setupInitialConfiguration() internal {
        // Set up initial treasury allocations (default 40/35/15/10 split)
        // Can be modified later by treasury manager

        // Configure loyalty program parameters
        // Default settings are already configured in constructor

        console.log("Initial configuration completed");
    }

    /**
     * @dev Test function to verify deployment
     */
    function testDeployment() external view {
        require(address(rewardsTreasury) != address(0), "RewardsTreasury not deployed");
        require(address(loyaltyManager) != address(0), "LoyaltyManager not deployed");
        require(address(rewardsIntegration) != address(0), "RewardsIntegration not deployed");

        // Verify configurations
        (uint256 customerPool, uint256 creatorPool, uint256 operationalPool, uint256 reservePool) =
            rewardsTreasury.pools();

        require(customerPool == 0, "Treasury should start empty");
        require(creatorPool == 0, "Treasury should start empty");

        console.log("All contracts deployed and configured correctly!");
    }
}
