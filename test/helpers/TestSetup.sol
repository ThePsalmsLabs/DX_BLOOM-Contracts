// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Core contracts
import { CommerceProtocolBase } from "../../src/CommerceProtocolBase.sol";
import { CommerceProtocolCore } from "../../src/CommerceProtocolCore.sol";
import { CommerceProtocolPermit } from "../../src/CommerceProtocolPermit.sol";

// Manager contracts
import { AccessManager } from "../../src/AccessManager.sol";
import { AdminManager } from "../../src/AdminManager.sol";
import { SignatureManager } from "../../src/SignatureManager.sol";
import { RefundManager } from "../../src/RefundManager.sol";
import { PermitPaymentManager } from "../../src/PermitPaymentManager.sol";
import { ViewManager } from "../../src/ViewManager.sol";

// Supporting contracts
import { CreatorRegistry } from "../../src/CreatorRegistry.sol";
import { ContentRegistry } from "../../src/ContentRegistry.sol";
import { PriceOracle } from "../../src/PriceOracle.sol";
import { PayPerView } from "../../src/PayPerView.sol";
import { SubscriptionManager } from "../../src/SubscriptionManager.sol";
import { IntentIdManager } from "../../src/IntentIdManager.sol";
import { RewardsTreasury } from "../../src/rewards/RewardsTreasury.sol";

// Interfaces and types
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { IBaseCommerceIntegration } from "../../src/interfaces/IPlatformInterfaces.sol";

// Test helper contracts
import { SignatureManagerTestHelper } from "./SignatureManagerTestHelper.sol";
import { ContentRegistryTestHelper } from "./ContentRegistryTestHelper.sol";
import { RewardsTreasuryTestHelper } from "./RewardsTreasuryTestHelper.sol";

// Mock contracts
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockIPFSStorage } from "../mocks/MockIPFSStorage.sol";
import { MockQuoterV2 } from "../mocks/MockQuoterV2.sol";
import { MockCommerceProtocol } from "../mocks/MockCommerceProtocol.sol";

/**
 * @title TestSetup
 * @dev Comprehensive base test contract with all contract deployments and utilities
 * @notice This contract provides the foundation for all unit and integration tests
 */
