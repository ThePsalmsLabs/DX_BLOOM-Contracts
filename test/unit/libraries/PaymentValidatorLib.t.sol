// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { PaymentValidatorLib } from "../../../src/libraries/PaymentValidatorLib.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title PaymentValidatorLibTest
 * @dev Unit tests for PaymentValidatorLib
 * @notice Tests all validation functions in isolation
 */
contract PaymentValidatorLibTest is TestSetup {
    using PaymentValidatorLib for *;

    // Test data
    PaymentValidatorLib.PlatformPaymentRequest testRequest;
    PaymentValidatorLib.CreatorValidationData testCreatorData;
    PaymentValidatorLib.ContentValidationData testContentData;

    function setUp() public override {
        super.setUp();

        // Set up test request
        testRequest = PaymentValidatorLib.PlatformPaymentRequest({
            paymentType: PaymentValidatorLib.PaymentType.PayPerView,
            creator: creator1,
            contentId: 1,
            paymentToken: address(mockUSDC),
            maxSlippage: 100, // 1%
            deadline: block.timestamp + 3600
        });

        // Set up test creator data
        testCreatorData = PaymentValidatorLib.CreatorValidationData({
            isRegistered: true,
            isActive: true,
            subscriptionPrice: 1e6 // $1.00
        });

        // Set up test content data
        testContentData = PaymentValidatorLib.ContentValidationData({
            creator: creator1,
            isActive: true,
            payPerViewPrice: 0.1e6 // $0.10
        });
    }

    // ============ PAYMENT REQUEST VALIDATION TESTS ============

    function test_ValidatePaymentRequest_ValidRequest() public {
        // Test valid PayPerView request
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidatePaymentRequest_InvalidPaymentType() public {
        // Test invalid payment type
        testRequest.paymentType = PaymentValidatorLib.PaymentType(uint8(4)); // Invalid payment type

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 1); // InvalidPaymentType
    }

    function test_ValidatePaymentRequest_InvalidCreator() public {
        // Test unregistered creator
        testCreatorData.isRegistered = false;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 2); // InvalidCreator
    }

    function test_ValidatePaymentRequest_InactiveCreator() public {
        // Test inactive creator
        testCreatorData.isActive = false;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 2); // InvalidCreator
    }

    function test_ValidatePaymentRequest_ExpiredDeadline() public {
        // Test expired deadline
        testRequest.deadline = block.timestamp - 1;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 3); // DeadlineExpired
    }

    function test_ValidatePaymentRequest_InvalidContentId() public {
        // Test PayPerView without content ID
        testRequest.contentId = 0;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 4); // InvalidPaymentRequest
    }

    function test_ValidatePaymentRequest_InvalidContent() public {
        // Test content from wrong creator
        testContentData.creator = creator2;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 5); // InvalidContent
    }

    function test_ValidatePaymentRequest_InactiveContent() public {
        // Test inactive content
        testContentData.isActive = false;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 5); // InvalidContent
    }

    function test_ValidatePaymentRequest_InvalidPaymentToken() public {
        // Test subscription without payment token
        testRequest.paymentType = PaymentValidatorLib.PaymentType.Subscription;
        testRequest.paymentToken = address(0);

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertFalse(isValid);
        assertEq(errorCode, 4); // InvalidPaymentRequest
    }

    // ============ EXECUTION CONTEXT VALIDATION TESTS ============

    function test_ValidateExecutionContext_ValidContext() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            user1, // contextUser
            block.timestamp + 3600, // deadline
            true, // hasSignature
            false // isProcessed
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidateExecutionContext_IntentNotFound() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            address(0), // contextUser - not found
            block.timestamp + 3600, // deadline
            true, // hasSignature
            false // isProcessed
        );

        assertFalse(isValid);
        assertEq(errorCode, 6); // IntentNotFound
    }

    function test_ValidateExecutionContext_NotIntentCreator() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            user2, // contextUser - different user
            block.timestamp + 3600, // deadline
            true, // hasSignature
            false // isProcessed
        );

        assertFalse(isValid);
        assertEq(errorCode, 7); // NotIntentCreator
    }

    function test_ValidateExecutionContext_IntentAlreadyProcessed() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            user1, // contextUser
            block.timestamp + 3600, // deadline
            true, // hasSignature
            true // isProcessed - already processed
        );

        assertFalse(isValid);
        assertEq(errorCode, 8); // IntentAlreadyProcessed
    }

    function test_ValidateExecutionContext_IntentExpired() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            user1, // contextUser
            block.timestamp - 1, // deadline - expired
            true, // hasSignature
            false // isProcessed
        );

        assertFalse(isValid);
        assertEq(errorCode, 3); // IntentExpired
    }

    function test_ValidateExecutionContext_NoOperatorSignature() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0), // intentId
            user1, // user
            user1, // contextUser
            block.timestamp + 3600, // deadline
            false, // hasSignature - no signature
            false // isProcessed
        );

        assertFalse(isValid);
        assertEq(errorCode, 9); // NoOperatorSignature
    }

    // ============ PAYMENT AMOUNTS VALIDATION TESTS ============

    function test_ValidatePaymentAmounts_ValidAmounts() public {
        uint256 totalAmount = 1000e6; // $1000
        uint256 creatorAmount = 900e6; // $900
        uint256 platformFee = 90e6; // $90
        uint256 operatorFee = 10e6; // $10

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentAmounts(
            totalAmount,
            creatorAmount,
            platformFee,
            operatorFee
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidatePaymentAmounts_ZeroAmount() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentAmounts(
            0, // totalAmount - zero
            900e6,
            90e6,
            10e6
        );

        assertFalse(isValid);
        assertEq(errorCode, 10); // ZeroAmount
    }

    function test_ValidatePaymentAmounts_ZeroCreatorAmount() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentAmounts(
            1000e6,
            0, // creatorAmount - zero
            90e6,
            10e6
        );

        assertFalse(isValid);
        assertEq(errorCode, 11); // ZeroCreatorAmount
    }

    function test_ValidatePaymentAmounts_FeeExceedsAmount() public {
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentAmounts(
            1000e6,
            1000e6, // creatorAmount
            90e6, // platformFee
            20e6 // operatorFee - fees exceed creator amount
        );

        assertFalse(isValid);
        assertEq(errorCode, 12); // FeeExceedsAmount
    }

    function test_ValidatePaymentAmounts_AmountMismatch() public {
        // Test where total calculation doesn't match
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentAmounts(
            1000e6, // totalAmount
            800e6, // creatorAmount - should be 900e6 for correct calculation
            90e6, // platformFee
            10e6 // operatorFee
        );

        assertFalse(isValid);
        assertEq(errorCode, 13); // AmountMismatch
    }

    // ============ PERMIT VALIDATION TESTS ============

    function test_ValidatePermitDeadline_Valid() public {
        uint256 futureDeadline = block.timestamp + 3600;
        bool isValid = PaymentValidatorLib.validatePermitDeadline(futureDeadline);
        assertTrue(isValid);
    }

    function test_ValidatePermitDeadline_Expired() public {
        uint256 pastDeadline = block.timestamp - 1;
        bool isValid = PaymentValidatorLib.validatePermitDeadline(pastDeadline);
        assertFalse(isValid);
    }

    function test_ValidatePermitNonce_Valid() public {
        bool isValid = PaymentValidatorLib.validatePermitNonce(5, 5);
        assertTrue(isValid);
    }

    function test_ValidatePermitNonce_Invalid() public {
        bool isValid = PaymentValidatorLib.validatePermitNonce(5, 6);
        assertFalse(isValid);
    }

    // ============ UTILITY FUNCTION TESTS ============

    function test_GetErrorMessage_ValidCodes() public {
        // Test all valid error codes
        assertEq(PaymentValidatorLib.getErrorMessage(0), "");
        assertEq(PaymentValidatorLib.getErrorMessage(1), "Invalid payment type");
        assertEq(PaymentValidatorLib.getErrorMessage(2), "Invalid creator");
        assertEq(PaymentValidatorLib.getErrorMessage(3), "Deadline expired");
        assertEq(PaymentValidatorLib.getErrorMessage(4), "Invalid payment request");
        assertEq(PaymentValidatorLib.getErrorMessage(5), "Invalid content");
        assertEq(PaymentValidatorLib.getErrorMessage(6), "Intent not found");
        assertEq(PaymentValidatorLib.getErrorMessage(7), "Not intent creator");
        assertEq(PaymentValidatorLib.getErrorMessage(8), "Intent already processed");
        assertEq(PaymentValidatorLib.getErrorMessage(9), "No operator signature");
        assertEq(PaymentValidatorLib.getErrorMessage(10), "Zero amount");
        assertEq(PaymentValidatorLib.getErrorMessage(11), "Zero creator amount");
        assertEq(PaymentValidatorLib.getErrorMessage(12), "Fee exceeds amount");
        assertEq(PaymentValidatorLib.getErrorMessage(13), "Amount mismatch");
    }

    function test_GetErrorMessage_InvalidCode() public {
        string memory message = PaymentValidatorLib.getErrorMessage(99);
        assertEq(message, "Unknown error");
    }

    function test_ValidatePaymentTypeSimple_ValidTypes() public {
        // Test all valid payment types
        assertTrue(PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType.PayPerView));
        assertTrue(PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType.Subscription));
        assertTrue(PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType.Tip));
        assertTrue(PaymentValidatorLib.validatePaymentTypeSimple(PaymentValidatorLib.PaymentType.Donation));
    }

    function test_ValidatePaymentTypeSimple_InvalidType() public {
        PaymentValidatorLib.PaymentType invalidType = PaymentValidatorLib.PaymentType(uint8(4)); // Invalid payment type
        assertFalse(PaymentValidatorLib.validatePaymentTypeSimple(invalidType));
    }

    // ============ EDGE CASE TESTS ============

    function test_ValidatePaymentRequest_ExactBoundaryValues() public {
        // Test with exact boundary values
        testRequest.deadline = block.timestamp + 1; // Just valid

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidatePaymentRequest_MaxValues() public {
        // Test with maximum reasonable values
        testRequest.maxSlippage = 10000; // 100% slippage
        testRequest.contentId = type(uint256).max;

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidatePaymentRequest_ZeroValues() public {
        // Test with zero values (where appropriate)
        testRequest.maxSlippage = 0;
        testRequest.contentId = 1; // Can't be zero for PayPerView

        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validatePaymentRequest(
            testRequest,
            testCreatorData,
            testContentData
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }

    function test_ValidateExecutionContext_BoundaryTimestamps() public {
        // Test with exact boundary timestamps
        (bool isValid, uint8 errorCode) = PaymentValidatorLib.validateExecutionContext(
            bytes16(0),
            user1,
            user1,
            block.timestamp, // Exactly now
            true,
            false
        );

        assertTrue(isValid);
        assertEq(errorCode, 0);
    }
}
