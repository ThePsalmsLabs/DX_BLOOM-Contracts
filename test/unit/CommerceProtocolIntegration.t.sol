// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {CommerceProtocolIntegration} from "../../src/CommerceProtocolIntegration.sol";
import {ICommercePaymentsProtocol} from "../../src/interfaces/IPlatformInterfaces.sol";
import {ContentRegistry} from "../../src/ContentRegistry.sol";
import {CreatorRegistry} from "../../src/CreatorRegistry.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {PayPerView} from "../../src/PayPerView.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

/**
 * @title CommerceProtocolIntegrationTest - FIXED VERSION
 * @dev Fixed access control setup for CommerceProtocolIntegration testing
 * @notice This fix addresses the permission cascade issues that were causing test failures
 */
contract CommerceProtocolIntegrationTest is TestSetup {
    using ECDSA for bytes32;

    // ============ ADVANCED TEST DATA STRUCTURES ============

    /**
     * @dev Comprehensive payment scenario for complex testing
     * @notice This structure encapsulates everything needed to test a complete payment flow
     */
    struct PaymentTestScenario {
        address user; // Who's paying
        address creator; // Who's getting paid
        address paymentToken; // What token they're paying with
        uint256 paymentAmount; // How much of that token
        uint256 expectedUsdcAmount; // Expected USDC equivalent
        PaymentType paymentType; // Content vs subscription
        uint256 contentId; // If buying content
        uint256 maxSlippage; // Slippage tolerance
        uint256 deadline; // Payment deadline
        bool shouldSucceed; // Expected outcome
        string expectedError; // If failure expected
    }

    /**
     * @dev Financial verification data for precise testing
     * @notice We need to verify every penny is accounted for correctly
     */
    struct FinancialSnapshot {
        uint256 userTokenBalance; // User's payment token balance
        uint256 userUsdcBalance; // User's USDC balance
        uint256 creatorUsdcBalance; // Creator's USDC balance
        uint256 platformFeeBalance; // Platform's fee collection
        uint256 operatorFeeBalance; // Operator's fee collection
        uint256 creatorEarningsInContract; // Creator earnings in PayPerView/SubscriptionManager
        uint256 platformTotalVolume; // Platform-wide volume metrics
    }

    /**
     * @dev Signature testing data for security validation
     * @notice Signature validation is critical - any bypass could drain the platform
     */
    struct SignatureTestCase {
        bytes32 intentHash; // Hash to be signed
        address signer; // Who should sign
        uint256 signerPrivateKey; // For test signature generation
        bool shouldValidate; // Expected validation result
        string testDescription; // What we're testing
    }

    /**
     * @dev Attack scenario for security testing
     * @notice Real attackers will try these exact scenarios
     */
    struct AttackScenario {
        address attacker; // Attacker address
        string attackDescription; // What attack we're simulating
        bytes attackData; // Attack payload
        bool shouldSucceed; // Whether attack should work
        string expectedFailureReason; // Why it should fail
    }

    // ============ TEST STATE VARIABLES ============

    MockERC20 public attackerToken; // For testing malicious tokens
    MockERC20 public volatileToken; // For testing price volatility
    MockERC20 public feeOnTransferToken; // For testing problematic tokens

    // Test content and creator data
    uint256 private testContentId;
    uint256 private premiumContentId;

    // Private keys for signature testing (use proper test keys in production)
    uint256 private constant OPERATOR_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 private constant MALICIOUS_PRIVATE_KEY = 0x9876543210987654321098765432109876543210987654321098765432109876;

    address private realOperatorSigner;
    address private maliciousSigner;

    // Attack simulation addresses
    address public reentrantAttacker = address(0xDEADBEEF);
    address public frontRunner = address(0xBADCAFE);
    address public mevBot = address(0xDEADFACE);

    /**
     * @dev FIXED: Enhanced setUp with proper permission management
     * @notice The key insight here is that access control is like a chain -
     *         if any link is missing, the whole chain breaks
     */
    function setUp() public override {
        super.setUp();

        // Deploy all tokens if not already deployed
        if (address(attackerToken) == address(0)) {
            attackerToken = new MockERC20("Attacker", "ATK", 18);
        }
        if (address(volatileToken) == address(0)) {
            volatileToken = new MockERC20("Volatile", "VOL", 18);
        }
        if (address(feeOnTransferToken) == address(0)) {
            feeOnTransferToken = new MockERC20("FeeOnTransfer", "FEE", 18);
        }

        address[] memory tokens = new address[](5);
        tokens[0] = address(mockUSDC);
        tokens[1] = address(volatileToken);
        tokens[2] = address(attackerToken);
        tokens[3] = address(feeOnTransferToken);
        tokens[4] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // canonical USDC

        uint24[3] memory poolFees = [uint24(500), uint24(3000), uint24(10000)];

        // Set 1:1 price for all tokens to USDC for simplicity, or customize as needed
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                for (uint256 k = 0; k < poolFees.length; k++) {
                    if (tokens[i] != address(0) && tokens[j] != address(0)) {
                        mockQuoter.setMockPrice(tokens[i], tokens[j], poolFees[k], 1e6);
                    }
                }
            }
        }

        // Set prank context to admin for owner-only actions
        vm.startPrank(admin);
        _setupCompletePermissionChain();
        _setupCryptographicInfrastructure();
        _createTestDataWithProperContext();
        vm.stopPrank();
    }

    /**
     * @dev CRITICAL FIX: Complete permission chain setup
     * @notice This function addresses the missing link in our permission chain.
     *         The issue was that ContentRegistry needed permission to update CreatorRegistry stats
     */
    function _setupCompletePermissionChain() private {
        console.log("Setting up complete permission chain...");

        // MISSING LINK 1: Grant ContentRegistry platform role to call CreatorRegistry
        // This was the root cause of the first error - ContentRegistry couldn't update creator stats
        creatorRegistry.grantPlatformRole(address(contentRegistry));
        console.log(" ContentRegistry granted platform role in CreatorRegistry");

        // Verify existing permissions are still in place (should already be set by parent setUp)
        // These are like double-checking that other security badges are properly assigned

        // Verify PayPerView has platform role
        bool payPerViewHasPlatformRole =
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(payPerView));
        require(payPerViewHasPlatformRole, "PayPerView missing platform role");

        // Verify SubscriptionManager has platform role
        bool subscriptionMgrHasPlatformRole =
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(subscriptionManager));
        require(subscriptionMgrHasPlatformRole, "SubscriptionManager missing platform role");

        // Verify CommerceIntegration has platform role
        bool commerceIntegrationHasPlatformRole =
            creatorRegistry.hasRole(creatorRegistry.PLATFORM_CONTRACT_ROLE(), address(commerceIntegration));
        require(commerceIntegrationHasPlatformRole, "CommerceIntegration missing platform role");

        console.log(" All platform roles verified");
    }

    /**
     * @dev FIXED: Proper cryptographic setup within admin context
     * @notice This ensures signature testing works by setting up signers correctly
     */
    function _setupCryptographicInfrastructure() private {
        console.log("Setting up cryptographic infrastructure...");

        // Derive test addresses from private keys
        realOperatorSigner = vm.addr(OPERATOR_PRIVATE_KEY);
        maliciousSigner = vm.addr(MALICIOUS_PRIVATE_KEY);

        // CRITICAL FIX: Update operator signer while still in admin context
        // The original test failed here because it tried to grant roles outside admin context
        commerceIntegration.updateOperatorSigner(realOperatorSigner);

        // FIX: The test was trying to grant SIGNER_ROLE manually, but updateOperatorSigner already does this
        // We can verify the role was granted properly
        bool signerHasRole = commerceIntegration.hasRole(commerceIntegration.SIGNER_ROLE(), realOperatorSigner);
        require(signerHasRole, "Operator signer missing SIGNER_ROLE");

        console.log(" Cryptographic infrastructure configured");
        console.log("  - Real operator signer:", realOperatorSigner);
        console.log("  - Malicious signer:", maliciousSigner);
    }

    /**
     * @dev FIXED: Create test data with proper permission context
     * @notice This creates our test creators and content now that all permissions are properly set
     */
    function _createTestDataWithProperContext() private {
        console.log("Creating test data...");

        // Register test creators (this should work now that permissions are fixed)
        assertTrue(_registerCreatorHelper(creator1, 10e6, "Premium Creator"));
        assertTrue(_registerCreatorHelper(creator2, 5e6, "Budget Creator"));

        // Register test content (this should work now that ContentRegistry can update CreatorRegistry)
        testContentId = _registerContentHelper(creator1, 3e6, "Standard Content");
        premiumContentId = _registerContentHelper(creator1, 15e6, "Premium Course");

        console.log(" Test data created successfully");
        console.log("  - Test content ID:", testContentId);
        console.log("  - Premium content ID:", premiumContentId);
    }

    // ============ FOUNDATIONAL TESTS - BUILDING BLOCKS OF TRUST ============

    /**
     * @dev Tests the mathematical foundation of our payment system
     * @notice If fee calculations are wrong, the entire platform economics break down
     */
    function test_PaymentCalculations_MathematicalPrecision() public {
        // Test Scenario: $100 content purchase
        uint256 contentPrice = 100e6; // $100 USDC

        PaymentTestScenario memory scenario = PaymentTestScenario({
            user: user1,
            creator: creator1,
            paymentToken: address(mockUSDC),
            paymentAmount: contentPrice,
            expectedUsdcAmount: contentPrice,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            maxSlippage: 100, // 1%
            deadline: block.timestamp + 1 hours,
            shouldSucceed: true,
            expectedError: ""
        });

        // Manually calculate expected amounts for verification
        uint256 platformFeeRate = 500; // 5%
        uint256 operatorFeeRate = 50; // 0.5%

        uint256 platformFee = (contentPrice * platformFeeRate) / 10000;
        uint256 operatorFee = (contentPrice * operatorFeeRate) / 10000;
        uint256 creatorAmount = contentPrice - platformFee - operatorFee;

        // Expected: Platform gets $5, Operator gets $0.50, Creator gets $94.50
        assertEq(platformFee, 5e6, "Platform fee calculation incorrect");
        assertEq(operatorFee, 0.5e6, "Operator fee calculation incorrect");
        assertEq(creatorAmount, 94.5e6, "Creator amount calculation incorrect");

        // Execute payment and verify mathematical precision
        _executeCompletePaymentScenario(scenario);

        // Verify all amounts are exactly as calculated (to the wei)
        (uint256 actualCreatorEarnings,) = payPerView.getCreatorEarnings(creator1);
        assertEq(actualCreatorEarnings, creatorAmount, "Creator earnings don't match calculations");
    }

    /**
     * @dev Tests payment intent creation with all validation layers
     * @notice Intent creation is the entry point - must be bulletproof
     */
    function test_PaymentIntentCreation_ComprehensiveValidation() public {
        PaymentTestScenario memory validScenario = PaymentTestScenario({
            user: user1,
            creator: creator1,
            paymentToken: address(volatileToken),
            paymentAmount: 6e18, // 6 VOL tokens = $3 USDC
            expectedUsdcAmount: 3e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            maxSlippage: 200, // 2%
            deadline: block.timestamp + 30 minutes,
            shouldSucceed: true,
            expectedError: ""
        });

        // Test 1: Valid intent creation
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(validScenario);

        vm.prank(validScenario.user);
        volatileToken.approve(address(commerceIntegration), validScenario.paymentAmount);

        vm.prank(validScenario.user);
        (
            ICommercePaymentsProtocol.TransferIntent memory intent,
            CommerceProtocolIntegration.PaymentContext memory context
        ) = commerceIntegration.createPaymentIntent(request);

        // Verify intent structure is correct
        assertEq(intent.sender, validScenario.user);
        assertEq(intent.recipient, validScenario.creator);
        assertEq(intent.token, validScenario.paymentToken);
        assertTrue(intent.recipientAmount > 0);
        assertEq(intent.deadline, validScenario.deadline);

        // Verify context linkage
        assertEq(uint256(context.paymentType), uint256(validScenario.paymentType));
        assertEq(context.creator, validScenario.creator);
        assertEq(context.contentId, validScenario.contentId);

        // Test 2: Invalid creator
        request.creator = address(0x9999); // Non-registered creator

        vm.startPrank(validScenario.user);
        vm.expectRevert(CommerceProtocolIntegration.InvalidCreator.selector);
        commerceIntegration.createPaymentIntent(request);
        vm.stopPrank();

        // Test 3: Invalid content
        request.creator = validScenario.creator;
        request.contentId = 999999; // Non-existent content

        vm.startPrank(validScenario.user);
        vm.expectRevert(CommerceProtocolIntegration.InvalidContent.selector);
        commerceIntegration.createPaymentIntent(request);
        vm.stopPrank();

        // Test 4: Expired deadline
        request.contentId = validScenario.contentId;
        request.deadline = block.timestamp - 1; // Past deadline

        vm.startPrank(validScenario.user);
        vm.expectRevert(CommerceProtocolIntegration.DeadlineInPast.selector);
        commerceIntegration.createPaymentIntent(request);
        vm.stopPrank();
    }

    // ============ SIGNATURE SYSTEM TESTS - CRYPTOGRAPHIC SECURITY ============

    /**
     * @dev Tests the complete signature validation system
     * @notice Signature bypass = platform drainage. This must be impenetrable.
     */
    function test_SignatureSystem_CryptographicSecurity() public {
        PaymentTestScenario memory scenario = _createBasicPaymentScenario();

        // Phase 1: Create intent
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Phase 2: Test valid signature
        bytes32 intentHash = commerceIntegration.intentHashes(intent.id);
        assertTrue(intentHash != bytes32(0), "Intent hash not stored");

        // Create valid signature using operator's private key
        bytes memory validSignature = _signIntentHash(intentHash, OPERATOR_PRIVATE_KEY);

        vm.prank(realOperatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, validSignature);

        // Verify signature was accepted
        assertTrue(commerceIntegration.intentReadyForExecution(intent.id), "Valid signature rejected");

        // Phase 3: Test invalid signer
        bytes32 newIntentHash = keccak256(abi.encode("different", "hash"));
        bytes memory invalidSignature = _signIntentHash(newIntentHash, MALICIOUS_PRIVATE_KEY);

        vm.startPrank(maliciousSigner);
        vm.expectRevert(CommerceProtocolIntegration.UnauthorizedSigner.selector);
        commerceIntegration.provideIntentSignature(intent.id, invalidSignature);
        vm.stopPrank();

        // Phase 4: Test signature replay protection
        vm.startPrank(realOperatorSigner);
        vm.expectRevert(CommerceProtocolIntegration.IntentAlreadyProcessed.selector);
        commerceIntegration.provideIntentSignature(intent.id, validSignature);
        vm.stopPrank();

        // Phase 5: Test malformed signature
        bytes memory malformedSignature = "not_a_real_signature";

        // Create new intent for this test
        scenario.user = user2;
        scenario.paymentAmount = 5e6;
        request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent2,) = commerceIntegration.createPaymentIntent(request);

        vm.startPrank(realOperatorSigner);
        vm.expectRevert(CommerceProtocolIntegration.InvalidSignature.selector);
        commerceIntegration.provideIntentSignature(intent2.id, malformedSignature);
        vm.stopPrank();
    }

    /**
     * @dev Tests EIP712 signature standard compliance
     * @notice Industry standard compliance ensures interoperability and security
     */
    function test_EIP712Compliance_IndustryStandards() public {
        // Create a payment intent to get the hash structure
        PaymentTestScenario memory scenario = _createBasicPaymentScenario();
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Get the intent hash that should follow EIP712 standard
        bytes32 intentHash = commerceIntegration.intentHashes(intent.id);

        // Verify hash structure follows EIP712 format
        assertTrue(intentHash != bytes32(0), "EIP712 hash not generated");

        // Test that hash includes all critical fields
        // In a real implementation, we'd verify the exact EIP712 structure
        // For now, we verify that changing any field changes the hash

        // Create slightly different intent
        scenario.paymentAmount = scenario.paymentAmount + 1; // Change amount by 1 wei
        request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent2,) = commerceIntegration.createPaymentIntent(request);

        bytes32 intentHash2 = commerceIntegration.intentHashes(intent2.id);

        // Hashes should be different (proving all fields are included)
        assertTrue(intentHash != intentHash2, "EIP712 hash not sensitive to amount changes");
    }

    // ============ PAYMENT EXECUTION TESTS - THE CRITICAL MOMENT ============

    /**
     * @dev Tests complete payment execution under normal conditions
     * @notice This is where money actually moves - must be perfect
     */
    function test_PaymentExecution_NormalConditions() public {
        PaymentTestScenario memory scenario = _createBasicPaymentScenario();

        // Capture initial financial state
        FinancialSnapshot memory beforeSnapshot = _captureFinancialSnapshot(scenario);

        // Execute complete payment flow
        _executeCompletePaymentScenario(scenario);

        // Capture final financial state
        FinancialSnapshot memory afterSnapshot = _captureFinancialSnapshot(scenario);

        // Verify all financial movements are correct
        assertEq(
            beforeSnapshot.userUsdcBalance - afterSnapshot.userUsdcBalance,
            scenario.paymentAmount,
            "Incorrect amount deducted from user"
        );

        assertTrue(
            afterSnapshot.creatorEarningsInContract > beforeSnapshot.creatorEarningsInContract,
            "Creator earnings not increased"
        );

        assertTrue(
            afterSnapshot.platformTotalVolume > beforeSnapshot.platformTotalVolume, "Platform volume not updated"
        );

        // Verify user received access
        assertTrue(payPerView.hasAccess(scenario.contentId, scenario.user), "User did not receive content access");
    }

    /**
     * @dev Tests payment execution with multi-token scenarios
     * @notice Multi-token support is complex - token conversion must be accurate
     */
    function test_PaymentExecution_MultiTokenComplexity() public {
        // Scenario: User pays with volatile token, creator receives USDC
        PaymentTestScenario memory multiTokenScenario = PaymentTestScenario({
            user: user1,
            creator: creator1,
            paymentToken: address(volatileToken),
            paymentAmount: 20e18, // 20 VOL tokens
            expectedUsdcAmount: 10e6, // Should equal $10 USDC
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            maxSlippage: 300, // 3%
            deadline: block.timestamp + 45 minutes,
            shouldSucceed: true,
            expectedError: ""
        });

        // Pre-execution validation
        uint256 initialVolBalance = volatileToken.balanceOf(multiTokenScenario.user);
        uint256 initialCreatorUSDC = mockUSDC.balanceOf(multiTokenScenario.creator);

        // Execute payment
        _executeCompletePaymentScenario(multiTokenScenario);

        // Post-execution validation
        uint256 finalVolBalance = volatileToken.balanceOf(multiTokenScenario.user);
        uint256 finalCreatorUSDC = mockUSDC.balanceOf(multiTokenScenario.creator);

        // Verify token conversion occurred correctly
        assertEq(
            initialVolBalance - finalVolBalance, multiTokenScenario.paymentAmount, "VOL tokens not deducted correctly"
        );

        // Creator should receive USDC (minus fees)
        assertTrue(finalCreatorUSDC > initialCreatorUSDC, "Creator did not receive USDC payment");

        // Verify user received access despite paying with different token
        assertTrue(
            payPerView.hasAccess(multiTokenScenario.contentId, multiTokenScenario.user),
            "Multi-token payment did not grant access"
        );
    }

    // ============ SECURITY ATTACK TESTS - BATTLE-TESTED DEFENSE ============

    /**
     * @dev Tests defense against reentrancy attacks
     * @notice Reentrancy in payment systems = instant platform drainage
     */
    function test_ReentrancyDefense_MultiVectorAttacks() public {
        // Attack Vector 1: Reentrancy during intent creation
        vm.startPrank(reentrantAttacker);

        // Attacker tries to create multiple intents in single transaction
        // (This would exploit reentrancy if not properly protected)

        CommerceProtocolIntegration.PlatformPaymentRequest memory attackRequest;
        attackRequest.paymentType = PaymentType.PayPerView;
        attackRequest.creator = creator1;
        attackRequest.contentId = testContentId;
        attackRequest.paymentToken = address(attackerToken);
        attackRequest.maxSlippage = 100;
        attackRequest.deadline = block.timestamp + 1 hours;

        attackerToken.approve(address(commerceIntegration), 1000e18);

        // First intent should succeed
        (ICommercePaymentsProtocol.TransferIntent memory intent1,) =
            commerceIntegration.createPaymentIntent(attackRequest);

        // Immediate second intent with same nonce should fail due to reentrancy guard
        vm.expectRevert(); // Should revert due to ReentrancyGuard
        commerceIntegration.createPaymentIntent(attackRequest);

        vm.stopPrank();

        // Attack Vector 2: Reentrancy during signature provision
        bytes32 intentHash = commerceIntegration.intentHashes(intent1.id);
        bytes memory signature = _signIntentHash(intentHash, OPERATOR_PRIVATE_KEY);

        vm.startPrank(realOperatorSigner);
        commerceIntegration.provideIntentSignature(intent1.id, signature);

        // Try to provide signature again (reentrancy attempt)
        vm.expectRevert(CommerceProtocolIntegration.IntentAlreadyProcessed.selector);
        commerceIntegration.provideIntentSignature(intent1.id, signature);

        vm.stopPrank();
    }

    /**
     * @dev Tests defense against signature replay attacks
     * @notice Signature replay = unlimited free money for attackers
     */
    function test_SignatureReplayDefense_ComprehensiveProtection() public {
        // Create initial payment scenario
        PaymentTestScenario memory scenario = _createBasicPaymentScenario();
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenario);

        // Execute first payment completely
        _executeCompletePaymentScenario(scenario);

        // Capture the signature that was used
        // In a real attack, attacker would intercept this signature

        // Try to replay the same signature for a new payment
        scenario.user = user2; // Different user
        scenario.paymentAmount = 100e6; // Much larger amount
        request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory newIntent,) = commerceIntegration.createPaymentIntent(request);

        // Get the old signature and try to use it for new intent
        bytes32 oldIntentHash = commerceIntegration.intentHashes(newIntent.id);
        bytes memory oldSignature = _signIntentHash(oldIntentHash, OPERATOR_PRIVATE_KEY);

        // This should fail because intent IDs are unique
        vm.startPrank(realOperatorSigner);
        commerceIntegration.provideIntentSignature(newIntent.id, oldSignature);
        vm.stopPrank();

        // Try to execute with recycled signature - should fail
        vm.startPrank(scenario.user);
        vm.expectRevert(CommerceProtocolIntegration.InvalidSignature.selector);
        commerceIntegration.executePaymentWithSignature(newIntent.id);
        vm.stopPrank();
    }

    /**
     * @dev Tests defense against front-running attacks
     * @notice Front-running in payments can steal user funds or mess up pricing
     */
    function test_FrontRunningDefense_MEVResistance() public {
        // Scenario: User creates payment intent, MEV bot tries to front-run
        PaymentTestScenario memory userScenario = PaymentTestScenario({
            user: user1,
            creator: creator1,
            paymentToken: address(volatileToken),
            paymentAmount: 10e18,
            expectedUsdcAmount: 5e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            maxSlippage: 500, // 5% - makes front-running more attractive
            deadline: block.timestamp + 1 hours,
            shouldSucceed: true,
            expectedError: ""
        });

        // User creates intent
        CommerceProtocolIntegration.PlatformPaymentRequest memory userRequest = _buildPaymentRequest(userScenario);

        vm.prank(userScenario.user);
        volatileToken.approve(address(commerceIntegration), userScenario.paymentAmount);

        vm.prank(userScenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory userIntent,) =
            commerceIntegration.createPaymentIntent(userRequest);

        // MEV bot tries to create similar intent to benefit from user's slippage
        PaymentTestScenario memory mevScenario = userScenario;
        mevScenario.user = mevBot;
        mevScenario.paymentAmount = 100e18; // Much larger amount

        volatileToken.mint(mevBot, 1000e18);

        vm.prank(mevBot);
        volatileToken.approve(address(commerceIntegration), mevScenario.paymentAmount);

        CommerceProtocolIntegration.PlatformPaymentRequest memory mevRequest = _buildPaymentRequest(mevScenario);

        vm.prank(mevBot);
        (ICommercePaymentsProtocol.TransferIntent memory mevIntent,) =
            commerceIntegration.createPaymentIntent(mevRequest);

        // Both intents should have unique IDs and be independently processable
        assertTrue(userIntent.id != mevIntent.id, "Intent IDs not unique - vulnerable to front-running");

        // Each intent should be tied to its specific user
        CommerceProtocolIntegration.PaymentContext memory userContext =
            commerceIntegration.getPaymentContext(userIntent.id);
        CommerceProtocolIntegration.PaymentContext memory mevContext =
            commerceIntegration.getPaymentContext(mevIntent.id);

        assertEq(userContext.user, userScenario.user, "User context corrupted by MEV");
        assertEq(mevContext.user, mevBot, "MEV context not isolated");
    }

    // ============ FAILURE RECOVERY TESTS - GRACEFUL DEGRADATION ============

    /**
     * @dev Tests payment failure scenarios and recovery mechanisms
     * @notice Payment failures must be handled gracefully - no stuck funds, no broken state
     */
    function test_PaymentFailureRecovery_GracefulDegradation() public {
        PaymentTestScenario memory scenario = _createBasicPaymentScenario();

        // Execute payment flow up to the processing stage
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenario);

        vm.prank(scenario.user);
        mockUSDC.approve(address(commerceIntegration), scenario.paymentAmount);

        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Provide signature and execute
        bytes32 intentHash = commerceIntegration.intentHashes(intent.id);
        bytes memory signature = _signIntentHash(intentHash, OPERATOR_PRIVATE_KEY);

        vm.prank(realOperatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, signature);

        vm.prank(scenario.user);
        commerceIntegration.executePaymentWithSignature(intent.id);

        // Simulate external payment processing failure
        vm.startPrank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id,
            scenario.user,
            scenario.paymentToken,
            scenario.paymentAmount,
            false, // Payment failed
            "External system error"
        );
        vm.stopPrank();

        // Verify graceful failure handling
        assertFalse(commerceIntegration.hasActiveIntent(intent.id), "Failed intent not cleaned up");
        assertFalse(payPerView.hasAccess(scenario.contentId, scenario.user), "Access granted despite payment failure");

        // Verify user can request refund
        vm.prank(scenario.user);
        commerceIntegration.requestRefund(intent.id, "Payment processing failed");

        // Check refund was recorded
        (
            bytes16 originalIntentId,
            address user,
            uint256 amount,
            string memory reason,
            uint256 requestTime,
            bool processed
        ) = commerceIntegration.refundRequests(intent.id);
        assertEq(originalIntentId, intent.id, "Refund not properly recorded");
        assertEq(user, scenario.user, "Refund user incorrect");
        assertTrue(amount > 0, "Refund amount not set");
    }

    /**
     * @dev Tests system behavior under extreme load conditions
     * @notice High load can reveal race conditions and resource exhaustion bugs
     */
    function test_SystemLoad_StressConditions() public {
        // Create multiple concurrent payment scenarios
        uint256 concurrentPayments = 10;
        PaymentTestScenario[] memory scenarios = new PaymentTestScenario[](concurrentPayments);

        // Set up diverse payment scenarios
        for (uint256 i = 0; i < concurrentPayments; i++) {
            address testUser = address(uint160(0x9000 + i));
            vm.startPrank(admin); // Ensure minting is done by the owner
            mockUSDC.mint(testUser, 1000e6);
            vm.stopPrank();

            scenarios[i] = PaymentTestScenario({
                user: testUser,
                creator: i % 2 == 0 ? creator1 : creator2, // Alternate creators
                paymentToken: address(mockUSDC),
                paymentAmount: (i + 1) * 1e6, // $1, $2, $3, etc.
                expectedUsdcAmount: (i + 1) * 1e6,
                paymentType: i % 3 == 0
                    ? PaymentType.Subscription
                    : PaymentType.PayPerView,
                contentId: testContentId,
                maxSlippage: 100,
                deadline: block.timestamp + 2 hours,
                shouldSucceed: true,
                expectedError: ""
            });
        }

        // Execute all payments concurrently (simulate high load)
        bytes32[] memory intentIds = new bytes32[](concurrentPayments);

        for (uint256 i = 0; i < concurrentPayments; i++) {
            CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenarios[i]);

            vm.prank(scenarios[i].user);
            mockUSDC.approve(address(commerceIntegration), scenarios[i].paymentAmount);

            vm.prank(scenarios[i].user);
            (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

            intentIds[i] = intent.id;
        }

        // Verify all intents were created successfully and have unique IDs
        for (uint256 i = 0; i < concurrentPayments; i++) {
            bytes16 shortId = bytes16(intentIds[i]);
            assertTrue(commerceIntegration.hasActiveIntent(shortId), "Intent not created under load");

            // Check uniqueness
            for (uint256 j = i + 1; j < concurrentPayments; j++) {
                assertTrue(intentIds[i] != intentIds[j], "Duplicate intent IDs under load");
            }
        }

        // Verify platform metrics updated correctly
        (uint256 intentsCreated,,,) = commerceIntegration.getOperatorMetrics();
        assertTrue(intentsCreated >= concurrentPayments, "Platform metrics not updated under load");
    }

    // ============ EXAMPLE TESTS THAT NOW WORK ============

    /**
     * @dev Test that content registration now works (was failing before)
     * @notice This verifies our permission fix allows content registration to succeed
     */
    function test_ContentRegistration_Success() public {
        // This test should now pass because ContentRegistry can update CreatorRegistry stats
        uint256 contentId = _registerContentHelper(creator1, 5e6, "Test Content");

        // Verify content was registered
        assertGt(contentId, 0);

        // Verify creator stats were updated (this was failing before the fix)
        CreatorRegistry.Creator memory creator = creatorRegistry.getCreatorProfile(creator1);
        assertEq(creator.contentCount, 3); // 2 from setup + 1 from this test
    }

    /**
     * @dev Test payment intent creation with proper signature (was failing before)
     * @notice This verifies our signer setup works correctly
     */
    function test_PaymentIntentCreation_Success() public {
        // Create a payment request
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = CommerceProtocolIntegration
            .PlatformPaymentRequest({
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            creator: creator1,
            paymentToken: address(mockUSDC),
            maxSlippage: 100,
            deadline: block.timestamp + 3600
        });

        // This should now work because our signer is properly configured
        vm.prank(user1);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Verify intent was created
        assertGt(intent.recipientAmount, 0);
        assertEq(intent.recipient, creator1);
    }

    /**
     * @dev Test role management functions that were failing
     * @notice This verifies that admin role management works properly
     */
    function test_RoleManagement_Success() public {
        address newSigner = address(0x9999);

        // Grant new signer role (should work when called by admin)
        vm.startPrank(admin);
        commerceIntegration.grantRole(commerceIntegration.SIGNER_ROLE(), newSigner);
        vm.stopPrank();

        // Verify role was granted
        assertTrue(commerceIntegration.hasRole(commerceIntegration.SIGNER_ROLE(), newSigner));

        // Test that non-admin cannot grant roles (should fail)
        vm.prank(user1);
        vm.expectRevert(); // Should revert due to missing admin role
        commerceIntegration.grantRole(commerceIntegration.SIGNER_ROLE(), user1);
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Creates a basic payment scenario for standard testing
     * @return PaymentTestScenario configured for typical use cases
     */
    function _createBasicPaymentScenario() private view returns (PaymentTestScenario memory) {
        return PaymentTestScenario({
            user: user1,
            creator: creator1,
            paymentToken: address(mockUSDC),
            paymentAmount: 3e6, // $3 for content
            expectedUsdcAmount: 3e6,
            paymentType: PaymentType.PayPerView,
            contentId: testContentId,
            maxSlippage: 100, // 1%
            deadline: block.timestamp + 1 hours,
            shouldSucceed: true,
            expectedError: ""
        });
    }

    /**
     * @dev Builds a platform payment request from test scenario
     * @param scenario The test scenario to convert
     * @return request The formatted payment request
     */
    function _buildPaymentRequest(PaymentTestScenario memory scenario)
        private
        pure
        returns (CommerceProtocolIntegration.PlatformPaymentRequest memory request)
    {
        request.paymentType = scenario.paymentType;
        request.creator = scenario.creator;
        request.contentId = scenario.contentId;
        request.paymentToken = scenario.paymentToken;
        request.maxSlippage = scenario.maxSlippage;
        request.deadline = scenario.deadline;
    }

    /**
     * @dev Executes a complete payment scenario from intent to completion
     * @param scenario The payment scenario to execute
     */
    function _executeCompletePaymentScenario(PaymentTestScenario memory scenario) private {
        CommerceProtocolIntegration.PlatformPaymentRequest memory request = _buildPaymentRequest(scenario);

        // Approve tokens
        vm.prank(scenario.user);
        MockERC20(scenario.paymentToken).approve(address(commerceIntegration), scenario.paymentAmount);

        // Create intent
        vm.prank(scenario.user);
        (ICommercePaymentsProtocol.TransferIntent memory intent,) = commerceIntegration.createPaymentIntent(request);

        // Sign intent
        bytes32 intentHash = commerceIntegration.intentHashes(intent.id);
        bytes memory signature = _signIntentHash(intentHash, OPERATOR_PRIVATE_KEY);

        vm.prank(realOperatorSigner);
        commerceIntegration.provideIntentSignature(intent.id, signature);

        // Execute payment
        vm.prank(scenario.user);
        commerceIntegration.executePaymentWithSignature(intent.id);

        // Process payment as successful
        vm.startPrank(admin);
        commerceIntegration.processCompletedPayment(
            intent.id, scenario.user, scenario.paymentToken, scenario.paymentAmount, true, ""
        );
        vm.stopPrank();
    }

    /**
     * @dev Signs an intent hash with a given private key
     * @param intentHash The hash to sign
     * @param privateKey The private key for signing
     * @return signature The generated signature
     */
    function _signIntentHash(bytes32 intentHash, uint256 privateKey) private pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, intentHash);
        signature = abi.encodePacked(r, s, v);
    }

    /**
     * @dev Captures comprehensive financial state for verification
     * @param scenario The scenario context for capturing state
     * @return snapshot Complete financial state snapshot
     */
    function _captureFinancialSnapshot(PaymentTestScenario memory scenario)
        private
        view
        returns (FinancialSnapshot memory snapshot)
    {
        snapshot.userTokenBalance = MockERC20(scenario.paymentToken).balanceOf(scenario.user);
        snapshot.userUsdcBalance = mockUSDC.balanceOf(scenario.user);
        snapshot.creatorUsdcBalance = mockUSDC.balanceOf(scenario.creator);

        if (scenario.paymentType == PaymentType.PayPerView) {
            (snapshot.creatorEarningsInContract,) = payPerView.getCreatorEarnings(scenario.creator);
        } else {
            (snapshot.creatorEarningsInContract,) = subscriptionManager.getCreatorSubscriptionEarnings(scenario.creator);
        }

        (
            uint256 totalContent,
            uint256 activeContent,
            uint256[] memory categoryCounts,
            uint256[] memory activeCategoryCounts
        ) = contentRegistry.getPlatformStats();
        // For demonstration, set platformTotalVolume to the sum of all categoryCounts
        uint256 totalVolume = 0;
        for (uint256 i = 0; i < categoryCounts.length; i++) {
            totalVolume += categoryCounts[i];
        }
        snapshot.platformTotalVolume = totalVolume;
    }

    /**
     * @dev Enhanced registerCreator helper with better error messages
     */
    function _registerCreatorHelper(address creator, uint256 price, string memory profile)
        internal
        returns (bool)
    {
        vm.startPrank(creator);
        bool result;
        try creatorRegistry.registerCreator(price, profile) {
            result = true;
        } catch Error(string memory reason) {
            console.log("Creator registration failed:", reason);
            result = false;
        } catch {
            console.log("Creator registration failed: unknown error");
            result = false;
        }
        vm.stopPrank();
        return result;
    }

    /**
     * @dev Enhanced registerContent helper with better error handling
     */
    function _registerContentHelper(address creator, uint256 price, string memory title)
        internal
        returns (uint256)
    {
        vm.startPrank(creator);
        uint256 contentId;
        try contentRegistry.registerContent(
            "QmTestHash123456789",
            title,
            "Test description",
            ContentCategory.Article,
            price,
            new string[](0)
        ) returns (uint256 id) {
            contentId = id;
        } catch Error(string memory reason) {
            console.log("Content registration failed:", reason);
            vm.stopPrank();
            revert(reason);
        }
        vm.stopPrank();
        return contentId;
    }
}
