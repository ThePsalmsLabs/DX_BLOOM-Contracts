// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

/**
 * @title CheckAddresses
 * @dev Script to validate that contract addresses exist on Base mainnet
 * @notice This script checks if the deployed contracts have code at their addresses
 */
contract CheckAddresses is Script {
    // Contract addresses to check
    address constant CREATOR_REGISTRY = 0x6b88ae6538FB8bf8cbA1ad64fABb458aa0CE4263;
    address constant CONTENT_REGISTRY = 0xB4cbF1923be6FF1bc4D45471246D753d34aB41d7;
    address constant PAY_PER_VIEW = 0x8A89fcAe4E674d6528A5a743E468eBE9BDCf3101;
    address constant SUBSCRIPTION_MANAGER = 0x06D92f5A03f177c50A6e14Ac6a231cb371e67Da4;
    address constant COMMERCE_INTEGRATION = 0x931601610C9491948e7cEeA2e9Df480162e45409;
    address constant PRICE_ORACLE = 0x13056B1dFE38dA0c058e6b2B2e3DaecCEdCEFFfF;
    address constant COMMERCE_PROTOCOL = 0x96A08D8e8631b6dB52Ea0cbd7232d9A85d239147;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    struct ContractInfo {
        string name;
        address addr;
        bool hasCode;
        uint256 codeSize;
    }

    function run() public {
        console.log("=== Checking Contract Addresses on Base Mainnet ===");
        console.log("RPC URL: https://mainnet.base.org");
        console.log("");

        ContractInfo[] memory contracts = new ContractInfo[](8);

        contracts[0] = ContractInfo("CreatorRegistry", CREATOR_REGISTRY, false, 0);
        contracts[1] = ContractInfo("ContentRegistry", CONTENT_REGISTRY, false, 0);
        contracts[2] = ContractInfo("PayPerView", PAY_PER_VIEW, false, 0);
        contracts[3] = ContractInfo("SubscriptionManager", SUBSCRIPTION_MANAGER, false, 0);
        contracts[4] = ContractInfo("CommerceProtocolIntegration", COMMERCE_INTEGRATION, false, 0);
        contracts[5] = ContractInfo("PriceOracle", PRICE_ORACLE, false, 0);
        contracts[6] = ContractInfo("CommerceProtocol", COMMERCE_PROTOCOL, false, 0);
        contracts[7] = ContractInfo("USDC", USDC, false, 0);

        uint256 validCount = 0;
        uint256 totalCount = contracts.length;

        for (uint i = 0; i < contracts.length; i++) {
            (contracts[i].hasCode, contracts[i].codeSize) = checkContract(contracts[i].addr);

            console.log(string.concat(contracts[i].name, " at ", vm.toString(contracts[i].addr)));

            if (contracts[i].hasCode) {
                console.log("  Contract exists - Code size:", contracts[i].codeSize, "bytes");
                validCount++;
            } else {
                console.log("  No contract code found at this address");
            }
            console.log("");
        }

        console.log("=== Address Check Summary ===");
        console.log("Valid contracts:", validCount, "/", totalCount);

        if (validCount == totalCount) {
            console.log("All contract addresses are valid!");
            console.log("You can proceed with verification.");
        } else {
            console.log("WARNING: Some addresses do not contain contracts.");
            console.log("Please verify the addresses are correct before running verification.");
        }
    }

    function checkContract(address _addr) internal returns (bool hasCode, uint256 codeSize) {
        string[] memory inputs = new string[](4);
        inputs[0] = "cast";
        inputs[1] = "code";
        inputs[2] = vm.toString(_addr);
        inputs[3] = "--rpc-url";
        inputs[4] = "https://mainnet.base.org";

        try vm.ffi(inputs) returns (bytes memory result) {
            // Remove "0x" prefix and count bytes
            if (result.length >= 2 && result[0] == "0" && result[1] == "x") {
                bytes memory code = slice(result, 2, result.length - 2);
                uint256 size = code.length / 2; // Each byte is 2 hex chars
                return (size > 0, size);
            }
            return (false, 0);
        } catch {
            return (false, 0);
        }
    }

    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }
}








