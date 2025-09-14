// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { TestSetup } from "../helpers/TestSetup.sol";
import { SignatureManager } from "../../src/SignatureManager.sol";
import { ICommercePaymentsProtocol } from "../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title SignatureManager Unit Tests
 * @dev Tests the signature management functions of the SignatureManager contract
 * @notice Tests intent signing, signature validation, signer management, etc.
 */
contract SignatureManagerTest is TestSetup {
    address public additionalSigner = address(0x9999);
    address public unauthorizedUser = address(0x8888);

    // Sample transfer intent for testing
    ICommercePaymentsProtocol.TransferIntent public testIntent;

    function setUp() public override {
        super.setUp();

        // SignatureManager is already deployed in TestSetup
        signatureManager = SignatureManager(commerceIntegration.signatureManager());

        // Create a sample transfer intent for testing
        testIntent = ICommercePaymentsProtocol.TransferIntent({
            recipientAmount: 1000e6, // 1000 USDC
            deadline: block.timestamp + 3600,
            recipient: payable(creator1),
            recipientCurrency: address(mockUSDC),
            refundDestination: user1,
            feeAmount: 5e6, // 5 USDC fee
            id: bytes16(keccak256("test-intent")),
            operator: address(commerceIntegration),
            signature: "",
            prefix: "",
            sender: user1,
            token: address(mockUSDC)
        });
    }

    // ============ SIGNER MANAGEMENT TESTS ============

    function test_AddAuthorizedSigner_Success() public {
        vm.prank(admin);

        signatureManager.addAuthorizedSigner(additionalSigner);

        assertTrue(signatureManager.isAuthorizedSigner(additionalSigner));
    }

    function test_AddAuthorizedSigner_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        signatureManager.addAuthorizedSigner(additionalSigner);
    }

    function test_AddAuthorizedSigner_RevertIfInvalidAddress() public {
        vm.prank(admin);

        vm.expectRevert("Invalid signer");
        signatureManager.addAuthorizedSigner(address(0));
    }

    function test_RemoveAuthorizedSigner_Success() public {
        vm.prank(admin);

        // First add the signer
        signatureManager.addAuthorizedSigner(additionalSigner);
        assertTrue(signatureManager.isAuthorizedSigner(additionalSigner));

        // Then remove it
        signatureManager.removeAuthorizedSigner(additionalSigner);
        assertFalse(signatureManager.isAuthorizedSigner(additionalSigner));
    }

    function test_RemoveAuthorizedSigner_RevertIfNotOwner() public {
        vm.prank(user1);

        vm.expectRevert("Ownable: caller is not the owner");
        signatureManager.removeAuthorizedSigner(admin);
    }

    function test_IsAuthorizedSigner_DefaultSigner() public view {
        // The operator signer set during construction should be authorized
        assertTrue(signatureManager.isAuthorizedSigner(commerceIntegration.operatorSigner()));
    }

    function test_IsAuthorizedSigner_UnauthorizedAddress() public view {
        assertFalse(signatureManager.isAuthorizedSigner(unauthorizedUser));
    }

    // ============ INTENT SIGNING TESTS ============

    function test_PrepareIntentForSigning_Success() public {
        vm.prank(admin);

        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Verify intent hash is stored
        assertEq(signatureManager.intentHashes(testIntent.id), intentHash);

        // Verify intent is not ready for execution yet (no signature)
        assertFalse(signatureManager.hasSignature(testIntent.id));

        // Verify intent hash is not zero
        assertTrue(intentHash != bytes32(0));
    }

    function test_PrepareIntentForSigning_Events() public {
        vm.prank(admin);

        vm.expectEmit(true, false, false, true);
        emit SignatureManager.IntentReadyForSigning(testIntent.id, bytes32(0), testIntent.deadline);

        signatureManager.prepareIntentForSigning(testIntent);
    }

    function test_PrepareIntentForSigning_IntentHashCalculation() public {
        vm.prank(admin);

        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Manually calculate the expected hash
        bytes32 structHash = keccak256(
            abi.encode(
                signatureManager.TRANSFER_INTENT_TYPEHASH(),
                testIntent.recipientAmount,
                testIntent.deadline,
                testIntent.recipient,
                testIntent.recipientCurrency,
                testIntent.refundDestination,
                testIntent.feeAmount,
                testIntent.id,
                testIntent.operator
            )
        );

        bytes32 expectedHash = keccak256(abi.encodePacked("\x19\x01", signatureManager.DOMAIN_SEPARATOR(), structHash));

        assertEq(intentHash, expectedHash);
    }

    // ============ SIGNATURE PROVIDER TESTS ============

    function test_ProvideIntentSignature_Success() public {
        vm.prank(admin);

        // First prepare the intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create a valid signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Provide the signature
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Verify signature is stored and intent is ready for execution
        assertTrue(signatureManager.hasSignature(testIntent.id));
        assertEq(signatureManager.getIntentSignature(testIntent.id), signature);
    }

    function test_ProvideIntentSignature_RevertIfIntentNotFound() public {
        vm.prank(admin);

        bytes16 invalidIntentId = bytes16(keccak256("invalid-intent"));
        bytes memory signature = "dummy-signature";

        vm.expectRevert("Intent not found");
        signatureManager.provideIntentSignature(invalidIntentId, signature, commerceIntegration.operatorSigner());
    }

    function test_ProvideIntentSignature_RevertIfInvalidSignatureLength() public {
        vm.prank(admin);

        // First prepare the intent for signing
        signatureManager.prepareIntentForSigning(testIntent);

        // Provide invalid signature (wrong length)
        bytes memory invalidSignature = "invalid";

        vm.expectRevert("Invalid signature length");
        signatureManager.provideIntentSignature(testIntent.id, invalidSignature, commerceIntegration.operatorSigner());
    }

    function test_ProvideIntentSignature_RevertIfUnauthorizedSigner() public {
        vm.prank(admin);

        // First prepare the intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create signature with unauthorized signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(unauthorizedUser)),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Unauthorized signer");
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());
    }

    function test_ProvideIntentSignature_RevertIfWrongCaller() public {
        vm.prank(admin);

        // First prepare the intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create valid signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to provide signature from wrong caller
        vm.prank(user1);
        vm.expectRevert("Only operator can provide signature");
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());
    }

    function test_ProvideIntentSignature_RevertIfAlreadySigned() public {
        vm.prank(admin);

        // First prepare the intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create and provide first signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Try to provide second signature
        vm.expectRevert("Intent already signed");
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());
    }

    function test_ProvideIntentSignature_Events() public {
        vm.prank(admin);

        // First prepare the intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create a valid signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, false, false, true);
        emit SignatureManager.IntentSigned(testIntent.id, signature);

        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());
    }

    // ============ GET SIGNATURE TESTS ============

    function test_GetIntentSignature_Success() public {
        vm.prank(admin);

        // First prepare and sign the intent
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Get the signature
        bytes memory retrievedSignature = signatureManager.getIntentSignature(testIntent.id);

        assertEq(retrievedSignature, signature);
    }

    function test_GetIntentSignature_RevertIfNotReady() public {
        vm.prank(admin);

        // Prepare intent but don't sign it
        signatureManager.prepareIntentForSigning(testIntent);

        vm.expectRevert("Intent not ready");
        signatureManager.getIntentSignature(testIntent.id);
    }

    // ============ HAS SIGNATURE TESTS ============

    function test_HasSignature_TrueAfterSigning() public {
        vm.prank(admin);

        // First prepare and sign the intent
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        assertTrue(signatureManager.hasSignature(testIntent.id));
    }

    function test_HasSignature_FalseBeforeSigning() public {
        vm.prank(admin);

        // Prepare intent but don't sign it
        signatureManager.prepareIntentForSigning(testIntent);

        assertFalse(signatureManager.hasSignature(testIntent.id));
    }

    function test_HasSignature_FalseForUnknownIntent() public view {
        bytes16 unknownIntentId = bytes16(keccak256("unknown-intent"));

        assertFalse(signatureManager.hasSignature(unknownIntentId));
    }

    // ============ COMPLETE SIGNING FLOW TESTS ============

    function test_CompleteSigningFlow_Success() public {
        vm.prank(admin);

        // Step 1: Prepare intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);
        assertFalse(signatureManager.hasSignature(testIntent.id));

        // Step 2: Create signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Step 3: Provide signature
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Step 4: Verify intent is ready for execution
        assertTrue(signatureManager.hasSignature(testIntent.id));
        assertEq(signatureManager.getIntentSignature(testIntent.id), signature);
    }

    function test_MultipleSigners_Success() public {
        vm.prank(admin);

        // Add additional authorized signer
        signatureManager.addAuthorizedSigner(additionalSigner);

        // Prepare intent for signing
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create signature with additional signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(additionalSigner)),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Provide signature with additional signer
        signatureManager.provideIntentSignature(testIntent.id, signature, commerceIntegration.operatorSigner());

        // Verify it works
        assertTrue(signatureManager.hasSignature(testIntent.id));
        assertEq(signatureManager.getIntentSignature(testIntent.id), signature);
    }

    function test_SignatureValidation_FullFlow() public {
        vm.prank(admin);

        // Prepare intent
        bytes32 intentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Create valid signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory validSignature = abi.encodePacked(r, s, v);

        // Create invalid signature (wrong private key)
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            uint256(uint160(unauthorizedUser)),
            intentHash
        );
        bytes memory invalidSignature = abi.encodePacked(r2, s2, v2);

        // Valid signature should work
        signatureManager.provideIntentSignature(testIntent.id, validSignature, commerceIntegration.operatorSigner());
        assertTrue(signatureManager.hasSignature(testIntent.id));

        // Reset for next test
        vm.prank(admin);
        testIntent.id = bytes16(keccak256("test-intent-2"));
        bytes32 newIntentHash = signatureManager.prepareIntentForSigning(testIntent);

        // Invalid signature should fail
        vm.expectRevert("Unauthorized signer");
        signatureManager.provideIntentSignature(testIntent.id, invalidSignature, commerceIntegration.operatorSigner());
    }

    // ============ EDGE CASE TESTS ============

    function test_ZeroAddressHandling() public {
        vm.prank(admin);

        // Test with zero address signer
        vm.expectRevert("Invalid signer");
        signatureManager.addAuthorizedSigner(address(0));

        // Test removing zero address
        signatureManager.removeAuthorizedSigner(address(0)); // Should not revert
    }

    function test_EmptySignatureHandling() public {
        vm.prank(admin);

        signatureManager.prepareIntentForSigning(testIntent);

        vm.expectRevert("Invalid signature length");
        signatureManager.provideIntentSignature(testIntent.id, "", commerceIntegration.operatorSigner());
    }

    function test_ExpiredIntentHandling() public {
        vm.prank(admin);

        // Create intent with past deadline
        ICommercePaymentsProtocol.TransferIntent memory expiredIntent = testIntent;
        expiredIntent.deadline = block.timestamp - 1;

        // Prepare intent (this doesn't validate deadline)
        signatureManager.prepareIntentForSigning(expiredIntent);

        // Create and provide signature
        bytes32 intentHash = signatureManager.intentHashes(expiredIntent.id);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(uint160(commerceIntegration.operatorSigner())),
            intentHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // This should still work (signature validation doesn't check deadline)
        signatureManager.provideIntentSignature(expiredIntent.id, signature, commerceIntegration.operatorSigner());
        assertTrue(signatureManager.hasSignature(expiredIntent.id));
    }
}
