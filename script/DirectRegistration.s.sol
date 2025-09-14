// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

/**
 * @title DirectRegistration
 * @dev Script to register directly with Base Commerce Protocol
 */
contract DirectRegistration is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Base Commerce Protocol on Base Sepolia - corrected address
        address commerceProtocolAddress = 0x96a08D8E8631B6ddb52ea0cbd7232d9a85D23914;
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Direct Base Commerce Protocol Registration ===");
        console.log("Commerce Protocol:", commerceProtocolAddress);
        console.log("Registering:", msg.sender);
        
        // Call registerOperator() directly
        (bool success, bytes memory data) = commerceProtocolAddress.call(
            abi.encodeWithSignature("registerOperator()")
        );
        
        if (success) {
            console.log("Successfully registered as operator with Base Commerce Protocol");
        } else {
            console.log("Registration failed");
            console.log("Error data:", string(data));
        }
        
        vm.stopBroadcast();
    }
}