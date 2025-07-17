// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";
import {PayPerView} from "../../src/PayPerView.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {CommerceProtocolIntegration} from "../../src/CommerceProtocolIntegration.sol";
import {PriceOracle} from "../../src/PriceOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockCommerceProtocol} from "../mocks/MockCommerceProtocol.sol";
import {MockQuoterV2} from "../mocks/MockQuoterV2.sol";
import {TestConstants} from "./TestConstants.sol";

/**
 * @title TestSetup
 * @dev Base contract for all tests - provides common setup and utilities
 * @notice This contract serves as the foundation for all test contracts, ensuring
 *         consistent setup and providing shared utilities across the test suite
 */
abstract contract TestSetup is Test, TestConstants {
    // Core contract instances - these will be deployed in each test
    CreatorRegistry public creatorRegistry;
    ContentRegistry public contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    CommerceProtocolIntegration public commerceIntegration;
    PriceOracle public priceOracle;

    // Mock contracts for external dependencies
    MockERC20 public mockUSDC;
    MockCommerceProtocol public mockCommerceProtocol;
    MockQuoterV2 public mockQuoter;

    // Test user addresses - using consistent addresses across all tests
    address public creator1 = address(0x1001);
    address public creator2 = address(0x1002);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    address public admin = address(0x3001);
    address public feeRecipient = address(0x3002);
    address public operatorSigner = address(0x3003);

    // Test constants for pricing and configuration

    // Events for testing - we'll check these are emitted correctly
    event CreatorRegistered(address indexed creator, uint256 subscriptionPrice, uint256 timestamp, string profileData);
    event ContentRegistered(
        uint256 indexed contentId,
        address indexed creator,
        string ipfsHash,
        string title,
        ContentRegistry.ContentCategory category,
        uint256 payPerViewPrice,
        uint256 timestamp
    );
    event ContentPurchased(uint256 indexed contentId, address indexed buyer, uint256 price, uint256 timestamp);
    event Subscribed(
        address indexed user,
        address indexed creator,
        uint256 price,
        uint256 platformFee,
        uint256 creatorEarning,
        uint256 startTime,
        uint256 endTime
    );

    /**
     * @dev Sets up the complete test environment
     * @notice This function is called before each test to ensure a clean state
     * It deploys all contracts and sets up the necessary permissions and configurations
     */
    function setUp() public virtual {
        // Set up the test environment with proper admin permissions
        vm.startPrank(admin);

        // Deploy mock external dependencies first
        _deployMockDependencies();

        // Deploy our core contracts with proper constructor parameters
        _deployCoreContracts();

        // Configure contracts with proper roles and permissions
        _configureContracts();

        // Set up test users with initial balances and permissions
        _setupTestUsers();

        vm.stopPrank();
    }

    /**
     * @dev Deploys mock contracts for external dependencies
     * @notice We use mocks to isolate our contract logic from external systems
     */
    function _deployMockDependencies() internal {
        // Deploy mock USDC with proper decimals and initial supply
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        mockUSDC.mint(admin, 1000000e6); // 1M USDC for testing

        // Deploy mock Commerce Protocol for payment testing
        mockCommerceProtocol = new MockCommerceProtocol();

        // Deploy mock Uniswap Quoter for price oracle testing
        mockQuoter = new MockQuoterV2();

        console.log("Mock dependencies deployed:");
        console.log("- Mock USDC:", address(mockUSDC));
        console.log("- Mock Commerce Protocol:", address(mockCommerceProtocol));
        console.log("- Mock Quoter:", address(mockQuoter));
    }

    /**
     * @dev Deploys all core platform contracts
     * @notice Order matters here due to constructor dependencies
     */
    function _deployCoreContracts() internal {
        // Deploy PriceOracle first (no dependencies)
        priceOracle = new PriceOracle();

        // Deploy CreatorRegistry (depends on USDC)
        creatorRegistry = new CreatorRegistry(feeRecipient, address(mockUSDC));

        // Deploy ContentRegistry (depends on CreatorRegistry)
        contentRegistry = new ContentRegistry(address(creatorRegistry));

        // Deploy PayPerView (depends on multiple contracts)
        payPerView =
            new PayPerView(address(creatorRegistry), address(contentRegistry), address(priceOracle), address(mockUSDC));

        // Deploy SubscriptionManager (depends on multiple contracts)
        subscriptionManager =
            new SubscriptionManager(address(creatorRegistry), address(contentRegistry), address(mockUSDC));

        // Deploy CommerceProtocolIntegration (depends on all contracts)
        commerceIntegration = new CommerceProtocolIntegration(
            address(mockCommerceProtocol),
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            feeRecipient,
            operatorSigner
        );

        console.log("Core contracts deployed:");
        console.log("- CreatorRegistry:", address(creatorRegistry));
        console.log("- ContentRegistry:", address(contentRegistry));
        console.log("- PayPerView:", address(payPerView));
        console.log("- SubscriptionManager:", address(subscriptionManager));
        console.log("- CommerceIntegration:", address(commerceIntegration));
    }

    /**
     * @dev Configures contracts with proper roles and integrations
     * @notice This sets up the permission structure that allows contracts to interact
     */
    function _configureContracts() internal {
        // Grant platform roles to core contracts in CreatorRegistry
        creatorRegistry.grantPlatformRole(address(payPerView));
        creatorRegistry.grantPlatformRole(address(subscriptionManager));
        creatorRegistry.grantPlatformRole(address(commerceIntegration));

        // Grant purchase recorder role to PayPerView in ContentRegistry
        contentRegistry.grantPurchaseRecorderRole(address(payPerView));

        // Grant payment processor role to CommerceIntegration in PayPerView
        payPerView.grantPaymentProcessorRole(address(commerceIntegration));

        // Grant subscription processor role to CommerceIntegration in SubscriptionManager
        subscriptionManager.grantSubscriptionProcessorRole(address(commerceIntegration));

        // Set up CommerceIntegration with other contract addresses
        commerceIntegration.setPayPerView(address(payPerView));
        commerceIntegration.setSubscriptionManager(address(subscriptionManager));

        console.log("Contract permissions configured");
    }

    /**
     * @dev Sets up test users with initial USDC balances
     * @notice This ensures all test users have sufficient funds for testing
     */
    function _setupTestUsers() internal {
        address[] memory users = new address[](4);
        users[0] = creator1;
        users[1] = creator2;
        users[2] = user1;
        users[3] = user2;

        // Give each user 1000 USDC for testing
        for (uint256 i = 0; i < users.length; i++) {
            mockUSDC.mint(users[i], 1000e6);
            vm.deal(users[i], 10 ether); // Also give them ETH for gas
        }

        console.log("Test users set up with initial balances");
    }

    /**
     * @dev Helper function to register a creator with default settings
     * @param creator The address to register as creator
     * @return success Whether the registration was successful
     */
    function registerCreator(address creator) internal returns (bool success) {
        return registerCreator(creator, DEFAULT_SUBSCRIPTION_PRICE, "Default profile");
    }

    /**
     * @dev Helper function to register a creator with custom settings
     * @param creator The address to register as creator
     * @param subscriptionPrice The monthly subscription price
     * @param profileData IPFS hash for profile data
     * @return success Whether the registration was successful
     */
    function registerCreator(address creator, uint256 subscriptionPrice, string memory profileData)
        internal
        returns (bool success)
    {
        vm.startPrank(creator);
        try creatorRegistry.registerCreator(subscriptionPrice, profileData) {
            success = true;
        } catch {
            success = false;
        }
        vm.stopPrank();
        return success;
    }

    /**
     * @dev Helper function to register content with default settings
     * @param creator The creator address
     * @return contentId The ID of the registered content
     */
    function registerContent(address creator) internal returns (uint256 contentId) {
        return registerContent(creator, DEFAULT_CONTENT_PRICE, "Sample content");
    }

    /**
     * @dev Helper function to register content with custom settings
     * @param creator The creator address
     * @param price The pay-per-view price
     * @param title The content title
     * @return contentId The ID of the registered content
     */
    function registerContent(address creator, uint256 price, string memory title)
        internal
        returns (uint256 contentId)
    {
        vm.startPrank(creator);

        string[] memory tags = new string[](2);
        tags[0] = "test";
        tags[1] = "content";

        contentId = contentRegistry.registerContent(
            "QmTestHash123456789", title, "Test description", ContentRegistry.ContentCategory.Article, price, tags
        );

        vm.stopPrank();
        return contentId;
    }

    /**
     * @dev Helper function to approve USDC spending
     * @param user The user address
     * @param spender The spender address
     * @param amount The amount to approve
     */
    function approveUSDC(address user, address spender, uint256 amount) internal {
        vm.prank(user);
        mockUSDC.approve(spender, amount);
    }

    /**
     * @dev Helper function to check if two strings are equal
     * @param a First string
     * @param b Second string
     * @return equal Whether the strings are equal
     */
    function stringEqual(string memory a, string memory b) internal pure returns (bool equal) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Helper function to advance time in tests
     * @param timeToAdvance The time to advance in seconds
     */
    function advanceTime(uint256 timeToAdvance) internal {
        vm.warp(block.timestamp + timeToAdvance);
    }

    /**
     * @dev Helper function to expect a specific revert message
     * @param expectedRevert The expected revert message
     */
    function expectRevert(string memory expectedRevert) internal {
        vm.expectRevert(bytes(expectedRevert));
    }
}
