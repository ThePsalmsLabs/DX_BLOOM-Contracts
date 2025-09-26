// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

/**
 * @title MockIPFSStorage
 * @dev Mock implementation of IPFS storage for testing
 * @notice This contract simulates IPFS storage functionality for content and profile management
 */
contract MockIPFSStorage {
    using stdStorage for StdStorage;

    // Storage mappings
    mapping(string => bool) public ipfsHashes;
    mapping(string => string) public hashToData;
    mapping(address => string) public addressToHash;

    // Test data
    mapping(string => bool) public moderationFlags;
    mapping(string => string[]) public hashTags;

    // Events for testing
    event HashStored(string hash, string data);
    event HashModerated(string hash, bool flagged);

    /**
     * @dev Store an IPFS hash with associated data
     * @param hash The IPFS hash
     * @param data The associated data
     */
    function storeHash(string memory hash, string memory data) external {
        ipfsHashes[hash] = true;
        hashToData[hash] = data;
        emit HashStored(hash, data);
    }

    /**
     * @dev Check if a hash exists
     * @param hash The IPFS hash to check
     * @return exists Whether the hash exists
     */
    function hashExists(string memory hash) external view returns (bool) {
        return ipfsHashes[hash];
    }

    /**
     * @dev Get data for a hash
     * @param hash The IPFS hash
     * @return data The associated data
     */
    function getHashData(string memory hash) external view returns (string memory) {
        return hashToData[hash];
    }

    /**
     * @dev Store address to hash mapping
     * @param addr The address
     * @param hash The IPFS hash
     */
    function storeAddressHash(address addr, string memory hash) external {
        addressToHash[addr] = hash;
    }

    /**
     * @dev Get hash for an address
     * @param addr The address
     * @return hash The associated IPFS hash
     */
    function getAddressHash(address addr) external view returns (string memory) {
        return addressToHash[addr];
    }

    /**
     * @dev Flag a hash for moderation
     * @param hash The IPFS hash
     * @param flagged Whether to flag it
     */
    function flagHash(string memory hash, bool flagged) external {
        moderationFlags[hash] = flagged;
        emit HashModerated(hash, flagged);
    }

    /**
     * @dev Check if a hash is flagged
     * @param hash The IPFS hash
     * @return flagged Whether the hash is flagged
     */
    function isHashFlagged(string memory hash) external view returns (bool) {
        return moderationFlags[hash];
    }

    /**
     * @dev Store tags for a hash
     * @param hash The IPFS hash
     * @param tags Array of tags
     */
    function storeHashTags(string memory hash, string[] memory tags) external {
        hashTags[hash] = tags;
    }

    /**
     * @dev Get tags for a hash
     * @param hash The IPFS hash
     * @return tags Array of tags
     */
    function getHashTags(string memory hash) external view returns (string[] memory) {
        return hashTags[hash];
    }

    /**
     * @dev Validate IPFS hash format
     * @param hash The IPFS hash to validate
     * @return valid Whether the hash format is valid
     */
    function validateHash(string memory hash) external pure returns (bool) {
        bytes memory hashBytes = bytes(hash);
        return hashBytes.length >= 7 && hashBytes.length <= 59; // IPFS hash length constraints
    }

    /**
     * @dev Check if hash contains banned words
     * @param hash The IPFS hash
     * @param bannedWords Array of banned words
     * @return containsBanned Whether the hash contains banned words
     */
    function checkBannedWords(string memory hash, string[] memory bannedWords) external view returns (bool) {
        string memory data = hashToData[hash];
        bytes memory dataBytes = bytes(data);

        for (uint256 i = 0; i < bannedWords.length; i++) {
            bytes memory bannedBytes = bytes(bannedWords[i]);
            if (_containsBytes(dataBytes, bannedBytes)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Internal helper to check if bytes contain a substring
     * @param source The source bytes
     * @param pattern The pattern to search for
     * @return contains Whether the pattern is found
     */
    function _containsBytes(bytes memory source, bytes memory pattern) internal pure returns (bool) {
        if (pattern.length == 0) return true;
        if (pattern.length > source.length) return false;

        for (uint256 i = 0; i <= source.length - pattern.length; i++) {
            bool foundMatch = true;
            for (uint256 j = 0; j < pattern.length; j++) {
                if (source[i + j] != pattern[j]) {
                    foundMatch = false;
                    break;
                }
            }
            if (foundMatch) return true;
        }
        return false;
    }

    /**
     * @dev Reset all storage (for testing)
     */
    function resetStorage() external {
        // Clear all mappings - in a real implementation, this would be more complex
        // For testing purposes, we just provide this function signature
    }

    /**
     * @dev Set up test data
     * @param hash The IPFS hash
     * @param data The data
     * @param tags Array of tags
     */
    function setupTestData(string memory hash, string memory data, string[] memory tags) external {
        ipfsHashes[hash] = true;
        hashToData[hash] = data;
        hashTags[hash] = tags;
    }
}
