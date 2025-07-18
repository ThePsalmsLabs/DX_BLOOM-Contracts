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
 * @title TestSetup - FIXED VERSION
 * @dev Base contract for all tests - provides common setup and utilities with proper mock injection
 * @notice CRITICAL IMPROVEMENT: This version properly configures all contracts to use mock dependencies
 *         instead of hardcoded mainnet addresses. This is a fundamental principle of isolated unit testing.
 */
abstract contract TestSetup is Test, TestConstants {
    // ============ CORE CONTRACT INSTANCES ============
    
    CreatorRegistry public creatorRegistry;
    ContentRegistry public contentRegistry;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    CommerceProtocolIntegration public commerceIntegration;
    PriceOracle public priceOracle;

    // ============ MOCK DEPENDENCIES ============
    
    MockERC20 public mockUSDC;
    MockCommerceProtocol public mockCommerceProtocol;
    MockQuoterV2 public mockQuoter;

    // ============ TEST USER ADDRESSES ============
    
    address public creator1 = address(0x1001);
    address public creator2 = address(0x1002);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);
    address public admin = address(0x3001);
    address public feeRecipient = address(0x3002);
    address public operatorSigner = address(0x3003);

    // ============ EVENTS FOR TESTING ============
    
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
     * @dev Sets up the complete test environment with proper dependency injection
     * @notice TEACHING MOMENT: This function demonstrates the correct way to set up isolated
     *         unit tests for smart contracts. Each step is carefully ordered to ensure
     *         proper dependency resolution and mock injection.
     */
    function setUp() public virtual {
        // Always start with admin privileges for setup
        vm.startPrank(admin);

        // Step 1: Deploy external mock dependencies first
        // PRINCIPLE: Always deploy dependencies before dependents
        _deployMockDependencies();

        // Step 2: Deploy core contracts with mock dependencies injected
        // CRITICAL: Pass mock addresses to constructors instead of using hardcoded mainnet addresses
        _deployCoreContracts();

        // Step 3: Configure contract permissions and relationships
        // PRINCIPLE: Set up all access controls after deployment but before testing
        _configureContracts();

        // Step 4: Set up test users with realistic balances
        // BEST PRACTICE: Mirror production-like conditions in tests
        _setupTestUsers();

        vm.stopPrank();
    }

    /**
     * @dev Deploys all mock external dependencies
     * @notice EDUCATIONAL: Mock contracts allow us to test our logic in isolation.
     *         Each mock simulates the behavior of external systems like Uniswap, USDC, etc.
     */
    function _deployMockDependencies() internal {
        console.log("Deploying mock dependencies...");
        
        // Deploy mock USDC with proper ERC20 configuration
        // DETAIL: 6 decimals matches real USDC, 1M supply for extensive testing
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        mockUSDC.mint(admin, 1000000e6); // 1M USDC for testing

        // Deploy mock Commerce Protocol for payment flow testing
        // PURPOSE: Simulates Coinbase Commerce without external dependencies
        mockCommerceProtocol = new MockCommerceProtocol();

        // Deploy mock Uniswap Quoter with realistic price data
        // CRITICAL: This replaces the hardcoded mainnet quoter address
        mockQuoter = new MockQuoterV2();

        console.log("Mock dependencies deployed:");
        console.log("- Mock USDC:", address(mockUSDC));
        console.log("- Mock Commerce Protocol:", address(mockCommerceProtocol));
        console.log("- Mock Quoter:", address(mockQuoter));
    }

    /**
     * @dev Deploys all core platform contracts with proper dependency injection
     * @notice CRITICAL LEARNING: The order of deployment matters due to constructor dependencies.
     *         Notice how we pass mock addresses to constructors instead of relying on hardcoded constants.
     */
    function _deployCoreContracts() internal {
        console.log("Deploying core contracts...");

        // Step 1: Deploy PriceOracle with injected mock quoter
        // FIX: Pass mockQuoter address to constructor instead of using hardcoded constant
        priceOracle = new PriceOracle(address(mockQuoter));
        console.log("- PriceOracle deployed at:", address(priceOracle));

        // Step 2: Deploy CreatorRegistry (no external dependencies)
        creatorRegistry = new CreatorRegistry(feeRecipient, address(mockUSDC));
        console.log("- CreatorRegistry deployed at:", address(creatorRegistry));

        // Step 3: Deploy ContentRegistry (depends on CreatorRegistry)
        contentRegistry = new ContentRegistry(address(creatorRegistry));
        console.log("- ContentRegistry deployed at:", address(contentRegistry));

        // Step 4: Deploy PayPerView (depends on multiple contracts)
        // PRINCIPLE: Always inject dependencies rather than having contracts find them
        payPerView = new PayPerView(
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle), // Now uses our configurable oracle
            address(mockUSDC)
        );
        console.log("- PayPerView deployed at:", address(payPerView));

        // Step 5: Deploy SubscriptionManager
        subscriptionManager = new SubscriptionManager(
            address(creatorRegistry),
            address(contentRegistry),
            address(mockUSDC)
        );
        console.log("- SubscriptionManager deployed at:", address(subscriptionManager));

        // Step 6: Deploy CommerceProtocolIntegration (most complex dependencies)
        commerceIntegration = new CommerceProtocolIntegration(
            address(mockCommerceProtocol), // Use mock instead of mainnet
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            address(mockUSDC),
            operatorSigner
        );
        console.log("- CommerceIntegration deployed at:", address(commerceIntegration));

        console.log("Core contracts deployed successfully");
    }

    /**
     * @dev Configures all contract permissions and cross-contract relationships
     * @notice TEACHING: This step is crucial for proper access control in complex DeFi systems.
     *         Each contract needs specific permissions to interact with others.
     */
    function _configureContracts() internal {
        console.log("Configuring contract permissions...");

        // Configure CreatorRegistry permissions
        // PRINCIPLE: Grant minimum necessary permissions for each operation
        creatorRegistry.grantRole(creatorRegistry.CONTENT_MANAGER_ROLE(), address(contentRegistry));
        creatorRegistry.grantRole(creatorRegistry.PAYMENT_PROCESSOR_ROLE(), address(payPerView));
        creatorRegistry.grantRole(creatorRegistry.PAYMENT_PROCESSOR_ROLE(), address(subscriptionManager));
        creatorRegistry.grantRole(creatorRegistry.PAYMENT_PROCESSOR_ROLE(), address(commerceIntegration));

        // Configure ContentRegistry permissions
        contentRegistry.grantRole(contentRegistry.PURCHASE_MANAGER_ROLE(), address(payPerView));
        contentRegistry.grantRole(contentRegistry.PURCHASE_MANAGER_ROLE(), address(commerceIntegration));

        // Configure PayPerView contract addresses
        // IMPORTANT: This allows PayPerView to communicate with other platform contracts
        payPerView.setCommerceIntegration(address(commerceIntegration));

        // Configure CommerceProtocolIntegration with all necessary contract addresses
        // ARCHITECTURAL NOTE: This creates the complete dependency graph
        commerceIntegration.setPayPerView(address(payPerView));
        commerceIntegration.setSubscriptionManager(address(subscriptionManager));

        // Grant necessary roles to CommerceProtocolIntegration
        commerceIntegration.grantRole(commerceIntegration.PAYMENT_MONITOR_ROLE(), admin);
        commerceIntegration.grantRole(commerceIntegration.SIGNER_ROLE(), operatorSigner);

        console.log("Contract permissions configured");
    }

    /**
     * @dev Sets up test users with realistic token balances and ETH
     * @notice BEST PRACTICE: Test users should have sufficient balances to execute
     *         all test scenarios without running into insufficient balance errors.
     */
    function _setupTestUsers() internal {
        console.log("Setting up test users...");

        address[4] memory users = [creator1, creator2, user1, user2];
        
        for (uint256 i = 0; i < users.length; i++) {
            // Give each user 1000 USDC for testing payments
            mockUSDC.mint(users[i], 1000e6);
            
            // Give each user 10 ETH for gas and ETH-based payments
            vm.deal(users[i], 10 ether);
        }

        console.log("Test users set up with initial balances");
    }

    /**
     * @dev Sets up realistic mock price data for testing
     * @notice EDUCATIONAL: This function demonstrates how to configure mock contracts
     *         with realistic market data for comprehensive testing scenarios.
     */
    function _setupMockPrices() internal {
        // Set up realistic ETH/USDC prices for different fee tiers
        // EXPLANATION: Different fee tiers often have slightly different prices due to liquidity
        
        // 0.05% fee tier (most liquid, best price)
        mockQuoter.setMockPrice(
            0x4200000000000000000000000000000000000006, // WETH
            address(mockUSDC),
            500,
            2000e6 // 1 ETH = 2000 USDC
        );

        // 0.3% fee tier (standard)
        mockQuoter.setMockPrice(
            0x4200000000000000000000000000000000000006, // WETH
            address(mockUSDC),
            3000,
            1995e6 // Slightly worse price due to higher fees
        );

        // 1% fee tier (least liquid, worst price)
        mockQuoter.setMockPrice(
            0x4200000000000000000000000000000000000006, // WETH
            address(mockUSDC),
            10000,
            1990e6 // Even worse price
        );

        // Set up reverse prices for USDC -> WETH
        mockQuoter.setMockPrice(
            address(mockUSDC),
            0x4200000000000000000000000000000000000006, // WETH
            3000,
            500000000000000 // 1 USDC = 0.0005 ETH (1/2000)
        );

        // Set up a test token for exotic pair testing
        mockQuoter.setMockPrice(
            0x1234567890123456789012345678901234567890, // Test token
            address(mockUSDC),
            3000,
            1e6 // 1 TEST = 1 USDC
        );
    }

    /**
     * @dev Registers test creators with the platform
     * @notice HELPER FUNCTION: This simplifies test setup by pre-registering creators
     *         with realistic subscription prices and profiles.
     */
    function _registerTestCreators() internal {
        vm.startPrank(creator1);
        creatorRegistry.registerCreator(
            5e6, // 5 USDC subscription price
            "ipfs://creator1-profile",
            "Test Creator 1"
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        creatorRegistry.registerCreator(
            10e6, // 10 USDC subscription price
            "ipfs://creator2-profile",
            "Test Creator 2"
        );
        vm.stopPrank();
    }

    /**
     * @dev Creates test content for various testing scenarios
     * @notice UTILITY: Pre-populates the platform with content for comprehensive testing
     */
    function _createTestContent() internal {
        _registerTestCreators();

        vm.startPrank(creator1);
        contentRegistry.registerContent(
            "ipfs://test-content-1",
            "Test Content 1",
            ContentRegistry.ContentCategory.VIDEO,
            2e6 // 2 USDC per view
        );
        vm.stopPrank();

        vm.startPrank(creator2);
        contentRegistry.registerContent(
            "ipfs://test-content-2", 
            "Test Content 2",
            ContentRegistry.ContentCategory.ARTICLE,
            1e6 // 1 USDC per view
        );
        vm.stopPrank();
    }

    /**
     * @dev Override this in test contracts for custom setup
     * @notice EXTENSIBILITY: Allows individual test contracts to add their own setup logic
     */
    function _customSetup() internal virtual {
        // Default implementation does nothing
        // Individual test contracts can override this
    }
}