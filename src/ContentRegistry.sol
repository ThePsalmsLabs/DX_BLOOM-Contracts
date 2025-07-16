// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";

/**
 * @title ContentRegistry
 * @dev Manages content metadata, IPFS storage, and pay-per-view pricing with enhanced moderation
 * @notice This contract stores content information and integrates with IPFS for decentralized storage
 */
contract ContentRegistry is Ownable, AccessControl, ReentrancyGuard, Pausable {
    
    // Role definitions
    bytes32 public constant PURCHASE_RECORDER_ROLE = keccak256("PURCHASE_RECORDER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    
    // Reference to the CreatorRegistry for validation
    CreatorRegistry public immutable creatorRegistry;
    
    // Content pricing limits (in USDC with 6 decimals)
    uint256 public constant MIN_PAY_PER_VIEW_PRICE = 0.01e6; // $0.01 minimum
    uint256 public constant MAX_PAY_PER_VIEW_PRICE = 50e6;   // $50 maximum
    
    // Content ID tracking
    uint256 public nextContentId = 1; // Start from 1 to avoid confusion with default values
    
    /**
     * @dev Content categories for better organization and filtering
     */
    enum ContentCategory {
        Article,       // Written content like blog posts, guides
        Video,         // Video content and tutorials  
        Audio,         // Podcasts, music, audio content
        Image,         // Photography, digital art
        Document,      // PDFs, presentations, documents
        Course,        // Educational course materials
        Other          // Miscellaneous content types
    }
    
    /**
     * @dev Content structure containing all metadata and pricing information
     */
    struct Content {
        address creator;              // Creator address
        string ipfsHash;             // IPFS content hash
        string title;                // Human-readable content title
        string description;          // Brief content description for discovery
        ContentCategory category;    // Content category for filtering and organization
        uint256 payPerViewPrice;     // Price for one-time access in USDC (6 decimals)
        bool isActive;               // Whether content is available for purchase
        uint256 createdAt;           // Timestamp when content was registered
        uint256 purchaseCount;       // Total number of purchases for analytics
        string[] tags;               // Searchable tags
        bool isReported;             // Whether content has been reported
        uint256 reportCount;         // Number of reports against this content
    }
    
    /**
     * @dev Content report structure for moderation
     */
    struct ContentReport {
        uint256 contentId;
        address reporter;
        string reason;
        uint256 timestamp;
        bool resolved;
        string action; // "ignored", "warning", "removed"
    }
    
    // Storage mappings for efficient content management
    mapping(uint256 => Content) public contents;
    mapping(address => uint256[]) public creatorContent; // Creator -> Content IDs
    mapping(ContentCategory => uint256[]) public categoryContent; // Category -> Content IDs
    mapping(uint256 => address[]) public contentPurchasers; // Content -> Purchaser addresses
    
    // Content discovery and search mappings
    mapping(string => uint256[]) public tagContent; // Tag -> Content IDs
    mapping(string => bool) public bannedWords; // Moderation system
    mapping(string => bool) public bannedPhrases; // Enhanced moderation
    
    // Reporting and moderation
    mapping(uint256 => ContentReport[]) public contentReports; // Content -> Reports
    mapping(address => mapping(uint256 => bool)) public hasReported; // User -> Content -> Reported
    uint256 public nextReportId = 1;
    
    // Analytics and metrics
    uint256 public totalContentCount;
    uint256 public activeContentCount;
    mapping(ContentCategory => uint256) public categoryCount;
    mapping(ContentCategory => uint256) public activeCategoryCount;
    
    // Moderation thresholds
    uint256 public autoModerateThreshold = 5; // Auto-deactivate after 5 reports
    uint256 public maxReportsPerUser = 10; // Max reports per user per day
    mapping(address => mapping(uint256 => uint256)) public userDailyReports; // User -> Day -> Count
    
    // Events for frontend integration and indexing
    event ContentRegistered(
        uint256 indexed contentId,
        address indexed creator,
        string ipfsHash,
        string title,
        ContentCategory category,
        uint256 payPerViewPrice,
        uint256 timestamp
    );
    
    event ContentUpdated(
        uint256 indexed contentId,
        uint256 newPrice,
        bool isActive
    );
    
    event ContentPurchased(
        uint256 indexed contentId,
        address indexed buyer,
        uint256 price,
        uint256 timestamp
    );
    
    event ContentDeactivated(
        uint256 indexed contentId, 
        string reason,
        address moderator
    );
    
    event ContentReported(
        uint256 indexed contentId,
        address indexed reporter,
        string reason,
        uint256 reportId
    );
    
    event ReportResolved(
        uint256 indexed reportId,
        uint256 indexed contentId,
        string action,
        address moderator
    );
    
    event WordBanned(string word, bool isPhrase);
    event WordUnbanned(string word, bool isPhrase);
    
    // Custom errors for gas-efficient error handling
    error CreatorNotRegistered();
    error InvalidContentId();
    error InvalidPrice();
    error InvalidIPFSHash();
    error ContentNotActive();
    error UnauthorizedCreator();
    error InvalidStringLength();
    error BannedWordDetected(string word);
    error ContentAlreadyExists();
    error AlreadyReported();
    error TooManyReports();
    error ReportNotFound();
    error InvalidReportReason();
    
    /**
     * @dev Constructor links to CreatorRegistry for validation
     * @param _creatorRegistry Address of the deployed CreatorRegistry contract
     */
    constructor(address _creatorRegistry) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid registry address");
        creatorRegistry = CreatorRegistry(_creatorRegistry);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MODERATOR_ROLE, msg.sender);
    }
    
    /**
     * @dev Registers new content with comprehensive metadata and validation
     * @param ipfsHash IPFS hash of the content (must be valid IPFS hash format)
     * @param title Content title (1-100 characters)
     * @param description Content description (1-500 characters)
     * @param category Content category from enum
     * @param payPerViewPrice Price for access in USDC (6 decimals)
     * @param tags Array of searchable tags (max 10 tags, each max 30 chars)
     * @return contentId The ID assigned to the new content
     */
    function registerContent(
        string memory ipfsHash,
        string memory title,
        string memory description,
        ContentCategory category,
        uint256 payPerViewPrice,
        string[] memory tags
    ) external nonReentrant whenNotPaused returns (uint256) {
        
        // Validate creator registration
        if (!creatorRegistry.isRegisteredCreator(msg.sender)) {
            revert CreatorNotRegistered();
        }
        
        // Validate content data
        _validateContentData(ipfsHash, title, description, payPerViewPrice, tags);
        
        // Check for content moderation
        _checkContentModeration(title, description, tags);
        
        uint256 contentId = nextContentId++;
        
        // Create and store content
        contents[contentId] = Content({
            creator: msg.sender,
            ipfsHash: ipfsHash,
            title: title,
            description: description,
            category: category,
            payPerViewPrice: payPerViewPrice,
            isActive: true,
            createdAt: block.timestamp,
            purchaseCount: 0,
            tags: tags,
            isReported: false,
            reportCount: 0
        });
        
        // Update tracking mappings
        creatorContent[msg.sender].push(contentId);
        categoryContent[category].push(contentId);
        
        // Index tags for searchability
        for (uint i = 0; i < tags.length; i++) {
            tagContent[_toLowerCase(tags[i])].push(contentId);
        }
        
        // Update counters
        totalContentCount++;
        activeContentCount++;
        categoryCount[category]++;
        activeCategoryCount[category]++;
        
        // Update creator stats in registry
        try creatorRegistry.updateCreatorStats(msg.sender, 0, 1, 0) {
            // Stats updated successfully
        } catch {
            // Continue if stats update fails (non-critical)
        }
        
        emit ContentRegistered(
            contentId,
            msg.sender,
            ipfsHash,
            title,
            category,
            payPerViewPrice,
            block.timestamp
        );
        
        return contentId;
    }
    
    /**
     * @dev Updates content pricing and availability (creator only)
     * @param contentId ID of content to update
     * @param newPrice New pay-per-view price (0 to keep current price)
     * @param isActive New availability status
     */
    function updateContent(
        uint256 contentId,
        uint256 newPrice,
        bool isActive
    ) external nonReentrant whenNotPaused {
        
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        if (contents[contentId].creator != msg.sender) revert UnauthorizedCreator();
        
        bool wasActive = contents[contentId].isActive;
        
        // Update price if new price is provided
        if (newPrice > 0) {
            if (newPrice < MIN_PAY_PER_VIEW_PRICE || newPrice > MAX_PAY_PER_VIEW_PRICE) {
                revert InvalidPrice();
            }
            contents[contentId].payPerViewPrice = newPrice;
        }
        
        contents[contentId].isActive = isActive;
        
        // Update active counters
        if (wasActive && !isActive) {
            activeContentCount--;
            activeCategoryCount[contents[contentId].category]--;
        } else if (!wasActive && isActive) {
            activeContentCount++;
            activeCategoryCount[contents[contentId].category]++;
        }
        
        emit ContentUpdated(contentId, newPrice, isActive);
    }
    
    /**
     * @dev Records a content purchase (called by authorized contracts only)
     * @param contentId ID of purchased content
     * @param buyer Address of the buyer
     */
    function recordPurchase(uint256 contentId, address buyer) 
        external 
        onlyRole(PURCHASE_RECORDER_ROLE) 
    {
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        if (!contents[contentId].isActive) revert ContentNotActive();
        
        contents[contentId].purchaseCount++;
        contentPurchasers[contentId].push(buyer);
        
        emit ContentPurchased(
            contentId,
            buyer,
            contents[contentId].payPerViewPrice,
            block.timestamp
        );
    }
    
    /**
     * @dev Reports content for moderation
     * @param contentId Content to report
     * @param reason Reason for reporting
     */
    function reportContent(uint256 contentId, string memory reason) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        if (!contents[contentId].isActive) revert ContentNotActive();
        if (hasReported[msg.sender][contentId]) revert AlreadyReported();
        if (bytes(reason).length == 0 || bytes(reason).length > 200) revert InvalidReportReason();
        
        // Check daily report limit
        uint256 today = block.timestamp / 1 days;
        if (userDailyReports[msg.sender][today] >= maxReportsPerUser) {
            revert TooManyReports();
        }
        
        // Create report
        uint256 reportId = nextReportId++;
        contentReports[contentId].push(ContentReport({
            contentId: contentId,
            reporter: msg.sender,
            reason: reason,
            timestamp: block.timestamp,
            resolved: false,
            action: ""
        }));
        
        // Update state
        hasReported[msg.sender][contentId] = true;
        userDailyReports[msg.sender][today]++;
        contents[contentId].reportCount++;
        contents[contentId].isReported = true;
        
        // Auto-moderate if threshold reached
        if (contents[contentId].reportCount >= autoModerateThreshold) {
            _autoModerateContent(contentId);
        }
        
        emit ContentReported(contentId, msg.sender, reason, reportId);
    }
    
    /**
     * @dev Resolves a content report (moderator only)
     * @param contentId Content ID
     * @param reportIndex Report index in the content's reports array
     * @param action Action taken ("ignored", "warning", "removed")
     */
    function resolveReport(
        uint256 contentId,
        uint256 reportIndex,
        string memory action
    ) external onlyRole(MODERATOR_ROLE) {
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        if (reportIndex >= contentReports[contentId].length) revert ReportNotFound();
        
        ContentReport storage report = contentReports[contentId][reportIndex];
        if (report.resolved) return; // Already resolved
        
        report.resolved = true;
        report.action = action;
        
        // Take action based on decision
        if (keccak256(bytes(action)) == keccak256(bytes("removed"))) {
            _deactivateContent(contentId, "Removed due to moderation", msg.sender);
        }
        
        emit ReportResolved(reportIndex, contentId, action, msg.sender);
    }
    
    /**
     * @dev Admin function to deactivate content (for moderation)
     * @param contentId Content ID to deactivate
     * @param reason Reason for deactivation
     */
    function deactivateContent(uint256 contentId, string memory reason) 
        external 
        onlyRole(MODERATOR_ROLE)
    {
        _deactivateContent(contentId, reason, msg.sender);
    }
    
    /**
     * @dev Admin function to manage banned words for content moderation
     * @param word Word to ban
     * @param isPhrase Whether this is a phrase (for substring matching)
     */
    function banWord(string memory word, bool isPhrase) external onlyRole(MODERATOR_ROLE) {
        string memory lowerWord = _toLowerCase(word);
        if (isPhrase) {
            bannedPhrases[lowerWord] = true;
        } else {
            bannedWords[lowerWord] = true;
        }
        emit WordBanned(lowerWord, isPhrase);
    }
    
    /**
     * @dev Admin function to unban words
     * @param word Word to unban
     * @param isPhrase Whether this is a phrase
     */
    function unbanWord(string memory word, bool isPhrase) external onlyRole(MODERATOR_ROLE) {
        string memory lowerWord = _toLowerCase(word);
        if (isPhrase) {
            bannedPhrases[lowerWord] = false;
        } else {
            bannedWords[lowerWord] = false;
        }
        emit WordUnbanned(lowerWord, isPhrase);
    }
    
    /**
     * @dev Updates moderation settings
     * @param newThreshold New auto-moderation threshold
     * @param newMaxReports New max reports per user per day
     */
    function updateModerationSettings(
        uint256 newThreshold,
        uint256 newMaxReports
    ) external onlyRole(MODERATOR_ROLE) {
        autoModerateThreshold = newThreshold;
        maxReportsPerUser = newMaxReports;
    }
    
    /**
     * @dev Grants purchase recorder role to authorized contracts
     * @param contractAddress Address of contract that can record purchases
     */
    function grantPurchaseRecorderRole(address contractAddress) external onlyOwner {
        _grantRole(PURCHASE_RECORDER_ROLE, contractAddress);
    }
    
    // View functions for content discovery and analytics
    
    /**
     * @dev Gets complete content information by ID
     * @param contentId Content ID to query
     * @return Content struct with all content data
     */
    function getContent(uint256 contentId) external view returns (Content memory) {
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        return contents[contentId];
    }
    
    /**
     * @dev Gets content IDs for a specific creator
     * @param creator Creator address
     * @return uint256[] Array of content IDs
     */
    function getCreatorContent(address creator) external view returns (uint256[] memory) {
        return creatorContent[creator];
    }
    
    /**
     * @dev Gets active content IDs for a creator
     * @param creator Creator address
     * @return uint256[] Array of active content IDs
     */
    function getCreatorActiveContent(address creator) external view returns (uint256[] memory) {
        uint256[] memory allContent = creatorContent[creator];
        uint256 activeCount = 0;
        
        // Count active content
        for (uint256 i = 0; i < allContent.length; i++) {
            if (contents[allContent[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build active content array
        uint256[] memory activeContent = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allContent.length; i++) {
            if (contents[allContent[i]].isActive) {
                activeContent[index] = allContent[i];
                index++;
            }
        }
        
        return activeContent;
    }
    
    /**
     * @dev Gets content IDs for a specific category
     * @param category Content category
     * @return uint256[] Array of content IDs
     */
    function getContentByCategory(ContentCategory category) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return categoryContent[category];
    }
    
    /**
     * @dev Gets active content IDs for a category
     * @param category Content category
     * @return uint256[] Array of active content IDs
     */
    function getActiveContentByCategory(ContentCategory category)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory allContent = categoryContent[category];
        uint256 activeCount = 0;
        
        // Count active content
        for (uint256 i = 0; i < allContent.length; i++) {
            if (contents[allContent[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build active content array
        uint256[] memory activeContent = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allContent.length; i++) {
            if (contents[allContent[i]].isActive) {
                activeContent[index] = allContent[i];
                index++;
            }
        }
        
        return activeContent;
    }
    
    /**
     * @dev Gets content IDs for a specific tag
     * @param tag Search tag
     * @return uint256[] Array of content IDs
     */
    function getContentByTag(string memory tag) external view returns (uint256[] memory) {
        return tagContent[_toLowerCase(tag)];
    }
    
    /**
     * @dev Gets paginated content list for browsing (active content only)
     * @param offset Starting index
     * @param limit Maximum number of items to return
     * @return contentIds Array of content IDs
     * @return total Total number of active content items
     */
    function getActiveContentPaginated(uint256 offset, uint256 limit) 
        external 
        view 
        returns (uint256[] memory contentIds, uint256 total) 
    {
        total = activeContentCount;
        
        if (offset >= total) {
            return (new uint256[](0), total);
        }
        
        uint256 collected = 0;
        uint256 checked = 0;
        uint256 currentId = 1;
        
        // Skip to offset
        while (checked < offset && currentId < nextContentId) {
            if (contents[currentId].isActive) {
                checked++;
            }
            currentId++;
        }
        
        // Collect content IDs
        uint256 maxCollect = limit;
        if (offset + limit > total) {
            maxCollect = total - offset;
        }
        
        contentIds = new uint256[](maxCollect);
        
        while (collected < maxCollect && currentId < nextContentId) {
            if (contents[currentId].isActive) {
                contentIds[collected] = currentId;
                collected++;
            }
            currentId++;
        }
        
        return (contentIds, total);
    }
    
    /**
     * @dev Gets reports for a content ID
     * @param contentId Content ID
     * @return ContentReport[] Array of reports
     */
    function getContentReports(uint256 contentId) 
        external 
        view 
        returns (ContentReport[] memory) 
    {
        return contentReports[contentId];
    }
    
    /**
     * @dev Gets platform analytics and metrics
     * @return totalContent Total content count
     * @return activeContent Active content count
     * @return categoryCounts Array of counts per category
     * @return activeCategoryCounts Array of active counts per category
     */
    function getPlatformStats() 
        external 
        view 
        returns (
            uint256 totalContent, 
            uint256 activeContent,
            uint256[] memory categoryCounts,
            uint256[] memory activeCategoryCounts
        ) 
    {
        totalContent = totalContentCount;
        activeContent = activeContentCount;
        categoryCounts = new uint256[](8); // Number of categories
        activeCategoryCounts = new uint256[](8);
        
        for (uint i = 0; i < 8; i++) {
            categoryCounts[i] = categoryCount[ContentCategory(i)];
            activeCategoryCounts[i] = activeCategoryCount[ContentCategory(i)];
        }
        
        return (totalContent, activeContent, categoryCounts, activeCategoryCounts);
    }
    
    // Internal helper functions
    
    /**
     * @dev Validates content registration data
     */
    function _validateContentData(
        string memory ipfsHash,
        string memory title,
        string memory description,
        uint256 payPerViewPrice,
        string[] memory tags
    ) internal pure {
        
        // Validate IPFS hash format (basic validation)
        bytes memory ipfsBytes = bytes(ipfsHash);
        if (ipfsBytes.length == 0 || ipfsBytes.length > 100) revert InvalidIPFSHash();
        
        // Validate title length
        bytes memory titleBytes = bytes(title);
        if (titleBytes.length == 0 || titleBytes.length > 100) revert InvalidStringLength();
        
        // Validate description length
        bytes memory descBytes = bytes(description);
        if (descBytes.length == 0 || descBytes.length > 500) revert InvalidStringLength();
        
        // Validate price range
        if (payPerViewPrice < MIN_PAY_PER_VIEW_PRICE || 
            payPerViewPrice > MAX_PAY_PER_VIEW_PRICE) {
            revert InvalidPrice();
        }
        
        // Validate tags (max 10 tags, each max 30 characters)
        if (tags.length > 10) revert InvalidStringLength();
        for (uint i = 0; i < tags.length; i++) {
            if (bytes(tags[i]).length > 30) revert InvalidStringLength();
        }
    }
    
    /**
     * @dev Checks content for banned words and moderation
     */
    function _checkContentModeration(
        string memory title,
        string memory description,
        string[] memory tags
    ) internal view {
        
        // Check title
        string memory lowerTitle = _toLowerCase(title);
        _checkTextForBannedContent(lowerTitle);
        
        // Check description
        string memory lowerDesc = _toLowerCase(description);
        _checkTextForBannedContent(lowerDesc);
        
        // Check tags
        for (uint i = 0; i < tags.length; i++) {
            string memory lowerTag = _toLowerCase(tags[i]);
            _checkTextForBannedContent(lowerTag);
        }
    }
    
    /**
     * @dev Checks text for banned words and phrases
     * @param text Text to check (should be lowercase)
     */
    function _checkTextForBannedContent(string memory text) internal view {
        // Check for exact banned words
        if (bannedWords[text]) {
            revert BannedWordDetected(text);
        }
        
        // Check for banned phrases (substring matching)
        // Note: This is a simplified implementation
        // In production, you'd use more sophisticated string matching
        bytes memory textBytes = bytes(text);
        
        // Check each banned phrase
        // This is a placeholder - in production you'd implement proper substring search
        // For now, we'll just check if banned phrases are exact matches
        if (bannedPhrases[text]) {
            revert BannedWordDetected(text);
        }
    }
    
    /**
     * @dev Converts string to lowercase
     * @param str Input string
     * @return string Lowercase string
     */
    function _toLowerCase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        
        return string(bLower);
    }
    
    /**
     * @dev Auto-moderates content when report threshold is reached
     * @param contentId Content to moderate
     */
    function _autoModerateContent(uint256 contentId) internal {
        _deactivateContent(contentId, "Auto-moderated due to reports", address(this));
    }
    
    /**
     * @dev Internal function to deactivate content
     * @param contentId Content to deactivate
     * @param reason Reason for deactivation
     * @param moderator Address performing the action
     */
    function _deactivateContent(uint256 contentId, string memory reason, address moderator) internal {
        if (contents[contentId].isActive) {
            contents[contentId].isActive = false;
            activeContentCount--;
            activeCategoryCount[contents[contentId].category]--;
        }
        
        emit ContentDeactivated(contentId, reason, moderator);
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Emergency unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}