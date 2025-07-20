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
import {ISharedTypes} from "../../src/interfaces/ISharedTypes.sol";

/**
 * @title TestSetup - FIXED VERSION
 * @dev Base contract for all tests with corrected constructor parameters and setup sequence
 */
abstract contract TestSetup is Test, TestConstants, ISharedTypes {
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

    // ============ MOCK TOKEN ADDRESSES (Base network standard) ============
    address public constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // ============ EVENTS FOR TESTING ============
    event CreatorRegistered(address indexed creator, uint256 subscriptionPrice, uint256 timestamp, string profileData);
    event ContentRegistered(
        uint256 indexed contentId,
        address indexed creator,
        string ipfsHash,
        string title,
        ContentCategory category,
        uint256 payPerViewPrice,
        uint256 timestamp
    );

    /**
     * @dev Sets up the complete test environment with proper dependency injection
     */
    function setUp() public virtual {
        // Always start with admin privileges for setup
        vm.startPrank(admin);

        // Step 1: Deploy external mock dependencies first
        _deployMockDependencies();

        // Step 2: Deploy core contracts with mock dependencies injected
        _deployCoreContracts();

        // Step 3: Configure contract permissions and relationships
        _configureContracts();

        // Step 4: Set up test users with realistic balances
        _setupTestUsers();

        // Step 5: Configure mock price data for testing
        _configureMockPrices();

        vm.stopPrank();
    }

    /**
     * @dev Deploys all mock external dependencies
     */
    function _deployMockDependencies() internal {
        console.log("Deploying mock dependencies...");

        // Deploy mock USDC with proper ERC20 configuration
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        mockUSDC.mint(admin, 1000000e6); // 1M USDC for testing

        // Deploy mock Commerce Protocol for payment flow testing
        mockCommerceProtocol = new MockCommerceProtocol();

        // Deploy mock Uniswap Quoter with realistic price data
        mockQuoter = new MockQuoterV2();

        console.log("Mock dependencies deployed:");
        console.log("- Mock USDC:", address(mockUSDC));
        console.log("- Mock Commerce Protocol:", address(mockCommerceProtocol));
        console.log("- Mock Quoter:", address(mockQuoter));
    }

    /**
     * @dev Deploys all core platform contracts with proper dependency injection
     * @notice CRITICAL FIX: PriceOracle now receives the mock quoter address
     */
    function _deployCoreContracts() internal {
        console.log("Deploying core contracts...");

        // Deploy PriceOracle with mock quoter and token addresses
        // FIX: Pass the mock quoter address instead of relying on hardcoded mainnet address
        priceOracle = new PriceOracle(
            address(mockQuoter), // Use mock quoter for testing
            WETH_BASE, // Standard WETH address on Base
            address(mockUSDC) // Use mock USDC for testing
        );
        console.log("- PriceOracle deployed at:", address(priceOracle));

        // Deploy CreatorRegistry
        creatorRegistry = new CreatorRegistry(feeRecipient, address(mockUSDC));
        console.log("- CreatorRegistry deployed at:", address(creatorRegistry));

        // Deploy ContentRegistry with creator registry reference
        contentRegistry = new ContentRegistry(address(creatorRegistry));
        console.log("- ContentRegistry deployed at:", address(contentRegistry));

        // Deploy PayPerView with all dependencies
        payPerView =
            new PayPerView(address(creatorRegistry), address(contentRegistry), address(priceOracle), address(mockUSDC));
        console.log("- PayPerView deployed at:", address(payPerView));

        // Deploy SubscriptionManager
        subscriptionManager =
            new SubscriptionManager(address(creatorRegistry), address(contentRegistry), address(mockUSDC));
        console.log("- SubscriptionManager deployed at:", address(subscriptionManager));

        // Deploy CommerceProtocolIntegration
        commerceIntegration = new CommerceProtocolIntegration(
            address(mockCommerceProtocol),
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            address(mockUSDC),
            feeRecipient,
            operatorSigner
        );
        console.log("- CommerceIntegration deployed at:", address(commerceIntegration));

        console.log("Core contracts deployed successfully");
    }

    /**
     * @dev Configures contract permissions and relationships
     * @notice CRITICAL: The order of role grants matters for proper access control
     */
    function _configureContracts() internal {
        console.log("Configuring contract permissions...");

        // Configure CreatorRegistry permissions
        // Grant platform role to all contracts that need to update creator stats
        creatorRegistry.grantPlatformRole(address(contentRegistry));
        creatorRegistry.grantPlatformRole(address(payPerView));
        creatorRegistry.grantPlatformRole(address(subscriptionManager));
        creatorRegistry.grantPlatformRole(address(commerceIntegration));

        // Configure ContentRegistry permissions
        // Grant purchase recorder role to contracts that record purchases
        contentRegistry.grantRole(contentRegistry.PURCHASE_RECORDER_ROLE(), address(payPerView));
        contentRegistry.grantRole(contentRegistry.PURCHASE_RECORDER_ROLE(), address(commerceIntegration));

        // Configure PayPerView permissions
        // Grant payment processor role to commerce integration
        payPerView.grantRole(payPerView.PAYMENT_PROCESSOR_ROLE(), address(commerceIntegration));

        // Configure CommerceProtocolIntegration addresses
        commerceIntegration.setPayPerView(address(payPerView));
        commerceIntegration.setSubscriptionManager(address(subscriptionManager));

        // Grant necessary roles to CommerceProtocolIntegration
        commerceIntegration.grantRole(commerceIntegration.PAYMENT_MONITOR_ROLE(), admin);
        commerceIntegration.grantRole(commerceIntegration.SIGNER_ROLE(), operatorSigner);

        console.log("Contract permissions configured");
    }

    /**
     * @dev Sets up test users with realistic token balances
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
     * @dev Configures mock price data for common token pairs
     * @notice FIX: This ensures MockQuoterV2 returns valid prices instead of "No liquidity"
     */
    function _configureMockPrices() internal virtual {
        console.log("Configuring mock price data...");

        // Set up WETH/USDC prices (1 WETH = 2000 USDC)
        mockQuoter.setMockPrice(WETH_BASE, address(mockUSDC), 500, 2000e6);
        mockQuoter.setMockPrice(WETH_BASE, address(mockUSDC), 3000, 2000e6);
        mockQuoter.setMockPrice(WETH_BASE, address(mockUSDC), 10000, 2000e6);

        // Set up reverse prices (1 USDC = 0.0005 WETH)
        mockQuoter.setMockPrice(address(mockUSDC), WETH_BASE, 500, 0.0005e18);
        mockQuoter.setMockPrice(address(mockUSDC), WETH_BASE, 3000, 0.0005e18);
        mockQuoter.setMockPrice(address(mockUSDC), WETH_BASE, 10000, 0.0005e18);

        // Set up USDC to USDC (for same-token edge cases)
        mockQuoter.setMockPrice(address(mockUSDC), address(mockUSDC), 500, 1e6);
        mockQuoter.setMockPrice(address(mockUSDC), address(mockUSDC), 3000, 1e6);

        console.log("Mock price data configured");
    }

    // Helper to advance block timestamp in tests
    function warpForward(uint256 secs) internal {
        vm.warp(block.timestamp + secs);
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Helper to register a creator with default subscription price
     */
    function registerCreator(address creator) internal returns (bool) {
        return registerCreator(creator, DEFAULT_SUBSCRIPTION_PRICE, "");
    }

    /**
     * @dev Helper to register a creator with custom subscription price
     */
    function registerCreator(address creator, uint256 subscriptionPrice, string memory profileData)
        internal
        returns (bool)
    {
        vm.prank(creator);
        creatorRegistry.registerCreator(subscriptionPrice, profileData);
        return creatorRegistry.isRegisteredCreator(creator);
    }

    /**
     * @dev Helper to register content for a creator
     */
    function registerContent(address creator, uint256 price, string memory title) internal returns (uint256) {
        vm.prank(creator);
        return contentRegistry.registerContent(
            "QmTestHash", title, "Test description", ContentCategory.Article, price, new string[](0)
        );
    }

    /**
     * @dev Helper to approve USDC spending
     */
    function approveUSDC(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        mockUSDC.approve(spender, amount);
    }

    /**
     * @dev Safely creates a PaymentType from uint8 for testing
     * @param value The payment type as uint8 (0-3)
     * @return paymentType The validated PaymentType enum
     * @notice This prevents test failures due to enum conversion issues
     */
    function createPaymentType(uint8 value) internal pure returns (PaymentType paymentType) {
        require(value <= 3, "Invalid payment type value"); // PaymentType goes 0-3
        return PaymentType(value);
    }

    /**
     * @dev Creates a payment request with proper enum validation
     * @param paymentTypeValue The payment type as uint8 (0=PayPerView, 1=Subscription, 2=Tip, 3=Donation)
     * @param creator The creator address
     * @param contentId The content ID (0 for subscriptions)
     * @return request The properly constructed payment request
     */
    function createValidatedPaymentRequest(
        uint8 paymentTypeValue,
        address creator, 
        uint256 contentId
    ) internal view returns (CommerceProtocolIntegration.PlatformPaymentRequest memory request) {
        // Validate enum value before using it
        require(paymentTypeValue <= uint8(PaymentType.Donation), "Invalid payment type");
        
        request.paymentType = PaymentType(paymentTypeValue);
        request.creator = creator;
        request.contentId = contentId;
        request.paymentToken = address(0); // Will be set by caller
        request.maxSlippage = 100; // 1% default
        request.deadline = block.timestamp + 1 hours; // Default deadline
        
        return request;
    }
}
