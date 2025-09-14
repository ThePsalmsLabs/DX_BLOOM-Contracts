// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

/**
 * @title VerifyBaseMainnet
 * @dev Verification script for Bloom contracts deployed on Base Mainnet
 * @notice This script verifies contracts using addresses from backup deployments
 */
contract VerifyBaseMainnet is Script {
    // Contract addresses to verify (from backup deployment)
    address constant CREATOR_REGISTRY = 0x6b88ae6538FB8bf8cbA1ad64fABb458aa0CE4263;
    address constant CONTENT_REGISTRY = 0xB4cbF1923be6FF1bc4D45471246D753d34aB41d7;
    address constant PAY_PER_VIEW = 0x8A89fcAe4E674d6528A5a743E468eBE9BDCf3101;
    address constant SUBSCRIPTION_MANAGER = 0x06D92f5A03f177c50A6e14Ac6a231cb371e67Da4;
    address constant COMMERCE_INTEGRATION = 0x931601610C9491948e7cEeA2e9Df480162e45409;
    address constant PRICE_ORACLE = 0x13056B1dFE38dA0c058e6b2B2e3DaecCEdCEFFfF;
    address constant COMMERCE_PROTOCOL = 0x96A08D8e8631b6dB52Ea0cbd7232d9A85d239147;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    // External contract addresses (Base Mainnet)
    address constant QUOTER_V2 = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Configuration addresses (these would need to be set based on deployment)
    address public feeRecipient;
    address public operatorSigner;

    function setUp() public {
        // Set configuration addresses - these should match the deployment configuration
        feeRecipient = vm.envOr("MAINNET_FEE_RECIPIENT", address(0));
        operatorSigner = vm.envOr("MAINNET_OPERATOR_SIGNER", address(0));

        require(feeRecipient != address(0), "MAINNET_FEE_RECIPIENT not set");
        require(operatorSigner != address(0), "MAINNET_OPERATOR_SIGNER not set");
    }

    function run() public {
        console.log("=== Starting Base Mainnet Contract Verification ===");
        console.log("Network: Base Mainnet (Chain ID: 8453)");
        console.log("");

        // Verify contracts in dependency order
        verifyPriceOracle();
        verifyCreatorRegistry();
        verifyContentRegistry();
        verifyPayPerView();
        verifySubscriptionManager();
        verifyCommerceProtocolIntegration();

        console.log("");
        console.log("=== Verification Complete ===");
        console.log("All contracts have been submitted for verification on Base mainnet");
        console.log("Check Basescan for verification status");
    }

    function verifyPriceOracle() internal {
        console.log("Verifying PriceOracle at:", PRICE_ORACLE);

        // NOTE: Update constructor args based on the actual backup PriceOracle contract
        // Common patterns:
        // - address _quoterV2, address _weth, address _usdc
        // - address _quoterV2, address _weth, address _usdc, address _usdt (older versions)

        bytes memory constructorArgs = abi.encode(QUOTER_V2, WETH, USDC);

        vm.broadcast();
        runVerification("src/PriceOracle.sol:PriceOracle", PRICE_ORACLE, constructorArgs);
    }

    function verifyCreatorRegistry() internal {
        console.log("Verifying CreatorRegistry at:", CREATOR_REGISTRY);

        // NOTE: Update constructor args based on the actual backup CreatorRegistry contract
        // Common patterns:
        // - address _feeRecipient, address _usdcToken
        // - address _feeRecipient, address _usdcToken, uint256 _platformFee
        // - address _feeRecipient, address _usdcToken, address _platformOwner

        bytes memory constructorArgs = abi.encode(feeRecipient, USDC);

        vm.broadcast();
        runVerification("src/CreatorRegistry.sol:CreatorRegistry", CREATOR_REGISTRY, constructorArgs);
    }

    function verifyContentRegistry() internal {
        console.log("Verifying ContentRegistry at:", CONTENT_REGISTRY);

        // NOTE: Update constructor args based on the actual backup ContentRegistry contract
        // Common patterns:
        // - address _creatorRegistry
        // - address _creatorRegistry, address _feeRecipient

        bytes memory constructorArgs = abi.encode(CREATOR_REGISTRY);

        vm.broadcast();
        runVerification("src/ContentRegistry.sol:ContentRegistry", CONTENT_REGISTRY, constructorArgs);
    }

    function verifyPayPerView() internal {
        console.log("Verifying PayPerView at:", PAY_PER_VIEW);

        // NOTE: Update constructor args based on the actual backup PayPerView contract
        // Common patterns:
        // - address _creatorRegistry, address _contentRegistry, address _priceOracle, address _usdcToken
        // - address _creatorRegistry, address _contentRegistry, address _priceOracle, address _usdcToken, address _feeRecipient

        bytes memory constructorArgs = abi.encode(CREATOR_REGISTRY, CONTENT_REGISTRY, PRICE_ORACLE, USDC);

        vm.broadcast();
        runVerification("src/PayPerView.sol:PayPerView", PAY_PER_VIEW, constructorArgs);
    }

    function verifySubscriptionManager() internal {
        console.log("Verifying SubscriptionManager at:", SUBSCRIPTION_MANAGER);

        // NOTE: Update constructor args based on the actual backup SubscriptionManager contract
        // Common patterns:
        // - address _creatorRegistry, address _contentRegistry, address _usdcToken
        // - address _creatorRegistry, address _contentRegistry, address _usdcToken, address _feeRecipient

        bytes memory constructorArgs = abi.encode(CREATOR_REGISTRY, CONTENT_REGISTRY, USDC);

        vm.broadcast();
        runVerification("src/SubscriptionManager.sol:SubscriptionManager", SUBSCRIPTION_MANAGER, constructorArgs);
    }

    function verifyCommerceProtocolIntegration() internal {
        console.log("Verifying CommerceProtocolIntegration at:", COMMERCE_INTEGRATION);

        // NOTE: This is the most complex contract. Update based on the actual backup CommerceProtocolIntegration
        // Common patterns (may have 8-15+ parameters):
        // - address _commerceProtocol, address _permit2, address _creatorRegistry, address _contentRegistry,
        //   address _priceOracle, address _usdcToken, address _feeRecipient, address _operatorSigner
        // Plus manager contracts if they exist in the backup version

        console.log("WARNING: CommerceProtocolIntegration constructor parameters vary significantly");
        console.log("Please update the constructor arguments based on the actual backup contract");

        // Placeholder - update with actual constructor args from backup
        bytes memory constructorArgs = abi.encode(
            COMMERCE_PROTOCOL,
            PERMIT2,
            CREATOR_REGISTRY,
            CONTENT_REGISTRY,
            PRICE_ORACLE,
            USDC,
            feeRecipient,
            operatorSigner
        );

        vm.broadcast();
        runVerification("src/CommerceProtocolIntegration.sol:CommerceProtocolIntegration", COMMERCE_INTEGRATION, constructorArgs);
    }

    function runVerification(string memory contractPath, address contractAddress, bytes memory constructorArgs) internal {
        string[] memory inputs = new string[](9);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = "--chain";
        inputs[3] = "8453"; // Base mainnet
        inputs[4] = "--etherscan-api-key";
        inputs[5] = vm.envString("BASESCAN_API_KEY");
        inputs[6] = vm.toString(contractAddress);
        inputs[7] = contractPath;
        inputs[8] = vm.toString(constructorArgs);

        // Execute verification
        vm.ffi(inputs);
    }

    // Helper function to verify if a contract is already verified
    function checkVerificationStatus(address contractAddress) internal returns (bool) {
        string[] memory inputs = new string[](5);
        inputs[0] = "cast";
        inputs[1] = "code";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = "--rpc-url";
        inputs[4] = "https://mainnet.base.org";

        try vm.ffi(inputs) returns (bytes memory result) {
            // If we get bytecode back, contract exists
            return result.length > 2; // "0x" + bytecode
        } catch {
            return false;
        }
    }

    // Function to verify all contracts at once (alternative approach)
    function verifyAll() public {
        console.log("=== Batch Verification of All Contracts ===");

        // Array of contract info for batch verification
        string[] memory contractPaths = new string[](6);
        address[] memory addresses = new address[](6);
        bytes[] memory constructorArgsArray = new bytes[](6);

        // PriceOracle
        contractPaths[0] = "src/PriceOracle.sol:PriceOracle";
        addresses[0] = PRICE_ORACLE;
        constructorArgsArray[0] = abi.encode(QUOTER_V2, WETH, USDC);

        // CreatorRegistry
        contractPaths[1] = "src/CreatorRegistry.sol:CreatorRegistry";
        addresses[1] = CREATOR_REGISTRY;
        constructorArgsArray[1] = abi.encode(feeRecipient, USDC);

        // ContentRegistry
        contractPaths[2] = "src/ContentRegistry.sol:ContentRegistry";
        addresses[2] = CONTENT_REGISTRY;
        constructorArgsArray[2] = abi.encode(CREATOR_REGISTRY);

        // PayPerView
        contractPaths[3] = "src/PayPerView.sol:PayPerView";
        addresses[3] = PAY_PER_VIEW;
        constructorArgsArray[3] = abi.encode(CREATOR_REGISTRY, CONTENT_REGISTRY, PRICE_ORACLE, USDC);

        // SubscriptionManager
        contractPaths[4] = "src/SubscriptionManager.sol:SubscriptionManager";
        addresses[4] = SUBSCRIPTION_MANAGER;
        constructorArgsArray[4] = abi.encode(CREATOR_REGISTRY, CONTENT_REGISTRY, USDC);

        // CommerceProtocolIntegration (placeholder - needs proper constructor args from backup)
        contractPaths[5] = "src/CommerceProtocolIntegration.sol:CommerceProtocolIntegration";
        addresses[5] = COMMERCE_INTEGRATION;
        constructorArgsArray[5] = abi.encode(
            COMMERCE_PROTOCOL,
            PERMIT2,
            CREATOR_REGISTRY,
            CONTENT_REGISTRY,
            PRICE_ORACLE,
            USDC,
            feeRecipient,
            operatorSigner
            // Add additional manager contract addresses if they exist in the backup version
        );

        // Execute batch verification
        for (uint i = 0; i < contractPaths.length; i++) {
            if (i == 5) { // Skip CommerceProtocolIntegration for now
                console.log("Skipping CommerceProtocolIntegration - requires manager contract addresses");
                continue;
            }

            console.log(string.concat("Verifying ", contractPaths[i]), "at", vm.toString(addresses[i]));
            runVerification(contractPaths[i], addresses[i], constructorArgsArray[i]);
        }
    }
}
