// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { CommerceProtocolIntegration } from "../../src/CommerceProtocolIntegration.sol";
import { AdminManager } from "../../src/AdminManager.sol";
import { SignatureManager } from "../../src/SignatureManager.sol";
import { RefundManager } from "../../src/RefundManager.sol";
import { PermitPaymentManager } from "../../src/PermitPaymentManager.sol";
import { ViewManager } from "../../src/ViewManager.sol";
import { AccessManager } from "../../src/AccessManager.sol";
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
 * @title Cross-Contract Manager Integration Tests
 * @dev Tests integration between CommerceProtocolIntegration and all manager contracts
 * @notice Tests delegation patterns, cross-contract calls, and complete workflows
 */
contract CrossContractManagerIntegrationTest is TestSetup {
    bytes16 public testIntentId = bytes16(keccak256("integration-test-intent"));
    bytes16 public refundIntentId = bytes16(keccak256("refund-test-intent"));

    // Test payment amounts
    uint256 public creatorAmount = 900e6; // 900 USDC
    uint256 public platformFee = 90e6;   // 90 USDC
    uint256 public operatorFee = 10e6;   // 10 USDC
    uint256 public totalAmount = 1000e6; // 1000 USDC total

    // Test deadline
    uint256 public deadline = block.timestamp + 3600;

    // Sample transfer intent for testing
    ICommercePaymentsProtocol.TransferIntent public testIntent;

    function setUp() public override {
        super.setUp();

        // Create a sample transfer intent for testing
        testIntent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: totalAmount,
            deadline: deadline,
            recipient: payable(creator1),
            recipientCurrency: address(mockUSDC),
            refundDestination: user1,
            feeAmount: operatorFee,
            id: testIntentId,
            operator: address(commerceIntegration),
            signature: "",
            prefix: "",
            sender: user1,
            token: address(mockUSDC)
        });
    }

    // ============ DELEGATION PATTERN TESTS ============

    function test_AdminFunctionDelegation_Success() public {
        vm.startPrank(admin);

        // Test delegation of admin functions to AdminManager
        address newPayPerView = address(0x1234);
        commerceIntegration.setPayPerView(newPayPerView);

        // Verify the call was delegated to AdminManager
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertEq(address(adminManager.payPerView()), newPayPerView);

        // Test other admin delegations
        address newSubscriptionManager = address(0x5678);
        commerceIntegration.setSubscriptionManager(newSubscriptionManager);
        assertEq(address(adminManager.subscriptionManager()), newSubscriptionManager);

        // Test operator registration delegation
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperator()"),
            abi.encode()
        );
        commerceIntegration.registerAsOperatorSimple();

        vm.stopPrank();
    }

    function test_SignatureFunctionDelegation_Success() public {
        vm.startPrank(admin);

        // Test delegation of signature functions to SignatureManager
        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(testIntent);

        // Verify the intent was prepared in SignatureManager
        SignatureManager signatureManager = SignatureManager(commerceIntegration.signatureManager());
        assertEq(signatureManager.intentHashes(testIntent.id), intentHash);
        assertFalse(signatureManager.hasSignature(testIntent.id));

        // Create and provide signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test delegation of signature provision
        commerceIntegration.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Verify signature was stored
        assertTrue(signatureManager.hasSignature(testIntent.id));
        assertEq(signatureManager.getIntentSignature(testIntent.id), signature);

        vm.stopPrank();
    }

    function test_RefundFunctionDelegation_Success() public {
        vm.startPrank(user1);

        // Test delegation of refund functions to RefundManager
        commerceIntegration.requestRefund(
            refundIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Integration test refund"
        );

        // Verify refund was requested in RefundManager
        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(refundIntentId);
        assertEq(refund.originalIntentId, refundIntentId);
        assertEq(refund.user, user1);
        assertEq(refund.amount, totalAmount);

        // Mint tokens and grant role for processing
        mockUSDC.mint(address(refundManager), totalAmount);
        vm.prank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Test delegation of refund processing
        vm.prank(admin);
        commerceIntegration.processRefund(refundIntentId);

        // Verify refund was processed
        refund = refundManager.getRefundRequest(refundIntentId);
        assertTrue(refund.processed);
        assertEq(mockUSDC.balanceOf(user1), totalAmount);

        vm.stopPrank();
    }

    function test_PermitFunctionDelegation_Success() public {
        vm.startPrank(user1);

        // Create permit data for testing
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "dummy-signature"
        });

        // Mock commerce protocol call
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // Test delegation of permit payment execution
        bool success = commerceIntegration.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            totalAmount,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        // Verify the call was delegated to PermitPaymentManager
        assertTrue(success);

        vm.stopPrank();
    }

    // ============ CROSS-CONTRACT WORKFLOW TESTS ============

    function test_CompletePaymentWorkflow_CrossContract() public {
        // Step 1: Admin sets up contracts (delegated to AdminManager)
        vm.startPrank(admin);

        address newPayPerView = address(0x1111);
        address newSubscriptionManager = address(0x2222);

        commerceIntegration.setPayPerView(newPayPerView);
        commerceIntegration.setSubscriptionManager(newSubscriptionManager);

        // Step 2: Add authorized signer (delegated to SignatureManager)
        address additionalSigner = address(0x3333);
        commerceIntegration.addAuthorizedSigner(additionalSigner);

        vm.stopPrank();

        // Step 3: User creates and signs intent (delegated to SignatureManager)
        vm.prank(admin);

        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(testIntent);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(additionalSigner)),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        commerceIntegration.provideIntentSignature(testIntent.id, signature, additionalSigner);

        // Step 4: User executes permit payment (delegated to PermitPaymentManager)
        vm.startPrank(user1);

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "payment-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "payment-signature"),
            abi.encode(true)
        );

        bool paymentSuccess = commerceIntegration.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            totalAmount,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        assertTrue(paymentSuccess);

        vm.stopPrank();
    }

    function test_FailedPaymentRefundWorkflow_CrossContract() public {
        // Step 1: Execute a failed payment
        vm.startPrank(user1);

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "failed-payment-signature"
        });

        // Mock failed payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "failed-payment-signature"),
            abi.encode(false)
        );

        bool paymentSuccess = commerceIntegration.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            totalAmount,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        assertFalse(paymentSuccess);

        // Step 2: Request refund (delegated to RefundManager)
        commerceIntegration.requestRefund(
            refundIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Payment failed - requesting refund"
        );

        vm.stopPrank();

        // Step 3: Process refund (delegated to RefundManager)
        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());
        mockUSDC.mint(address(refundManager), totalAmount);

        vm.startPrank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        commerceIntegration.processRefund(refundIntentId);

        // Verify refund was processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(refundIntentId);
        assertTrue(refund.processed);
        assertEq(mockUSDC.balanceOf(user1), totalAmount);

        vm.stopPrank();
    }

    // ============ MULTI-CONTRACT COORDINATION TESTS ============

    function test_MultiContractCoordination_PayPerView() public {
        // Test coordination between multiple managers for PayPerView payments

        // Step 1: Admin setup (AdminManager)
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        // Grant payment monitor role (AdminManager)
        address paymentMonitor = address(0x9999);
        commerceIntegration.grantPaymentMonitorRole(paymentMonitor);

        vm.stopPrank();

        // Step 2: Signature preparation (SignatureManager)
        vm.prank(admin);

        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(testIntent);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.signatureManager())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        commerceIntegration.provideIntentSignature(testIntent.id, signature, commerceIntegration.signatureManager());

        // Step 3: Payment execution (PermitPaymentManager)
        vm.startPrank(user1);

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "coordination-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "coordination-signature"),
            abi.encode(true)
        );

        bool success = commerceIntegration.executePaymentWithPermit(
            testIntentId,
            user1,
            address(mockUSDC),
            totalAmount,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        assertTrue(success);

        vm.stopPrank();
    }

    function test_MultiContractCoordination_Subscription() public {
        // Test coordination between multiple managers for Subscription payments

        // Step 1: Admin setup (AdminManager)
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        vm.stopPrank();

        // Step 2: Signature preparation (SignatureManager)
        vm.prank(admin);

        ICommercePaymentsProtocol.TransferIntent memory subscriptionIntent = testIntent;
        subscriptionIntent.id = bytes16(keccak256("subscription-intent"));

        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(subscriptionIntent);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.signatureManager())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        commerceIntegration.provideIntentSignature(subscriptionIntent.id, signature, commerceIntegration.signatureManager());

        // Step 3: Payment execution (PermitPaymentManager)
        vm.startPrank(user1);

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 0,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "subscription-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "subscription-signature"),
            abi.encode(true)
        );

        bool success = commerceIntegration.executePaymentWithPermit(
            subscriptionIntent.id,
            user1,
            address(mockUSDC),
            totalAmount,
            creator1,
            creatorAmount,
            platformFee,
            operatorFee,
            deadline,
            ISharedTypes.PaymentType.Subscription,
            "signature",
            permitData
        );

        assertTrue(success);

        vm.stopPrank();
    }

    // ============ EMERGENCY CONTROL TESTS ============

    function test_EmergencyControlDelegation_CrossContract() public {
        // Test that emergency controls are properly delegated

        // Step 1: Test pause delegation (AdminManager)
        vm.startPrank(admin);

        commerceIntegration.pause();

        // Verify pause was delegated to AdminManager
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertTrue(adminManager.paused());

        // Verify pause was also set in PermitPaymentManager
        PermitPaymentManager permitManager = PermitPaymentManager(commerceIntegration.permitPaymentManager());
        assertTrue(permitManager.paused());

        // Step 2: Test unpause delegation
        commerceIntegration.unpause();

        assertFalse(adminManager.paused());
        assertFalse(permitManager.paused());

        // Step 3: Test emergency token recovery delegation
        mockUSDC.mint(address(adminManager), 1000e6);

        uint256 initialBalance = mockUSDC.balanceOf(admin);
        commerceIntegration.emergencyTokenRecovery(address(mockUSDC), 500e6);

        assertEq(mockUSDC.balanceOf(admin), initialBalance + 500e6);

        vm.stopPrank();
    }

    // ============ VIEW FUNCTION DELEGATION TESTS ============

    function test_ViewFunctionDelegation_Success() public {
        // Test that view functions are properly delegated

        // Test operator status delegation
        (bool registered, address feeDestination) = commerceIntegration.getOperatorStatus();

        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        (bool expectedRegistered, address expectedFeeDestination) = adminManager.getOperatorStatus();

        assertEq(registered, expectedRegistered);
        assertEq(feeDestination, expectedFeeDestination);

        // Test permit nonce delegation
        uint256 nonce = commerceIntegration.getPermitNonce(user1);

        PermitPaymentManager permitManager = PermitPaymentManager(commerceIntegration.permitPaymentManager());
        uint256 expectedNonce = permitManager.getPermitNonce(user1);

        assertEq(nonce, expectedNonce);

        // Test domain separator delegation
        bytes32 domainSeparator = commerceIntegration.getPermitDomainSeparator();
        bytes32 expectedDomainSeparator = permitManager.getPermitDomainSeparator();

        assertEq(domainSeparator, expectedDomainSeparator);
    }

    // ============ CROSS-CONTRACT EVENT TESTS ============

    function test_CrossContractEventEmission() public {
        vm.startPrank(user1);

        // Test that events are properly emitted across contracts

        // Request refund
        vm.expectEmit(true, true, false, true);
        emit RefundManager.RefundRequested(
            refundIntentId,
            user1,
            totalAmount,
            "Cross-contract event test"
        );

        commerceIntegration.requestRefund(
            refundIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Cross-contract event test"
        );

        vm.stopPrank();

        // Process refund
        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());
        mockUSDC.mint(address(refundManager), totalAmount);

        vm.startPrank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        vm.expectEmit(true, true, false, true);
        emit RefundManager.RefundProcessed(refundIntentId, user1, totalAmount);

        commerceIntegration.processRefund(refundIntentId);

        vm.stopPrank();
    }

    // ============ ERROR HANDLING TESTS ============

    function test_CrossContractErrorHandling() public {
        // Test that errors are properly handled across contract boundaries

        // Test invalid address handling
        vm.startPrank(admin);

        vm.expectRevert("Invalid address");
        commerceIntegration.setPayPerView(address(0));

        vm.expectRevert("Invalid address");
        commerceIntegration.setSubscriptionManager(address(0));

        vm.stopPrank();

        // Test unauthorized access handling
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        commerceIntegration.setPayPerView(address(0x1234));

        vm.expectRevert("Ownable: caller is not the owner");
        commerceIntegration.pause();
    }

    // ============ PERFORMANCE AND GAS TESTS ============

    function test_DelegationGasEfficiency() public {
        vm.startPrank(admin);

        // Measure gas usage for delegated calls vs direct calls
        uint256 gasBefore;

        // Test delegation gas cost
        gasBefore = gasleft();
        commerceIntegration.setPayPerView(address(0x1234));
        uint256 delegationGas = gasBefore - gasleft();

        // Test direct call gas cost for comparison
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        gasBefore = gasleft();
        adminManager.setPayPerView(address(0x5678));
        uint256 directGas = gasBefore - gasleft();

        // Delegation should have reasonable overhead (less than 50% more gas)
        assertTrue(delegationGas < directGas * 3/2);

        vm.stopPrank();
    }

    // ============ INTEGRATION EDGE CASES ============

    function test_CrossContractStateSynchronization() public {
        // Test that state changes are properly synchronized across contracts

        vm.startPrank(admin);

        // Change operator fee rate
        uint256 newRate = 150; // 1.5%
        commerceIntegration.updateOperatorFeeRate(newRate);

        // Verify it's reflected in AdminManager
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertEq(adminManager.operatorFeeRate(), newRate);

        // Change operator signer
        address newSigner = address(0x8888);
        commerceIntegration.updateOperatorSigner(newSigner);

        assertEq(adminManager.operatorSigner(), newSigner);

        // Verify signer is authorized in SignatureManager
        SignatureManager signatureManager = SignatureManager(commerceIntegration.signatureManager());
        assertTrue(signatureManager.isAuthorizedSigner(newSigner));

        vm.stopPrank();
    }

    function test_CrossContractFailureRecovery() public {
        // Test recovery mechanisms when cross-contract calls fail

        vm.startPrank(user1);

        // Request refund
        commerceIntegration.requestRefund(
            refundIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Failure recovery test"
        );

        vm.stopPrank();

        // Try to process refund without tokens (should handle gracefully)
        vm.startPrank(admin);

        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // This should revert due to insufficient balance, but not corrupt state
        vm.expectRevert(); // ERC20 transfer will revert
        commerceIntegration.processRefund(refundIntentId);

        // Verify refund request is still intact
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(refundIntentId);
        assertFalse(refund.processed);
        assertEq(refund.amount, totalAmount);

        vm.stopPrank();
    }
}
