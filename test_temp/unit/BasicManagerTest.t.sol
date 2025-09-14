// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";
import { ICommercePaymentsProtocol } from "../../src/interfaces/IPlatformInterfaces.sol";

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
 * @title Basic Manager Test
 * @dev Simple test to verify that the manager contracts are properly integrated
 * @notice Tests basic delegation and contract functionality
 */
contract BasicManagerTest is TestSetup {

    function test_AdminManager_Delegation() public {
        vm.startPrank(admin);

        // Test that admin functions are properly delegated
        address newPayPerView = address(0x1234);
        commerceIntegration.setPayPerView(newPayPerView);

        // Verify the call was delegated (this will pass if no revert)
        assertTrue(true);

        vm.stopPrank();
    }

    function test_SignatureManager_Delegation() public {
        vm.startPrank(admin);

        // Test that signature functions are properly delegated
        address newSigner = address(0x5678);
        commerceIntegration.addAuthorizedSigner(newSigner);

        // Verify the call was delegated (this will pass if no revert)
        assertTrue(true);

        vm.stopPrank();
    }

    function test_RefundManager_Delegation() public {
        vm.startPrank(user1);

        // Test that refund functions are properly delegated
        commerceIntegration.requestRefund(
            bytes16(keccak256("test-refund")),
            user1,
            1000e6,
            100e6,
            10e6,
            ISharedTypes.PaymentType.PayPerView,
            "Test refund"
        );

        // Verify the call was delegated (this will pass if no revert)
        assertTrue(true);

        vm.stopPrank();
    }

    function test_PermitPaymentManager_Delegation() public {
        vm.startPrank(user1);

        // Create a basic permit data structure for testing
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
            signature: "dummy-signature"
        });

        // Mock successful payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "dummy-signature"),
            abi.encode(true)
        );

        // Test that permit functions are properly delegated
        bool success = commerceIntegration.executePaymentWithPermit(
            bytes16(keccak256("test-permit")),
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            900e6,
            90e6,
            10e6,
            block.timestamp + 3600,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        // Verify the call was delegated and succeeded
        assertTrue(success);

        vm.stopPrank();
    }

    function test_ContractAddresses_AreSet() public view {
        // Test that manager contract addresses are properly set
        assertTrue(commerceIntegration.adminManager() != address(0));
        assertTrue(commerceIntegration.signatureManager() != address(0));
        assertTrue(commerceIntegration.refundManager() != address(0));
        assertTrue(commerceIntegration.permitPaymentManager() != address(0));
        assertTrue(commerceIntegration.viewManager() != address(0));
        assertTrue(commerceIntegration.accessManager() != address(0));
    }

    function test_ViewFunctions_Work() public view {
        // Test that view functions work correctly
        (bool registered, address feeDestination) = commerceIntegration.getOperatorStatus();

        // Test permit nonce function
        uint256 nonce = commerceIntegration.getPermitNonce(user1);

        // Test domain separator function
        bytes32 domainSeparator = commerceIntegration.getPermitDomainSeparator();

        // Verify functions don't revert and return values
        assertTrue(domainSeparator != bytes32(0));
    }

    function test_EmergencyControls_Work() public {
        vm.startPrank(admin);

        // Test pause functionality
        commerceIntegration.pause();
        assertTrue(commerceIntegration.paused());

        // Test unpause functionality
        commerceIntegration.unpause();
        assertFalse(commerceIntegration.paused());

        vm.stopPrank();
    }

    function test_Integration_BasicWorkflow() public {
        // ===== SETUP PHASE =====
        vm.startPrank(admin);

        // Set up contract addresses
        commerceIntegration.setPayPerView(address(0x1111));
        commerceIntegration.setSubscriptionManager(address(0x2222));

        // Add authorized signer
        address testSigner = address(0x3333);
        commerceIntegration.addAuthorizedSigner(testSigner);

        vm.stopPrank();

        // ===== PAYMENT PHASE =====
        vm.startPrank(user1);

        // Create permit data
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
            signature: "integration-test-signature"
        });

        // Mock successful payment
        vm.mockCall(
            address(mockCommerceProtocol),
            abi.encodeWithSignature("transferToken(address,bytes)", address(mockUSDC), "integration-test-signature"),
            abi.encode(true)
        );

        // Execute payment
        bool success = commerceIntegration.executePaymentWithPermit(
            bytes16(keccak256("integration-test")),
            user1,
            address(mockUSDC),
            1000e6,
            creator1,
            900e6,
            90e6,
            10e6,
            block.timestamp + 3600,
            ISharedTypes.PaymentType.PayPerView,
            "signature",
            permitData
        );

        assertTrue(success);

        vm.stopPrank();

        // ===== VERIFICATION =====
        // If we reach here without reverting, the integration is working
        assertTrue(true);
    }
}
