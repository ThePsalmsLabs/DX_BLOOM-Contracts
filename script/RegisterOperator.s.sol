// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/CommerceProtocolIntegration.sol";
import "../src/AdminManager.sol";

/**
 * @title RegisterOperator
 * @dev Script to register as operator after deployment
 * @notice Use this script to manually register as operator if it fails during deployment
 */
contract RegisterOperator is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address commerceIntegrationAddress = vm.envAddress("COMMERCE_INTEGRATION_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        CommerceProtocolIntegration commerceIntegration = CommerceProtocolIntegration(commerceIntegrationAddress);
        address adminManagerAddress = address(commerceIntegration.adminManager());

        console.log("=== Registering as Commerce Protocol Operator ===");
        console.log("CommerceProtocolIntegration:", address(commerceIntegration));
        console.log("AdminManager:", adminManagerAddress);
        console.log("Operator:", msg.sender);

        // Get AdminManager instance
        AdminManager adminManager = AdminManager(adminManagerAddress);

        try adminManager.registerAsOperator() {
            console.log("Successfully registered as Commerce Protocol operator");
            
            // Verify registration by checking if we can create a test intent
            // (This is just a verification, not an actual payment)
            console.log("Verifying registration...");
            
            // Check if operator signer has correct role
            bytes32 signerRole = commerceIntegration.SIGNER_ROLE();
            address operatorSigner = adminManager.operatorSigner();
            bool hasRole = commerceIntegration.hasRole(signerRole, operatorSigner);
            
            console.log("Operator signer:", operatorSigner);
            console.log("Has SIGNER_ROLE:", hasRole);
            
            if (hasRole) {
                console.log("Operator registration verified successfully");
            } else {
                console.log("Registration completed but signer role verification failed");
            }
            
        } catch Error(string memory reason) {
            console.log("Registration failed with error:", reason);
            _printTroubleshootingSteps();
        } catch (bytes memory lowLevelData) {
            console.log("Registration failed with unknown error");
            console.log("Low level data:", string(lowLevelData));
            _printTroubleshootingSteps();
        }
        
        vm.stopBroadcast();
    }
    
    function _printTroubleshootingSteps() internal pure {
        console.log("");
        console.log("=== Troubleshooting Steps ===");
        console.log("1. Verify the Commerce Protocol address is correct for your network");
        console.log("2. Check if the protocol requires whitelisting or pre-approval");
        console.log("3. Ensure the fee destination address is valid (not zero address)");
        console.log("4. Try registering from an EOA instead of a contract");
        console.log("5. Contact Coinbase/Base support for operator registration requirements");
        console.log("");
        console.log("Alternative: Consider using Coinbase Commerce API instead of self-operating");
    }
}

// Usage:
// COMMERCE_INTEGRATION_ADDRESS=0xYourCommerceIntegrationAddress forge script script/RegisterOperator.s.sol:RegisterOperator --rpc-url base_sepolia --account deployer --broadcast