// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { ViewManager } from "../../../src/ViewManager.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";
import { ISignatureTransfer } from "../../../src/interfaces/IPlatformInterfaces.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockCommerceProtocol } from "../../mocks/MockCommerceProtocol.sol";

/**
 * @title ViewManagerTest
 * @dev Unit tests for ViewManager contract - Read-only functions tests
 * @notice Tests utility functions, permit management, metrics, and validation
 */
contract ViewManagerTest is TestSetup {
    // Test contracts
    ViewManager public testViewManager;
    MockCommerceProtocol public testMockCommerceProtocol;

    // Test data
    address testUser = address(0x1234);
    address testOperator = address(0x5678);
    uint256 testNonce = 42;
    bytes32 testDomainSeparator = keccak256("test-domain-separator");

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testMockCommerceProtocol = new MockCommerceProtocol();
        testViewManager = new ViewManager(address(testMockCommerceProtocol));

        // Set up mock responses
        testMockCommerceProtocol.setNonce(testUser, testNonce);
        // Note: setDomainSeparator doesn't exist in MockCommerceProtocol, skipping
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidSetup() public {
        // Test that constructor sets up correctly
        // ViewManager has no state variables, so just verify it deploys
        assertTrue(address(testViewManager) != address(0));
    }

    // ============ PERMIT FUNCTIONS TESTS ============

    function test_GetPermitNonce_ValidUser() public {
        // Test getting permit nonce for valid user
        uint256 nonce = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), testUser);

        assertEq(nonce, testNonce);
    }

    function test_GetPermitNonce_ZeroAddress() public {
        // Test getting permit nonce for zero address
        uint256 nonce = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), address(0));

        assertEq(nonce, 0); // Should return 0 for zero address in mock
    }

    function test_GetPermitNonce_MultipleCalls() public {
        // Test that nonce is consistent across multiple calls
        uint256 nonce1 = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), testUser);
        uint256 nonce2 = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), testUser);

        assertEq(nonce1, nonce2);
        assertEq(nonce1, testNonce);
    }

    function test_GetPermitDomainSeparator_ValidContract() public {
        // Test getting permit domain separator
        bytes32 domainSeparator = testViewManager.getPermitDomainSeparator(ISignatureTransfer(testMockCommerceProtocol));

        assertEq(domainSeparator, testDomainSeparator);
    }

    function test_GetPermitDomainSeparator_ZeroAddress() public {
        // Test getting domain separator with zero address contract
        // This should revert since the contract doesn't exist
        vm.expectRevert();
        testViewManager.getPermitDomainSeparator(ISignatureTransfer(address(0)));
    }

    // ============ METRICS FUNCTIONS TESTS ============

    function test_GetOperatorMetrics_ValidData() public {
        // Test getting operator metrics with valid data
        uint256 totalIntents = 100;
        uint256 totalPayments = 95;
        uint256 totalFees = 5e6; // 5 USDC
        uint256 totalRefunds = 2;

        (uint256 intents, uint256 payments, uint256 fees, uint256 refunds) = testViewManager.getOperatorMetrics(
            totalIntents,
            totalPayments,
            totalFees,
            totalRefunds
        );

        assertEq(intents, totalIntents);
        assertEq(payments, totalPayments);
        assertEq(fees, totalFees);
        assertEq(refunds, totalRefunds);
    }

    function test_GetOperatorMetrics_ZeroValues() public {
        // Test getting operator metrics with zero values
        (uint256 intents, uint256 payments, uint256 fees, uint256 refunds) = testViewManager.getOperatorMetrics(
            0, 0, 0, 0
        );

        assertEq(intents, 0);
        assertEq(payments, 0);
        assertEq(fees, 0);
        assertEq(refunds, 0);
    }

    function test_GetOperatorMetrics_LargeValues() public {
        // Test getting operator metrics with large values
        uint256 maxValue = type(uint256).max;

        (uint256 intents, uint256 payments, uint256 fees, uint256 refunds) = testViewManager.getOperatorMetrics(
            maxValue, maxValue, maxValue, maxValue
        );

        assertEq(intents, maxValue);
        assertEq(payments, maxValue);
        assertEq(fees, maxValue);
        assertEq(refunds, maxValue);
    }

    // ============ PAYMENT TYPE VALIDATION TESTS ============

    function test_ValidatePaymentType_ValidTypes() public {
        // Test validation of valid payment types
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.PayPerView));
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.Subscription));
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.Tip));
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.Donation));
    }

    function test_ValidatePaymentType_InvalidType() public {
        // Test validation of invalid payment type (beyond enum range)
        ISharedTypes.PaymentType invalidType = ISharedTypes.PaymentType(uint8(255)); // Invalid value

        assertFalse(testViewManager.validatePaymentType(invalidType));
    }

    // ============ PAYMENT TYPE NAME TESTS ============

    function test_GetPaymentTypeName_ValidTypes() public {
        // Test getting names for valid payment types
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.PayPerView), "PayPerView");
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Subscription), "Subscription");
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Tip), "Tip");
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Donation), "Donation");
    }

    function test_GetPaymentTypeName_InvalidType() public {
        // Test getting name for invalid payment type
        ISharedTypes.PaymentType invalidType = ISharedTypes.PaymentType(uint8(255));

        assertEq(testViewManager.getPaymentTypeName(invalidType), "Unknown");
    }

    // ============ OPERATOR STATUS TESTS ============

    function test_GetOperatorStatus_Registered() public {
        // Test getting operator status when registered
        (bool registered, address feeDestination) = testViewManager.getOperatorStatus();

        // Should return placeholder values as implemented
        assertTrue(registered);
        assertEq(feeDestination, address(0));
    }

    function test_GetOperatorStatus_MultipleCalls() public {
        // Test that operator status is consistent across multiple calls
        (bool registered1, address feeDestination1) = testViewManager.getOperatorStatus();
        (bool registered2, address feeDestination2) = testViewManager.getOperatorStatus();

        assertEq(registered1, registered2);
        assertEq(feeDestination1, feeDestination2);
    }

    // ============ EDGE CASE TESTS ============

    function test_GetPermitNonce_AfterNonceChange() public {
        // Test nonce retrieval when nonce changes (simulated by updating mock)
        uint256 newNonce = 123;
        testMockCommerceProtocol.setNonce(testUser, newNonce);

        uint256 retrievedNonce = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), testUser);

        assertEq(retrievedNonce, newNonce);
    }

    function test_GetPermitDomainSeparator_Consistency() public {
        // Test domain separator consistency across multiple calls
        bytes32 separator1 = testViewManager.getPermitDomainSeparator(ISignatureTransfer(testMockCommerceProtocol));
        bytes32 separator2 = testViewManager.getPermitDomainSeparator(ISignatureTransfer(testMockCommerceProtocol));

        assertEq(separator1, separator2);
        assertEq(separator1, testDomainSeparator);
    }

    function test_ValidatePaymentType_EnumBoundaries() public {
        // Test validation at enum boundaries
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(0)))); // First enum value
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(3)))); // Last valid enum value

        // Values beyond enum should be invalid
        assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(4))));
        assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(10))));
        assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(100))));
    }

    function test_GetPaymentTypeName_AllTypes() public {
        // Test name retrieval for all defined payment types
        string memory name0 = testViewManager.getPaymentTypeName(ISharedTypes.PaymentType(uint8(0)));
        string memory name1 = testViewManager.getPaymentTypeName(ISharedTypes.PaymentType(uint8(1)));
        string memory name2 = testViewManager.getPaymentTypeName(ISharedTypes.PaymentType(uint8(2)));
        string memory name3 = testViewManager.getPaymentTypeName(ISharedTypes.PaymentType(uint8(3)));

        // Should return proper names, not "Unknown"
        assertNotEq(name0, "Unknown");
        assertNotEq(name1, "Unknown");
        assertNotEq(name2, "Unknown");
        assertNotEq(name3, "Unknown");

        // Verify specific names
        assertEq(name0, "PayPerView");
        assertEq(name1, "Subscription");
        assertEq(name2, "Tip");
        assertEq(name3, "Donation");
    }

    // ============ INTEGRATION TESTS ============

    function test_FullViewManagerWorkflow() public {
        // Test a complete workflow using ViewManager functions

        // 1. Get permit nonce
        uint256 nonce = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), testUser);
        assertEq(nonce, testNonce);

        // 2. Get domain separator
        bytes32 domainSep = testViewManager.getPermitDomainSeparator(ISignatureTransfer(testMockCommerceProtocol));
        assertEq(domainSep, testDomainSeparator);

        // 3. Get operator metrics
        (uint256 intents, uint256 payments, uint256 fees, uint256 refunds) = testViewManager.getOperatorMetrics(
            100, 95, 5e6, 2
        );
        assertEq(intents, 100);
        assertEq(payments, 95);
        assertEq(fees, 5e6);
        assertEq(refunds, 2);

        // 4. Validate payment types
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.PayPerView));
        assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType.Subscription));

        // 5. Get payment type names
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.PayPerView), "PayPerView");
        assertEq(testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Tip), "Tip");

        // 6. Get operator status
        (bool registered, address feeDest) = testViewManager.getOperatorStatus();
        assertTrue(registered);
        assertEq(feeDest, address(0));
    }

    function test_PaymentTypeValidationScenarios() public {
        // Test various payment type validation scenarios

        // Valid types
        for (uint8 i = 0; i <= uint8(ISharedTypes.PaymentType.Donation); i++) {
            assertTrue(testViewManager.validatePaymentType(ISharedTypes.PaymentType(i)));
        }

        // Invalid types (beyond enum)
        for (uint8 i = uint8(ISharedTypes.PaymentType.Donation) + 1; i < 10; i++) {
            assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(i)));
        }

        // Test with very high invalid values
        assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(255))));
        assertFalse(testViewManager.validatePaymentType(ISharedTypes.PaymentType(uint8(200))));
    }

    function test_NameGenerationForAllTypes() public {
        // Test name generation for all valid payment types
        ISharedTypes.PaymentType[] memory types = new ISharedTypes.PaymentType[](4);
        types[0] = ISharedTypes.PaymentType.PayPerView;
        types[1] = ISharedTypes.PaymentType.Subscription;
        types[2] = ISharedTypes.PaymentType.Tip;
        types[3] = ISharedTypes.PaymentType.Donation;

        string[4] memory expectedNames = ["PayPerView", "Subscription", "Tip", "Donation"];

        for (uint256 i = 0; i < types.length; i++) {
            string memory actualName = testViewManager.getPaymentTypeName(types[i]);
            assertEq(actualName, expectedNames[i]);
        }

        // Test invalid type
        ISharedTypes.PaymentType invalidType = ISharedTypes.PaymentType(uint8(99));
        assertEq(testViewManager.getPaymentTypeName(invalidType), "Unknown");
    }

    // ============ FUZZING TESTS ============

    function testFuzz_GetOperatorMetrics_ValidInputs(
        uint256 intents,
        uint256 payments,
        uint256 fees,
        uint256 refunds
    ) public {
        // Test metrics function with fuzzed inputs
        (uint256 returnedIntents, uint256 returnedPayments, uint256 returnedFees, uint256 returnedRefunds) = testViewManager.getOperatorMetrics(
            intents, payments, fees, refunds
        );

        assertEq(returnedIntents, intents);
        assertEq(returnedPayments, payments);
        assertEq(returnedFees, fees);
        assertEq(returnedRefunds, refunds);
    }

    function testFuzz_ValidatePaymentType_EnumValues(uint8 paymentTypeValue) public {
        // Test payment type validation with fuzzed enum values
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType(paymentTypeValue);

        bool isValid = testViewManager.validatePaymentType(paymentType);

        // Should be valid only for values within the enum range
        if (paymentTypeValue <= uint8(ISharedTypes.PaymentType.Donation)) {
            assertTrue(isValid);
        } else {
            assertFalse(isValid);
        }
    }

    function testFuzz_GetPaymentTypeName_EnumValues(uint8 paymentTypeValue) public {
        // Test payment type name with fuzzed enum values
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType(paymentTypeValue);

        string memory name = testViewManager.getPaymentTypeName(paymentType);

        // Should return "Unknown" for invalid values, proper names for valid ones
        if (paymentTypeValue <= uint8(ISharedTypes.PaymentType.Donation)) {
            assertNotEq(name, "Unknown");
            assert(bytes(name).length > 0);
        } else {
            assertEq(name, "Unknown");
        }
    }

    function testFuzz_GetPermitNonce_AnyAddress(address user) public {
        // Test permit nonce retrieval with fuzzed addresses
        uint256 nonce = testViewManager.getPermitNonce(ISignatureTransfer(testMockCommerceProtocol), user);

        // Should handle any address (including zero, contracts, etc.)
        assertTrue(nonce >= 0); // Nonce should always be >= 0
    }

    // ============ GAS OPTIMIZATION TESTS ============

    function test_GasEfficiency_MultipleCalls() public {
        // Test gas efficiency for multiple view function calls
        uint256 gasBefore = gasleft();

        // Multiple view calls in sequence
        testViewManager.getOperatorStatus();
        testViewManager.validatePaymentType(ISharedTypes.PaymentType.PayPerView);
        testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Subscription);
        testViewManager.getOperatorMetrics(1, 2, 3, 4);

        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (less than 100,000 gas for these view calls)
        assertTrue(gasUsed < 100000, "Gas usage should be reasonable for view functions");
    }

    function test_PureFunctionEfficiency() public {
        // Test that pure functions (no state access) are gas efficient
        uint256 gasBefore = gasleft();

        // Call multiple pure functions
        testViewManager.validatePaymentType(ISharedTypes.PaymentType.PayPerView);
        testViewManager.getPaymentTypeName(ISharedTypes.PaymentType.Tip);
        testViewManager.getOperatorMetrics(100, 200, 300, 400);

        uint256 gasUsed = gasBefore - gasleft();

        // Pure functions should be very gas efficient
        assertTrue(gasUsed < 50000, "Pure functions should be very gas efficient");
    }
}