abstract contract TestSetup is Test {
    // ============ CONTRACT INSTANCES ============

    // Core contracts
    CommerceProtocolCore public commerceProtocolCore;
    CommerceProtocolPermit public commerceProtocolPermit;

    // Manager contracts
    AccessManager public accessManager;
    AdminManager public adminManager;
    SignatureManager public signatureManager;
    RefundManager public refundManager;
    PermitPaymentManager public permitPaymentManager;
    ViewManager public viewManager;

    // Supporting contracts
    CreatorRegistry public creatorRegistry;
    ContentRegistry public contentRegistry;
    PriceOracle public priceOracle;
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    RewardsTreasury public rewardsTreasury;

    // ============ MOCK CONTRACTS ============

    MockERC20 public mockUSDC;
    MockERC20 public mockWETH;
    MockIPFSStorage public mockIPFSStorage;
    MockQuoterV2 public mockQuoterV2;
    MockCommerceProtocol public mockCommerceProtocol;

    // ============ TEST ADDRESSES ============

    address public admin = address(0x1000);
    address public operator = address(0x2000);
    address public operatorSigner = address(0x3000);
    address public operatorFeeDestination = address(0x4000);

    address public user1 = address(0x5000);
    address public user2 = address(0x6000);
    address public user3 = address(0x7000);

    address public creator1 = address(0x8000);
    address public creator2 = address(0x9000);
    address public creator3 = address(0xA000);

    address public paymentMonitor = address(0xB000);

    // ============ TEST HELPER CONTRACTS ============

    SignatureManagerTestHelper public signatureTestHelper;
    ContentRegistryTestHelper public contentTestHelper;
    RewardsTreasuryTestHelper public rewardsTestHelper;

    // ============ TEST CONSTANTS ============

    uint256 public constant INITIAL_USDC_BALANCE = 1000000e6; // 1M USDC
    uint256 public constant INITIAL_ETH_BALANCE = 100 ether;
    uint256 public constant DEFAULT_DEADLINE = 1 hours;
    uint256 public constant PLATFORM_FEE_RATE = 250; // 2.5%
    uint256 public constant OPERATOR_FEE_RATE = 50;  // 0.5%

    // ============ SETUP FUNCTIONS ============

    function setUp() public virtual {
        // Deploy mock contracts first
        _deployMocks();

        // Deploy supporting contracts
        _deploySupportingContracts();

        // Deploy manager contracts
        _deployManagerContracts();

        // Deploy core contracts
        _deployCoreContracts();

        // Deploy test helpers
        _deployTestHelpers();

        // Set up initial state
        _setupInitialState();

        // Set up test users
        _setupTestUsers();
    }

    function _deployMocks() internal {
        // Deploy mock USDC token
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock WETH token
        mockWETH = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy mock IPFS storage
        mockIPFSStorage = new MockIPFSStorage();

        // Deploy mock quoter
        mockQuoterV2 = new MockQuoterV2();

        // Deploy mock commerce protocol
        mockCommerceProtocol = new MockCommerceProtocol();

        // Set up mock quoter with USDC alias for testing
        mockQuoterV2.setUSDCAlias(address(mockUSDC));
    }

    function _deploySupportingContracts() internal {
        // Deploy IntentIdManager library helper (this is a library, so no address)

        // Deploy Price Oracle
        priceOracle = new PriceOracle(
            address(mockQuoterV2),
            address(mockUSDC),
            address(mockWETH)
        );

        // Deploy Creator Registry
        creatorRegistry = new CreatorRegistry(
            operatorFeeDestination,
            address(mockUSDC)
        );

        // Deploy Content Registry
        contentRegistry = new ContentRegistry(
            address(mockIPFSStorage)
        );

        // Deploy PayPerView
        payPerView = new PayPerView(
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            address(mockUSDC),
            address(mockWETH)
        );

        // Deploy Subscription Manager
        subscriptionManager = new SubscriptionManager(
            address(creatorRegistry),
            address(contentRegistry),
            address(mockUSDC)
        );

        // Deploy Rewards Treasury
        rewardsTreasury = new RewardsTreasury(address(mockUSDC));

        // Deploy View Manager
        viewManager = new ViewManager(address(mockCommerceProtocol)); // Use mock for testing
    }

    function _deployManagerContracts() internal {
        // Deploy Access Manager
        accessManager = new AccessManager(
            address(payPerView),
            address(subscriptionManager),
            address(creatorRegistry)
        );

        // Deploy Signature Manager
        signatureManager = new SignatureManager(admin);

        // Deploy Refund Manager
        refundManager = new RefundManager(
            address(payPerView),
            address(subscriptionManager),
            address(mockUSDC)
        );

        // Deploy Permit Payment Manager
        permitPaymentManager = new PermitPaymentManager(
            address(mockCommerceProtocol),
            address(0), // permit2 - mock
            address(mockUSDC)
        );

        // Deploy Admin Manager
        adminManager = new AdminManager(
            operatorFeeDestination,
            operatorSigner,
            address(mockCommerceProtocol) // Use mock for testing
        );
    }

    function _deployTestHelpers() internal {
        // Deploy test helper contracts
        signatureTestHelper = new SignatureManagerTestHelper(address(signatureManager));
        contentTestHelper = new ContentRegistryTestHelper(address(contentRegistry));
        rewardsTestHelper = new RewardsTreasuryTestHelper(address(rewardsTreasury));
    }

    function _deployCoreContracts() internal {
        // Deploy CommerceProtocolCore
        commerceProtocolCore = new CommerceProtocolCore(
            address(mockCommerceProtocol),
            address(0), // permit2 - mock
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            address(mockUSDC),
            operatorFeeDestination,
            operatorSigner,
            address(adminManager),
            address(viewManager),
            address(accessManager),
            address(signatureManager),
            address(refundManager),
            address(permitPaymentManager),
            address(0) // rewards integration - optional
        );

        // Deploy CommerceProtocolPermit
        commerceProtocolPermit = new CommerceProtocolPermit(
            address(mockCommerceProtocol),
            address(0), // permit2 - mock
            address(creatorRegistry),
            address(contentRegistry),
            address(priceOracle),
            address(mockUSDC),
            operatorFeeDestination,
            operatorSigner,
            address(adminManager),
            address(viewManager),
            address(accessManager),
            address(signatureManager),
            address(refundManager),
            address(permitPaymentManager),
            address(0) // rewards integration - optional
        );

        // Update manager contracts with deployed addresses
        _updateManagerContractReferences();
    }

    function _updateManagerContractReferences() internal {
        // Update PermitPaymentManager with core contract reference
        // Note: PermitPaymentManager doesn't have setCommerceProtocolCore method in this version

        // Grant roles to payment monitor
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), paymentMonitor);

        vm.prank(admin);
        commerceProtocolCore.grantRole(keccak256("PAYMENT_MONITOR_ROLE"), paymentMonitor);
    }

    function _setupInitialState() internal {
        // Register test creators
        vm.prank(creator1);
        creatorRegistry.registerCreator(
            1e6, // $1.00 subscription price
            "QmTestIPFSHash1"
        );

        vm.prank(creator2);
        creatorRegistry.registerCreator(
            2e6, // $2.00 subscription price
            "QmTestIPFSHash2"
        );

        // Update subscription prices
        vm.prank(creator1);
        creatorRegistry.updateSubscriptionPrice(1e6); // $1.00

        vm.prank(creator2);
        creatorRegistry.updateSubscriptionPrice(2e6); // $2.00

        // Register test content
        vm.prank(creator1);
        contentRegistry.registerContent(
            "QmContentHash1",
            "Test Article 1",
            "This is a test article",
            ISharedTypes.ContentCategory.Article,
            0.1e6, // $0.10
            new string[](0)
        );

        vm.prank(creator2);
        contentRegistry.registerContent(
            "QmContentHash2",
            "Test Video 1",
            "This is a test video",
            ISharedTypes.ContentCategory.Video,
            0.5e6, // $0.50
            new string[](0)
        );
    }

    function _setupTestUsers() internal {
        // Mint USDC to test users
        mockUSDC.mint(user1, INITIAL_USDC_BALANCE);
        mockUSDC.mint(user2, INITIAL_USDC_BALANCE);
        mockUSDC.mint(user3, INITIAL_USDC_BALANCE);
        mockUSDC.mint(creator1, INITIAL_USDC_BALANCE);
        mockUSDC.mint(creator2, INITIAL_USDC_BALANCE);

        // Mint ETH to test users
        vm.deal(user1, INITIAL_ETH_BALANCE);
        vm.deal(user2, INITIAL_ETH_BALANCE);
        vm.deal(user3, INITIAL_ETH_BALANCE);
        vm.deal(creator1, INITIAL_ETH_BALANCE);
        vm.deal(creator2, INITIAL_ETH_BALANCE);
        vm.deal(admin, INITIAL_ETH_BALANCE);
        vm.deal(operator, INITIAL_ETH_BALANCE);
    }

    // ============ TEST UTILITY FUNCTIONS ============

    function createTestPaymentRequest(
        address creator,
        uint256 contentId,
        address paymentToken,
        uint256 maxSlippage,
        uint256 deadline,
        ISharedTypes.PaymentType paymentType
    ) internal view returns (ISharedTypes.PlatformPaymentRequest memory) {
        return ISharedTypes.PlatformPaymentRequest({
            paymentType: paymentType,
            creator: creator,
            contentId: contentId,
            paymentToken: paymentToken,
            maxSlippage: maxSlippage,
            deadline: deadline
        });
    }

    function generateTestSignature(
        bytes32 hash,
        address signer
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), hash);
        return abi.encodePacked(r, s, v);
    }

    function expectEmit_PaymentIntentCreated(
        bytes16 intentId,
        address user,
        address creator,
        ISharedTypes.PaymentType paymentType
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit CommerceProtocolBase.PaymentIntentCreated(
            intentId,
            user,
            creator,
            paymentType,
            0, // totalAmount - will be any
            0, // creatorAmount - will be any
            0, // platformFee - will be any
            0, // operatorFee - will be any
            address(mockUSDC), // paymentToken
            0  // expectedAmount - will be any
        );
    }

    function expectEmit_PaymentCompleted(
        bytes16 intentId,
        address user,
        address creator,
        ISharedTypes.PaymentType paymentType,
        bool success
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit CommerceProtocolBase.PaymentCompleted(
            intentId,
            user,
            creator,
            paymentType,
            0, // contentId - will be any
            address(mockUSDC), // paymentToken
            0, // amountPaid - will be any
            success
        );
    }

    function assertPaymentContext(
        bytes16 intentId,
        address expectedUser,
        address expectedCreator,
        ISharedTypes.PaymentType expectedPaymentType,
        bool expectedProcessed
    ) internal {
        ISharedTypes.PaymentContext memory context = commerceProtocolCore.getPaymentContext(intentId);

        assertEq(context.user, expectedUser);
        assertEq(context.creator, expectedCreator);
        assertEq(uint8(context.paymentType), uint8(expectedPaymentType));
        assertEq(context.processed, expectedProcessed);
    }

    function calculateExpectedFees(
        uint256 amount,
        uint256 platformFeeRate,
        uint256 operatorFeeRate
    ) internal pure returns (
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee
    ) {
        platformFee = (amount * platformFeeRate) / 10000;
        operatorFee = (amount * operatorFeeRate) / 10000;
        creatorAmount = amount - platformFee;
        totalAmount = creatorAmount + platformFee + operatorFee;
    }

    // ============ MOCK HELPERS ============

    function mockPriceOracle() internal {
        // Mock price oracle responses
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSignature("validateQuoteBeforeSwap(address,address,uint256,uint256,uint256,uint24)"),
            abi.encode(true, 1000000) // valid quote
        );

        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSignature("checkPriceImpact(address,address,uint256,uint256)"),
            abi.encode(100, true) // 1% impact, acceptable
        );
    }

    function mockBaseCommerceIntegration() internal {
        // Mock BaseCommerceIntegration responses
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("executeEscrowPayment((address,address,uint256,uint8,bytes,bool))"),
            abi.encode(bytes32(0))
        );
    }

    // ============ TIME HELPERS ============

    function advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function setNextBlockTimestamp(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    // ============ TEST HELPER UTILITIES ============

    /**
     * @dev Helper function to set up test intent with signature
     * @param intentId The intent ID
     * @param hash The intent hash
     */
    function setupTestIntent(bytes16 intentId, bytes32 hash) internal {
        signatureTestHelper.setIntentHashForTesting(intentId, hash);
    }

    /**
     * @dev Helper function to create test content
     * @param creator Creator address
     * @param title Content title
     * @param description Content description
     * @param category Content category
     * @param price Content price
     * @return contentId The registered content ID
     */
    function createTestContent(
        address creator,
        string memory title,
        string memory description,
        ISharedTypes.ContentCategory category,
        uint256 price
    ) internal returns (uint256 contentId) {
        string[] memory tags = new string[](0); // No tags for test content
        contentId = contentRegistry.registerContent(
            "QmTestIPFSHash",
            title,
            description,
            category,
            price,
            tags
        );
    }

    /**
     * @dev Helper function to set up test treasury scenario
     * @param customerRewards Customer rewards pool balance
     * @param creatorIncentives Creator incentives pool balance
     * @param operational Operational pool balance
     * @param reserve Reserve pool balance
     */
    function setupTestTreasury(
        uint256 customerRewards,
        uint256 creatorIncentives,
        uint256 operational,
        uint256 reserve
    ) internal {
        // Note: Direct pool balance setting is not available in production
        // Tests should use proper deposit and allocation functions instead
        // This is a placeholder for demonstration
    }
}
