// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

/**
 * @title AnalyzeConstructorArgs
 * @dev Script to analyze constructor arguments from deployed contract bytecode
 * @notice This script helps determine the constructor arguments used during deployment
 */
contract AnalyzeConstructorArgs is Script {
    // Contract addresses to analyze (from backup deployment)
    address constant CREATOR_REGISTRY = 0x6b88ae6538FB8bf8cbA1ad64fABb458aa0CE4263;
    address constant CONTENT_REGISTRY = 0xB4cbF1923be6FF1bc4D45471246D753d34aB41d7;
    address constant PAY_PER_VIEW = 0x8A89fcAe4E674d6528A5a743E468eBE9BDCf3101;
    address constant SUBSCRIPTION_MANAGER = 0x06D92f5A03f177c50A6e14Ac6a231cb371e67Da4;
    address constant COMMERCE_INTEGRATION = 0x931601610C9491948e7cEeA2e9Df480162e45409;
    address constant PRICE_ORACLE = 0x13056B1dFE38dA0c058e6b2B2e3DaecCEdCEFFfF;

    function run() public {
        console.log("=== Analyzing Constructor Arguments from Deployed Contracts ===");
        console.log("Network: Base Mainnet (Chain ID: 8453)");
        console.log("");

        analyzeContract("PriceOracle", PRICE_ORACLE);
        analyzeContract("CreatorRegistry", CREATOR_REGISTRY);
        analyzeContract("ContentRegistry", CONTENT_REGISTRY);
        analyzeContract("PayPerView", PAY_PER_VIEW);
        analyzeContract("SubscriptionManager", SUBSCRIPTION_MANAGER);
        analyzeContract("CommerceProtocolIntegration", COMMERCE_INTEGRATION);

        console.log("");
        console.log("=== Analysis Complete ===");
        console.log("Use the constructor arguments shown above to update the verification script");
    }

    function analyzeContract(string memory name, address contractAddr) internal {
        console.log(string.concat("Analyzing ", name, " at ", vm.toString(contractAddr)));

        // Get the deployed bytecode
        string[] memory codeInputs = new string[](4);
        codeInputs[0] = "cast";
        codeInputs[1] = "code";
        codeInputs[2] = vm.toString(contractAddr);
        codeInputs[3] = "--rpc-url";
        codeInputs[4] = "https://mainnet.base.org";

        try vm.ffi(codeInputs) returns (bytes memory bytecode) {
            if (bytecode.length >= 2 && bytecode[0] == "0" && bytecode[1] == "x") {
                bytes memory codeBytes = slice(bytecode, 2, bytecode.length - 2);
                uint256 codeSize = codeBytes.length / 2;

                console.log("  Code size:", codeSize, "bytes");

                // Try to extract constructor arguments from the end of the bytecode
                // Constructor args are typically at the end of the deployed bytecode
                if (codeSize > 0) {
                    analyzeConstructorArgs(name, codeBytes);
                }
            } else {
                console.log("   Invalid bytecode format");
            }
        } catch {
            console.log("   Failed to fetch bytecode");
        }

        console.log("");
    }

    function analyzeConstructorArgs(string memory name, bytes memory bytecode) internal {
        // Constructor arguments are typically appended to the contract creation code
        // We can look for common patterns in the bytecode

        console.log("  Constructor args analysis:");

        // Look for address patterns in the bytecode (0x followed by 40 hex chars)
        uint256 addressCount = 0;
        for (uint256 i = 0; i < bytecode.length - 42; i++) {
            if (bytecode[i] == "0" && bytecode[i+1] == "x") {
                // Check if next 40 chars are valid hex
                bool isAddress = true;
                for (uint256 j = 2; j < 42; j++) {
                    bytes1 b = bytecode[i+j];
                    if (!isHexChar(b)) {
                        isAddress = false;
                        break;
                    }
                }
                if (isAddress) {
                    addressCount++;
                    console.log(string.concat("    Found address ", vm.toString(addressCount), ":"));

                    // Extract the address
                    bytes memory addrBytes = new bytes(40);
                    for (uint256 j = 0; j < 40; j++) {
                        addrBytes[j] = bytecode[i+j+2];
                    }
                    string memory addrStr = string.concat("0x", string(addrBytes));
                    console.log(string.concat("      ", addrStr));
                }
            }
        }

        if (addressCount == 0) {
            console.log("    No address patterns found in bytecode");
        }

        console.log("    Total addresses found:", addressCount);

        // Provide suggestions based on contract type
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("PriceOracle"))) {
            console.log("    Expected args: address _quoterV2, address _weth, address _usdc");
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("CreatorRegistry"))) {
            console.log("    Expected args: address _feeRecipient, address _usdcToken");
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("ContentRegistry"))) {
            console.log("    Expected args: address _creatorRegistry");
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("PayPerView"))) {
            console.log("    Expected args: address _creatorRegistry, address _contentRegistry, address _priceOracle, address _usdcToken");
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("SubscriptionManager"))) {
            console.log("    Expected args: address _creatorRegistry, address _contentRegistry, address _usdcToken");
        } else if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("CommerceProtocolIntegration"))) {
            console.log("    Expected args: address _commerceProtocol, address _permit2, address _creatorRegistry, address _contentRegistry, address _priceOracle, address _usdcToken, address _feeRecipient, address _operatorSigner [+ manager contracts]");
        }
    }

    function isHexChar(bytes1 b) internal pure returns (bool) {
        return (b >= "0" && b <= "9") || (b >= "a" && b <= "f") || (b >= "A" && b <= "F");
    }

    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    // Helper function to manually decode constructor args once you know the pattern
    function decodeConstructorArgs(address contractAddr, string memory signature) internal {
        console.log(string.concat("Manual decoding for ", vm.toString(contractAddr)));
        console.log(string.concat("Expected signature: ", signature));

        // Example of how to manually decode once you know the pattern:
        // bytes memory args = abi.encode(address1, address2, address3);
        // Then use this in the verification script
    }
}








