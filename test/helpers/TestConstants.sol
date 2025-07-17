// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title TestConstants
 * @dev Contains all constants used across the test suite
 * @notice This contract centralizes all testing constants to ensure consistency
 *         and make it easy to update values across the entire test suite
 */
contract TestConstants {
    // ============ PRICING CONSTANTS ============

    // Subscription pricing boundaries (in USDC with 6 decimals)
    uint256 public constant MIN_SUBSCRIPTION_PRICE = 0.01e6; // $0.01 minimum
    uint256 public constant MAX_SUBSCRIPTION_PRICE = 100e6; // $100 maximum
    uint256 public constant DEFAULT_SUBSCRIPTION_PRICE = 1e6; // $1 default

    // Content pricing boundaries (in USDC with 6 decimals)
    uint256 public constant MIN_CONTENT_PRICE = 0.01e6; // $0.01 minimum
    uint256 public constant MAX_CONTENT_PRICE = 50e6; // $50 maximum
    uint256 public constant DEFAULT_CONTENT_PRICE = 0.1e6; // $0.10 default

    // Fee structure (in basis points - 1 basis point = 0.01%)
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5% platform fee
    uint256 public constant OPERATOR_FEE_BPS = 50; // 0.5% operator fee
    uint256 public constant MAX_FEE_BPS = 1000; // 10% maximum fee

    // ============ TIME CONSTANTS ============

    // Subscription duration and timing
    uint256 public constant SUBSCRIPTION_DURATION = 30 days; // Fixed 30-day subscriptions
    uint256 public constant GRACE_PERIOD = 3 days; // Grace period for expired subscriptions
    uint256 public constant RENEWAL_WINDOW = 1 days; // Window before expiry for renewal

    // Payment timeouts and windows
    uint256 public constant PAYMENT_TIMEOUT = 1 hours; // Payment intent expiry
    uint256 public constant REFUND_WINDOW = 24 hours; // Refund eligibility window

    // Auto-renewal settings
    uint256 public constant RENEWAL_COOLDOWN = 4 hours; // Cooldown between renewal attempts
    uint256 public constant MAX_RENEWAL_ATTEMPTS = 3; // Max renewal attempts per day

    // ============ SAMPLE DATA CONSTANTS ============

    // Sample IPFS hashes for testing
    string public constant SAMPLE_IPFS_HASH = "QmTestHash123456789012345678901234567890123456789";
    string public constant SAMPLE_IPFS_HASH_2 = "QmTestHash987654321098765432109876543210987654321";

    // Sample profile data
    string public constant SAMPLE_PROFILE_DATA = "QmProfileHash123456789012345678901234567890123456789";
    string public constant SAMPLE_PROFILE_DATA_2 = "QmProfileHash987654321098765432109876543210987654321";

    // Sample content metadata
    string public constant SAMPLE_CONTENT_TITLE = "Sample Article Title";
    string public constant SAMPLE_CONTENT_DESCRIPTION = "This is a sample article description for testing purposes.";
    string public constant SAMPLE_CONTENT_TITLE_2 = "Another Sample Article";
    string public constant SAMPLE_CONTENT_DESCRIPTION_2 = "This is another sample article description.";

    // ============ MODERATION CONSTANTS ============

    // Moderation thresholds
    uint256 public constant AUTO_MODERATE_THRESHOLD = 5; // Auto-deactivate after 5 reports
    uint256 public constant MAX_REPORTS_PER_USER = 10; // Max reports per user per day
    uint256 public constant CLEANUP_INTERVAL = 7 days; // Cleanup interval for expired content

    // Sample banned words for testing moderation
    string public constant BANNED_WORD_1 = "spam";
    string public constant BANNED_WORD_2 = "scam";
    string public constant BANNED_PHRASE_1 = "get rich quick";

    // ============ BALANCE CONSTANTS ============

    // Initial balances for test users (in USDC with 6 decimals)
    uint256 public constant INITIAL_USER_BALANCE = 1000e6; // $1000 per user
    uint256 public constant INITIAL_CREATOR_BALANCE = 1000e6; // $1000 per creator
    uint256 public constant INITIAL_ADMIN_BALANCE = 1000000e6; // $1M for admin

    // ETH balances for gas (in wei)
    uint256 public constant INITIAL_ETH_BALANCE = 10 ether;

    // ============ SLIPPAGE AND PRICE CONSTANTS ============

    // Slippage settings (in basis points)
    uint256 public constant DEFAULT_SLIPPAGE = 100; // 1% default slippage
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% maximum slippage
    uint256 public constant MIN_SLIPPAGE = 10; // 0.1% minimum slippage

    // Mock price ratios for testing (these represent token prices)
    uint256 public constant MOCK_ETH_USDC_RATIO = 2000; // 1 ETH = 2000 USDC
    uint256 public constant MOCK_WETH_USDC_RATIO = 2000; // 1 WETH = 2000 USDC

    // ============ COMMERCE PROTOCOL CONSTANTS ============

    // Pool fee tiers for Uniswap (in basis points)
    uint24 public constant POOL_FEE_LOW = 500; // 0.05% for stablecoin pairs
    uint24 public constant POOL_FEE_MEDIUM = 3000; // 0.3% for most pairs
    uint24 public constant POOL_FEE_HIGH = 10000; // 1% for exotic pairs

    // Intent and signature constants
    uint256 public constant INTENT_DEADLINE_BUFFER = 1 hours; // Buffer for intent deadlines

    // ============ CONTENT CATEGORY CONSTANTS ============

    // We'll use these to test different content categories
    uint8 public constant ARTICLE_CATEGORY = 0;
    uint8 public constant VIDEO_CATEGORY = 1;
    uint8 public constant AUDIO_CATEGORY = 2;
    uint8 public constant IMAGE_CATEGORY = 3;
    uint8 public constant DOCUMENT_CATEGORY = 4;
    uint8 public constant COURSE_CATEGORY = 5;
    uint8 public constant OTHER_CATEGORY = 6;

    // ============ ERROR MESSAGE CONSTANTS ============

    // Common error messages we'll test for
    string public constant ERROR_CREATOR_NOT_REGISTERED = "CreatorNotRegistered()";
    string public constant ERROR_INVALID_PRICE = "InvalidPrice()";
    string public constant ERROR_INVALID_IPFS_HASH = "InvalidIPFSHash()";
    string public constant ERROR_ALREADY_SUBSCRIBED = "AlreadySubscribed()";
    string public constant ERROR_CONTENT_NOT_ACTIVE = "ContentNotActive()";
    string public constant ERROR_INSUFFICIENT_BALANCE = "InsufficientBalance()";
    string public constant ERROR_UNAUTHORIZED_ACCESS = "UnauthorizedAccess()";
    string public constant ERROR_SUBSCRIPTION_EXPIRED = "SubscriptionAlreadyExpired()";

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Calculates the expected platform fee for a given amount
     * @param amount The amount to calculate fee for
     * @return fee The platform fee amount
     */
    function calculatePlatformFee(uint256 amount) public pure returns (uint256 fee) {
        return (amount * PLATFORM_FEE_BPS) / 10000;
    }

    /**
     * @dev Calculates the expected operator fee for a given amount
     * @param amount The amount to calculate fee for
     * @return fee The operator fee amount
     */
    function calculateOperatorFee(uint256 amount) public pure returns (uint256 fee) {
        return (amount * OPERATOR_FEE_BPS) / 10000;
    }

    /**
     * @dev Calculates the creator's net earnings after platform fees
     * @param amount The gross amount before fees
     * @return netEarnings The creator's net earnings
     */
    function calculateCreatorEarnings(uint256 amount) public pure returns (uint256 netEarnings) {
        uint256 platformFee = calculatePlatformFee(amount);
        return amount - platformFee;
    }

    /**
     * @dev Calculates the total fees (platform + operator) for a given amount
     * @param amount The amount to calculate fees for
     * @return totalFees The combined platform and operator fees
     */
    function calculateTotalFees(uint256 amount) public pure returns (uint256 totalFees) {
        return calculatePlatformFee(amount) + calculateOperatorFee(amount);
    }

    /**
     * @dev Creates a sample tags array for testing content registration
     * @return tags Array of sample tags
     */
    function createSampleTags() public pure returns (string[] memory tags) {
        tags = new string[](3);
        tags[0] = "blockchain";
        tags[1] = "tutorial";
        tags[2] = "beginner";
        return tags;
    }

    /**
     * @dev Creates a sample tags array with banned words for testing moderation
     * @return tags Array of tags containing banned words
     */
    function createBannedTags() public pure returns (string[] memory tags) {
        tags = new string[](2);
        tags[0] = BANNED_WORD_1;
        tags[1] = "legitimate";
        return tags;
    }
}
