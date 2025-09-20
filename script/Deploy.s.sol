// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/CreatorRegistry.sol";
import "../src/ContentRegistry.sol";
import "../src/PayPerView.sol";
import "../src/SubscriptionManager.sol";
import "../src/CommerceProtocolCore.sol";
import "../src/CommerceProtocolPermit.sol";
import "../src/PriceOracle.sol";
import "../src/AdminManager.sol";
import "../src/ViewManager.sol";
import "../src/AccessManager.sol";
import "../src/SignatureManager.sol";
import "../src/RefundManager.sol";
import "../src/PermitPaymentManager.sol";
import "../src/BaseCommerceIntegration.sol";
import "../src/rewards/RewardsTreasury.sol";
import "../src/rewards/LoyaltyManager.sol";
import "../src/rewards/RewardsIntegration.sol";

/**
 * @title Deploy - FIXED VERSION
 * @dev Complete deployment script for the Onchain Content Subscription Platform
 * @notice Supports both Base mainnet and Base Sepolia deployments with proper network detection
 */
contract Deploy is Script {
    // Network Configuration
    struct NetworkConfig {
        address usdc;
        address authCaptureEscrow;      // Real Base Commerce Protocol escrow
        address permit2Collector;      // Real Permit2 token collector
        address permit2;               // Uniswap Permit2
        address quoterV2;
        address weth;
        uint256 chainId;
        string name;
    }

    // Deployment configuration
    address public platformOwner;
    address public feeRecipient;
    address public operatorSigner;

    // Deployed contracts
    PriceOracle public priceOracle;
    CreatorRegistry public creatorRegistry;
    ContentRegistry public contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    CommerceProtocolCore public commerceCore;
    CommerceProtocolPermit public commercePermit;
    AdminManager public adminManager;
    ViewManager public viewManager;
    AccessManager public accessManager;
    SignatureManager public signatureManager;
    RefundManager public refundManager;
    PermitPaymentManager public permitPaymentManager;
    BaseCommerceIntegration public baseCommerceIntegration;

    // Rewards system contracts
    RewardsTreasury public rewardsTreasury;
    LoyaltyManager public loyaltyManager;
    RewardsIntegration public rewardsIntegration;

    // Network configurations
    mapping(uint256 => NetworkConfig) public networkConfigs;

    function setUp() public {
        // Configure networks
        _configureNetworks();
    }

    function _configureNetworks() internal {
        // Base Mainnet (Chain ID: 8453)
        networkConfigs[8453] = NetworkConfig({
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            authCaptureEscrow: 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff,      // ✅ REAL
            permit2Collector: 0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26,       // ✅ REAL
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3, // Uniswap Permit2
            quoterV2: 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a,
            weth: 0x4200000000000000000000000000000000000006,
            chainId: 8453,
            name: "Base Mainnet"
        });

        // Base Sepolia (Chain ID: 84532)
        networkConfigs[84532] = NetworkConfig({
            usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            authCaptureEscrow: 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff,      // ✅ REAL
            permit2Collector: 0x992476B9Ee81d52a5BdA0622C333938D0Af0aB26,       // ✅ REAL
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3, // Uniswap Permit2
            quoterV2: 0xC5290058841028F1614F3A6F0F5816cAd0df5E27,
            weth: 0x4200000000000000000000000000000000000006,
            chainId: 84532,
            name: "Base Sepolia"
        });

        // Celo Mainnet (Chain ID: 42220)
        networkConfigs[42220] = NetworkConfig({
            usdc: 0xcebA9300f2b948710d2653dD7B07f33A8B32118C,           // Circle USDC
            authCaptureEscrow: address(0),                               // No Base Commerce Protocol on Celo
            permit2Collector: address(0),                                // No Base Commerce Protocol on Celo
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,        // Uniswap Permit2
            quoterV2: 0x82825d0554fA07f7FC52Ab63c961F330fdEFa8E8,       // Uniswap V3 QuoterV2
            weth: 0x471EcE3750Da237f93B8E339c536989b8978a438,           // CELO (native token)
            chainId: 42220,
            name: "Celo Mainnet"
        });

        // Celo Alfajores Testnet (Chain ID: 44787)
        networkConfigs[44787] = NetworkConfig({
            usdc: 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B,           // Test USDC on Alfajores
            authCaptureEscrow: address(0),                               // No Base Commerce Protocol on Celo
            permit2Collector: address(0),                                // No Base Commerce Protocol on Celo
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,        // Uniswap Permit2
            quoterV2: 0x3c1FCF8D6f3A579E98F4AE75EB0adA6de70f5673,       // Uniswap V3 QuoterV2
            weth: 0x471EcE3750Da237f93B8E339c536989b8978a438,           // CELO (native token)
            chainId: 44787,
            name: "Celo Alfajores"
        });
    }

    function run() public {
        NetworkConfig memory config = networkConfigs[block.chainid];
        require(config.chainId != 0, "Unsupported network");
        
        // Support both PRIVATE_KEY env and Foundry keystore accounts via --account
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }
        // Set platform owner to current broadcaster
        platformOwner = msg.sender;
        
        if (block.chainid == 8453) {
            // Base Mainnet - Production addresses
            feeRecipient = vm.envAddress("MAINNET_FEE_RECIPIENT");
            operatorSigner = vm.envAddress("MAINNET_OPERATOR_SIGNER");
        } else if (block.chainid == 84532) {
            // Base Sepolia - Test addresses
            feeRecipient = vm.envOr("TESTNET_FEE_RECIPIENT", msg.sender);
            operatorSigner = vm.envOr("TESTNET_OPERATOR_SIGNER", msg.sender);
        } else if (block.chainid == 42220) {
            // Celo Mainnet - Production addresses
            feeRecipient = vm.envAddress("CELO_MAINNET_FEE_RECIPIENT");
            operatorSigner = vm.envAddress("CELO_MAINNET_OPERATOR_SIGNER");
        } else if (block.chainid == 44787) {
            // Celo Alfajores - Test addresses
            feeRecipient = vm.envOr("CELO_TESTNET_FEE_RECIPIENT", msg.sender);
            operatorSigner = vm.envOr("CELO_TESTNET_OPERATOR_SIGNER", msg.sender);
        } else {
            revert("Unsupported network");
        }

        console.log("=== Deploying Onchain Content Subscription Platform ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("Deployer:", platformOwner);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Operator Signer:", operatorSigner);
        console.log("");

        _deployContracts(config);
        _setupPermissions();
        _configureIntegrations();
        _registerOperator();

        vm.stopBroadcast();
        
        _printDeploymentSummary();
        _printPostDeploymentInstructions();
    }

    function _deployContracts(NetworkConfig memory config) internal {
        // 1. Deploy PriceOracle
        console.log("1. Deploying PriceOracle...");
        priceOracle = new PriceOracle(config.quoterV2, config.weth, config.usdc);
        console.log("   PriceOracle deployed at:", address(priceOracle));

        // 2. Deploy CreatorRegistry
        console.log("2. Deploying CreatorRegistry...");
        creatorRegistry = new CreatorRegistry(feeRecipient, config.usdc);
        console.log("   CreatorRegistry deployed at:", address(creatorRegistry));

        // 3. Deploy ContentRegistry
        console.log("3. Deploying ContentRegistry...");
        contentRegistry = new ContentRegistry(address(creatorRegistry));
        console.log("   ContentRegistry deployed at:", address(contentRegistry));

        // 4. Deploy PayPerView
        console.log("4. Deploying PayPerView...");
        payPerView =
            new PayPerView(address(creatorRegistry), address(contentRegistry), address(priceOracle), config.usdc);
        console.log("   PayPerView deployed at:", address(payPerView));

        // 5. Deploy SubscriptionManager
        console.log("5. Deploying SubscriptionManager...");
        subscriptionManager = new SubscriptionManager(address(creatorRegistry), address(contentRegistry), config.usdc);
        console.log("   SubscriptionManager deployed at:", address(subscriptionManager));

        // 6. Deploy AdminManager
        console.log("6. Deploying AdminManager...");
        adminManager = new AdminManager(
            feeRecipient,
            operatorSigner
        );
        console.log("   AdminManager deployed at:", address(adminManager));

        // 7. Deploy ViewManager
        console.log("7. Deploying ViewManager...");
        viewManager = new ViewManager();
        console.log("   ViewManager deployed at:", address(viewManager));

        // 8. Deploy AccessManager
        console.log("8. Deploying AccessManager...");
        accessManager = new AccessManager(
            address(payPerView),
            address(subscriptionManager),
            address(creatorRegistry)
        );
        console.log("   AccessManager deployed at:", address(accessManager));

        // 9. Deploy SignatureManager
        console.log("9. Deploying SignatureManager...");
        signatureManager = new SignatureManager(operatorSigner);
        console.log("   SignatureManager deployed at:", address(signatureManager));

        // 10. Deploy RefundManager
        console.log("10. Deploying RefundManager...");
        refundManager = new RefundManager(address(payPerView), address(subscriptionManager), config.usdc);
        console.log("   RefundManager deployed at:", address(refundManager));

        // 11. Deploy BaseCommerceIntegration (REAL Base Commerce Protocol Integration)
        console.log("11. Deploying BaseCommerceIntegration...");
        baseCommerceIntegration = new BaseCommerceIntegration(
            config.usdc,
            feeRecipient
        );
        console.log("   BaseCommerceIntegration deployed at:", address(baseCommerceIntegration));

        // 12. Deploy Rewards System
        console.log("12. Deploying Rewards System...");
        
        // 12a. Deploy RewardsTreasury
        console.log("12a. Deploying RewardsTreasury...");
        rewardsTreasury = new RewardsTreasury(config.usdc);
        console.log("   RewardsTreasury deployed at:", address(rewardsTreasury));
        
        // 12b. Deploy LoyaltyManager
        console.log("12b. Deploying LoyaltyManager...");
        loyaltyManager = new LoyaltyManager(address(rewardsTreasury));
        console.log("   LoyaltyManager deployed at:", address(loyaltyManager));

        // 13. Deploy PermitPaymentManager
        console.log("12. Deploying PermitPaymentManager...");
        permitPaymentManager = new PermitPaymentManager(address(baseCommerceIntegration), config.permit2, config.usdc);
        console.log("   PermitPaymentManager deployed at:", address(permitPaymentManager));

        // 14. Deploy RewardsIntegration (requires CommerceProtocolCore address, will be set after deployment)
        console.log("14. Deploying RewardsIntegration placeholder...");
        // Note: We'll deploy this after CommerceProtocolCore and then update the reference

        // 15. Deploy CommerceProtocolCore (with all manager addresses)
        console.log("13. Deploying CommerceProtocolCore...");
        commerceCore = new CommerceProtocolCore(
            address(baseCommerceIntegration),
            config.permit2,
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            config.usdc,
            feeRecipient,
            operatorSigner,
            // Manager contract addresses
            address(adminManager),
            address(viewManager),
            address(accessManager),
            address(signatureManager),
            address(refundManager),
            address(permitPaymentManager),
            address(0) // Will be set after RewardsIntegration deployment
        );
        console.log("   CommerceProtocolCore deployed at:", address(commerceCore));

        // 14. Deploy CommerceProtocolPermit (with all manager addresses)
        console.log("14. Deploying CommerceProtocolPermit...");
        commercePermit = new CommerceProtocolPermit(
            address(baseCommerceIntegration),
            config.permit2,
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            config.usdc,
            feeRecipient,
            operatorSigner,
            // Manager contract addresses
            address(adminManager),
            address(viewManager),
            address(accessManager),
            address(signatureManager),
            address(refundManager),
            address(permitPaymentManager),
            address(0) // Will be set after RewardsIntegration deployment
        );
        console.log("   CommerceProtocolPermit deployed at:", address(commercePermit));

        // 16. Now deploy RewardsIntegration with proper CommerceProtocolCore address
        console.log("16. Deploying RewardsIntegration...");
        rewardsIntegration = new RewardsIntegration(
            address(rewardsTreasury),
            address(loyaltyManager),
            address(commerceCore)
        );
        console.log("   RewardsIntegration deployed at:", address(rewardsIntegration));

        // 17. Set RewardsIntegration in CommerceProtocol contracts
        console.log("17. Configuring RewardsIntegration references...");
        commerceCore.setRewardsIntegration(address(rewardsIntegration));
        commercePermit.setRewardsIntegration(address(rewardsIntegration));
        console.log("   RewardsIntegration configured in protocol contracts");

        // 18. Configure rewards system permissions
        console.log("18. Setting up rewards system permissions...");
        rewardsTreasury.grantRole(rewardsTreasury.REVENUE_COLLECTOR_ROLE(), address(rewardsIntegration));
        rewardsTreasury.grantRole(rewardsTreasury.REWARDS_DISTRIBUTOR_ROLE(), address(rewardsIntegration));
        loyaltyManager.grantRole(loyaltyManager.POINTS_MANAGER_ROLE(), address(rewardsIntegration));
        loyaltyManager.grantRole(loyaltyManager.DISCOUNT_MANAGER_ROLE(), address(rewardsIntegration));
        rewardsIntegration.grantRole(rewardsIntegration.REWARDS_TRIGGER_ROLE(), address(commerceCore));
        rewardsIntegration.grantRole(rewardsIntegration.REWARDS_TRIGGER_ROLE(), address(commercePermit));
        console.log("   Rewards system permissions configured");
    }

    function _setupPermissions() internal {
        // CRITICAL: This was the missing link!
        creatorRegistry.grantPlatformRole(address(contentRegistry));

        // Complete permission setup
        creatorRegistry.grantPlatformRole(address(payPerView));
        creatorRegistry.grantPlatformRole(address(subscriptionManager));
        creatorRegistry.grantPlatformRole(address(commerceCore));
        creatorRegistry.grantPlatformRole(address(commercePermit));

        contentRegistry.grantPurchaseRecorderRole(address(payPerView));
        contentRegistry.grantPurchaseRecorderRole(address(commerceCore));
        contentRegistry.grantPurchaseRecorderRole(address(commercePermit));

        payPerView.grantPaymentProcessorRole(address(commerceCore));
        payPerView.grantPaymentProcessorRole(address(commercePermit));
        subscriptionManager.grantSubscriptionProcessorRole(address(commerceCore));
        subscriptionManager.grantSubscriptionProcessorRole(address(commercePermit));

        commerceCore.grantRole(commerceCore.PAYMENT_MONITOR_ROLE(), msg.sender);
        commercePermit.grantRole(commercePermit.PAYMENT_MONITOR_ROLE(), msg.sender);

        // Verify all role assignments
        _verifyRoles();
    }

    function _verifyRoles() internal view {
        // Verify CreatorRegistry platform roles
        require(
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(contentRegistry)),
            "ContentRegistry missing platform role"
        );
        require(
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(payPerView)),
            "PayPerView missing platform role"
        );
        require(
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(subscriptionManager)),
            "SubscriptionManager missing platform role"
        );
        require(
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(commerceCore)),
            "CommerceProtocolCore missing platform role"
        );
        require(
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(commercePermit)),
            "CommerceProtocolPermit missing platform role"
        );

        // Verify ContentRegistry purchase recorder roles
        require(
            contentRegistry.hasRole(contentRegistry.PURCHASE_RECORDER_ROLE(), address(payPerView)),
            "PayPerView missing purchase recorder role"
        );
        require(
            contentRegistry.hasRole(contentRegistry.PURCHASE_RECORDER_ROLE(), address(commerceCore)),
            "CommerceProtocolCore missing purchase recorder role"
        );
        require(
            contentRegistry.hasRole(contentRegistry.PURCHASE_RECORDER_ROLE(), address(commercePermit)),
            "CommerceProtocolPermit missing purchase recorder role"
        );

        // Verify PayPerView payment processor role
        require(
            payPerView.hasRole(payPerView.PAYMENT_PROCESSOR_ROLE(), address(commerceCore)),
            "CommerceProtocolCore missing payment processor role"
        );
        require(
            payPerView.hasRole(payPerView.PAYMENT_PROCESSOR_ROLE(), address(commercePermit)),
            "CommerceProtocolPermit missing payment processor role"
        );

        // Verify SubscriptionManager subscription processor role
        require(
            subscriptionManager.hasRole(subscriptionManager.SUBSCRIPTION_PROCESSOR_ROLE(), address(commerceCore)),
            "CommerceProtocolCore missing subscription processor role"
        );
        require(
            subscriptionManager.hasRole(subscriptionManager.SUBSCRIPTION_PROCESSOR_ROLE(), address(commercePermit)),
            "CommerceProtocolPermit missing subscription processor role"
        );

        // Verify Commerce Protocol payment monitor roles
        require(
            commerceCore.hasRole(commerceCore.PAYMENT_MONITOR_ROLE(), platformOwner),
            "Deployer missing payment monitor role on Core"
        );
        require(
            commercePermit.hasRole(commercePermit.PAYMENT_MONITOR_ROLE(), platformOwner),
            "Deployer missing payment monitor role on Permit"
        );
    }

    function _configureIntegrations() internal {
        // Configure AdminManager with contract addresses
        adminManager.setPayPerView(address(payPerView));
        adminManager.setSubscriptionManager(address(subscriptionManager));

        // Verify integrations worked
        _verifyIntegrations();
    }

    function _verifyIntegrations() internal view {
        require(
            address(adminManager.payPerView()) == address(payPerView), "PayPerView integration not set correctly"
        );
        require(
            address(adminManager.subscriptionManager()) == address(subscriptionManager),
            "SubscriptionManager integration not set correctly"
        );
    }

    function _registerOperator() internal {
        // Skip operator registration during deployment for now
        // This can be done manually after deployment or via a separate transaction
        console.log("Skipping operator registration during deployment");
        console.log("You can register manually later using:");
        console.log(
            "cast send",
            address(commerceCore),
            "registerAsOperator()",
            "--rpc-url base_sepolia --account deployer"
        );

        // Alternatively, make it optional with an environment variable
        if (vm.envOr("REGISTER_OPERATOR", false)) {
            try adminManager.registerAsOperator() {
                require(
                    adminManager.hasRole(adminManager.PAYMENT_MONITOR_ROLE(), platformOwner),
                    "Admin manager missing PAYMENT_MONITOR_ROLE after registration"
                );
                console.log("Successfully registered as Commerce Protocol operator via AdminManager");
            } catch Error(string memory reason) {
                console.log("Operator registration failed:", reason);
                console.log("You can try registering manually later via AdminManager");
            } catch {
                console.log("Operator registration failed with unknown error");
                console.log("You can try registering manually later via AdminManager");
            }
        }
    }

    function _printDeploymentSummary() internal view {
        console.log("Contract Addresses:");
        console.log("==================");
        console.log("PriceOracle:", address(priceOracle));
        console.log("CreatorRegistry:", address(creatorRegistry));
        console.log("ContentRegistry:", address(contentRegistry));
        console.log("PayPerView:", address(payPerView));
        console.log("SubscriptionManager:", address(subscriptionManager));
        console.log("CommerceProtocolCore:", address(commerceCore));
        console.log("CommerceProtocolPermit:", address(commercePermit));
        console.log("AdminManager:", address(adminManager));
        console.log("AccessManager:", address(accessManager));
        console.log("ViewManager:", address(viewManager));
        console.log("SignatureManager:", address(signatureManager));
        console.log("RefundManager:", address(refundManager));
        console.log("PermitPaymentManager:", address(permitPaymentManager));
        console.log("BaseCommerceIntegration:", address(baseCommerceIntegration));
        console.log("");
        console.log("Configuration:");
        console.log("==============");
        console.log("Platform Owner:", platformOwner);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Operator Signer:", operatorSigner);
    }

    function _printPostDeploymentInstructions() internal pure {
        console.log("Post-Deployment Instructions:");
        console.log("============================");
        console.log("1. Update frontend with new contract addresses");
        console.log("2. Set up backend monitoring service for payment processing");
        console.log("3. Configure proper operator signing keys");
        console.log("4. Test all payment flows on testnet before mainnet");
        console.log("5. Set up subgraph indexing for events");
        console.log("6. Configure Commerce Protocol operator registration");
        console.log("7. Update documentation with new addresses");
    }

    // Function to verify all deployments
    function verifyDeployments() public view {
        console.log("=== Deployment Verification ===");
        console.log("All contracts deployed successfully:");
        console.log("PriceOracle:", address(priceOracle));
        console.log("CreatorRegistry:", address(creatorRegistry));
        console.log("ContentRegistry:", address(contentRegistry));
        console.log("PayPerView:", address(payPerView));
        console.log("SubscriptionManager:", address(subscriptionManager));
        console.log("CommerceProtocolCore:", address(commerceCore));
        console.log("CommerceProtocolPermit:", address(commercePermit));

        // Verify network configuration
        NetworkConfig memory config = networkConfigs[block.chainid];
        console.log("Network:", config.name);
        console.log("Chain ID:", config.chainId);
    }
}
