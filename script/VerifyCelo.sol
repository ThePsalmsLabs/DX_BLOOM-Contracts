// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

/**
 * @title VerifyCelo
 * @dev Verification script for Bloom contracts deployed on Celo networks
 * @notice This script verifies contracts on both Celo Mainnet and Celo Alfajores
 */
contract VerifyCelo is Script {
    // Network configuration
    struct NetworkConfig {
        uint256 chainId;
        string name;
        string apiKey;
        string rpcUrl;
    }

    // Network configurations
    mapping(uint256 => NetworkConfig) public networkConfigs;

    // Configuration addresses (set via environment variables)
    address public feeRecipient;
    address public operatorSigner;

    // Contract addresses to verify (will be set based on deployment)
    address public creatorRegistry;
    address public contentRegistry;
    address public payPerView;
    address public subscriptionManager;
    address public commerceCore;
    address public commercePermit;
    address public priceOracle;
    address public adminManager;
    address public viewManager;
    address public accessManager;
    address public signatureManager;
    address public refundManager;
    address public permitPaymentManager;
    address public baseCommerceIntegration;

    function setUp() public {
        _configureNetworks();
        _loadConfiguration();
        _loadContractAddresses();
    }

    function _configureNetworks() internal {
        // Celo Mainnet (Chain ID: 42220)
        networkConfigs[42220] = NetworkConfig({
            chainId: 42220,
            name: "Celo Mainnet",
            apiKey: "CELOSCAN_API_KEY",
            rpcUrl: "https://forno.celo.org"
        });

        // Celo Alfajores (Chain ID: 44787)
        networkConfigs[44787] = NetworkConfig({
            chainId: 44787,
            name: "Celo Alfajores",
            apiKey: "CELOSCAN_API_KEY",
            rpcUrl: "https://alfajores-forno.celo-testnet.org"
        });
    }

    function _loadConfiguration() internal {
        if (block.chainid == 42220) {
            // Celo Mainnet
            feeRecipient = vm.envAddress("CELO_MAINNET_FEE_RECIPIENT");
            operatorSigner = vm.envAddress("CELO_MAINNET_OPERATOR_SIGNER");
        } else if (block.chainid == 44787) {
            // Celo Alfajores
            feeRecipient = vm.envOr("CELO_TESTNET_FEE_RECIPIENT", msg.sender);
            operatorSigner = vm.envOr("CELO_TESTNET_OPERATOR_SIGNER", msg.sender);
        } else {
            revert("Unsupported network for Celo verification");
        }
    }

    function _loadContractAddresses() internal {
        // Load contract addresses from environment variables or deployment artifacts
        // These should be set after deployment
        creatorRegistry = vm.envOr("CREATOR_REGISTRY", address(0));
        contentRegistry = vm.envOr("CONTENT_REGISTRY", address(0));
        payPerView = vm.envOr("PAY_PER_VIEW", address(0));
        subscriptionManager = vm.envOr("SUBSCRIPTION_MANAGER", address(0));
        commerceCore = vm.envOr("COMMERCE_CORE", address(0));
        commercePermit = vm.envOr("COMMERCE_PERMIT", address(0));
        priceOracle = vm.envOr("PRICE_ORACLE", address(0));
        adminManager = vm.envOr("ADMIN_MANAGER", address(0));
        viewManager = vm.envOr("VIEW_MANAGER", address(0));
        accessManager = vm.envOr("ACCESS_MANAGER", address(0));
        signatureManager = vm.envOr("SIGNATURE_MANAGER", address(0));
        refundManager = vm.envOr("REFUND_MANAGER", address(0));
        permitPaymentManager = vm.envOr("PERMIT_PAYMENT_MANAGER", address(0));
        baseCommerceIntegration = vm.envOr("BASE_COMMERCE_INTEGRATION", address(0));

        // Require at least some core contracts to be set
        require(creatorRegistry != address(0), "CreatorRegistry address not set");
        require(contentRegistry != address(0), "ContentRegistry address not set");
        require(commerceCore != address(0), "CommerceCore address not set");
    }

    function run() public {
        NetworkConfig memory config = networkConfigs[block.chainid];
        require(config.chainId != 0, "Unsupported network");

        console.log("=== Starting Celo Contract Verification ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Operator Signer:", operatorSigner);
        console.log("");

        // Verify contracts in dependency order
        verifyPriceOracle();
        verifyCreatorRegistry();
        verifyContentRegistry();
        verifyPayPerView();
        verifySubscriptionManager();
        verifyManagerContracts();
        verifyBaseCommerceIntegration();
        verifyCommerceProtocols();

        console.log("");
        console.log("=== Verification Complete ===");
        console.log("All contracts have been submitted for verification on", config.name);
        console.log("Check Celoscan for verification status");
    }

    function verifyPriceOracle() internal {
        if (priceOracle == address(0)) return;
        
        console.log("Verifying PriceOracle at:", priceOracle);

        address quoterV2 = block.chainid == 42220 
            ? 0x82825d0554fA07f7FC52Ab63c961F330fdEFa8E8  // Celo Mainnet
            : 0x3c1FCF8D6f3A579E98F4AE75EB0adA6de70f5673; // Celo Alfajores
            
        address weth = 0x471EcE3750Da237f93B8E339c536989b8978a438; // CELO token
        
        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        bytes memory constructorArgs = abi.encode(quoterV2, weth, usdc);
        runVerification("src/PriceOracle.sol:PriceOracle", priceOracle, constructorArgs);
    }

    function verifyCreatorRegistry() internal {
        if (creatorRegistry == address(0)) return;
        
        console.log("Verifying CreatorRegistry at:", creatorRegistry);

        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        bytes memory constructorArgs = abi.encode(feeRecipient, usdc);
        runVerification("src/CreatorRegistry.sol:CreatorRegistry", creatorRegistry, constructorArgs);
    }

    function verifyContentRegistry() internal {
        if (contentRegistry == address(0)) return;
        
        console.log("Verifying ContentRegistry at:", contentRegistry);

        bytes memory constructorArgs = abi.encode(creatorRegistry);
        runVerification("src/ContentRegistry.sol:ContentRegistry", contentRegistry, constructorArgs);
    }

    function verifyPayPerView() internal {
        if (payPerView == address(0)) return;
        
        console.log("Verifying PayPerView at:", payPerView);

        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        bytes memory constructorArgs = abi.encode(creatorRegistry, contentRegistry, priceOracle, usdc);
        runVerification("src/PayPerView.sol:PayPerView", payPerView, constructorArgs);
    }

    function verifySubscriptionManager() internal {
        if (subscriptionManager == address(0)) return;
        
        console.log("Verifying SubscriptionManager at:", subscriptionManager);

        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        bytes memory constructorArgs = abi.encode(creatorRegistry, contentRegistry, usdc);
        runVerification("src/SubscriptionManager.sol:SubscriptionManager", subscriptionManager, constructorArgs);
    }

    function verifyManagerContracts() internal {
        // AdminManager
        if (adminManager != address(0)) {
            console.log("Verifying AdminManager at:", adminManager);
            bytes memory constructorArgs = abi.encode(feeRecipient, operatorSigner);
            runVerification("src/AdminManager.sol:AdminManager", adminManager, constructorArgs);
        }

        // ViewManager
        if (viewManager != address(0)) {
            console.log("Verifying ViewManager at:", viewManager);
            bytes memory constructorArgs = abi.encode();
            runVerification("src/ViewManager.sol:ViewManager", viewManager, constructorArgs);
        }

        // AccessManager
        if (accessManager != address(0)) {
            console.log("Verifying AccessManager at:", accessManager);
            bytes memory constructorArgs = abi.encode(payPerView, subscriptionManager, creatorRegistry);
            runVerification("src/AccessManager.sol:AccessManager", accessManager, constructorArgs);
        }

        // SignatureManager
        if (signatureManager != address(0)) {
            console.log("Verifying SignatureManager at:", signatureManager);
            bytes memory constructorArgs = abi.encode(operatorSigner);
            runVerification("src/SignatureManager.sol:SignatureManager", signatureManager, constructorArgs);
        }

        // RefundManager
        if (refundManager != address(0)) {
            console.log("Verifying RefundManager at:", refundManager);
            address usdc = block.chainid == 42220
                ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
                : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC
            bytes memory constructorArgs = abi.encode(payPerView, subscriptionManager, usdc);
            runVerification("src/RefundManager.sol:RefundManager", refundManager, constructorArgs);
        }

        // PermitPaymentManager
        if (permitPaymentManager != address(0)) {
            console.log("Verifying PermitPaymentManager at:", permitPaymentManager);
            address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Uniswap Permit2
            address usdc = block.chainid == 42220
                ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
                : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC
            bytes memory constructorArgs = abi.encode(baseCommerceIntegration, permit2, usdc);
            runVerification("src/PermitPaymentManager.sol:PermitPaymentManager", permitPaymentManager, constructorArgs);
        }
    }

    function verifyBaseCommerceIntegration() internal {
        if (baseCommerceIntegration == address(0)) return;
        
        console.log("Verifying BaseCommerceIntegration at:", baseCommerceIntegration);

        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        bytes memory constructorArgs = abi.encode(usdc, feeRecipient);
        runVerification("src/BaseCommerceIntegration.sol:BaseCommerceIntegration", baseCommerceIntegration, constructorArgs);
    }

    function verifyCommerceProtocols() internal {
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Uniswap Permit2
        address usdc = block.chainid == 42220
            ? 0xcebA9300f2b948710d2653dD7B07f33A8B32118C  // Celo Mainnet USDC
            : 0x2F25deB3848C207fc8E0c34035B3Ba7fC157602B; // Alfajores Test USDC

        // CommerceProtocolCore
        if (commerceCore != address(0)) {
            console.log("Verifying CommerceProtocolCore at:", commerceCore);
            bytes memory constructorArgs = abi.encode(
                baseCommerceIntegration,
                permit2,
                creatorRegistry,
                contentRegistry,
                priceOracle,
                usdc,
                feeRecipient,
                operatorSigner,
                adminManager,
                viewManager,
                accessManager,
                signatureManager,
                refundManager,
                permitPaymentManager
            );
            runVerification("src/CommerceProtocolCore.sol:CommerceProtocolCore", commerceCore, constructorArgs);
        }

        // CommerceProtocolPermit
        if (commercePermit != address(0)) {
            console.log("Verifying CommerceProtocolPermit at:", commercePermit);
            bytes memory constructorArgs = abi.encode(
                baseCommerceIntegration,
                permit2,
                creatorRegistry,
                contentRegistry,
                priceOracle,
                usdc,
                feeRecipient,
                operatorSigner,
                adminManager,
                viewManager,
                accessManager,
                signatureManager,
                refundManager,
                permitPaymentManager
            );
            runVerification("src/CommerceProtocolPermit.sol:CommerceProtocolPermit", commercePermit, constructorArgs);
        }
    }

    function runVerification(string memory contractPath, address contractAddress, bytes memory constructorArgs) internal {
        NetworkConfig memory config = networkConfigs[block.chainid];
        
        string[] memory inputs = new string[](9);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = "--chain";
        inputs[3] = vm.toString(config.chainId);
        inputs[4] = "--etherscan-api-key";
        inputs[5] = vm.envString(config.apiKey);
        inputs[6] = vm.toString(contractAddress);
        inputs[7] = contractPath;
        inputs[8] = vm.toString(constructorArgs);

        // Execute verification
        vm.ffi(inputs);
    }

    // Helper function to set contract addresses manually if needed
    function setContractAddresses(
        address _creatorRegistry,
        address _contentRegistry,
        address _payPerView,
        address _subscriptionManager,
        address _commerceCore,
        address _commercePermit,
        address _priceOracle,
        address _adminManager,
        address _viewManager,
        address _accessManager,
        address _signatureManager,
        address _refundManager,
        address _permitPaymentManager,
        address _baseCommerceIntegration
    ) external {
        creatorRegistry = _creatorRegistry;
        contentRegistry = _contentRegistry;
        payPerView = _payPerView;
        subscriptionManager = _subscriptionManager;
        commerceCore = _commerceCore;
        commercePermit = _commercePermit;
        priceOracle = _priceOracle;
        adminManager = _adminManager;
        viewManager = _viewManager;
        accessManager = _accessManager;
        signatureManager = _signatureManager;
        refundManager = _refundManager;
        permitPaymentManager = _permitPaymentManager;
        baseCommerceIntegration = _baseCommerceIntegration;
    }
}