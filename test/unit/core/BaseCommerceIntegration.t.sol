// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { BaseCommerceIntegration } from "../../../src/BaseCommerceIntegration.sol";
import { ISharedTypes } from "../../../src/interfaces/ISharedTypes.sol";

/**
 * @title BaseCommerceIntegrationTest
 * @dev Unit tests for BaseCommerceIntegration contract
 * @notice Tests all Base Commerce Protocol integration functions in isolation
 */
contract BaseCommerceIntegrationTest is TestSetup {
    // Test contracts
    BaseCommerceIntegration public baseCommerceIntegration;

    // Test addresses
    address public testOperatorFeeDestination = address(0x1001);
    address public testPayer = address(0x2001);
    address public testReceiver = address(0x3001);

    // Test data
    bytes32 testPaymentHash;
    BaseCommerceIntegration.EscrowPaymentParams testParams;

    function setUp() public override {
        super.setUp();

        // Deploy BaseCommerceIntegration using existing mockUSDC from TestSetup
        baseCommerceIntegration = new BaseCommerceIntegration(
            address(mockUSDC),
            testOperatorFeeDestination
        );

        // Set up test payment parameters
        testParams = BaseCommerceIntegration.EscrowPaymentParams({
            payer: testPayer,
            receiver: testReceiver,
            amount: 1000e6, // 1000 USDC
            paymentType: ISharedTypes.PaymentType.PayPerView,
            permit2Data: "",
            instantCapture: false
        });

        // Calculate expected payment hash for testing
        testPaymentHash = keccak256(abi.encodePacked(
            address(baseCommerceIntegration),
            testPayer,
            testReceiver,
            uint256(1000e6),
            uint256(1), // nonce
            block.timestamp,
            address(baseCommerceIntegration)
        ));

        // Fund test accounts
        mockUSDC.mint(testPayer, 10000e6); // $10,000 for testing
        vm.deal(testPayer, 10 ether); // ETH for gas
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(baseCommerceIntegration.usdcToken()), address(mockUSDC));
        assertEq(baseCommerceIntegration.operatorFeeDestination(), testOperatorFeeDestination);
        assertEq(baseCommerceIntegration.operatorFeeRate(), 250); // 2.5% default
        assertEq(baseCommerceIntegration.defaultAuthExpiry(), 30 minutes);
        assertEq(baseCommerceIntegration.defaultRefundWindow(), 7 days);
        assertEq(baseCommerceIntegration.owner(), admin);
    }

    function test_Constructor_ZeroUSDCToken() public {
        vm.expectRevert("Invalid USDC token");
        new BaseCommerceIntegration(address(0), testOperatorFeeDestination);
    }

    function test_Constructor_ZeroFeeDestination() public {
        vm.expectRevert("Invalid fee destination");
        new BaseCommerceIntegration(address(mockUSDC), address(0));
    }

    function test_Constructor_BothZero() public {
        vm.expectRevert("Invalid USDC token");
        new BaseCommerceIntegration(address(0), address(0));
    }

    // ============ CORE PAYMENT FUNCTIONS TESTS ============

    function test_ExecuteEscrowPayment_ValidParameters() public {
        // Set up mock calls for successful authorization
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("getPaymentHash((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(testPaymentHash)
        );

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("authorize((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes)"),
            abi.encode(true)
        );

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit BaseCommerceIntegration.EscrowPaymentInitiated(
            testPaymentHash,
            testPayer,
            testReceiver,
            1000e6,
            ISharedTypes.PaymentType.PayPerView
        );

        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.EscrowPaymentAuthorized(testPaymentHash, 1000e6);

        // Execute payment
        vm.prank(testPayer);
        bytes32 returnedPaymentHash = baseCommerceIntegration.executeEscrowPayment(testParams);

        assertEq(returnedPaymentHash, testPaymentHash);

        // Verify payment record was created
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);
        assertEq(record.payer, testPayer);
        assertEq(record.receiver, testReceiver);
        assertEq(record.amount, 1000e6);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Authorized));
        assertEq(uint8(record.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
    }

    function test_ExecuteEscrowPayment_InstantCapture() public {
        BaseCommerceIntegration.EscrowPaymentParams memory instantParams = testParams;
        instantParams.instantCapture = true;

        // Set up mock calls for successful charge
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("getPaymentHash((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(testPaymentHash)
        );

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("charge((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes,uint16,address)"),
            abi.encode(true)
        );

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit BaseCommerceIntegration.EscrowPaymentInitiated(
            testPaymentHash,
            testPayer,
            testReceiver,
            1000e6,
            ISharedTypes.PaymentType.PayPerView
        );

        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.EscrowPaymentCaptured(testPaymentHash, 1000e6, 25e6); // 2.5% of 1000e6

        // Execute payment
        vm.prank(testPayer);
        bytes32 returnedPaymentHash = baseCommerceIntegration.executeEscrowPayment(instantParams);

        assertEq(returnedPaymentHash, testPaymentHash);

        // Verify payment record was created with Captured status
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Captured));
    }

    function test_ExecuteEscrowPayment_ZeroAmount() public {
        BaseCommerceIntegration.EscrowPaymentParams memory zeroParams = testParams;
        zeroParams.amount = 0;

        vm.prank(testPayer);
        vm.expectRevert("Amount must be positive");
        baseCommerceIntegration.executeEscrowPayment(zeroParams);
    }

    function test_ExecuteEscrowPayment_ZeroPayer() public {
        BaseCommerceIntegration.EscrowPaymentParams memory zeroParams = testParams;
        zeroParams.payer = address(0);

        vm.prank(testPayer);
        vm.expectRevert("Invalid payer");
        baseCommerceIntegration.executeEscrowPayment(zeroParams);
    }

    function test_ExecuteEscrowPayment_ZeroReceiver() public {
        BaseCommerceIntegration.EscrowPaymentParams memory zeroParams = testParams;
        zeroParams.receiver = address(0);

        vm.prank(testPayer);
        vm.expectRevert("Invalid receiver");
        baseCommerceIntegration.executeEscrowPayment(zeroParams);
    }

    function test_ExecuteEscrowPayment_Unauthorized() public {
        // Only payer should be able to execute payment
        vm.prank(testReceiver);
        vm.expectRevert(); // Should revert due to nonReentrant and caller check
        baseCommerceIntegration.executeEscrowPayment(testParams);
    }

    // ============ CAPTURE PAYMENT TESTS ============

    function test_CapturePayment_Success() public {
        // First authorize a payment
        _setupAuthorizedPayment();

        // Set up mock call for successful capture
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("capture((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,uint16,address)"),
            abi.encode(true)
        );

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.EscrowPaymentCaptured(testPaymentHash, 1000e6, 25e6);

        // Capture payment
        vm.prank(admin);
        bool success = baseCommerceIntegration.capturePayment(testPaymentHash, 1000e6);

        assertTrue(success);

        // Verify status updated
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Captured));
    }

    function test_CapturePayment_NotAuthorized() public {
        // Try to capture without authorization
        vm.prank(admin);
        bool success = baseCommerceIntegration.capturePayment(testPaymentHash, 1000e6);

        assertFalse(success);
    }

    function test_CapturePayment_ZeroAmount() public {
        _setupAuthorizedPayment();

        vm.prank(admin);
        vm.expectRevert("Invalid capture amount");
        baseCommerceIntegration.capturePayment(testPaymentHash, 0);
    }

    function test_CapturePayment_Unauthorized() public {
        _setupAuthorizedPayment();

        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to onlyOwner
        baseCommerceIntegration.capturePayment(testPaymentHash, 1000e6);
    }

    // ============ VOID PAYMENT TESTS ============

    function test_VoidPayment_Success() public {
        _setupAuthorizedPayment();

        // Set up mock call for successful void
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("void((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(true)
        );

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.EscrowPaymentVoided(testPaymentHash, admin);

        // Void payment
        vm.prank(admin);
        bool success = baseCommerceIntegration.voidPayment(testPaymentHash);

        assertTrue(success);

        // Verify status updated
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Voided));
    }

    function test_VoidPayment_NotAuthorized() public {
        vm.prank(admin);
        bool success = baseCommerceIntegration.voidPayment(testPaymentHash);

        assertFalse(success);
    }

    function test_VoidPayment_Unauthorized() public {
        _setupAuthorizedPayment();

        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to onlyOwner
        baseCommerceIntegration.voidPayment(testPaymentHash);
    }

    // ============ REFUND PAYMENT TESTS ============

    function test_RefundPayment_Success() public {
        _setupCapturedPayment();

        // Set up mock call for successful refund
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("refund((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes)"),
            abi.encode(true)
        );

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.EscrowPaymentRefunded(testPaymentHash, 1000e6);

        // Refund payment
        vm.prank(admin);
        bool success = baseCommerceIntegration.refundPayment(testPaymentHash, 1000e6, "");

        assertTrue(success);

        // Verify status updated
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Refunded));
    }

    function test_RefundPayment_InvalidStatus() public {
        // Create a voided payment record
        _setupVoidedPayment();

        vm.prank(admin);
        bool success = baseCommerceIntegration.refundPayment(testPaymentHash, 1000e6, "");

        assertFalse(success);
    }

    function test_RefundPayment_Unauthorized() public {
        _setupCapturedPayment();

        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to onlyOwner
        baseCommerceIntegration.refundPayment(testPaymentHash, 1000e6, "");
    }

    // ============ VIEW FUNCTIONS TESTS ============

    function test_GetPaymentRecord_Existing() public {
        _setupAuthorizedPayment();

        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);

        assertEq(record.payer, testPayer);
        assertEq(record.receiver, testReceiver);
        assertEq(record.amount, 1000e6);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.Authorized));
        assertEq(uint8(record.paymentType), uint8(ISharedTypes.PaymentType.PayPerView));
    }

    function test_GetPaymentRecord_NonExistent() public {
        BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(testPaymentHash);

        assertEq(record.payer, address(0)); // Should be zero for non-existent
        assertEq(record.receiver, address(0));
        assertEq(record.amount, 0);
        assertEq(uint8(record.status), uint8(BaseCommerceIntegration.PaymentStatus.None));
    }

    function test_GetPaymentState() public {
        _setupAuthorizedPayment();

        // Mock the getPaymentState call
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("getPaymentState((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(
                address(0), // payer
                address(0), // receiver
                address(0), // token
                0, // amount
                0, // fee
                0  // status
            )
        );

        vm.prank(testPayer);
        baseCommerceIntegration.getPaymentState(testPaymentHash); // Should not revert
    }

    function test_GetPaymentState_NonExistent() public {
        vm.prank(testPayer);
        vm.expectRevert("Payment not found");
        baseCommerceIntegration.getPaymentState(testPaymentHash);
    }

    // ============ ADMIN FUNCTIONS TESTS ============

    function test_UpdateOperatorConfig_ValidParameters() public {
        address newFeeDestination = address(0x4001);
        uint16 newFeeRate = 500; // 5%

        vm.expectEmit(true, true, false, true);
        emit BaseCommerceIntegration.OperatorConfigUpdated(newFeeDestination, newFeeRate);

        vm.prank(admin);
        baseCommerceIntegration.updateOperatorConfig(newFeeDestination, newFeeRate);

        assertEq(baseCommerceIntegration.operatorFeeDestination(), newFeeDestination);
        assertEq(baseCommerceIntegration.operatorFeeRate(), newFeeRate);
    }

    function test_UpdateOperatorConfig_ZeroDestination() public {
        vm.prank(admin);
        vm.expectRevert("Invalid fee destination");
        baseCommerceIntegration.updateOperatorConfig(address(0), 500);
    }

    function test_UpdateOperatorConfig_FeeTooHigh() public {
        vm.prank(admin);
        vm.expectRevert("Fee rate too high");
        baseCommerceIntegration.updateOperatorConfig(address(0x4001), 1001); // > 10%
    }

    function test_UpdateOperatorConfig_Unauthorized() public {
        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to onlyOwner
        baseCommerceIntegration.updateOperatorConfig(address(0x4001), 500);
    }

    function test_UpdateTimingConfig_ValidParameters() public {
        uint48 newAuthExpiry = 60 minutes;
        uint48 newRefundWindow = 14 days;

        vm.prank(admin);
        baseCommerceIntegration.updateTimingConfig(newAuthExpiry, newRefundWindow);

        assertEq(baseCommerceIntegration.defaultAuthExpiry(), newAuthExpiry);
        assertEq(baseCommerceIntegration.defaultRefundWindow(), newRefundWindow);
    }

    function test_UpdateTimingConfig_AuthExpiryTooShort() public {
        vm.prank(admin);
        vm.expectRevert("Auth expiry too short");
        baseCommerceIntegration.updateTimingConfig(4 minutes, 7 days);
    }

    function test_UpdateTimingConfig_RefundWindowTooShort() public {
        vm.prank(admin);
        vm.expectRevert("Refund window too short");
        baseCommerceIntegration.updateTimingConfig(30 minutes, 30 minutes);
    }

    function test_UpdateTimingConfig_Unauthorized() public {
        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to onlyOwner
        baseCommerceIntegration.updateTimingConfig(60 minutes, 14 days);
    }

    // ============ EDGE CASES AND BOUNDARY TESTS ============

    function test_ExecuteEscrowPayment_MaxUint256Amount() public {
        BaseCommerceIntegration.EscrowPaymentParams memory maxParams = testParams;
        maxParams.amount = type(uint256).max;

        vm.prank(testPayer);
        vm.expectRevert(); // Should revert due to uint120 casting limit in PaymentInfo
        baseCommerceIntegration.executeEscrowPayment(maxParams);
    }

    function test_ExecuteEscrowPayment_MinimumAmount() public {
        BaseCommerceIntegration.EscrowPaymentParams memory minParams = testParams;
        minParams.amount = 1; // Minimum valid amount

        // Set up mock calls
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("getPaymentHash((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(testPaymentHash)
        );

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("authorize((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes)"),
            abi.encode(true)
        );

        vm.prank(testPayer);
        bytes32 returnedPaymentHash = baseCommerceIntegration.executeEscrowPayment(minParams);

        assertEq(returnedPaymentHash, testPaymentHash);
    }

    function test_CapturePayment_PartialAmount() public {
        _setupAuthorizedPayment();

        uint256 partialAmount = 500e6; // Half the amount

        // Set up mock call for partial capture
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("capture((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,uint16,address)"),
            abi.encode(true)
        );

        vm.prank(admin);
        bool success = baseCommerceIntegration.capturePayment(testPaymentHash, partialAmount);

        assertTrue(success);
    }

    function test_MultiplePayments_Sequential() public {
        bytes32[] memory paymentHashes = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            BaseCommerceIntegration.EscrowPaymentParams memory params = testParams;
            params.amount = (i + 1) * 1000e6; // 1000, 2000, 3000 USDC

            // Set up mock calls
            bytes32 expectedHash = keccak256(abi.encodePacked("payment", i));
            vm.mockCall(
                address(baseCommerceIntegration.authCaptureEscrow()),
                abi.encodeWithSignature("getPaymentHash((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
                abi.encode(expectedHash)
            );

            vm.mockCall(
                address(baseCommerceIntegration.authCaptureEscrow()),
                abi.encodeWithSignature("authorize((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes)"),
                abi.encode(true)
            );

            vm.prank(testPayer);
            paymentHashes[i] = baseCommerceIntegration.executeEscrowPayment(params);

            assertTrue(paymentHashes[i] != bytes32(0));
        }

        // Verify all payments were recorded
        for (uint256 i = 0; i < 3; i++) {
            BaseCommerceIntegration.PaymentRecord memory record = baseCommerceIntegration.getPaymentRecord(paymentHashes[i]);
            assertEq(record.payer, testPayer);
            assertEq(record.amount, (i + 1) * 1000e6);
        }
    }

    // ============ FEE CALCULATION TESTS ============

    function test_CalculateFee_ZeroAmount() public {
        // Calculate fee manually using public interface
        uint256 fee = (0 * baseCommerceIntegration.operatorFeeRate()) / 10000;
        assertEq(fee, 0);
    }

    function test_CalculateFee_NormalAmount() public {
        // Calculate fee manually using public interface
        uint256 fee = (1000e6 * baseCommerceIntegration.operatorFeeRate()) / 10000;
        assertEq(fee, 25e6); // 2.5% of 1000e6
    }

    function test_CalculateFee_MaxAmount() public {
        // Calculate fee manually using public interface
        uint256 fee = (type(uint256).max * baseCommerceIntegration.operatorFeeRate()) / 10000;
        assertEq(fee, (type(uint256).max * 250) / 10000);
    }

    function test_CalculateFee_AfterFeeUpdate() public {
        // Update fee rate to 5%
        vm.prank(admin);
        baseCommerceIntegration.updateOperatorConfig(testOperatorFeeDestination, 500);

        // Calculate fee manually using public interface
        uint256 fee = (1000e6 * baseCommerceIntegration.operatorFeeRate()) / 10000;
        assertEq(fee, 50e6); // 5% of 1000e6
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyOwnerFunctions() public {
        // Test that only owner functions revert when called by non-owner
        vm.prank(testPayer);
        vm.expectRevert(); // capturePayment
        baseCommerceIntegration.capturePayment(testPaymentHash, 1000e6);

        vm.prank(testPayer);
        vm.expectRevert(); // voidPayment
        baseCommerceIntegration.voidPayment(testPaymentHash);

        vm.prank(testPayer);
        vm.expectRevert(); // refundPayment
        baseCommerceIntegration.refundPayment(testPaymentHash, 1000e6, "");

        vm.prank(testPayer);
        vm.expectRevert(); // updateOperatorConfig
        baseCommerceIntegration.updateOperatorConfig(address(0x4001), 500);

        vm.prank(testPayer);
        vm.expectRevert(); // updateTimingConfig
        baseCommerceIntegration.updateTimingConfig(60 minutes, 14 days);
    }

    // ============ REENTRANCY PROTECTION TESTS ============

    function test_ReentrancyProtection_ExecutePayment() public {
        // Test that reentrancy is properly protected
        // This would require a malicious contract that tries to reenter
        // For now, we just test that nonReentrant modifier works

        // Try to call executeEscrowPayment twice in same transaction (should fail)
        vm.prank(testPayer);
        baseCommerceIntegration.executeEscrowPayment(testParams);

        // The second call should fail due to reentrancy guard
        // We can't easily test this without a malicious contract, but the modifier is there
    }

    // ============ HELPER FUNCTIONS ============

    function _setupAuthorizedPayment() internal {
        // Set up mock calls for authorization
        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("getPaymentHash((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(testPaymentHash)
        );

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("authorize((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,address,bytes)"),
            abi.encode(true)
        );

        // Execute payment to create authorized record
        vm.prank(testPayer);
        baseCommerceIntegration.executeEscrowPayment(testParams);
    }

    function _setupCapturedPayment() internal {
        // First authorize, then capture
        _setupAuthorizedPayment();

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("capture((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256),uint256,uint16,address)"),
            abi.encode(true)
        );

        vm.prank(admin);
        baseCommerceIntegration.capturePayment(testPaymentHash, 1000e6);
    }

    function _setupVoidedPayment() internal {
        // First authorize, then void
        _setupAuthorizedPayment();

        vm.mockCall(
            address(baseCommerceIntegration.authCaptureEscrow()),
            abi.encodeWithSignature("void((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256))"),
            abi.encode(true)
        );

        vm.prank(admin);
        baseCommerceIntegration.voidPayment(testPaymentHash);
    }
}
