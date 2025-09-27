// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/ContentRegistry.sol";
import "../../src/interfaces/ISharedTypes.sol";

/**
 * @title ContentRegistryTestHelper
 * @dev Test utilities for ContentRegistry - NOT FOR PRODUCTION DEPLOYMENT
 * @notice This contract provides testing-specific functionality
 */
contract ContentRegistryTestHelper {
    ContentRegistry public immutable contentRegistry;

    // Test environment check
    modifier testOnly() {
        require(
            block.chainid == 31337 || // Foundry local
            block.chainid == 84532,   // Base Sepolia testnet
            "Test helper: Production use not allowed"
        );
        _;
    }

    constructor(address _contentRegistry) {
        require(_contentRegistry != address(0), "Invalid contract address");
        contentRegistry = ContentRegistry(_contentRegistry);
    }

    /**
     * @dev TEST ONLY: Gets purchaser list for content for testing
     * @param contentId The content ID
     * @return purchasers Array of purchaser addresses
     */
    function getContentPurchasersForTesting(uint256 contentId) external view testOnly returns (address[] memory purchasers) {
        // Access through public interface only
        return contentRegistry.getContentPurchasers(contentId);
    }

    /**
     * @dev TEST ONLY: Gets banned words list for testing
     * @return words Array of banned words
     */
    function getBannedWordsForTesting() external view testOnly returns (string[] memory words) {
        // Note: This would need to be implemented differently since we removed the direct access
        // For now, return empty array - tests should use moderation functions instead
        return new string[](0);
    }

    /**
     * @dev TEST ONLY: Gets content report for testing
     * @param contentId The content ID
     * @param reportIndex The report index
     * @return reporter The reporter address
     * @return reason The report reason
     * @return timestamp The report timestamp
     * @return action The action taken
     */
    function getContentReportForTesting(uint256 contentId, uint256 reportIndex) external view testOnly returns (
        address reporter,
        string memory reason,
        uint256 timestamp,
        string memory action
    ) {
        // Access through public interface only
        ContentRegistry.ContentReport[] memory reports = contentRegistry.getContentReports(contentId);
        require(reportIndex < reports.length, "Invalid report index");

        ContentRegistry.ContentReport memory report = reports[reportIndex];
        return (report.reporter, report.reason, report.timestamp, report.action);
    }

    /**
     * @dev TEST ONLY: Gets content view count for testing
     * @param contentId The content ID
     * @return views Number of views (returns 0 since view tracking not implemented)
     */
    function getContentViewsForTesting(uint256 contentId) external view testOnly returns (uint256 views) {
        // Content view tracking not implemented in current version
        return 0;
    }

    /**
     * @dev TEST ONLY: Gets total content count for testing
     * @return count Total content count
     */
    function getTotalContentCountForTesting() external view testOnly returns (uint256 count) {
        (count,,,) = contentRegistry.getPlatformStats();
        return count;
    }

    /**
     * @dev TEST ONLY: Gets active content count for testing
     * @return count Active content count
     */
    function getActiveContentCountForTesting() external view testOnly returns (uint256 count) {
        (,count,,) = contentRegistry.getPlatformStats();
        return count;
    }

    /**
     * @dev TEST ONLY: Gets content metadata for testing
     * @param contentId The content ID
     * @return creator The content creator
     * @return title The content title
     * @return description The content description
     * @return ipfsHash The IPFS hash
     * @return payPerViewPrice The content price
     * @return isActive Whether the content is active
     * @return createdAt The creation timestamp
     */
    function getContentMetadataForTesting(uint256 contentId) external view testOnly returns (
        address creator,
        string memory title,
        string memory description,
        string memory ipfsHash,
        uint256 payPerViewPrice,
        bool isActive,
        uint256 createdAt
    ) {
        // Access through public interface only
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        return (
            content.creator,
            content.title,
            content.description,
            content.ipfsHash,
            content.payPerViewPrice,
            content.isActive,
            content.createdAt
        );
    }

    /**
     * @dev TEST ONLY: Gets content access for testing
     * @param contentId The content ID
     * @param user The user address
     * @return hasAccess Whether the user has access
     */
    function getContentAccessForTesting(uint256 contentId, address user) external view testOnly returns (bool hasAccess) {
        // Access through public interface only
        address[] memory purchasers = contentRegistry.getContentPurchasers(contentId);
        for (uint256 i = 0; i < purchasers.length; i++) {
            if (purchasers[i] == user) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev TEST ONLY: Sets up test scenarios
     * @param creator Creator address
     * @param title Content title
     * @param description Content description
     * @param category Content category
     * @param price Content price
     * @param tags Content tags
     * @return contentId The registered content ID
     */
    function setupTestContentScenario(
        address creator,
        string memory title,
        string memory description,
        ISharedTypes.ContentCategory category,
        uint256 price,
        string[] memory tags
    ) external testOnly returns (uint256 contentId) {
        // Use the production contract's registerContent function
        contentId = contentRegistry.registerContent(
            "QmTestIPFSHash", // Mock IPFS hash
            title,
            description,
            category,
            price,
            tags
        );
    }

    /**
     * @dev TEST ONLY: Batch create test content
     * @param creators Array of creator addresses
     * @param titles Array of content titles
     * @param prices Array of content prices
     * @return contentIds Array of registered content IDs
     */
    function batchCreateTestContent(
        address[] calldata creators,
        string[] calldata titles,
        uint256[] calldata prices
    ) external testOnly returns (uint256[] memory contentIds) {
        require(creators.length == titles.length && titles.length == prices.length, "Array length mismatch");
        contentIds = new uint256[](creators.length);

        for (uint256 i = 0; i < creators.length; i++) {
            string[] memory tags = new string[](0); // No tags for test content
            contentIds[i] = contentRegistry.registerContent(
                "QmTestIPFSHash",
                titles[i],
                "Test description",
                ISharedTypes.ContentCategory.Article,
                prices[i],
                tags
            );
        }
    }

    /**
     * @dev TEST ONLY: Gets all internal data for testing verification
     * @param contentId The content ID
     * @return creator The content creator
     * @return title The content title
     * @return description The content description
     * @return isActive Whether the content is active
     * @return purchaseCount The purchase count
     */
    function getAllContentDataForTesting(uint256 contentId) external view testOnly returns (
        address creator,
        string memory title,
        string memory description,
        bool isActive,
        uint256 purchaseCount
    ) {
        // Access through public interfaces only
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        return (content.creator, content.title, content.description, content.isActive, content.purchaseCount);
    }
}