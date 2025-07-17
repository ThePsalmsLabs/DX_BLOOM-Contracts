// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/CreatorRegistry.sol";
import "../src/ContentRegistry.sol";
import "../src/PayPerView.sol";
import "../src/SubscriptionManager.sol";
import "../src/CommerceProtocolIntegration.sol";
import "../src/PriceOracle.sol";

/**
 * @title Deploy
 * @dev Deployment script for the Onchain Content Subscription Platform
 */
contract Deploy is Script {
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
    CommerceProtocolIntegration public commerceIntegration;

    function setUp() public {
        // Set deployment parameters
        platformOwner = msg.sender;
        feeRecipient = msg.sender; // Can be changed later
        operatorSigner = msg.sender; // Should be a dedicated signing key in production
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Use local variables for addresses
        address USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address COMMERCE_PROTOCOL_BASE = 0xeADE6bE02d043b3550bE19E960504dbA14A14971;

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying Onchain Content Subscription Platform ===");
        console.log("Deployer:", msg.sender);
        console.log("Network:", block.chainid);
        console.log("");

        // 1. Deploy PriceOracle
        console.log("1. Deploying PriceOracle...");
        priceOracle = new PriceOracle();
        console.log("   PriceOracle deployed at:", address(priceOracle));

        // 2. Deploy CreatorRegistry
        console.log("2. Deploying CreatorRegistry...");
        creatorRegistry = new CreatorRegistry(feeRecipient, USDC_BASE);
        console.log("   CreatorRegistry deployed at:", address(creatorRegistry));

        // 3. Deploy ContentRegistry
        console.log("3. Deploying ContentRegistry...");
        contentRegistry = new ContentRegistry(address(creatorRegistry));
        console.log("   ContentRegistry deployed at:", address(contentRegistry));

        // 4. Deploy PayPerView
        console.log("4. Deploying PayPerView...");
        payPerView = new PayPerView(address(creatorRegistry), address(contentRegistry), address(priceOracle), USDC_BASE);
        console.log("   PayPerView deployed at:", address(payPerView));

        // 5. Deploy SubscriptionManager
        console.log("5. Deploying SubscriptionManager...");
        subscriptionManager = new SubscriptionManager(address(creatorRegistry), address(contentRegistry), USDC_BASE);
        console.log("   SubscriptionManager deployed at:", address(subscriptionManager));

        // 6. Deploy CommerceProtocolIntegration
        console.log("6. Deploying CommerceProtocolIntegration...");
        commerceIntegration = new CommerceProtocolIntegration(
            COMMERCE_PROTOCOL_BASE,
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            feeRecipient,
            operatorSigner
        );
        console.log("   CommerceProtocolIntegration deployed at:", address(commerceIntegration));

        console.log("");
        console.log("=== Setting up contract permissions ===");

        // 7. Set up permissions and roles
        _setupPermissions();

        // 8. Configure contract integrations
        _configureIntegrations();

        // 9. Register as Commerce Protocol operator
        _registerOperator();

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        _printDeploymentSummary();
    }

    function _setupPermissions() internal {
        console.log("Setting up permissions...");

        // Grant platform contract roles to CreatorRegistry
        creatorRegistry.grantPlatformRole(address(payPerView));
        creatorRegistry.grantPlatformRole(address(subscriptionManager));
        creatorRegistry.grantPlatformRole(address(commerceIntegration));

        // Grant purchase recorder role to PayPerView
        contentRegistry.grantPurchaseRecorderRole(address(payPerView));

        // Grant payment processor role to CommerceIntegration
        payPerView.grantPaymentProcessorRole(address(commerceIntegration));

        // Grant subscription processor role to CommerceIntegration
        subscriptionManager.grantSubscriptionProcessorRole(address(commerceIntegration));

        // Grant payment monitor role to deployer (should be backend service in production)
        commerceIntegration.grantPaymentMonitorRole(msg.sender);

        console.log("All permissions configured");
    }

    function _configureIntegrations() internal {
        console.log("Configuring contract integrations...");

        // Set PayPerView and SubscriptionManager in CommerceIntegration
        commerceIntegration.setPayPerView(address(payPerView));
        commerceIntegration.setSubscriptionManager(address(subscriptionManager));

        console.log("    Contract integrations configured");
    }

    function _registerOperator() internal {
        console.log("Registering as Commerce Protocol operator...");

        try commerceIntegration.registerAsOperator() {
            console.log("    Successfully registered as operator");
        } catch {
            console.log(" Failed to register as operator - may need to be done manually");
        }
    }

    function _printDeploymentSummary() internal view {
        console.log("Contract Addresses:");
        console.log("  PriceOracle:              ", address(priceOracle));
        console.log("  CreatorRegistry:          ", address(creatorRegistry));
        console.log("  ContentRegistry:          ", address(contentRegistry));
        console.log("  PayPerView:               ", address(payPerView));
        console.log("  SubscriptionManager:      ", address(subscriptionManager));
        console.log("  CommerceProtocolIntegration:", address(commerceIntegration));

        console.log("");
        console.log("Configuration:");
        console.log("  Platform Owner:           ", platformOwner);
        console.log("  Fee Recipient:            ", feeRecipient);
        console.log("  Operator Signer:          ", operatorSigner);
        console.log("  USDC Token:               ", 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // This will need to be updated in runTestnet
        console.log("  Commerce Protocol:        ", 0xeADE6bE02d043b3550bE19E960504dbA14A14971); // This will need to be updated in runTestnet

        console.log("");
        console.log("Next Steps:");
        console.log("1. Update frontend with new contract addresses");
        console.log("2. Set up backend monitoring service for payment processing");
        console.log("3. Configure proper operator signing keys");
        console.log("4. Test all payment flows on testnet before mainnet");
        console.log("5. Set up subgraph indexing for events");
    }

    // Helper function to deploy to testnet
    function runTestnet() public {
        // Use testnet addresses as local variables
        address USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        address COMMERCE_PROTOCOL_BASE_SEPOLIA = 0x96A08D8e8631b6dB52Ea0cbd7232d9A85d239147;

        // Call run() with testnet addresses
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying Onchain Content Subscription Platform (Testnet) ===");
        console.log("Deployer:", msg.sender);
        console.log("Network:", block.chainid);
        console.log("");

        // 1. Deploy PriceOracle
        console.log("1. Deploying PriceOracle...");
        priceOracle = new PriceOracle();
        console.log("   PriceOracle deployed at:", address(priceOracle));

        // 2. Deploy CreatorRegistry
        console.log("2. Deploying CreatorRegistry...");
        creatorRegistry = new CreatorRegistry(feeRecipient, USDC_BASE_SEPOLIA);
        console.log("   CreatorRegistry deployed at:", address(creatorRegistry));

        // 3. Deploy ContentRegistry
        console.log("3. Deploying ContentRegistry...");
        contentRegistry = new ContentRegistry(address(creatorRegistry));
        console.log("   ContentRegistry deployed at:", address(contentRegistry));

        // 4. Deploy PayPerView
        console.log("4. Deploying PayPerView...");
        payPerView =
            new PayPerView(address(creatorRegistry), address(contentRegistry), address(priceOracle), USDC_BASE_SEPOLIA);
        console.log("   PayPerView deployed at:", address(payPerView));

        // 5. Deploy SubscriptionManager
        console.log("5. Deploying SubscriptionManager...");
        subscriptionManager =
            new SubscriptionManager(address(creatorRegistry), address(contentRegistry), USDC_BASE_SEPOLIA);
        console.log("   SubscriptionManager deployed at:", address(subscriptionManager));

        // 6. Deploy CommerceProtocolIntegration
        console.log("6. Deploying CommerceProtocolIntegration...");
        commerceIntegration = new CommerceProtocolIntegration(
            COMMERCE_PROTOCOL_BASE_SEPOLIA,
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            feeRecipient,
            operatorSigner
        );
        console.log("   CommerceProtocolIntegration deployed at:", address(commerceIntegration));

        console.log("");
        console.log("=== Setting up contract permissions ===");

        // 7. Set up permissions and roles
        _setupPermissions();

        // 8. Configure contract integrations
        _configureIntegrations();

        // 9. Register as Commerce Protocol operator
        _registerOperator();

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        _printDeploymentSummary();
    }

    // Function to verify all deployments
    function verify() public view {
        console.log("=== Verifying Deployments ===");

        // Check if all contracts are deployed
        require(address(priceOracle).code.length > 0, "PriceOracle not deployed");
        require(address(creatorRegistry).code.length > 0, "CreatorRegistry not deployed");
        require(address(contentRegistry).code.length > 0, "ContentRegistry not deployed");
        require(address(payPerView).code.length > 0, "PayPerView not deployed");
        require(address(subscriptionManager).code.length > 0, "SubscriptionManager not deployed");
        require(address(commerceIntegration).code.length > 0, "CommerceProtocolIntegration not deployed");

        // Check basic configurations
        require(creatorRegistry.owner() == platformOwner, "CreatorRegistry owner incorrect");
        require(contentRegistry.owner() == platformOwner, "ContentRegistry owner incorrect");
        require(payPerView.owner() == platformOwner, "PayPerView owner incorrect");

        console.log(" All contracts deployed and configured correctly");
    }
}
