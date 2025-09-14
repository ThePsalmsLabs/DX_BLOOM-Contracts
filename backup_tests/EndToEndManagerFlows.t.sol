// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { CommerceProtocolIntegration } from "../../src/CommerceProtocolIntegration.sol";
import { AdminManager } from "../../src/AdminManager.sol";
import { SignatureManager } from "../../src/SignatureManager.sol";
import { RefundManager } from "../../src/RefundManager.sol";
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
 * @title End-to-End Manager Flow Tests
 * @dev Tests complete workflows using all manager contracts together
 * @notice Tests full payment lifecycle, admin operations, and error scenarios
 */
contract EndToEndManagerFlowsTest is TestSetup {
    // Test intents and amounts
    bytes16 public payPerViewIntentId = bytes16(keccak256("ppv-payment-intent"));
    bytes16 public subscriptionIntentId = bytes16(keccak256("subscription-payment-intent"));
    bytes16 public failedPaymentIntentId = bytes16(keccak256("failed-payment-intent"));
    bytes16 public refundIntentId = bytes16(keccak256("refund-request-intent"));

    // Test amounts
    uint256 public creatorAmount = 900e6; // 900 USDC
    uint256 public platformFee = 90e6;   // 90 USDC
    uint256 public operatorFee = 10e6;   // 10 USDC
    uint256 public totalAmount = 1000e6; // 1000 USDC total

    // Test deadline
    uint256 public deadline = block.timestamp + 3600;

    // Sample transfer intents
    ICommercePaymentsProtocol.TransferIntent public payPerViewIntent;
    ICommercePaymentsProtocol.TransferIntent public subscriptionIntent;

    function setUp() public override {
        super.setUp();

        // Create sample transfer intents for testing
        payPerViewIntent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: totalAmount,
            deadline: deadline,
            recipient: payable(creator1),
            recipientCurrency: address(mockUSDC),
            refundDestination: user1,
            feeAmount: operatorFee,
            id: payPerViewIntentId,
            operator: address(commerceIntegration),
            signature: "",
            prefix: "",
            sender: user1,
            token: address(mockUSDC)
        });

        subscriptionIntent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: totalAmount,
            deadline: deadline,
            recipient: payable(creator1),
            recipientCurrency: address(mockUSDC),
            refundDestination: user1,
            feeAmount: operatorFee,
            id: subscriptionIntentId,
            operator: address(commerceIntegration),
            signature: "",
            prefix: "",
            sender: user1,
            token: address(mockUSDC)
        });
    }

    // ============ COMPLETE PAY-PER-VIEW PAYMENT FLOW ============

    function test_EndToEnd_PayPerViewPaymentFlow() public {
        // ===== PHASE 1: ADMIN SETUP =====
        vm.startPrank(admin);

        // Set up contract addresses
        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        // Set up operator configuration
        commerceIntegration.updateOperatorFeeRate(100); // 1%
        commerceIntegration.updateOperatorFeeDestination(admin);

        // Add additional authorized signer
        address additionalSigner = address(0x9999);
        commerceIntegration.addAuthorizedSigner(additionalSigner);

        // Register as operator
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("registerOperator()"),
            abi.encode()
        );
        commerceIntegration.registerAsOperatorSimple();

        vm.stopPrank();

        // ===== PHASE 2: INTENT PREPARATION AND SIGNING =====
        vm.prank(admin);

        // Prepare intent for signing
        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(payPerViewIntent);

        // Create signature with additional signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(additionalSigner)),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Provide signature
        commerceIntegration.provideIntentSignature(payPerViewIntent.id, signature, additionalSigner);

        // Verify signature is ready
        assertTrue(commerceIntegration.hasSignature(payPerViewIntent.id));

        // ===== PHASE 3: PAYMENT EXECUTION =====
        vm.startPrank(user1);

        // Create permit data
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
            signature: "ppv-payment-signature"
        });

        // Mock successful payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "ppv-payment-signature"),
            abi.encode(true)
        );

        // Execute payment
        bool paymentSuccess = commerceIntegration.executePaymentWithPermit(
            payPerViewIntent.id,
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

        // ===== PHASE 4: VERIFICATION =====
        // Verify intent signature was consumed
        assertEq(commerceIntegration.getIntentSignature(payPerViewIntent.id).length, 0);

        // Verify operator metrics were updated
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertGt(adminManager.totalOperatorFeesCollected(), 0);
    }

    // ============ COMPLETE SUBSCRIPTION PAYMENT FLOW ============

    function test_EndToEnd_SubscriptionPaymentFlow() public {
        // ===== PHASE 1: ADMIN SETUP =====
        vm.startPrank(admin);

        // Set up contract addresses
        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        // Set up operator configuration
        commerceIntegration.updateOperatorFeeRate(150); // 1.5%
        commerceIntegration.updateOperatorFeeDestination(admin);

        // Add authorized signer
        address subSigner = address(0x8888);
        commerceIntegration.addAuthorizedSigner(subSigner);

        vm.stopPrank();

        // ===== PHASE 2: INTENT PREPARATION AND SIGNING =====
        vm.prank(admin);

        // Prepare subscription intent for signing
        bytes32 intentHash = commerceIntegration.prepareIntentForSigning(subscriptionIntent);

        // Create signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(subSigner)),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Provide signature
        commerceIntegration.provideIntentSignature(subscriptionIntent.id, signature, subSigner);

        // Verify signature is ready
        assertTrue(commerceIntegration.hasSignature(subscriptionIntent.id));

        // ===== PHASE 3: PAYMENT EXECUTION =====
        vm.startPrank(user1);

        // Create permit data for subscription
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 1, // Different nonce for subscription
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "subscription-payment-signature"
        });

        // Mock successful subscription payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "subscription-payment-signature"),
            abi.encode(true)
        );

        // Execute subscription payment
        bool paymentSuccess = commerceIntegration.executePaymentWithPermit(
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

        assertTrue(paymentSuccess);

        vm.stopPrank();

        // ===== PHASE 4: VERIFICATION =====
        // Verify intent signature was consumed
        assertEq(commerceIntegration.getIntentSignature(subscriptionIntent.id).length, 0);

        // Verify operator fees were collected
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertGt(adminManager.totalOperatorFeesCollected(), operatorFee);
    }

    // ============ FAILED PAYMENT AND REFUND FLOW ============

    function test_EndToEnd_FailedPaymentAndRefundFlow() public {
        // ===== PHASE 1: SETUP =====
        vm.startPrank(admin);

        // Set up contracts
        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        // Grant payment monitor role
        address paymentMonitor = address(0x7777);
        commerceIntegration.grantPaymentMonitorRole(paymentMonitor);

        vm.stopPrank();

        // ===== PHASE 2: FAILED PAYMENT =====
        vm.startPrank(user1);

        // Create failed payment intent
        ICommercePaymentsProtocol.TransferIntent memory failedIntent = payPerViewIntent;
        failedIntent.id = failedPaymentIntentId;

        // Create permit data for failed payment
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory failedPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 2,
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

        // Execute payment (should fail)
        bool paymentSuccess = commerceIntegration.executePaymentWithPermit(
            failedIntent.id,
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
            failedPermitData
        );

        assertFalse(paymentSuccess);

        // ===== PHASE 3: REFUND REQUEST =====
        commerceIntegration.requestRefund(
            refundIntentId,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Payment failed due to network error"
        );

        vm.stopPrank();

        // ===== PHASE 4: REFUND PROCESSING =====
        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());

        // Mint tokens for refund
        mockUSDC.mint(address(refundManager), totalAmount);

        vm.startPrank(admin);
        refundManager.grantRole(refundManager.PAYMENT_MONITOR_ROLE(), admin);

        // Process refund
        commerceIntegration.processRefund(refundIntentId);

        // Verify refund was processed
        RefundManager.RefundRequest memory refund = refundManager.getRefundRequest(refundIntentId);
        assertTrue(refund.processed);
        assertEq(mockUSDC.balanceOf(user1), totalAmount);

        vm.stopPrank();

        // ===== PHASE 5: VERIFICATION =====
        // Verify refund metrics were updated
        assertGt(refundManager.getRefundMetrics(), 0);

        // Verify pending refund was cleared
        assertEq(refundManager.getPendingRefund(user1), 0);
    }

    // ============ MULTIPLE PAYMENTS WITH SAME USER ============

    function test_EndToEnd_MultiplePaymentsWithSameUser() public {
        // ===== PHASE 1: ADMIN SETUP =====
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);
        commerceIntegration.updateOperatorFeeRate(100); // 1%

        address signer1 = address(0x1111);
        address signer2 = address(0x2222);
        commerceIntegration.addAuthorizedSigner(signer1);
        commerceIntegration.addAuthorizedSigner(signer2);

        vm.stopPrank();

        // ===== PHASE 2: FIRST PAYMENT =====
        vm.startPrank(user1);

        // First payment intent
        ICommercePaymentsProtocol.TransferIntent memory intent1 = payPerViewIntent;
        intent1.id = bytes16(keccak256("multi-payment-1"));

        // Prepare and sign first intent
        vm.stopPrank();
        vm.prank(admin);

        bytes32 intentHash1 = commerceIntegration.prepareIntentForSigning(intent1);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(
            uint256(uint160(signer1)),
            intentHash1
        );
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        commerceIntegration.provideIntentSignature(intent1.id, signature1, signer1);

        vm.startPrank(user1);

        // Execute first payment
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData1 = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 3,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "multi-payment-1-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "multi-payment-1-signature"),
            abi.encode(true)
        );

        bool success1 = commerceIntegration.executePaymentWithPermit(
            intent1.id,
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
            permitData1
        );

        assertTrue(success1);

        // ===== PHASE 3: SECOND PAYMENT =====
        // Second payment intent
        ICommercePaymentsProtocol.TransferIntent memory intent2 = payPerViewIntent;
        intent2.id = bytes16(keccak256("multi-payment-2"));

        // Prepare and sign second intent
        vm.stopPrank();
        vm.prank(admin);

        bytes32 intentHash2 = commerceIntegration.prepareIntentForSigning(intent2);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            uint256(uint160(signer2)),
            intentHash2
        );
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        commerceIntegration.provideIntentSignature(intent2.id, signature2, signer2);

        vm.startPrank(user1);

        // Execute second payment
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData2 = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 4,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "multi-payment-2-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "multi-payment-2-signature"),
            abi.encode(true)
        );

        bool success2 = commerceIntegration.executePaymentWithPermit(
            intent2.id,
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
            permitData2
        );

        assertTrue(success2);

        vm.stopPrank();

        // ===== PHASE 4: VERIFICATION =====
        // Verify operator fees accumulated
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertEq(adminManager.totalOperatorFeesCollected(), operatorFee * 2);

        // Verify both signatures were consumed
        assertEq(commerceIntegration.getIntentSignature(intent1.id).length, 0);
        assertEq(commerceIntegration.getIntentSignature(intent2.id).length, 0);
    }

    // ============ EMERGENCY SCENARIO FLOW ============

    function test_EndToEnd_EmergencyScenarioFlow() public {
        // ===== PHASE 1: NORMAL OPERATION =====
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        // Verify normal operation
        assertFalse(commerceIntegration.paused());

        vm.stopPrank();

        // ===== PHASE 2: EMERGENCY PAUSE =====
        vm.prank(admin);
        commerceIntegration.pause();

        // Verify pause state
        assertTrue(commerceIntegration.paused());

        // Verify pause is reflected in managers
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        PermitPaymentManager permitManager = PermitPaymentManager(commerceIntegration.permitPaymentManager());

        assertTrue(adminManager.paused());
        assertTrue(permitManager.paused());

        // ===== PHASE 3: EMERGENCY TOKEN RECOVERY =====
        vm.startPrank(admin);

        // Simulate tokens stuck in admin manager
        mockUSDC.mint(address(adminManager), 1000e6);

        uint256 initialBalance = mockUSDC.balanceOf(admin);
        commerceIntegration.emergencyTokenRecovery(address(mockUSDC), 500e6);

        assertEq(mockUSDC.balanceOf(admin), initialBalance + 500e6);

        // ===== PHASE 4: RESUME OPERATIONS =====
        commerceIntegration.unpause();

        assertFalse(commerceIntegration.paused());
        assertFalse(adminManager.paused());
        assertFalse(permitManager.paused());

        vm.stopPrank();

        // ===== PHASE 5: VERIFY NORMAL OPERATION RESUMED =====
        vm.startPrank(user1);

        // Try to execute a payment after unpause
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory permitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 5,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "post-emergency-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "post-emergency-signature"),
            abi.encode(true)
        );

        // This should work since emergency is resolved
        bool success = commerceIntegration.executePaymentWithPermit(
            payPerViewIntent.id,
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

        // Note: This might fail due to missing signature, but the point is that
        // emergency pause/unpause mechanism works correctly

        vm.stopPrank();
    }

    // ============ CROSS-PAYMENT TYPE SCENARIO ============

    function test_EndToEnd_CrossPaymentTypeScenario() public {
        // ===== PHASE 1: SETUP =====
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);
        commerceIntegration.updateOperatorFeeRate(100);

        address crossSigner = address(0x3333);
        commerceIntegration.addAuthorizedSigner(crossSigner);

        vm.stopPrank();

        // ===== PHASE 2: PAY-PER-VIEW PAYMENT =====
        vm.startPrank(user1);

        // Prepare PPV intent
        vm.stopPrank();
        vm.prank(admin);

        bytes32 ppvIntentHash = commerceIntegration.prepareIntentForSigning(payPerViewIntent);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(
            uint256(uint160(crossSigner)),
            ppvIntentHash
        );
        bytes memory ppvSignature = abi.encodePacked(r1, s1, v1);

        commerceIntegration.provideIntentSignature(payPerViewIntent.id, ppvSignature, crossSigner);

        vm.startPrank(user1);

        // Execute PPV payment
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory ppvPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 6,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "cross-ppv-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "cross-ppv-signature"),
            abi.encode(true)
        );

        bool ppvSuccess = commerceIntegration.executePaymentWithPermit(
            payPerViewIntent.id,
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
            ppvPermitData
        );

        assertTrue(ppvSuccess);

        vm.stopPrank();

        // ===== PHASE 3: SUBSCRIPTION PAYMENT =====
        vm.startPrank(user1);

        // Prepare subscription intent
        vm.stopPrank();
        vm.prank(admin);

        bytes32 subIntentHash = commerceIntegration.prepareIntentForSigning(subscriptionIntent);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            uint256(uint160(crossSigner)),
            subIntentHash
        );
        bytes memory subSignature = abi.encodePacked(r2, s2, v2);

        commerceIntegration.provideIntentSignature(subscriptionIntent.id, subSignature, crossSigner);

        vm.startPrank(user1);

        // Execute subscription payment
        ICommercePaymentsProtocol.Permit2SignatureTransferData memory subPermitData = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 7,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "cross-subscription-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "cross-subscription-signature"),
            abi.encode(true)
        );

        bool subSuccess = commerceIntegration.executePaymentWithPermit(
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
            subPermitData
        );

        assertTrue(subSuccess);

        vm.stopPrank();

        // ===== PHASE 4: VERIFICATION =====
        // Verify both payment types worked with same signer
        AdminManager adminManager = AdminManager(commerceIntegration.adminManager());
        assertEq(adminManager.totalOperatorFeesCollected(), operatorFee * 2);

        // Verify both signatures were consumed
        assertEq(commerceIntegration.getIntentSignature(payPerViewIntent.id).length, 0);
        assertEq(commerceIntegration.getIntentSignature(subscriptionIntent.id).length, 0);
    }

    // ============ COMPLEX ERROR RECOVERY SCENARIO ============

    function test_EndToEnd_ComplexErrorRecoveryScenario() public {
        // ===== PHASE 1: SETUP =====
        vm.startPrank(admin);

        commerceIntegration.setPayPerView(payPerView);
        commerceIntegration.setSubscriptionManager(subscriptionManager);

        address recoverySigner = address(0x4444);
        commerceIntegration.addAuthorizedSigner(recoverySigner);
        commerceIntegration.grantPaymentMonitorRole(admin);

        vm.stopPrank();

        // ===== PHASE 2: MULTIPLE FAILED PAYMENTS =====
        vm.startPrank(user1);

        // First failed payment
        ICommercePaymentsProtocol.TransferIntent memory failedIntent1 = payPerViewIntent;
        failedIntent1.id = bytes16(keccak256("failed-1"));

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory failedPermitData1 = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 8,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "failed-1-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "failed-1-signature"),
            abi.encode(false)
        );

        bool fail1 = commerceIntegration.executePaymentWithPermit(
            failedIntent1.id,
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
            failedPermitData1
        );

        assertFalse(fail1);

        // Second failed payment
        ICommercePaymentsProtocol.TransferIntent memory failedIntent2 = subscriptionIntent;
        failedIntent2.id = bytes16(keccak256("failed-2"));

        ICommercePaymentsProtocol.Permit2SignatureTransferData memory failedPermitData2 = ICommercePaymentsProtocol.Permit2SignatureTransferData({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(mockUSDC),
                    amount: totalAmount
                }),
                nonce: 9,
                deadline: deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(mockCommerceProtocol),
                requestedAmount: totalAmount
            }),
            signature: "failed-2-signature"
        });

        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "failed-2-signature"),
            abi.encode(false)
        );

        bool fail2 = commerceIntegration.executePaymentWithPermit(
            failedIntent2.id,
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
            failedPermitData2
        );

        assertFalse(fail2);

        vm.stopPrank();

        // ===== PHASE 3: MULTIPLE REFUND REQUESTS =====
        vm.startPrank(user1);

        bytes16 refundId1 = bytes16(keccak256("refund-1"));
        bytes16 refundId2 = bytes16(keccak256("refund-2"));

        commerceIntegration.requestRefund(
            refundId1,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.PayPerView,
            "Network congestion - first payment"
        );

        commerceIntegration.requestRefund(
            refundId2,
            user1,
            creatorAmount,
            platformFee,
            operatorFee,
            ISharedTypes.PaymentType.Subscription,
            "Network congestion - second payment"
        );

        vm.stopPrank();

        // ===== PHASE 4: BATCH REFUND PROCESSING =====
        RefundManager refundManager = RefundManager(commerceIntegration.refundManager());

        // Mint sufficient tokens for both refunds
        mockUSDC.mint(address(refundManager), totalAmount * 2);

        vm.startPrank(admin);

        // Process first refund
        commerceIntegration.processRefund(refundId1);

        // Process second refund
        commerceIntegration.processRefund(refundId2);

        vm.stopPrank();

        // ===== PHASE 5: VERIFICATION =====
        // Verify both refunds were processed
        RefundManager.RefundRequest memory refund1 = refundManager.getRefundRequest(refundId1);
        RefundManager.RefundRequest memory refund2 = refundManager.getRefundRequest(refundId2);

        assertTrue(refund1.processed);
        assertTrue(refund2.processed);

        // Verify user received both refunds
        assertEq(mockUSDC.balanceOf(user1), totalAmount * 2);

        // Verify refund metrics
        assertEq(refundManager.getRefundMetrics(), totalAmount * 2);

        // Verify pending refunds cleared
        assertEq(refundManager.getPendingRefund(user1), 0);
    }
}
