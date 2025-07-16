// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {CreatorRegistry} from "./CreatorRegistry.sol";

/**
 * @title ContentRegistry
 * @dev Manages content metadata, IPFS storage, and pay-per-view pricing
 * @notice This contract stores content information and integrates with IPFS for decentralized storage
 */
contract ContentRegistry is Ownable, ReentrancyGuard, Pausable {
    
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
     * @param creator Address of the content creator
     * @param ipfsHash IPFS hash for decentralized content storage
     * @param title Human-readable content title
     * @param description Brief content description for discovery
     * @param category Content category for filtering and organization
     * @param payPerViewPrice Price for one-time access in USDC (6 decimals)
     * @param isActive Whether content is available for purchase
     * @param createdAt Timestamp when content was registered
     * @param purchaseCount Total number of purchases for analytics
     * @param tags Content tags for improved searchability
     */
    struct Content {
        address creator;              // Creator address
        string ipfsHash;             // IPFS content hash
        string title;                // Content title (max 100 chars)
        string description;          // Content description (max 500 chars)
        ContentCategory category;    // Content category
        uint256 payPerViewPrice;     // Pay-per-view price in USDC
        bool isActive;               // Content availability status
        uint256 createdAt;           // Creation timestamp
        uint256 purchaseCount;       // Number of purchases
        string[] tags;               // Searchable tags
    }
    
    // Storage mappings for efficient content management
    mapping(uint256 => Content) public contents;
    mapping(address => uint256[]) public creatorContent; // Creator -> Content IDs
    mapping(ContentCategory => uint256[]) public categoryContent; // Category -> Content IDs
    
    // Content discovery and search mappings
    mapping(string => uint256[]) public tagContent; // Tag -> Content IDs
    mapping(string => bool) public bannedWords; // Moderation system
    
    // Analytics and metrics
    uint256 public totalContentCount;
    mapping(ContentCategory => uint256) public categoryCount;
    
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
    
    event ContentDeactivated(uint256 indexed contentId, string reason);
    event WordBanned(string word);
    event WordUnbanned(string word);
    
    // Custom errors for gas-efficient error handling
    error CreatorNotRegistered();
    error InvalidContentId();
    error InvalidPrice();
    error InvalidIPFSHash();
    error ContentNotActive();
    error UnauthorizedCreator();
    error InvalidStringLength();
    error BannedWordDetected();
    error ContentAlreadyExists();
    
    /**
     * @dev Constructor links to CreatorRegistry for validation
     * @param _creatorRegistry Address of the deployed CreatorRegistry contract
     */
    constructor(address _creatorRegistry) Ownable(msg.sender) {
        require(_creatorRegistry != address(0), "Invalid registry address");
        creatorRegistry = CreatorRegistry(_creatorRegistry);
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
            tags: tags
        });
        
        // Update tracking mappings
        creatorContent[msg.sender].push(contentId);
        categoryContent[category].push(contentId);
        
        // Index tags for searchability
        for (uint i = 0; i < tags.length; i++) {
            tagContent[tags[i]].push(contentId);
        }
        
        // Update counters
        totalContentCount++;
        categoryCount[category]++;
        
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
        
        // Update price if new price is provided
        if (newPrice > 0) {
            if (newPrice < MIN_PAY_PER_VIEW_PRICE || newPrice > MAX_PAY_PER_VIEW_PRICE) {
                revert InvalidPrice();
            }
            contents[contentId].payPerViewPrice = newPrice;
        }
        
        contents[contentId].isActive = isActive;
        
        emit ContentUpdated(contentId, newPrice, isActive);
    }
    
    /**
     * @dev Records a content purchase (called by PayPerView contract)
     * @param contentId ID of purchased content
     * @param buyer Address of the buyer
     */
    function recordPurchase(uint256 contentId, address buyer) external {
        // In production, this would have proper access control to only allow PayPerView contract
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        if (!contents[contentId].isActive) revert ContentNotActive();
        
        contents[contentId].purchaseCount++;
        
        emit ContentPurchased(
            contentId,
            buyer,
            contents[contentId].payPerViewPrice,
            block.timestamp
        );
    }
    
    /**
     * @dev Admin function to deactivate content (for moderation)
     * @param contentId Content ID to deactivate
     * @param reason Reason for deactivation
     */
    function deactivateContent(uint256 contentId, string memory reason) 
        external 
        onlyOwner 
    {
        if (contentId == 0 || contentId >= nextContentId) revert InvalidContentId();
        
        contents[contentId].isActive = false;
        emit ContentDeactivated(contentId, reason);
    }
    
    /**
     * @dev Admin function to manage banned words for content moderation
     * @param word Word to ban
     */
    function banWord(string memory word) external onlyOwner {
        bannedWords[word] = true;
        emit WordBanned(word);
    }
    
    /**
     * @dev Admin function to unban words
     * @param word Word to unban
     */
    function unbanWord(string memory word) external onlyOwner {
        bannedWords[word] = false;
        emit WordUnbanned(word);
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
     * @dev Gets content IDs for a specific tag
     * @param tag Search tag
     * @return uint256[] Array of content IDs
     */
    function getContentByTag(string memory tag) external view returns (uint256[] memory) {
        return tagContent[tag];
    }
    
    /**
     * @dev Gets paginated content list for browsing
     * @param offset Starting index
     * @param limit Maximum number of items to return
     * @return contentIds Array of content IDs
     * @return total Total number of content items
     */
    function getContentPaginated(uint256 offset, uint256 limit) 
        external 
        view 
        returns (uint256[] memory contentIds, uint256 total) 
    {
        total = totalContentCount;
        
        if (offset >= total) {
            return (new uint256[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 length = end - offset;
        contentIds = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            contentIds[i] = offset + i + 1; // Content IDs start from 1
        }
        
        return (contentIds, total);
    }
    
    /**
     * @dev Gets platform analytics and metrics
     * @return totalContent Total content count
     * @return categoryCounts Array of counts per category
     */
    function getPlatformStats() 
        external 
        view 
        returns (uint256 totalContent, uint256[] memory categoryCounts) 
    {
        totalContent = totalContentCount;
        categoryCounts = new uint256[](8); // Number of categories
        
        for (uint i = 0; i < 8; i++) {
            categoryCounts[i] = categoryCount[ContentCategory(i)];
        }
        
        return (totalContent, categoryCounts);
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
        
        // Simple banned word checking - in production this would be more sophisticated
        // For MVP, we'll implement basic checks
        
        // Check title for banned words (simplified)
        if (_containsBannedWord(title)) revert BannedWordDetected();
        
        // Check description for banned words (simplified)
        if (_containsBannedWord(description)) revert BannedWordDetected();
        
        // Check tags for banned words
        for (uint i = 0; i < tags.length; i++) {
            if (_containsBannedWord(tags[i])) revert BannedWordDetected();
        }
    }
    
    /**
     * @dev Simple banned word detection (placeholder for more sophisticated filtering)
     */
    function _containsBannedWord(string memory text) internal view returns (bool) {
        // This is a simplified implementation - production would use more sophisticated filtering
        return bannedWords[text];
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