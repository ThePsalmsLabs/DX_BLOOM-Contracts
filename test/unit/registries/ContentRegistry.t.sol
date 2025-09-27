// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { ContentRegistry } from "../../../src/ContentRegistry.sol";
import { ContentRegistryTestHelper } from "../../helpers/ContentRegistryTestHelper.sol";
import { CreatorRegistry } from "../../../src/CreatorRegistry.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";
import { MockIPFSStorage } from "../../mocks/MockIPFSStorage.sol";

/**
 * @title ContentRegistryTest
 * @dev Unit tests for ContentRegistry contract - Core functionality tests
 * @notice Tests content management, moderation, search, and analytics features
 */
contract ContentRegistryTest is TestSetup {
    // Test contracts
    ContentRegistry public testContentRegistry;
    ContentRegistryTestHelper public testHelper;
    CreatorRegistry public testCreatorRegistry;
    MockIPFSStorage public testIPFSStorage;

    // Test data
    address testCreator = address(0x1234);
    address testModerator = address(0x5678);
    address testUser = address(0x9ABC);
    uint256 testContentId;

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testIPFSStorage = new MockIPFSStorage();
        testContentRegistry = new ContentRegistry(address(testIPFSStorage));
        testCreatorRegistry = creatorRegistry;

        // Create test helper
        testHelper = new ContentRegistryTestHelper(address(testContentRegistry));

        // Set up test creator
        vm.prank(testCreator);
        testCreatorRegistry.registerCreator(1e6, "QmTestCreatorHash");

        // Grant moderator role
        vm.prank(admin);
        testContentRegistry.grantRole(testContentRegistry.MODERATOR_ROLE(), testModerator);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(testContentRegistry.creatorRegistry()), address(testCreatorRegistry));
        assertEq(testContentRegistry.owner(), admin);

        // Test role setup
        assertTrue(testContentRegistry.hasRole(testContentRegistry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(testContentRegistry.hasRole(testContentRegistry.MODERATOR_ROLE(), testModerator));
        assertTrue(testContentRegistry.hasRole(testContentRegistry.MODERATOR_ROLE(), admin));
    }

    function test_Constructor_ZeroAddress() public {
        // Test constructor with zero address should revert
        vm.expectRevert("Invalid registry address");
        new ContentRegistry(address(0));
    }

    // ============ CONTENT REGISTRATION TESTS ============

    function test_RegisterContent_ValidData() public {
        string memory ipfsHash = "QmTestContentHash123456789";
        string memory title = "Test Content Title";
        string memory description = "This is a test content description for unit testing";
        ISharedTypes.ContentCategory category = ISharedTypes.ContentCategory.Article;
        uint256 price = 0.1e6; // $0.10
        string[] memory tags = new string[](2);
        tags[0] = "test";
        tags[1] = "article";

        // Register content
        vm.prank(testCreator);
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ContentRegistered(1, testCreator, ipfsHash, title, category, price, block.timestamp);
        uint256 contentId = testContentRegistry.registerContent(ipfsHash, title, description, category, price, tags);

        // Verify content was registered
        assertEq(contentId, 1);
        assertEq(testContentRegistry.nextContentId(), 2);

        // Verify content data
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertEq(content.creator, testCreator);
        assertEq(content.ipfsHash, ipfsHash);
        assertEq(content.title, title);
        assertEq(content.description, description);
        assertEq(uint256(content.category), uint256(category));
        assertEq(content.payPerViewPrice, price);
        assertTrue(content.isActive);
        assertEq(content.purchaseCount, 0);
        assertEq(content.tags.length, 2);
        assertEq(content.tags[0], "test");
        assertEq(content.tags[1], "article");
    }

    function test_RegisterContent_UnauthorizedCreator() public {
        // Non-registered creator should not be able to register content
        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.CreatorNotRegistered.selector);
        testContentRegistry.registerContent("QmTestHash", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));
    }

    function test_RegisterContent_InvalidData() public {
        // Test invalid IPFS hash (too short)
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidIPFSHash.selector);
        testContentRegistry.registerContent("short", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Test invalid price (too low)
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidPrice.selector);
        testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.005e6, new string[](0));

        // Test invalid price (too high)
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidPrice.selector);
        testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 100e6, new string[](0));

        // Test empty title
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidStringLength.selector);
        testContentRegistry.registerContent("QmTestHash123456789", "", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Test title too long
        string memory longTitle = "This is a very long title that exceeds the 100 character limit for content titles in the system";
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidStringLength.selector);
        testContentRegistry.registerContent("QmTestHash123456789", longTitle, "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Test too many tags
        string[] memory manyTags = new string[](15);
        for (uint256 i = 0; i < 15; i++) {
            manyTags[i] = "tag";
        }
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidStringLength.selector);
        testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, manyTags);
    }

    function test_RegisterContent_BannedWords() public {
        // Ban a word
        vm.prank(testModerator);
        testContentRegistry.banWord("inappropriate", false);

        // Try to register content with banned word in title
        vm.prank(testCreator);
        vm.expectRevert("BannedWordDetected");
        testContentRegistry.registerContent("QmTestHash123456789", "Inappropriate Title", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Try to register content with banned word in description
        vm.prank(testCreator);
        vm.expectRevert("BannedWordDetected");
        testContentRegistry.registerContent("QmTestHash123456789", "Valid Title", "This is inappropriate content", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Try to register content with banned word in tags
        string[] memory badTags = new string[](1);
        badTags[0] = "inappropriate";
        vm.prank(testCreator);
        vm.expectRevert("BannedWordDetected");
        testContentRegistry.registerContent("QmTestHash123456789", "Valid Title", "Valid Desc", ISharedTypes.ContentCategory.Article, 0.1e6, badTags);
    }

    // ============ CONTENT UPDATE TESTS ============

    function test_UpdateContent_ValidUpdate() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Update price and availability
        vm.prank(testCreator);
        vm.expectEmit(true, true, false, false);
        emit ContentRegistry.ContentUpdated(contentId, 0.2e6, true);
        testContentRegistry.updateContent(contentId, 0.2e6, true);

        // Verify update
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertEq(content.payPerViewPrice, 0.2e6);
        assertTrue(content.isActive);
    }

    function test_UpdateContent_UnauthorizedUser() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Non-creator should not be able to update
        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.UnauthorizedCreator.selector);
        testContentRegistry.updateContent(contentId, 0.2e6, true);
    }

    function test_UpdateContent_InvalidContentId() public {
        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        testContentRegistry.updateContent(999, 0.2e6, true);

        vm.prank(testCreator);
        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        testContentRegistry.updateContent(0, 0.2e6, true);
    }

    // ============ CONTENT PURCHASE TESTS ============

    function test_RecordPurchase_ValidPurchase() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Grant purchase recorder role to test contract
        vm.prank(admin);
        testContentRegistry.grantPurchaseRecorderRole(address(this));

        // Record purchase
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ContentPurchased(contentId, testUser, 0.1e6, block.timestamp);
        testContentRegistry.recordPurchase(contentId, testUser);

        // Verify purchase was recorded
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertEq(content.purchaseCount, 1);

        // Verify purchaser tracking using test helper
        address[] memory purchasers = testHelper.getContentPurchasersForTesting(contentId);
        assertEq(purchasers.length, 1);
        assertEq(purchasers[0], testUser);
    }

    function test_RecordPurchase_UnauthorizedRecorder() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Try to record purchase without role
        vm.expectRevert();
        testContentRegistry.recordPurchase(contentId, testUser);
    }

    function test_RecordPurchase_InactiveContent() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Deactivate content
        vm.prank(testCreator);
        testContentRegistry.updateContent(contentId, 0, false);

        // Grant role and try to record purchase
        vm.prank(admin);
        testContentRegistry.grantPurchaseRecorderRole(address(this));

        vm.expectRevert(ContentRegistry.ContentNotActive.selector);
        testContentRegistry.recordPurchase(contentId, testUser);
    }

    // ============ CONTENT REPORTING TESTS ============

    function test_ReportContent_ValidReport() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report content
        vm.prank(testUser);
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ContentReported(contentId, testUser, "Inappropriate content", 1);
        testContentRegistry.reportContent(contentId, "Inappropriate content");

        // Verify report was created
        ContentRegistry.ContentReport[] memory reports = testContentRegistry.getContentReports(contentId);
        assertEq(reports.length, 1);
        assertEq(reports[0].reporter, testUser);
        assertEq(reports[0].reason, "Inappropriate content");
        assertFalse(reports[0].resolved);

        // Verify content state
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertTrue(content.isReported);
        assertEq(content.reportCount, 1);
        assertTrue(testContentRegistry.hasReported(testUser, contentId));
    }

    function test_ReportContent_DuplicateReport() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report content twice by same user
        vm.prank(testUser);
        testContentRegistry.reportContent(contentId, "Inappropriate content");

        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.AlreadyReported.selector);
        testContentRegistry.reportContent(contentId, "Another reason");
    }

    function test_ReportContent_InvalidReason() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Empty reason
        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.InvalidReportReason.selector);
        testContentRegistry.reportContent(contentId, "");

        // Reason too long
        string memory longReason = "This is a very long reason that exceeds the 200 character limit for content reporting. This is a very long reason that exceeds the 200 character limit for content reporting. This is a very long reason that exceeds the 200 character limit for content reporting.";
        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.InvalidReportReason.selector);
        testContentRegistry.reportContent(contentId, longReason);
    }

    function test_ReportContent_DailyLimit() public {
        // Set low daily limit
        vm.prank(testModerator);
        testContentRegistry.updateModerationSettings(10, 3); // 3 reports per day

        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report 3 times (should work)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(testUser);
            testContentRegistry.reportContent(contentId, "Report reason");
        }

        // 4th report should fail
        vm.prank(testUser);
        vm.expectRevert(ContentRegistry.TooManyReports.selector);
        testContentRegistry.reportContent(contentId, "Another report");
    }

    // ============ REPORT RESOLUTION TESTS ============

    function test_ResolveReport_ValidResolution() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report content
        vm.prank(testUser);
        testContentRegistry.reportContent(contentId, "Inappropriate content");

        // Resolve report
        vm.prank(testModerator);
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ReportResolved(0, contentId, "ignored", testModerator);
        testContentRegistry.resolveReport(contentId, 0, "ignored");

        // Verify resolution
        ContentRegistry.ContentReport[] memory reports = testContentRegistry.getContentReports(contentId);
        assertTrue(reports[0].resolved);
        assertEq(reports[0].action, "ignored");
    }

    function test_ResolveReport_UnauthorizedResolver() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report content
        vm.prank(testUser);
        testContentRegistry.reportContent(contentId, "Inappropriate content");

        // Non-moderator should not be able to resolve
        vm.prank(testUser);
        vm.expectRevert();
        testContentRegistry.resolveReport(contentId, 0, "ignored");
    }

    function test_ResolveReport_RemoveAction() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Report content
        vm.prank(testUser);
        testContentRegistry.reportContent(contentId, "Inappropriate content");

        // Resolve with "removed" action
        vm.prank(testModerator);
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ContentDeactivated(contentId, "Removed due to moderation", testModerator);
        testContentRegistry.resolveReport(contentId, 0, "removed");

        // Verify content was deactivated
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertFalse(content.isActive);
    }

    // ============ CONTENT DEACTIVATION TESTS ============

    function test_DeactivateContent_AdminFunction() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Deactivate content
        vm.prank(testModerator);
        vm.expectEmit(true, true, true, true);
        emit ContentRegistry.ContentDeactivated(contentId, "Administrative removal", testModerator);
        testContentRegistry.deactivateContent(contentId, "Administrative removal");

        // Verify deactivation
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertFalse(content.isActive);
    }

    function test_DeactivateContent_UnauthorizedUser() public {
        // First register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Non-moderator should not be able to deactivate
        vm.prank(testUser);
        vm.expectRevert();
        testContentRegistry.deactivateContent(contentId, "Unauthorized removal");
    }

    // ============ CONTENT MODERATION TESTS ============

    function test_BanWord_AdminFunction() public {
        // Ban a word
        vm.prank(testModerator);
        vm.expectEmit(true, true, false, false);
        emit ContentRegistry.WordBanned("testword", false);
        testContentRegistry.banWord("testword", false);

        // Verify word is banned
        assertTrue(testContentRegistry.bannedWords("testword"));

        // Check banned words list
        string[] memory bannedWords = new string[](1);
        // Note: We can't easily test the bannedWordsList due to internal implementation
    }

    function test_BanWord_UnauthorizedUser() public {
        // Non-moderator should not be able to ban words
        vm.prank(testUser);
        vm.expectRevert();
        testContentRegistry.banWord("testword", false);
    }

    function test_UnbanWord_AdminFunction() public {
        // First ban a word
        vm.prank(testModerator);
        testContentRegistry.banWord("testword", false);

        // Unban the word
        vm.prank(testModerator);
        vm.expectEmit(true, true, false, false);
        emit ContentRegistry.WordUnbanned("testword", false);
        testContentRegistry.unbanWord("testword", false);

        // Verify word is unbanned
        assertFalse(testContentRegistry.bannedWords("testword"));
    }

    // ============ SEARCH AND DISCOVERY TESTS ============

    function test_GetContent_ValidId() public {
        // Register content
        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmTestHash123456789", "Test Title", "Test Description", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Get content
        ContentRegistry.Content memory content = testContentRegistry.getContent(contentId);
        assertEq(content.creator, testCreator);
        assertEq(content.title, "Test Title");
        assertEq(content.description, "Test Description");
        assertEq(uint256(content.category), uint256(ISharedTypes.ContentCategory.Article));
    }

    function test_GetContent_InvalidId() public {
        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        testContentRegistry.getContent(999);

        vm.expectRevert(ContentRegistry.InvalidContentId.selector);
        testContentRegistry.getContent(0);
    }

    function test_GetCreatorContent() public {
        // Register multiple content items
        vm.prank(testCreator);
        uint256 contentId1 = testContentRegistry.registerContent("QmHash1", "Title1", "Desc1", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        vm.prank(testCreator);
        uint256 contentId2 = testContentRegistry.registerContent("QmHash2", "Title2", "Desc2", ISharedTypes.ContentCategory.Video, 0.2e6, new string[](0));

        // Get creator content
        uint256[] memory creatorContent = testContentRegistry.getCreatorContent(testCreator);
        assertEq(creatorContent.length, 2);
        assertEq(creatorContent[0], contentId1);
        assertEq(creatorContent[1], contentId2);
    }

    function test_GetCreatorActiveContent() public {
        // Register multiple content items
        vm.prank(testCreator);
        uint256 contentId1 = testContentRegistry.registerContent("QmHash1", "Title1", "Desc1", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        vm.prank(testCreator);
        uint256 contentId2 = testContentRegistry.registerContent("QmHash2", "Title2", "Desc2", ISharedTypes.ContentCategory.Video, 0.2e6, new string[](0));

        // Deactivate one
        vm.prank(testCreator);
        testContentRegistry.updateContent(contentId2, 0, false);

        // Get active creator content
        uint256[] memory activeContent = testContentRegistry.getCreatorActiveContent(testCreator);
        assertEq(activeContent.length, 1);
        assertEq(activeContent[0], contentId1);
    }

    function test_GetContentByCategory() public {
        // Register content in different categories
        vm.prank(testCreator);
        uint256 contentId1 = testContentRegistry.registerContent("QmHash1", "Article", "Desc1", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        vm.prank(testCreator);
        uint256 contentId2 = testContentRegistry.registerContent("QmHash2", "Video", "Desc2", ISharedTypes.ContentCategory.Video, 0.2e6, new string[](0));

        // Get content by category
        uint256[] memory articles = testContentRegistry.getContentByCategory(ISharedTypes.ContentCategory.Article);
        uint256[] memory videos = testContentRegistry.getContentByCategory(ISharedTypes.ContentCategory.Video);

        assertEq(articles.length, 1);
        assertEq(videos.length, 1);
        assertEq(articles[0], contentId1);
        assertEq(videos[0], contentId2);
    }

    function test_GetContentByTag() public {
        string[] memory tags = new string[](1);
        tags[0] = "blockchain";

        vm.prank(testCreator);
        uint256 contentId = testContentRegistry.registerContent("QmHash1", "Blockchain Article", "Desc1", ISharedTypes.ContentCategory.Article, 0.1e6, tags);

        // Get content by tag
        uint256[] memory taggedContent = testContentRegistry.getContentByTag("blockchain");
        assertEq(taggedContent.length, 1);
        assertEq(taggedContent[0], contentId);
    }

    // ============ PLATFORM ANALYTICS TESTS ============

    function test_GetPlatformStats() public {
        // Register content in different categories
        vm.prank(testCreator);
        testContentRegistry.registerContent("QmHash1", "Article", "Desc1", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        vm.prank(testCreator);
        testContentRegistry.registerContent("QmHash2", "Video", "Desc2", ISharedTypes.ContentCategory.Video, 0.2e6, new string[](0));

        // Deactivate one
        vm.prank(testCreator);
        testContentRegistry.updateContent(2, 0, false);

        // Get platform stats
        (uint256 totalContent, uint256 activeContent, uint256[] memory categoryCounts, uint256[] memory activeCategoryCounts) = testContentRegistry.getPlatformStats();

        assertEq(totalContent, 2);
        assertEq(activeContent, 1);
        assertEq(categoryCounts.length, 8); // Supports up to Podcast category
        assertEq(activeCategoryCounts.length, 8);
        assertEq(categoryCounts[uint256(ISharedTypes.ContentCategory.Article)], 1);
        assertEq(categoryCounts[uint256(ISharedTypes.ContentCategory.Video)], 1);
        assertEq(activeCategoryCounts[uint256(ISharedTypes.ContentCategory.Article)], 1);
        assertEq(activeCategoryCounts[uint256(ISharedTypes.ContentCategory.Video)], 0);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_GrantPurchaseRecorderRole() public {
        // Grant role
        vm.prank(admin);
        testContentRegistry.grantPurchaseRecorderRole(testUser);

        // Verify role was granted
        assertTrue(testContentRegistry.hasRole(testContentRegistry.PURCHASE_RECORDER_ROLE(), testUser));
    }

    function test_GrantPurchaseRecorderRole_UnauthorizedUser() public {
        // Non-owner should not be able to grant roles
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testContentRegistry.grantPurchaseRecorderRole(testUser);
    }

    // ============ PAUSE/UNPAUSE TESTS ============

    function test_Pause_Unpause() public {
        // Pause
        vm.prank(admin);
        testContentRegistry.pause();
        assertTrue(testContentRegistry.paused());

        // Try to register content while paused
        vm.prank(testCreator);
        vm.expectRevert("Pausable: paused");
        testContentRegistry.registerContent("QmHash", "Title", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));

        // Unpause
        vm.prank(admin);
        testContentRegistry.unpause();
        assertFalse(testContentRegistry.paused());

        // Should work after unpause
        vm.prank(testCreator);
        testContentRegistry.registerContent("QmHash", "Title", "Desc", ISharedTypes.ContentCategory.Article, 0.1e6, new string[](0));
    }

    function test_Pause_UnauthorizedUser() public {
        // Non-owner should not be able to pause
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testContentRegistry.pause();
    }
}
