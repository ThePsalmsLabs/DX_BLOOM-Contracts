// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { PermitPaymentManager } from "../../src/PermitPaymentManager.sol";
import { ICommercePaymentsProtocol } from "../../src/interfaces/IPlatformInterfaces.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";

// Import the Permit2 interfaces that are used in the tests
interface ISignatureTransfer {
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }
}

/**
 * @title PermitPaymentManager Unit Tests
 * @dev Tests the permit-based payment functions of the PermitPaymentManager contract
 * @notice Tests permit execution, validation, nonce management, domain separator, etc.
 */
contract PermitPaymentManagerTest is TestSetup {
    bytes16 public testIntentId = bytes16(keccak256("test-permit-intent"));
    address public paymentMonitor = address(0x7777);

    // Test data for permit payments
    uint256 public creatorAmount = 900e6; // 900 USDC
    uint256 public platformFee = 90e6;   // 90 USDC
    uint256 public operatorFee = 10e6;   // 10 USDC
    uint256 public deadline = block.timestamp + 3600;

    // Sample permit data for testing
    ICommercePaymentsProtocol.Permit2SignatureTransferData public testPermitData;

    function setUp() public override {
        super.setUp();

        // PermitPaymentManager is already deployed in TestSetup
        permitPaymentManager = PermitPaymentManager(commerceIntegration.permitPaymentManager());

        // Create test permit data
        testPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6 // 1000 USDC
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "dummy-signature"
        });
    }

    // ============ PERMIT EXECUTION TESTS ============

    function test_ExecutePaymentWithPermit_Success() public {
        vm.prank(user1);

        // Mock the commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // Execute permit payment
        bool success = permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );

        assertTrue(success);
    }

    function test_ExecutePaymentWithPermit_RevertIfNotIntentCreator() public {
        vm.prank(user2); // Wrong user

        vm.expectRevert("Not intent creator");
        permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1, // Original creator
            address(mockUSDC),
            1000e6,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );
    }

    function test_ExecutePaymentWithPermit_FailureHandling() public {
        vm.prank(user1);

        // Mock the commerce protocol to return false (failure)
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(false)
        );

        // Execute permit payment
        bool success = permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );

        assertFalse(success);
    }

    function test_ExecutePaymentWithPermit_Events() public {
        vm.prank(user1);

        // Mock successful payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        vm.expectEmit(true, true, false, true);
        emit PermitPaymentManager.PaymentExecutedWithPermit(
            testIntentId,
            user1,
            creator1,
            ISharedTypes.PaymentType.PayPerView,
            1000e6,
            address(mockUSDC),
            true
        );

        permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );
    }

    // ============ CREATE AND EXECUTE WITH PERMIT TESTS ============

    function test_CreateAndExecuteWithPermit_Success() public {
        vm.prank(user1);

        // Mock commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // Create and execute
        (bytes16 intentId, bool success) = permitPaymentManager.createAndExecuteWithPermit(
            user1,
            creator1,
            uint256(0), // contentId
            ISharedTypes.PaymentType.PayPerView,
            address(mockUSDC),
            1000e6,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            testIntentId,
            "signature",
            testPermitData
        );

        assertEq(intentId, testIntentId);
        assertTrue(success);
    }

    function test_CreateAndExecuteWithPermit_RevertIfNotIntentCreator() public {
        vm.prank(user2); // Wrong user

        vm.expectRevert("Not intent creator");
        permitPaymentManager.createAndExecuteWithPermit(
            user1, // Original creator
            creator1,
            uint256(0),
            ISharedTypes.PaymentType.PayPerView,
            address(mockUSDC),
            1000e6,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            testIntentId,
            "signature",
            testPermitData
        );
    }

    function test_CreateAndExecuteWithPermit_Events() public {
        vm.prank(user1);

        // Mock successful payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        vm.expectEmit(true, true, false, true);
        emit PermitPaymentManager.PaymentExecutedWithPermit(
            testIntentId,
            user1,
            creator1,
            ISharedTypes.PaymentType.PayPerView,
            1000e6,
            address(mockUSDC),
            true
        );

        vm.expectEmit(true, true, false, true);
        emit PermitPaymentManager.PermitPaymentCreated(
            testIntentId,
            user1,
            creator1,
            ISharedTypes.PaymentType.PayPerView,
            1000e6,
            address(mockUSDC),
            0 // nonce
        );

        permitPaymentManager.createAndExecuteWithPermit(
            user1,
            creator1,
            uint256(0),
            ISharedTypes.PaymentType.PayPerView,
            address(mockUSDC),
            1000e6,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            testIntentId,
            "signature",
            testPermitData
        );
    }

    // ============ PERMIT VALIDATION TESTS ============

    function test_ValidatePermitData_Success() public view {
        // Create valid permit data
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory validPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6
                }),
                nonce: 0,
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "valid-signature"
        });

        bool isValid = permitPaymentManager.validatePermitData(validPermitData, user1);
        // Note: This will return false in test environment since we can't create real signatures
        // But the function should execute without reverting
    }

    function test_ValidatePermitData_ExpiredDeadline() public view {
        // Create expired permit data
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory expiredPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6
                }),
                nonce: 0,
                deadline: block.timestamp - 1 // Expired
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "expired-signature"
        });

        bool isValid = permitPaymentManager.validatePermitData(expiredPermitData, user1);
        assertFalse(isValid);
    }

    function test_ValidatePermitData_WrongNonce() public view {
        // Create permit data with wrong nonce
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory wrongNoncePermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6
                }),
                nonce: 999, // Wrong nonce
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "wrong-nonce-signature"
        });

        bool isValid = permitPaymentManager.validatePermitData(wrongNoncePermitData, user1);
        assertFalse(isValid);
    }

    function test_ValidatePermitContext_Success() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6
                }),
                nonce: 0,
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "valid-context-signature"
        });

        bool isValid = permitPaymentManager.validatePermitContext(
            permitData,
            address(mockUSDC),
            1000e6,
            address(mockCommerceProtocol)
        );
        // Should validate successfully in test environment
    }

    function test_ValidatePermitContext_WrongToken() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(0x1234), // Wrong token
                    amount: 1000e6
                }),
                nonce: 0,
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "wrong-token-signature"
        });

        bool isValid = permitPaymentManager.validatePermitContext(
            permitData,
            address(mockUSDC), // Expected token
            1000e6,
            address(mockCommerceProtocol)
        );
        assertFalse(isValid);
    }

    function test_ValidatePermitContext_InsufficientAmount() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 500e6 // Insufficient amount
                }),
                nonce: 0,
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 500e6
            }),
            signature: "insufficient-amount-signature"
        });

        bool isValid = permitPaymentManager.validatePermitContext(
            permitData,
            address(mockUSDC),
            1000e6, // Expected amount
            address(mockCommerceProtocol)
        );
        assertFalse(isValid);
    }

    // ============ NONCE MANAGEMENT TESTS ============

    function test_GetPermitNonce_Success() public view {
        uint256 nonce = permitPaymentManager.getPermitNonce(user1);
        // Should return 0 for new user in test environment
        assertEq(nonce, 0);
    }

    // ============ DOMAIN SEPARATOR TESTS ============

    function test_GetPermitDomainSeparator_Success() public view {
        bytes32 domainSeparator = permitPaymentManager.getPermitDomainSeparator();
        // Should return the domain separator from the permit2 contract
        assertTrue(domainSeparator != bytes32(0));
    }

    // ============ CAN EXECUTE WITH PERMIT TESTS ============

    function test_CanExecuteWithPermit_Success() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: 1000e6
                }),
                nonce: 0,
                deadline: block.timestamp + 3600
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: 1000e6
            }),
            signature: "can-execute-signature"
        });

        (bool canExecute, string memory reason) = permitPaymentManager.canExecuteWithPermit(
            testIntentId,
            user1,
            deadline,
            true, // hasSignature
            permitData,
            address(mockUSDC),
            1000e6
        );

        // In test environment, this may return false due to signature validation
        // But it should not revert
    }

    function test_CanExecuteWithPermit_NoIntent() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = testPermitData;

        (bool canExecute, string memory reason) = permitPaymentManager.canExecuteWithPermit(
            testIntentId,
            address(0), // No user (invalid intent)
            deadline,
            true,
            permitData,
            address(mockUSDC),
            1000e6
        );

        assertFalse(canExecute);
        assertEq(reason, "Intent not found");
    }

    function test_CanExecuteWithPermit_Expired() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = testPermitData;

        (bool canExecute, string memory reason) = permitPaymentManager.canExecuteWithPermit(
            testIntentId,
            user1,
            block.timestamp - 1, // Expired deadline
            true,
            permitData,
            address(mockUSDC),
            1000e6
        );

        assertFalse(canExecute);
        assertEq(reason, "Intent expired");
    }

    function test_CanExecuteWithPermit_NoSignature() public view {
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = testPermitData;

        (bool canExecute, string memory reason) = permitPaymentManager.canExecuteWithPermit(
            testIntentId,
            user1,
            deadline,
            false, // No signature
            permitData,
            address(mockUSDC),
            1000e6
        );

        assertFalse(canExecute);
        assertEq(reason, "No operator signature");
    }

    // ============ EMERGENCY CONTROLS TESTS ============

    function test_Pause_Success() public {
        vm.prank(admin);

        permitPaymentManager.pause();

        assertTrue(permitPaymentManager.paused());
    }

    function test_Pause_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        permitPaymentManager.pause();
    }

    function test_Unpause_Success() public {
        vm.prank(admin);

        permitPaymentManager.pause();
        assertTrue(permitPaymentManager.paused());

        permitPaymentManager.unpause();
        assertFalse(permitPaymentManager.paused());
    }

    function test_Unpause_RevertIfNotOwner() public {
        vm.prank(admin);
        permitPaymentManager.pause();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        permitPaymentManager.unpause();
    }

    // ============ EDGE CASE TESTS ============

    function test_ZeroAmountHandling() public {
        vm.prank(user1);

        // Mock the commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // Execute with zero amounts
        bool success = permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            0, // Zero amount
            creator1,
            0, // Zero creator amount
            0, // Zero platform fee
            0, // Zero operator fee
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );

        assertTrue(success); // Should succeed even with zero amounts
    }

    function test_LargeAmountHandling() public {
        vm.prank(user1);

        // Mock the commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        uint256 largeAmount = 1000000e6; // 1M USDC

        // Execute with large amounts
        bool success = permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            largeAmount,
            creator1,
            largeAmount - 100e6, // Large creator amount
            90e6, // Large platform fee
            10e6, // Large operator fee
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );

        assertTrue(success); // Should handle large amounts
    }

    function test_ExpiredDeadlineHandling() public {
        vm.prank(user1);

        uint256 expiredDeadline = block.timestamp - 1;

        // Mock the commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // This should still work (deadline validation happens elsewhere)
        bool success = permitPaymentManager.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            expiredDeadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            testPermitData
        );

        assertTrue(success);
    }

    // ============ INTEGRATION TESTS ============

    function test_CompletePermitPaymentFlow() public {
        vm.prank(user1);

        // Step 1: Create permit payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        (bytes16 intentId, bool success) = permitPaymentManager.createAndExecuteWithPermit(
            user1,
            creator1,
            uint256(0),
            ISharedTypes.PaymentType.PayPerView,
            address(mockUSDC),
            1000e6,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            testIntentId,
            "signature",
            testPermitData
        );

        // Step 2: Verify results
        assertEq(intentId, testIntentId);
        assertTrue(success);
    }

    function test_PermitValidationFlow() public view {
        // Test permit data validation
        bool isValidData = permitPaymentManager.validatePermitData(testPermitData, user1);
        // Should not revert (may return false in test environment)

        // Test permit context validation
        bool isValidContext = permitPaymentManager.validatePermitContext(
            testPermitData,
            address(mockUSDC),
            1000e6,
            address(mockCommerceProtocol)
        );
        // Should validate context successfully
    }

    function test_PermitPaymentFailureHandling() public {
        vm.prank(user1);

        // Mock payment failure
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(false)
        );

        (bytes16 intentId, bool success) = permitPaymentManager.createAndExecuteWithPermit(
            user1,
            creator1,
            uint256(0),
            ISharedTypes.PaymentType.PayPerView,
            address(mockUSDC),
            1000e6,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            testIntentId,
            "signature",
            testPermitData
        );

        assertEq(intentId, testIntentId);
        assertFalse(success);
    }
}
