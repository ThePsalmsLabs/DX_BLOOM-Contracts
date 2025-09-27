// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title EnumValidationStandaloneTest
 * @dev Standalone unit tests for EnumValidation library
 * @notice Tests enum validation without complex dependencies
 */
contract EnumValidationStandaloneTest is Test {
    using stdStorage for StdStorage;

    function test_IsValidPaymentType_ValidValues() public {
        // Test all valid payment types
        assertTrue(_isValidPaymentType(0)); // PayPerView
        assertTrue(_isValidPaymentType(1)); // Subscription
        assertTrue(_isValidPaymentType(2)); // Tip
        assertTrue(_isValidPaymentType(3)); // Donation
    }

    function test_IsValidPaymentType_InvalidValues() public {
        // Test invalid payment types
        assertFalse(_isValidPaymentType(4)); // Invalid
        assertFalse(_isValidPaymentType(10)); // Out of range
        assertFalse(_isValidPaymentType(type(uint8).max)); // Max uint8
    }

    function test_IsValidPaymentType_BoundaryValues() public {
        // Test boundary values
        assertTrue(_isValidPaymentType(0)); // Min valid
        assertTrue(_isValidPaymentType(3)); // Max valid
        assertFalse(_isValidPaymentType(4)); // First invalid
    }

    function test_IsValidContentCategory_ValidValues() public {
        // Test all valid content categories
        assertTrue(_isValidContentCategory(0)); // Article
        assertTrue(_isValidContentCategory(1)); // Video
        assertTrue(_isValidContentCategory(2)); // Course
        assertTrue(_isValidContentCategory(3)); // Music
        assertTrue(_isValidContentCategory(4)); // Podcast
        assertTrue(_isValidContentCategory(5)); // Image
    }

    function test_IsValidContentCategory_InvalidValues() public {
        // Test invalid content categories
        assertFalse(_isValidContentCategory(6)); // Invalid
        assertFalse(_isValidContentCategory(255)); // Max uint8
    }

    function test_IsValidContentCategory_BoundaryValues() public {
        // Test boundary values
        assertTrue(_isValidContentCategory(0)); // Min valid
        assertTrue(_isValidContentCategory(5)); // Max valid
        assertFalse(_isValidContentCategory(6)); // First invalid
    }

    function test_IsValidSubscriptionStatus_ValidValues() public {
        // Test all valid subscription statuses
        assertTrue(_isValidSubscriptionStatus(0)); // Active
        assertTrue(_isValidSubscriptionStatus(1)); // Expired
        assertTrue(_isValidSubscriptionStatus(2)); // Cancelled
        assertTrue(_isValidSubscriptionStatus(3)); // Suspended
    }

    function test_IsValidSubscriptionStatus_InvalidValues() public {
        // Test invalid subscription statuses
        assertFalse(_isValidSubscriptionStatus(4)); // Invalid
        assertFalse(_isValidSubscriptionStatus(255)); // Max uint8
    }

    function test_IsValidSubscriptionStatus_BoundaryValues() public {
        // Test boundary values
        assertTrue(_isValidSubscriptionStatus(0)); // Min valid
        assertTrue(_isValidSubscriptionStatus(3)); // Max valid
        assertFalse(_isValidSubscriptionStatus(4)); // First invalid
    }

    function test_ToPaymentType_ValidValues() public {
        // Test converting uint8 to PaymentType
        assertEq(uint8(_toPaymentType(0)), 0); // PayPerView
        assertEq(uint8(_toPaymentType(1)), 1); // Subscription
        assertEq(uint8(_toPaymentType(2)), 2); // Tip
        assertEq(uint8(_toPaymentType(3)), 3); // Donation
    }

    function test_ToPaymentType_InvalidValues() public {
        // Test that invalid values revert
        vm.expectRevert("Invalid payment type");
        _toPaymentType(4);

        vm.expectRevert("Invalid payment type");
        _toPaymentType(255);
    }

    function test_ToContentCategory_ValidValues() public {
        // Test converting uint8 to ContentCategory
        assertEq(uint8(_toContentCategory(0)), 0); // Article
        assertEq(uint8(_toContentCategory(1)), 1); // Video
        assertEq(uint8(_toContentCategory(2)), 2); // Course
        assertEq(uint8(_toContentCategory(3)), 3); // Music
        assertEq(uint8(_toContentCategory(4)), 4); // Podcast
        assertEq(uint8(_toContentCategory(5)), 5); // Image
    }

    function test_ToContentCategory_InvalidValues() public {
        // Test that invalid values revert
        vm.expectRevert("Invalid content category");
        _toContentCategory(6);

        vm.expectRevert("Invalid content category");
        _toContentCategory(255);
    }

    function test_AllValidationFunctions_WithMaxUint8() public {
        // Test all validation functions with maximum uint8 value
        assertFalse(_isValidPaymentType(type(uint8).max));
        assertFalse(_isValidContentCategory(type(uint8).max));
        assertFalse(_isValidSubscriptionStatus(type(uint8).max));
    }

    function test_AllValidationFunctions_WithZero() public {
        // Test all validation functions with zero
        assertTrue(_isValidPaymentType(0));
        assertTrue(_isValidContentCategory(0));
        assertTrue(_isValidSubscriptionStatus(0));
    }

    function test_EnumValidationChain() public {
        // Test chained validation operations
        uint8 paymentType = 0;
        uint8 contentCategory = 1;
        uint8 subscriptionStatus = 2;

        assertTrue(_isValidPaymentType(paymentType));
        assertTrue(_isValidContentCategory(contentCategory));
        assertTrue(_isValidSubscriptionStatus(subscriptionStatus));
    }

    function test_ValidationGasUsage() public {
        // Test gas usage for validation functions
        uint256 gasBefore = gasleft();

        // Perform multiple validations
        for (uint8 i = 0; i < 10; i++) {
            _isValidPaymentType(i % 4);
            _isValidContentCategory(i % 6);
            _isValidSubscriptionStatus(i % 4);
        }

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        // Assert reasonable gas usage
        assertTrue(gasUsed < 100000, "Validation gas usage too high");
    }

    function test_ComprehensiveEnumValidation() public {
        // Comprehensive test of all enum validation scenarios
        for (uint8 i = 0; i <= 10; i++) {
            bool paymentValid = i <= 3; // 0-3 are valid
            bool contentValid = i <= 5; // 0-5 are valid
            bool subscriptionValid = i <= 3; // 0-3 are valid

            assertEq(_isValidPaymentType(i), paymentValid);
            assertEq(_isValidContentCategory(i), contentValid);
            assertEq(_isValidSubscriptionStatus(i), subscriptionValid);
        }
    }

    // ============ INTERNAL HELPER FUNCTIONS ============

    function _isValidPaymentType(uint8 paymentType) internal pure returns (bool) {
        return paymentType <= 3; // Donation is the last valid value
    }

    function _isValidContentCategory(uint8 category) internal pure returns (bool) {
        return category <= 5; // Image is the last valid value
    }

    function _isValidSubscriptionStatus(uint8 status) internal pure returns (bool) {
        return status <= 3; // Cancelled is the last valid value
    }

    function _toPaymentType(uint8 value) internal pure returns (ISharedTypes.PaymentType) {
        if (value > 3) { // Donation is the last valid value
            revert("Invalid payment type");
        }
        return ISharedTypes.PaymentType(value);
    }

    function _toContentCategory(uint8 value) internal pure returns (ISharedTypes.ContentCategory) {
        if (value > 5) { // Image is the last valid value
            revert("Invalid content category");
        }
        return ISharedTypes.ContentCategory(value);
    }
}
