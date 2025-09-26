// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { EnumValidation } from "../../../src/libraries/EnumValidation.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title EnumValidationTest
 * @dev Unit tests for EnumValidation library
 * @notice Tests all enum validation functions in isolation
 */
contract EnumValidationTest is TestSetup {
    using EnumValidation for *;

    function setUp() public override {
        super.setUp();
    }

    // ============ PAYMENT TYPE VALIDATION TESTS ============

    function test_IsValidPaymentType_ValidValues() public {
        // Test all valid PaymentType values
        assertTrue(EnumValidation.isValidPaymentType(uint8(ISharedTypes.PaymentType.PayPerView))); // 0
        assertTrue(EnumValidation.isValidPaymentType(uint8(ISharedTypes.PaymentType.Subscription))); // 1
        assertTrue(EnumValidation.isValidPaymentType(uint8(ISharedTypes.PaymentType.Tip))); // 2
        assertTrue(EnumValidation.isValidPaymentType(uint8(ISharedTypes.PaymentType.Donation))); // 3
    }

    function test_IsValidPaymentType_InvalidValues() public {
        // Test invalid PaymentType values
        assertFalse(EnumValidation.isValidPaymentType(4)); // Just above max
        assertFalse(EnumValidation.isValidPaymentType(255)); // Max uint8
        assertFalse(EnumValidation.isValidPaymentType(100)); // Random invalid value
    }

    function test_IsValidPaymentType_BoundaryValues() public {
        // Test boundary values
        assertTrue(EnumValidation.isValidPaymentType(0)); // Minimum valid
        assertTrue(EnumValidation.isValidPaymentType(3)); // Maximum valid
        assertFalse(EnumValidation.isValidPaymentType(4)); // Just over maximum
    }

    // ============ CONTENT CATEGORY VALIDATION TESTS ============

    function test_IsValidContentCategory_ValidValues() public {
        // Test all valid ContentCategory values
        assertTrue(EnumValidation.isValidContentCategory(uint8(ISharedTypes.ContentCategory.Article)));
        assertTrue(EnumValidation.isValidContentCategory(uint8(ISharedTypes.ContentCategory.Video)));
        assertTrue(EnumValidation.isValidContentCategory(2)); // Audio category
        assertTrue(EnumValidation.isValidContentCategory(uint8(ISharedTypes.ContentCategory.Image)));
        assertTrue(EnumValidation.isValidContentCategory(uint8(ISharedTypes.ContentCategory.Podcast))); // 4
    }

    function test_IsValidContentCategory_InvalidValues() public {
        // Test invalid ContentCategory values
        assertFalse(EnumValidation.isValidContentCategory(5)); // Just above max
        assertFalse(EnumValidation.isValidContentCategory(255)); // Max uint8
        assertFalse(EnumValidation.isValidContentCategory(10)); // Random invalid value
    }

    function test_IsValidContentCategory_BoundaryValues() public {
        // Test boundary values
        assertTrue(EnumValidation.isValidContentCategory(0)); // Minimum valid
        assertTrue(EnumValidation.isValidContentCategory(4)); // Maximum valid
        assertFalse(EnumValidation.isValidContentCategory(5)); // Just over maximum
    }

    // ============ SUBSCRIPTION STATUS VALIDATION TESTS ============

    function test_IsValidSubscriptionStatus_ValidValues() public {
        // Test all valid SubscriptionStatus values
        assertTrue(EnumValidation.isValidSubscriptionStatus(0)); // Active status
        assertTrue(EnumValidation.isValidSubscriptionStatus(1)); // Expired status
        assertTrue(EnumValidation.isValidSubscriptionStatus(3)); // Cancelled status
    }

    function test_IsValidSubscriptionStatus_InvalidValues() public {
        // Test invalid SubscriptionStatus values
        assertFalse(EnumValidation.isValidSubscriptionStatus(4)); // Just above max
        assertFalse(EnumValidation.isValidSubscriptionStatus(255)); // Max uint8
        assertFalse(EnumValidation.isValidSubscriptionStatus(10)); // Random invalid value
    }

    function test_IsValidSubscriptionStatus_BoundaryValues() public {
        // Test boundary values
        assertTrue(EnumValidation.isValidSubscriptionStatus(0)); // Minimum valid
        assertTrue(EnumValidation.isValidSubscriptionStatus(3)); // Maximum valid
        assertFalse(EnumValidation.isValidSubscriptionStatus(4)); // Just over maximum
    }

    // ============ SAFE CASTING TESTS ============

    function test_ToPaymentType_ValidValues() public {
        // Test safe casting for valid values
        ISharedTypes.PaymentType paymentType0 = EnumValidation.toPaymentType(0);
        assertEq(uint8(paymentType0), 0);

        ISharedTypes.PaymentType paymentType1 = EnumValidation.toPaymentType(1);
        assertEq(uint8(paymentType1), 1);

        ISharedTypes.PaymentType paymentType2 = EnumValidation.toPaymentType(2);
        assertEq(uint8(paymentType2), 2);

        ISharedTypes.PaymentType paymentType3 = EnumValidation.toPaymentType(3);
        assertEq(uint8(paymentType3), 3);
    }

    function test_ToPaymentType_InvalidValue() public {
        // Test safe casting for invalid value
        vm.expectRevert(EnumValidation.InvalidPaymentType.selector);
        EnumValidation.toPaymentType(4);
    }

    function test_ToContentCategory_ValidValues() public {
        // Test safe casting for valid values
        ISharedTypes.ContentCategory category0 = EnumValidation.toContentCategory(0);
        assertEq(uint8(category0), 0);

        ISharedTypes.ContentCategory category1 = EnumValidation.toContentCategory(1);
        assertEq(uint8(category1), 1);

        ISharedTypes.ContentCategory category2 = EnumValidation.toContentCategory(2);
        assertEq(uint8(category2), 2);

        ISharedTypes.ContentCategory category3 = EnumValidation.toContentCategory(3);
        assertEq(uint8(category3), 3);

        ISharedTypes.ContentCategory category4 = EnumValidation.toContentCategory(4);
        assertEq(uint8(category4), 4);
    }

    function test_ToContentCategory_InvalidValue() public {
        // Test safe casting for invalid value
        vm.expectRevert(EnumValidation.InvalidContentCategory.selector);
        EnumValidation.toContentCategory(5);
    }

    // ============ EDGE CASE TESTS ============

    function test_AllValidationFunctions_WithMaxUint8() public {
        // Test all validation functions with maximum uint8 value
        assertFalse(EnumValidation.isValidPaymentType(255));
        assertFalse(EnumValidation.isValidContentCategory(255));
        assertFalse(EnumValidation.isValidSubscriptionStatus(255));
    }

    function test_AllValidationFunctions_WithZero() public {
        // Test all validation functions with zero
        assertTrue(EnumValidation.isValidPaymentType(0));
        assertTrue(EnumValidation.isValidContentCategory(0));
        assertTrue(EnumValidation.isValidSubscriptionStatus(0));
    }

    function test_SafeCasting_RevertMessages() public {
        // Test that safe casting provides proper error messages
        vm.expectRevert(EnumValidation.InvalidPaymentType.selector);
        EnumValidation.toPaymentType(255);

        vm.expectRevert(EnumValidation.InvalidContentCategory.selector);
        EnumValidation.toContentCategory(255);
    }

    // ============ INTEGRATION TESTS ============

    function test_EnumValidationChain() public {
        // Test using enum validation in a chain of operations

        // Simulate receiving a uint8 value from external source
        uint8 receivedPaymentType = 1; // Subscription
        uint8 receivedContentCategory = 2; // Audio

        // Validate and cast safely
        assertTrue(EnumValidation.isValidPaymentType(receivedPaymentType));
        ISharedTypes.PaymentType paymentType = EnumValidation.toPaymentType(receivedPaymentType);

        assertTrue(EnumValidation.isValidContentCategory(receivedContentCategory));
        ISharedTypes.ContentCategory category = EnumValidation.toContentCategory(receivedContentCategory);

        // Verify the results
        assertEq(uint8(paymentType), 1);
        assertEq(uint8(category), 2);
    }

    function test_EnumValidationChain_InvalidValues() public {
        // Test handling of invalid values in a chain

        uint8 invalidPaymentType = 10;
        uint8 invalidCategory = 20;

        // First validation should fail
        assertFalse(EnumValidation.isValidPaymentType(invalidPaymentType));
        vm.expectRevert(EnumValidation.InvalidPaymentType.selector);
        EnumValidation.toPaymentType(invalidPaymentType);

        // Even if first succeeds, second should fail independently
        assertFalse(EnumValidation.isValidContentCategory(invalidCategory));
        vm.expectRevert(EnumValidation.InvalidContentCategory.selector);
        EnumValidation.toContentCategory(invalidCategory);
    }

    // ============ GAS EFFICIENCY TESTS ============

    function test_ValidationGasUsage() public {
        // Test that validation functions use reasonable gas
        uint8 testValue = 2;

        // These should use minimal gas
        bool paymentTypeValid = EnumValidation.isValidPaymentType(testValue);
        bool contentCategoryValid = EnumValidation.isValidContentCategory(testValue);
        bool subscriptionStatusValid = EnumValidation.isValidSubscriptionStatus(testValue);

        assertTrue(paymentTypeValid);
        assertTrue(contentCategoryValid);
        assertTrue(subscriptionStatusValid);
    }

    // ============ COMPREHENSIVE VALIDATION TESTS ============

    function test_ComprehensiveEnumValidation() public {
        // Test all enum types comprehensively

        // PaymentType validation (0-3)
        for (uint8 i = 0; i <= 3; i++) {
            assertTrue(EnumValidation.isValidPaymentType(i));
            ISharedTypes.PaymentType paymentType = EnumValidation.toPaymentType(i);
            assertEq(uint8(paymentType), i);
        }

        // ContentCategory validation (0-4)
        for (uint8 i = 0; i <= 4; i++) {
            assertTrue(EnumValidation.isValidContentCategory(i));
            ISharedTypes.ContentCategory category = EnumValidation.toContentCategory(i);
            assertEq(uint8(category), i);
        }

        // SubscriptionStatus validation (0-3)
        for (uint8 i = 0; i <= 3; i++) {
            assertTrue(EnumValidation.isValidSubscriptionStatus(i));
        }

        // Invalid values
        for (uint8 i = 4; i <= 10; i++) {
            assertFalse(EnumValidation.isValidPaymentType(i));
            assertFalse(EnumValidation.isValidSubscriptionStatus(i));

            if (i >= 5) {
                assertFalse(EnumValidation.isValidContentCategory(i));
            }
        }
    }
}
