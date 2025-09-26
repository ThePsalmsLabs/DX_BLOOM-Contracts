// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { PaymentUtilsLib } from "../../../src/libraries/PaymentUtilsLib.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title PaymentUtilsLibTest
 * @dev Unit tests for PaymentUtilsLib
 * @notice Tests all payment calculation and utility functions in isolation
 */
contract PaymentUtilsLibTest is TestSetup {
    using PaymentUtilsLib for *;

    function setUp() public override {
        super.setUp();
    }

    // ============ PAYMENT AMOUNT CALCULATION TESTS ============

    function test_CalculateBasicPaymentAmounts_PayPerView() public {
        // Test PayPerView payment calculation
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.PayPerView;
        uint256 contentPrice = 0.1e6; // $0.10
        uint256 subscriptionPrice = 0; // Not used for PayPerView
        uint256 platformFeeRate = 250; // 2.5%

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        // Expected calculations:
        // platformFee = (0.1e6 * 250) / 10000 = 25 USDC (6 decimals)
        // creatorAmount = 0.1e6 - 25 = 99975 USDC
        // totalAmount = 0.1e6 = 100000 USDC

        assertEq(platformFee, 25);
        assertEq(creatorAmount, 99975);
        assertEq(totalAmount, 100000);
    }

    function test_CalculateBasicPaymentAmounts_Subscription() public {
        // Test Subscription payment calculation
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.Subscription;
        uint256 contentPrice = 0; // Not used for Subscription
        uint256 subscriptionPrice = 1e6; // $1.00
        uint256 platformFeeRate = 250; // 2.5%

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        // Expected calculations:
        // platformFee = (1e6 * 250) / 10000 = 250 USDC
        // creatorAmount = 1e6 - 250 = 999750 USDC
        // totalAmount = 1e6 = 1000000 USDC

        assertEq(platformFee, 250);
        assertEq(creatorAmount, 999750);
        assertEq(totalAmount, 1000000);
    }

    function test_CalculateBasicPaymentAmounts_Tip() public {
        // Test Tip payment calculation
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.Tip;
        uint256 contentPrice = 0; // Not used for Tip
        uint256 subscriptionPrice = 0; // Not used for Tip
        uint256 platformFeeRate = 250; // 2.5%

        // For tips, we need to provide an amount
        uint256 tipAmount = 0.5e6; // $0.50 tip

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                tipAmount, // Use tip amount as content price for this calculation
                subscriptionPrice,
                platformFeeRate
            );

        // Expected calculations:
        // platformFee = (0.5e6 * 250) / 10000 = 125 USDC
        // creatorAmount = 0.5e6 - 125 = 499875 USDC
        // totalAmount = 0.5e6 = 500000 USDC

        assertEq(platformFee, 125);
        assertEq(creatorAmount, 499875);
        assertEq(totalAmount, 500000);
    }

    function test_CalculateBasicPaymentAmounts_Donation() public {
        // Test Donation payment calculation
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.Donation;
        uint256 contentPrice = 0; // Not used for Donation
        uint256 subscriptionPrice = 0; // Not used for Donation
        uint256 platformFeeRate = 250; // 2.5%

        // For donations, we need to provide an amount
        uint256 donationAmount = 2e6; // $2.00 donation

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                donationAmount, // Use donation amount as content price for this calculation
                subscriptionPrice,
                platformFeeRate
            );

        // Expected calculations:
        // platformFee = (2e6 * 250) / 10000 = 500 USDC
        // creatorAmount = 2e6 - 500 = 1999500 USDC
        // totalAmount = 2e6 = 2000000 USDC

        assertEq(platformFee, 500);
        assertEq(creatorAmount, 1999500);
        assertEq(totalAmount, 2000000);
    }

    function test_CalculateBasicPaymentAmounts_ZeroAmount() public {
        // Test zero amount handling
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.PayPerView;
        uint256 contentPrice = 0;
        uint256 subscriptionPrice = 0;
        uint256 platformFeeRate = 250;

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        assertEq(platformFee, 0);
        assertEq(creatorAmount, 0);
        assertEq(totalAmount, 0);
    }

    function test_CalculateBasicPaymentAmounts_MaxFeeRate() public {
        // Test maximum fee rate
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.PayPerView;
        uint256 contentPrice = 1e6; // $1.00
        uint256 subscriptionPrice = 0;
        uint256 platformFeeRate = 10000; // 100% fee

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        // Expected calculations:
        // platformFee = (1e6 * 10000) / 10000 = 1000000 USDC
        // creatorAmount = 1e6 - 1000000 = 0 USDC
        // totalAmount = 1e6 = 1000000 USDC

        assertEq(platformFee, 1000000);
        assertEq(creatorAmount, 0);
        assertEq(totalAmount, 1000000);
    }

    // ============ EXPECTED PAYMENT AMOUNT TESTS ============

    function test_CalculateExpectedPaymentAmount_USDC() public {
        // Test expected amount calculation for USDC
        address paymentToken = address(mockUSDC);
        uint256 totalAmount = 1000e6; // $1000
        uint256 maxSlippage = 100; // 1%
        address oracle = address(priceOracle);

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        // For USDC, expected amount should equal total amount (no conversion)
        assertEq(expectedAmount, totalAmount);
    }

    function test_CalculateExpectedPaymentAmount_ETH() public {
        // Test expected amount calculation for ETH
        address paymentToken = address(0); // Native ETH
        uint256 totalAmount = 1e18; // 1 ETH
        uint256 maxSlippage = 100; // 1%
        address oracle = address(priceOracle);

        // Mock price oracle response
        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getETHPrice()"),
            abi.encode(2000e6) // 1 ETH = 2000 USDC
        );

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        // Expected: 1 ETH * 2000 USDC/ETH = 2000 USDC
        assertEq(expectedAmount, 2000e6);
    }

    function test_CalculateExpectedPaymentAmount_WithSlippage() public {
        // Test expected amount calculation with slippage
        address paymentToken = address(0); // Native ETH
        uint256 totalAmount = 1e18; // 1 ETH
        uint256 maxSlippage = 500; // 5%
        address oracle = address(priceOracle);

        // Mock price oracle response
        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getETHPrice()"),
            abi.encode(2000e6) // 1 ETH = 2000 USDC
        );

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        // Expected: 2000 USDC * (1 - 0.05) = 1900 USDC (minimum amount after slippage)
        assertEq(expectedAmount, 1900e6);
    }

    // ============ DEADLINE VALIDATION TESTS ============

    function test_ValidateDeadline_Valid() public {
        uint256 futureDeadline = block.timestamp + 3600; // 1 hour from now
        uint256 maxFuture = 7 days; // 7 days max

        bool isValid = PaymentUtilsLib.validateDeadline(futureDeadline, maxFuture);
        assertTrue(isValid);
    }

    function test_ValidateDeadline_PastDeadline() public {
        uint256 pastDeadline = block.timestamp - 1;
        uint256 maxFuture = 7 days;

        bool isValid = PaymentUtilsLib.validateDeadline(pastDeadline, maxFuture);
        assertFalse(isValid);
    }

    function test_ValidateDeadline_TooFarInFuture() public {
        uint256 farFutureDeadline = block.timestamp + 8 days; // 8 days from now
        uint256 maxFuture = 7 days; // 7 days max

        bool isValid = PaymentUtilsLib.validateDeadline(farFutureDeadline, maxFuture);
        assertFalse(isValid);
    }

    function test_ValidateDeadline_ExactBoundary() public {
        uint256 exactBoundary = block.timestamp + 7 days; // Exactly max future
        uint256 maxFuture = 7 days;

        bool isValid = PaymentUtilsLib.validateDeadline(exactBoundary, maxFuture);
        assertTrue(isValid);
    }

    // ============ BASIC LIBRARY TESTS ============

    function test_BasicCalculations() public {
        // Test basic mathematical calculations that the library would perform
        uint256 amount = 1000e6; // $1000
        uint256 platformFeeRate = 250; // 2.5%
        uint256 operatorFeeRate = 50; // 0.5%

        // Test fee calculations (library doesn't have these functions, but they use similar logic)
        uint256 platformFee = (amount * platformFeeRate) / 10000;
        uint256 operatorFee = (amount * operatorFeeRate) / 10000;
        uint256 totalFees = platformFee + operatorFee;

        assertEq(platformFee, 250); // (1000e6 * 250) / 10000 = 250
        assertEq(operatorFee, 50); // (1000e6 * 50) / 10000 = 50
        assertEq(totalFees, 300); // 250 + 50 = 300
    }

    // ============ CREATOR AMOUNT CALCULATION TESTS ============

    function test_CalculateCreatorAmount_WithFees() public {
        uint256 totalAmount = 1000e6; // $1000
        uint256 platformFeeRate = 250; // 2.5%
        uint256 operatorFeeRate = 50; // 0.5%

        // Test manual calculation since library doesn't have this function
        uint256 platformFee = (totalAmount * platformFeeRate) / 10000;
        uint256 operatorFee = (totalAmount * operatorFeeRate) / 10000;
        uint256 creatorAmount = totalAmount - platformFee - operatorFee;

        // Expected: 1000e6 - (1000e6 * 250 / 10000) - (1000e6 * 50 / 10000) = 1000e6 - 250 - 50 = 999700
        assertEq(creatorAmount, 999700);
    }

    function test_CalculateCreatorAmount_NoFees() public {
        uint256 totalAmount = 1000e6; // $1000
        uint256 platformFeeRate = 0;
        uint256 operatorFeeRate = 0;

        // Test manual calculation
        uint256 platformFee = (totalAmount * platformFeeRate) / 10000;
        uint256 operatorFee = (totalAmount * operatorFeeRate) / 10000;
        uint256 creatorAmount = totalAmount - platformFee - operatorFee;

        assertEq(creatorAmount, totalAmount);
    }

    // ============ EDGE CASE TESTS ============

    function test_CalculateBasicPaymentAmounts_MinimumValues() public {
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.PayPerView;
        uint256 contentPrice = 1; // 1 wei
        uint256 subscriptionPrice = 0;
        uint256 platformFeeRate = 1; // 0.01%

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        // Even with minimum values, calculations should work
        assertEq(platformFee, 0); // 1 * 1 / 10000 = 0 (rounded down)
        assertEq(creatorAmount, 1);
        assertEq(totalAmount, 1);
    }

    function test_CalculateBasicPaymentAmounts_MaximumValues() public {
        ISharedTypes.PaymentType paymentType = ISharedTypes.PaymentType.Subscription;
        uint256 contentPrice = 0;
        uint256 subscriptionPrice = type(uint256).max;
        uint256 platformFeeRate = 10000; // 100%

        (uint256 totalAmount, uint256 creatorAmount, uint256 platformFee) =
            PaymentUtilsLib.calculateBasicPaymentAmounts(
                paymentType,
                contentPrice,
                subscriptionPrice,
                platformFeeRate
            );

        // Should handle maximum values without overflow
        assertEq(creatorAmount, 0); // All goes to fees
        assertEq(platformFee, type(uint256).max);
        assertEq(totalAmount, type(uint256).max);
    }

    function test_CalculateExpectedPaymentAmount_ZeroAmount() public {
        address paymentToken = address(mockUSDC);
        uint256 totalAmount = 0;
        uint256 maxSlippage = 100;
        address oracle = address(priceOracle);

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        assertEq(expectedAmount, 0);
    }

    function test_CalculateExpectedPaymentAmount_ZeroSlippage() public {
        address paymentToken = address(0); // ETH
        uint256 totalAmount = 1e18;
        uint256 maxSlippage = 0; // No slippage
        address oracle = address(priceOracle);

        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getETHPrice()"),
            abi.encode(2000e6)
        );

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        assertEq(expectedAmount, 2000e6); // No slippage reduction
    }

    function test_CalculateExpectedPaymentAmount_MaxSlippage() public {
        address paymentToken = address(0); // ETH
        uint256 totalAmount = 1e18;
        uint256 maxSlippage = 10000; // 100% slippage
        address oracle = address(priceOracle);

        vm.mockCall(
            oracle,
            abi.encodeWithSignature("getETHPrice()"),
            abi.encode(2000e6)
        );

        uint256 expectedAmount = PaymentUtilsLib.calculateExpectedPaymentAmount(
            paymentToken,
            totalAmount,
            maxSlippage,
            oracle
        );

        assertEq(expectedAmount, 0); // Maximum slippage reduction
    }

    // ============ ROUNDING TESTS ============

    function test_FeeCalculationRounding() public {
        // Test fee calculation with amounts that don't divide evenly
        uint256 amount = 1001; // Odd number
        uint256 feeRate = 333; // 3.33%

        // Test manual calculation
        uint256 fee = (amount * feeRate) / 10000;

        // (1001 * 333) / 10000 = 333333 / 10000 = 33.3333, should round down to 33
        assertEq(fee, 33);
    }

    function test_CreatorAmountRounding() public {
        // Test creator amount calculation with rounding
        uint256 totalAmount = 1000;
        uint256 platformFeeRate = 333; // 3.33%
        uint256 operatorFeeRate = 167; // 1.67%

        // Test manual calculation
        uint256 platformFee = (totalAmount * platformFeeRate) / 10000;
        uint256 operatorFee = (totalAmount * operatorFeeRate) / 10000;
        uint256 creatorAmount = totalAmount - platformFee - operatorFee;

        // platformFee = (1000 * 333) / 10000 = 33
        // operatorFee = (1000 * 167) / 10000 = 16
        // creatorAmount = 1000 - 33 - 16 = 951

        assertEq(creatorAmount, 951);
    }
}
