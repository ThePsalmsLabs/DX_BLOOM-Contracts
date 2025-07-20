// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";

/**
 * @title ContentRegistryTest
 * @dev Comprehensive unit tests for the ContentRegistry contract
 * @notice This test suite covers content registration, metadata management, pricing updates,
 *         content discovery, moderation features, and purchase tracking. We test both the
 *         happy path scenarios and edge cases to ensure robust content management.
 *
 * The ContentRegistry is the heart of our content management system, so these tests are
 * crucial for ensuring creators can safely publish content while users can discover and
 * access it properly. We'll test content registration, updates, moderation, and analytics.
 */
contract ContentRegistryTest is TestSetup {
    // Events we'll test for proper emission
    event ContentUpdated(uint256 indexed contentId, uint256 newPrice, bool isActive);
    event ContentDeactivated(uint256 indexed contentId, string reason, address moderator);
    event ContentReported(uint256 indexed contentId, address indexed reporter, string reason, uint256 reportId);
    event ReportResolved(uint256 indexed reportId, uint256 indexed contentId, string action, address moderator);
    event WordBanned(string word, bool isPhrase);
    event WordUnbanned(string word, bool isPhrase);

    /**
     * @dev Test setup specific to ContentRegistry tests
     * @notice This runs before each test to ensure we have registered creators available
     */
    function setUp() public override {
        super.setUp();

        // Register creators that we'll use in content tests
        // This is important because only registered creators can publish content
        assertTrue(registerCreator(creator1, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 1"));
        assertTrue(registerCreator(creator2, DEFAULT_SUBSCRIPTION_PRICE, "Test Profile 2"));
    }

    // Helper for string equality
    function stringEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ============ CONTENT REGISTRATION TESTS ============

    /**
     * @dev Tests successful content registration with valid parameters
     * @notice This is our happy path test - everything should work perfectly
     * We test that content can be registered with all required fields and that
     * the contract state is updated correctly
     */
    function test_RegisterContent_Success() public {
        // Arrange: Set up valid content parameters
        string memory ipfsHash = SAMPLE_IPFS_HASH;
        string memory title = SAMPLE_CONTENT_TITLE;
        string memory description = SAMPLE_CONTENT_DESCRIPTION;
        ContentCategory category = ContentCategory.Article;
        uint256 price = DEFAULT_CONTENT_PRICE;
        string[] memory tags = createSampleTags();

        // Act: Register content as creator1
        vm.startPrank(creator1);

        // We expect the ContentRegistered event to be emitted with correct parameters
        vm.expectEmit(true, true, false, true);
        emit ContentRegistered(1, creator1, ipfsHash, title, category, price, block.timestamp);

        uint256 contentId = contentRegistry.registerContent(ipfsHash, title, description, category, price, tags);
        vm.stopPrank();

        // Assert: Verify the content was registered correctly
        assertEq(contentId, 1); // Should be the first content ID

        // Verify the content details are stored correctly
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.creator, creator1);
        assertTrue(stringEqual(content.ipfsHash, ipfsHash));
        assertTrue(stringEqual(content.title, title));
        assertTrue(stringEqual(content.description, description));
        assertTrue(content.category == category);
        assertEq(content.payPerViewPrice, price);
        assertTrue(content.isActive);
        assertEq(content.createdAt, block.timestamp);
        assertEq(content.purchaseCount, 0);
        assertFalse(content.isReported);
        assertEq(content.reportCount, 0);

        // Verify the tags were stored correctly
        assertEq(content.tags.length, tags.length);
        for (uint256 i = 0; i < tags.length; i++) {
            assertTrue(stringEqual(content.tags[i], tags[i]));
        }

        // Verify the content appears in creator's content list
        uint256[] memory creatorContent = contentRegistry.getCreatorContent(creator1);
        assertEq(creatorContent.length, 1);
        assertEq(creatorContent[0], contentId);

        // Verify the content appears in category lists
        uint256[] memory categoryContent = contentRegistry.getContentByCategory(category);
        assertEq(categoryContent.length, 1);
        assertEq(categoryContent[0], contentId);

        // Verify the content appears in tag searches
        uint256[] memory tagContent = contentRegistry.getContentByTag(tags[0]);
        assertEq(tagContent.length, 1);
        assertEq(tagContent[0], contentId);

        // Verify platform statistics were updated
        (uint256 totalContent, uint256 activeContent,,) = contentRegistry.getPlatformStats();
        assertEq(totalContent, 1);
        assertEq(activeContent, 1);
    }

    /**
     * @dev Tests that non-registered creators cannot register content
     * @notice This tests our creator validation - only registered creators should be able to publish
     */
    function test_RegisterContent_CreatorNotRegistered() public {
        // Arrange: Use a user who is not a registered creator
        address nonCreator = user1;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(nonCreator);
        vm.expectRevert(ContentRegistry.CreatorNotRegistered.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            SAMPLE_CONTENT_TITLE,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();

        // Verify no content was registered
        (uint256 totalContent,,,) = contentRegistry.getPlatformStats();
        assertEq(totalContent, 0);
    }

    /**
     * @dev Tests content registration with price too low
     * @notice This tests our price validation - content must have a minimum price
     */
    function test_RegisterContent_PriceTooLow() public {
        // Arrange: Set up a price below the minimum
        uint256 invalidPrice = MIN_CONTENT_PRICE - 1;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidPrice.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            SAMPLE_CONTENT_TITLE,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            invalidPrice,
            createSampleTags()
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests content registration with price too high
     * @notice This tests the upper bound of our price validation
     */
    function test_RegisterContent_PriceTooHigh() public {
        // Arrange: Set up a price above the maximum
        uint256 invalidPrice = MAX_CONTENT_PRICE + 1;

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidPrice.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            SAMPLE_CONTENT_TITLE,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            invalidPrice,
            createSampleTags()
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests content registration with invalid IPFS hash
     * @notice This tests our IPFS hash validation
     */
    function test_RegisterContent_InvalidIPFSHash() public {
        // Arrange: Set up an invalid IPFS hash (too short)
        string memory invalidHash = "invalid";

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidIPFSHash.selector);
        contentRegistry.registerContent(
            invalidHash,
            SAMPLE_CONTENT_TITLE,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests content registration with empty title
     * @notice This tests our title validation
     */
    function test_RegisterContent_EmptyTitle() public {
        // Arrange: Set up an empty title
        string memory emptyTitle = "";

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidStringLength.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            emptyTitle,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests content registration with too many tags
     * @notice This tests our tag validation - we limit tags to prevent spam
     */
    function test_RegisterContent_TooManyTags() public {
        // Arrange: Set up too many tags (limit is 10)
        string[] memory tooManyTags = new string[](11);
        for (uint256 i = 0; i < 11; i++) {
            tooManyTags[i] = "tag";
        }

        // Act & Assert: Expect the transaction to revert
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidStringLength.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            SAMPLE_CONTENT_TITLE,
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            tooManyTags
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests content registration with different categories
     * @notice This tests that all content categories work correctly
     */
    function test_RegisterContent_DifferentCategories() public {
        // Arrange: Test each category type
        ContentCategory[] memory categories = new ContentCategory[](5);
        categories[0] = ContentCategory.Article;
        categories[1] = ContentCategory.Video;
        categories[2] = ContentCategory.Course;
        categories[3] = ContentCategory.Music;
        categories[4] = ContentCategory.Podcast;

        vm.startPrank(creator1);

        // Act & Assert: Register content in each category
        for (uint256 i = 0; i < categories.length; i++) {
            uint256 contentId = contentRegistry.registerContent(
                SAMPLE_IPFS_HASH,
                SAMPLE_CONTENT_TITLE,
                SAMPLE_CONTENT_DESCRIPTION,
                categories[i],
                DEFAULT_CONTENT_PRICE,
                createSampleTags()
            );

            // Verify the content was registered with the correct category
            ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
            assertTrue(content.category == categories[i]);

            // Verify the content appears in the correct category list
            uint256[] memory categoryContent = contentRegistry.getContentByCategory(categories[i]);
            assertEq(categoryContent.length, 1);
            assertEq(categoryContent[0], contentId);
        }

        vm.stopPrank();

        // Verify total content count
        (uint256 totalContent,,,) = contentRegistry.getPlatformStats();
        assertEq(totalContent, 5);
    }

    // ============ CONTENT UPDATE TESTS ============

    /**
     * @dev Tests successful content price update
     * @notice This tests that creators can update their content pricing
     */
    function test_UpdateContent_PriceUpdate() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");
        uint256 newPrice = DEFAULT_CONTENT_PRICE * 2; // Double the price

        // Act: Update the content price
        vm.startPrank(creator1);

        // Expect the ContentUpdated event
        vm.expectEmit(true, false, false, true);
        emit ContentUpdated(contentId, newPrice, true);

        contentRegistry.updateContent(contentId, newPrice, true);
        vm.stopPrank();

        // Assert: Verify the price was updated
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.payPerViewPrice, newPrice);
        assertTrue(content.isActive);
    }

    /**
     * @dev Tests content deactivation
     * @notice This tests that creators can deactivate their content
     */
    function test_UpdateContent_Deactivation() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Verify content is initially active
        assertTrue(contentRegistry.getContent(contentId).isActive);

        // Act: Deactivate the content
        vm.startPrank(creator1);

        // Expect the ContentUpdated event
        vm.expectEmit(true, false, false, true);
        emit ContentUpdated(contentId, 0, false);

        contentRegistry.updateContent(contentId, 0, false);
        vm.stopPrank();

        // Assert: Verify the content was deactivated
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertFalse(content.isActive);

        // Verify active content count decreased
        (, uint256 activeContent,,) = contentRegistry.getPlatformStats();
        assertEq(activeContent, 0);
    }

    /**
     * @dev Tests that only the creator can update their content
     * @notice This tests our access control for content updates
     */
    function test_UpdateContent_OnlyCreator() public {
        // Arrange: Register content as creator1
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Act & Assert: Try to update as creator2 (should fail)
        vm.startPrank(creator2);
        vm.expectRevert(ContentRegistry.UnauthorizedCreator.selector);
        contentRegistry.updateContent(contentId, DEFAULT_CONTENT_PRICE * 2, true);
        vm.stopPrank();

        // Verify the content wasn't changed
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.payPerViewPrice, DEFAULT_CONTENT_PRICE);
    }

    /**
     * @dev Tests updating content with invalid price
     * @notice This tests price validation during updates
     */
    function test_UpdateContent_InvalidPrice() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");
        uint256 invalidPrice = MIN_CONTENT_PRICE - 1;

        // Act & Assert: Try to update with invalid price
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.InvalidPrice.selector);
        contentRegistry.updateContent(contentId, invalidPrice, true);
        vm.stopPrank();

        // Verify the price wasn't changed
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.payPerViewPrice, DEFAULT_CONTENT_PRICE);
    }

    // ============ PURCHASE RECORDING TESTS ============

    /**
     * @dev Tests recording a content purchase
     * @notice This tests the purchase tracking functionality
     */
    function test_RecordPurchase_Success() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Give the test contract the purchase recorder role
        vm.prank(admin);
        contentRegistry.grantPurchaseRecorderRole(address(this));

        // Act: Record a purchase
        vm.expectEmit(true, true, false, true);
        emit ContentRegistry.ContentPurchased(contentId, user1, DEFAULT_CONTENT_PRICE, block.timestamp);

        contentRegistry.recordPurchase(contentId, user1);

        // Assert: Verify the purchase was recorded
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.purchaseCount, 1);
    }

    /**
     * @dev Tests that only authorized contracts can record purchases
     * @notice This tests our access control for purchase recording
     */
    function test_RecordPurchase_OnlyAuthorized() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Act & Assert: Try to record purchase without authorization
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to missing PURCHASE_RECORDER_ROLE
        contentRegistry.recordPurchase(contentId, user1);
        vm.stopPrank();

        // Verify the purchase count didn't change
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.purchaseCount, 0);
    }

    /**
     * @dev Tests recording purchase for inactive content
     * @notice This tests that purchases can't be recorded for inactive content
     */
    function test_RecordPurchase_InactiveContent() public {
        // Arrange: Register content and deactivate it
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        vm.prank(creator1);
        contentRegistry.updateContent(contentId, 0, false);

        // Give the test contract the purchase recorder role
        vm.prank(admin);
        contentRegistry.grantPurchaseRecorderRole(address(this));

        // Act & Assert: Try to record purchase for inactive content
        vm.expectRevert(ContentRegistry.ContentNotActive.selector);
        contentRegistry.recordPurchase(contentId, user1);
    }

    // ============ CONTENT MODERATION TESTS ============

    /**
     * @dev Tests reporting content for moderation
     * @notice This tests our content moderation system
     */
    function test_ReportContent_Success() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");
        string memory reportReason = "Inappropriate content";

        // Act: Report the content
        vm.startPrank(user1);

        // Expect the ContentReported event
        vm.expectEmit(true, true, false, true);
        emit ContentReported(contentId, user1, reportReason, 1);

        contentRegistry.reportContent(contentId, reportReason);
        vm.stopPrank();

        // Assert: Verify the report was recorded
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertTrue(content.isReported);
        assertEq(content.reportCount, 1);

        // Verify the report details
        ContentRegistry.ContentReport[] memory reports = contentRegistry.getContentReports(contentId);
        assertEq(reports.length, 1);
        assertEq(reports[0].contentId, contentId);
        assertEq(reports[0].reporter, user1);
        assertTrue(stringEqual(reports[0].reason, reportReason));
        assertEq(reports[0].timestamp, block.timestamp);
        assertFalse(reports[0].resolved);
    }

    /**
     * @dev Tests that a user cannot report the same content twice
     * @notice This tests our duplicate report prevention
     */
    function test_ReportContent_AlreadyReported() public {
        // Arrange: Register content and report it once
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        vm.prank(user1);
        contentRegistry.reportContent(contentId, "First report");

        // Act & Assert: Try to report the same content again
        vm.startPrank(user1);
        vm.expectRevert(ContentRegistry.AlreadyReported.selector);
        contentRegistry.reportContent(contentId, "Second report");
        vm.stopPrank();

        // Verify the report count didn't increase
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertEq(content.reportCount, 1);
    }

    /**
     * @dev Tests auto-moderation when report threshold is reached
     * @notice This tests our automatic content moderation
     */
    function test_ReportContent_AutoModeration() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Create multiple user addresses for reporting
        address[] memory reporters = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            reporters[i] = address(uint160(0x4000 + i));
        }

        // Act: Report the content 5 times (threshold for auto-moderation)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(reporters[i]);
            contentRegistry.reportContent(contentId, "Report from user");
        }

        // Assert: Verify the content was auto-moderated (deactivated)
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertFalse(content.isActive);
        assertEq(content.reportCount, 5);
    }

    /**
     * @dev Tests resolving a content report
     * @notice This tests the moderation resolution process
     */
    function test_ResolveReport_Success() public {
        // Arrange: Register content and report it
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        vm.prank(user1);
        contentRegistry.reportContent(contentId, "Test report");

        // Act: Resolve the report as admin
        vm.startPrank(admin);

        // Expect the ReportResolved event
        vm.expectEmit(true, true, false, true);
        emit ReportResolved(0, contentId, "ignored", admin);

        contentRegistry.resolveReport(contentId, 0, "ignored");
        vm.stopPrank();

        // Assert: Verify the report was resolved
        ContentRegistry.ContentReport[] memory reports = contentRegistry.getContentReports(contentId);
        assertTrue(reports[0].resolved);
        assertTrue(stringEqual(reports[0].action, "ignored"));
    }

    /**
     * @dev Tests content removal through moderation
     * @notice This tests the content removal process
     */
    function test_ResolveReport_RemoveContent() public {
        // Arrange: Register content and report it
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        vm.prank(user1);
        contentRegistry.reportContent(contentId, "Harmful content");

        // Act: Resolve the report with removal
        vm.startPrank(admin);

        // Expect the ContentDeactivated event
        vm.expectEmit(true, false, false, true);
        emit ContentDeactivated(contentId, "Removed due to moderation", admin);

        contentRegistry.resolveReport(contentId, 0, "removed");
        vm.stopPrank();

        // Assert: Verify the content was deactivated
        ContentRegistry.Content memory content = contentRegistry.getContent(contentId);
        assertFalse(content.isActive);

        // Verify active content count decreased
        (, uint256 activeContent,,) = contentRegistry.getPlatformStats();
        assertEq(activeContent, 0);
    }

    // ============ CONTENT DISCOVERY TESTS ============

    /**
     * @dev Tests getting content by creator
     * @notice This tests content discovery by creator
     */
    function test_GetCreatorContent_Success() public {
        // Arrange: Register multiple content pieces for creator1
        uint256 contentId1 = registerContent(creator1, DEFAULT_CONTENT_PRICE, "First Content");
        uint256 contentId2 = registerContent(creator1, DEFAULT_CONTENT_PRICE * 2, "Second Content");

        // Register content for creator2 as well
        uint256 contentId3 = registerContent(creator2, DEFAULT_CONTENT_PRICE, "Third Content");

        // Act: Get content for creator1
        uint256[] memory creator1Content = contentRegistry.getCreatorContent(creator1);
        uint256[] memory creator2Content = contentRegistry.getCreatorContent(creator2);

        // Assert: Verify the correct content is returned
        assertEq(creator1Content.length, 2);
        assertEq(creator1Content[0], contentId1);
        assertEq(creator1Content[1], contentId2);

        assertEq(creator2Content.length, 1);
        assertEq(creator2Content[0], contentId3);
    }

    /**
     * @dev Tests getting active content by creator
     * @notice This tests filtering active content for a creator
     */
    function test_GetCreatorActiveContent_Success() public {
        // Arrange: Register content and deactivate one
        uint256 contentId1 = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Active Content");
        uint256 contentId2 = registerContent(creator1, DEFAULT_CONTENT_PRICE * 2, "Inactive Content");

        // Deactivate the second content
        vm.prank(creator1);
        contentRegistry.updateContent(contentId2, 0, false);

        // Act: Get active content for creator1
        uint256[] memory activeContent = contentRegistry.getCreatorActiveContent(creator1);

        // Assert: Verify only active content is returned
        assertEq(activeContent.length, 1);
        assertEq(activeContent[0], contentId1);
    }

    /**
     * @dev Tests getting content by category
     * @notice This tests content discovery by category
     */
    function test_GetContentByCategory_Success() public {
        // Arrange: Register content in different categories
        vm.startPrank(creator1);

        uint256 articleId = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            "Article Title",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );

        uint256 videoId = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH_2,
            "Video Title",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Video,
            DEFAULT_CONTENT_PRICE * 2,
            createSampleTags()
        );

        vm.stopPrank();

        // Act: Get content by category
        uint256[] memory articles = contentRegistry.getContentByCategory(ContentCategory.Article);
        uint256[] memory videos = contentRegistry.getContentByCategory(ContentCategory.Video);

        // Assert: Verify the correct content is returned
        assertEq(articles.length, 1);
        assertEq(articles[0], articleId);

        assertEq(videos.length, 1);
        assertEq(videos[0], videoId);
    }

    /**
     * @dev Tests getting content by tags
     * @notice This tests content discovery by tags
     */
    function test_GetContentByTag_Success() public {
        // Arrange: Register content with specific tags
        string[] memory tags1 = new string[](2);
        tags1[0] = "blockchain";
        tags1[1] = "tutorial";

        string[] memory tags2 = new string[](2);
        tags2[0] = "blockchain";
        tags2[1] = "advanced";

        vm.startPrank(creator1);

        uint256 contentId1 = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            "Blockchain Tutorial",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            tags1
        );

        uint256 contentId2 = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH_2,
            "Advanced Blockchain",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE * 2,
            tags2
        );

        vm.stopPrank();

        // Act: Get content by tag
        uint256[] memory blockchainContent = contentRegistry.getContentByTag("blockchain");
        uint256[] memory tutorialContent = contentRegistry.getContentByTag("tutorial");
        uint256[] memory advancedContent = contentRegistry.getContentByTag("advanced");

        // Assert: Verify the correct content is returned
        assertEq(blockchainContent.length, 2);
        assertEq(tutorialContent.length, 1);
        assertEq(tutorialContent[0], contentId1);
        assertEq(advancedContent.length, 1);
        assertEq(advancedContent[0], contentId2);
    }

    /**
     * @dev Tests paginated content listing
     * @notice This tests our pagination functionality for content discovery
     */
    function test_GetActiveContentPaginated_Success() public {
        // Arrange: Register multiple content pieces
        uint256[] memory contentIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            contentIds[i] = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Content");
        }

        // Act: Get paginated content
        (uint256[] memory firstPage, uint256 total) = contentRegistry.getActiveContentPaginated(0, 3);
        (uint256[] memory secondPage,) = contentRegistry.getActiveContentPaginated(3, 3);

        // Assert: Verify pagination works correctly
        assertEq(total, 5);
        assertEq(firstPage.length, 3);
        assertEq(secondPage.length, 2);

        // Verify content IDs are returned in order
        for (uint256 i = 0; i < 3; i++) {
            assertEq(firstPage[i], contentIds[i]);
        }
        for (uint256 i = 0; i < 2; i++) {
            assertEq(secondPage[i], contentIds[i + 3]);
        }
    }

    // ============ BANNED WORDS MODERATION TESTS ============

    /**
     * @dev Tests banning words for content moderation
     * @notice This tests our content moderation word filtering
     */
    function test_BanWord_Success() public {
        // Arrange: Set up a word to ban
        string memory bannedWord = "spam";

        // Act: Ban the word as admin
        vm.startPrank(admin);

        // Expect the WordBanned event
        vm.expectEmit(false, false, false, true);
        emit WordBanned(bannedWord, false);

        contentRegistry.banWord(bannedWord, false);
        vm.stopPrank();

        // Assert: Try to register content with banned word in title
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.BannedWordDetected.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            "This is spam content",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();
    }

    /**
     * @dev Tests banning phrases for content moderation
     * @notice This tests our phrase-based content filtering
     */
    function test_BanPhrase_Success() public {
        // Arrange: Set up a phrase to ban
        string memory bannedPhrase = "get rich quick";

        // Act: Ban the phrase as admin
        vm.startPrank(admin);

        // Expect the WordBanned event
        vm.expectEmit(false, false, false, true);
        emit WordBanned(bannedPhrase, true);

        contentRegistry.banPhrase(bannedPhrase);
        vm.stopPrank();

        // Assert: Try to register content with banned phrase in description
        vm.startPrank(creator1);
        vm.expectRevert(ContentRegistry.BannedWordDetected.selector);
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            SAMPLE_CONTENT_TITLE,
            "This will help you get rich quick with crypto",
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();
    }

    // ============ PLATFORM ANALYTICS TESTS ============

    /**
     * @dev Tests platform statistics
     * @notice This tests our analytics and metrics functionality
     */
    function test_GetPlatformStats_Success() public {
        // Arrange: Register content in different categories
        vm.startPrank(creator1);

        // Register content in different categories
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            "Article",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );

        uint256 videoId = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH_2,
            "Video",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Video,
            DEFAULT_CONTENT_PRICE * 2,
            createSampleTags()
        );

        // Deactivate the video
        contentRegistry.updateContent(videoId, 0, false);

        vm.stopPrank();

        // Act: Get platform statistics
        (
            uint256 totalContent,
            uint256 activeContent,
            uint256[] memory categoryCounts,
            uint256[] memory activeCategoryCounts
        ) = contentRegistry.getPlatformStats();

        // Assert: Verify statistics are correct
        assertEq(totalContent, 2);
        assertEq(activeContent, 1);
        assertEq(categoryCounts.length, 8); // All categories
        assertEq(activeCategoryCounts.length, 8);

        // Verify category counts
        assertEq(categoryCounts[0], 1); // Article category
        assertEq(categoryCounts[1], 1); // Video category
        assertEq(activeCategoryCounts[0], 1); // Active article
        assertEq(activeCategoryCounts[1], 0); // No active video
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @dev Tests contract pause and unpause functionality
     * @notice This tests our emergency pause system
     */
    function test_PauseUnpause_Success() public {
        // Arrange: Register content first
        uint256 contentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "Test Content");

        // Act: Pause the contract
        vm.prank(admin);
        contentRegistry.pause();

        // Assert: Content registration should fail when paused
        vm.startPrank(creator1);
        vm.expectRevert(); // Should revert due to whenNotPaused modifier
        contentRegistry.registerContent(
            SAMPLE_IPFS_HASH_2,
            "New Content",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            DEFAULT_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();

        // Act: Unpause the contract
        vm.prank(admin);
        contentRegistry.unpause();

        // Assert: Content registration should work again
        uint256 newContentId = registerContent(creator1, DEFAULT_CONTENT_PRICE, "New Content");
        assertTrue(newContentId > contentId);
    }

    /**
     * @dev Tests getting content with invalid ID
     * @notice This tests our error handling for invalid content IDs
     */
    function test_GetContent_InvalidId() public {
        // Act & Assert: Try to get content with invalid ID
        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        contentRegistry.getContent(999);

        // Try with ID 0
        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        contentRegistry.getContent(0);
    }

    /**
     * @dev Tests content registration with minimum and maximum valid values
     * @notice This tests our boundary conditions
     */
    function test_RegisterContent_BoundaryValues() public {
        // Test with minimum price
        vm.startPrank(creator1);
        uint256 contentId1 = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH,
            "Min Price Content",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            MIN_CONTENT_PRICE,
            createSampleTags()
        );

        // Test with maximum price
        uint256 contentId2 = contentRegistry.registerContent(
            SAMPLE_IPFS_HASH_2,
            "Max Price Content",
            SAMPLE_CONTENT_DESCRIPTION,
            ContentCategory.Article,
            MAX_CONTENT_PRICE,
            createSampleTags()
        );
        vm.stopPrank();

        // Verify both registrations succeeded
        assertEq(contentRegistry.getContent(contentId1).payPerViewPrice, MIN_CONTENT_PRICE);
        assertEq(contentRegistry.getContent(contentId2).payPerViewPrice, MAX_CONTENT_PRICE);
    }
}
