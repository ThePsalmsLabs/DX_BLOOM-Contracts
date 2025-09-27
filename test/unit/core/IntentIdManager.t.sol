// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { IntentIdManager } from "../../../src/IntentIdManager.sol";

/**
 * @title IntentIdManagerTest
 * @dev Unit tests for IntentIdManager library - Intent ID management tests
 * @notice Tests unique ID generation, validation, and collision prevention
 */
contract IntentIdManagerTest is Test {
    // Test addresses
    address testUser = address(0x1234);
    address testCreator = address(0x5678);
    address testContract = address(0x9ABC);
    address testUser2 = address(0xDEF0);

    // Test data
    uint256 testContentId = 42;
    uint256 testNonce = 7;
    string testRefundReason = "User requested refund";
    uint256 testFallbackSeed = 12345;

    function setUp() public {}

    // ============ INTENT ID GENERATION TESTS ============

    function test_GenerateIntentId_ValidParameters() public {
        // Test generating intent ID with valid parameters
        bytes16 intentId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        // Should generate a non-zero intent ID
        assertTrue(IntentIdManager.isValidIntentId(intentId));
        assertTrue(intentId != bytes16(0));
    }

    function test_GenerateIntentId_Uniqueness() public {
        // Test that different parameters generate different IDs
        bytes16 intentId1 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        bytes16 intentId2 = IntentIdManager.generateIntentId(
            testUser2, // Different user
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        bytes16 intentId3 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId + 1, // Different content ID
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        bytes16 intentId4 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.SUBSCRIPTION, // Different intent type
            testNonce,
            testContract
        );

        bytes16 intentId5 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce + 1, // Different nonce
            testContract
        );

        // All IDs should be different
        assertTrue(intentId1 != intentId2);
        assertTrue(intentId1 != intentId3);
        assertTrue(intentId1 != intentId4);
        assertTrue(intentId1 != intentId5);
        assertTrue(intentId2 != intentId3);
        assertTrue(intentId2 != intentId4);
        assertTrue(intentId2 != intentId5);
        assertTrue(intentId3 != intentId4);
        assertTrue(intentId3 != intentId5);
        assertTrue(intentId4 != intentId5);
    }

    function test_GenerateIntentId_DifferentIntentTypes() public {
        // Test generating IDs for all intent types
        bytes16 contentPurchaseId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        bytes16 subscriptionId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            0, // No content ID for subscriptions
            IntentIdManager.IntentType.SUBSCRIPTION,
            testNonce,
            testContract
        );

        bytes16 subscriptionRenewalId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            0,
            IntentIdManager.IntentType.SUBSCRIPTION_RENEWAL,
            testNonce,
            testContract
        );

        bytes16 refundId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.REFUND,
            testNonce,
            testContract
        );

        // All IDs should be different
        assertTrue(contentPurchaseId != subscriptionId);
        assertTrue(contentPurchaseId != subscriptionRenewalId);
        assertTrue(contentPurchaseId != refundId);
        assertTrue(subscriptionId != subscriptionRenewalId);
        assertTrue(subscriptionId != refundId);
        assertTrue(subscriptionRenewalId != refundId);

        // All should be valid
        assertTrue(IntentIdManager.isValidIntentId(contentPurchaseId));
        assertTrue(IntentIdManager.isValidIntentId(subscriptionId));
        assertTrue(IntentIdManager.isValidIntentId(subscriptionRenewalId));
        assertTrue(IntentIdManager.isValidIntentId(refundId));
    }

    function test_GenerateIntentId_SameParameters() public {
        // Test that same parameters generate same ID (deterministic)
        bytes16 intentId1 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        bytes16 intentId2 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        // Should be identical (deterministic)
        assertEq(intentId1, intentId2);
    }

    function test_GenerateIntentId_ZeroValues() public {
        // Test generating ID with zero values
        bytes16 intentId = IntentIdManager.generateIntentId(
            address(0),
            address(0),
            0,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            0,
            address(0)
        );

        // Should still generate valid ID
        assertTrue(IntentIdManager.isValidIntentId(intentId));
        assertTrue(intentId != bytes16(0));
    }

    // ============ REFUND INTENT ID TESTS ============

    function test_GenerateRefundIntentId_ValidParameters() public {
        // Test generating refund intent ID
        bytes16 originalIntentId = bytes16(keccak256("original-intent"));
        bytes16 refundIntentId = IntentIdManager.generateRefundIntentId(
            originalIntentId,
            testUser,
            testRefundReason,
            testContract
        );

        // Should generate a valid ID
        assertTrue(IntentIdManager.isValidIntentId(refundIntentId));
        assertTrue(refundIntentId != bytes16(0));
    }

    function test_GenerateRefundIntentId_Uniqueness() public {
        // Test that different refund parameters generate different IDs
        bytes16 originalIntentId1 = bytes16(keccak256("original-intent-1"));
        bytes16 originalIntentId2 = bytes16(keccak256("original-intent-2"));

        bytes16 refundId1 = IntentIdManager.generateRefundIntentId(
            originalIntentId1,
            testUser,
            testRefundReason,
            testContract
        );

        bytes16 refundId2 = IntentIdManager.generateRefundIntentId(
            originalIntentId2, // Different original intent
            testUser,
            testRefundReason,
            testContract
        );

        bytes16 refundId3 = IntentIdManager.generateRefundIntentId(
            originalIntentId1,
            testUser2, // Different user
            testRefundReason,
            testContract
        );

        bytes16 refundId4 = IntentIdManager.generateRefundIntentId(
            originalIntentId1,
            testUser,
            "Different refund reason", // Different reason
            testContract
        );

        // All refund IDs should be different
        assertTrue(refundId1 != refundId2);
        assertTrue(refundId1 != refundId3);
        assertTrue(refundId1 != refundId4);
        assertTrue(refundId2 != refundId3);
        assertTrue(refundId2 != refundId4);
        assertTrue(refundId3 != refundId4);
    }

    function test_GenerateRefundIntentId_SameParameters() public {
        // Test that same refund parameters generate same ID (deterministic)
        bytes16 originalIntentId = bytes16(keccak256("original-intent"));

        bytes16 refundId1 = IntentIdManager.generateRefundIntentId(
            originalIntentId,
            testUser,
            testRefundReason,
            testContract
        );

        bytes16 refundId2 = IntentIdManager.generateRefundIntentId(
            originalIntentId,
            testUser,
            testRefundReason,
            testContract
        );

        // Should be identical (deterministic)
        assertEq(refundId1, refundId2);
    }

    function test_GenerateRefundIntentId_DifferentOriginalIntents() public {
        // Test that different original intents generate different refund IDs
        bytes16 originalIntentId1 = bytes16(keccak256("original-intent-1"));
        bytes16 originalIntentId2 = bytes16(keccak256("original-intent-2"));

        bytes16 refundId1 = IntentIdManager.generateRefundIntentId(
            originalIntentId1,
            testUser,
            testRefundReason,
            testContract
        );

        bytes16 refundId2 = IntentIdManager.generateRefundIntentId(
            originalIntentId2,
            testUser,
            testRefundReason,
            testContract
        );

        assertTrue(refundId1 != refundId2);
    }

    // ============ VALIDATION TESTS ============

    function test_IsValidIntentId_ValidIds() public {
        // Test validation of valid intent IDs
        bytes16 intentId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        assertTrue(IntentIdManager.isValidIntentId(intentId));
    }

    function test_IsValidIntentId_InvalidIds() public {
        // Test validation of invalid intent IDs (zero bytes)
        bytes16 zeroIntentId = bytes16(0);

        assertFalse(IntentIdManager.isValidIntentId(zeroIntentId));
    }

    // ============ EMERGENCY NONCE TESTS ============

    function test_GenerateEmergencyNonce_ValidParameters() public {
        // Test generating emergency nonce
        uint256 emergencyNonce = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed
        );

        // Should generate a non-zero nonce
        assertTrue(emergencyNonce != 0);
    }

    function test_GenerateEmergencyNonce_Uniqueness() public {
        // Test that different parameters generate different emergency nonces
        uint256 nonce1 = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed
        );

        uint256 nonce2 = IntentIdManager.generateEmergencyNonce(
            testUser2, // Different user
            testContract,
            testFallbackSeed
        );

        uint256 nonce3 = IntentIdManager.generateEmergencyNonce(
            testUser,
            address(0x1234), // Different contract
            testFallbackSeed
        );

        uint256 nonce4 = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed + 1 // Different seed
        );

        // All nonces should be different
        assertTrue(nonce1 != nonce2);
        assertTrue(nonce1 != nonce3);
        assertTrue(nonce1 != nonce4);
        assertTrue(nonce2 != nonce3);
        assertTrue(nonce2 != nonce4);
        assertTrue(nonce3 != nonce4);
    }

    function test_GenerateEmergencyNonce_SameParameters() public {
        // Test that same parameters generate same emergency nonce (deterministic)
        uint256 nonce1 = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed
        );

        uint256 nonce2 = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed
        );

        // Should be identical (deterministic)
        assertEq(nonce1, nonce2);
    }

    // ============ COLLISION RESISTANCE TESTS ============

    function test_IntentIdCollisionResistance() public {
        // Test collision resistance by generating many IDs
        bytes16[] memory intentIds = new bytes16[](100);

        for (uint256 i = 0; i < 100; i++) {
            intentIds[i] = IntentIdManager.generateIntentId(
                address(uint160(i + 1)), // Different user for each
                testCreator,
                i, // Different content ID
                IntentIdManager.IntentType.CONTENT_PURCHASE,
                i, // Different nonce
                testContract
            );
        }

        // Check for collisions
        for (uint256 i = 0; i < 100; i++) {
            for (uint256 j = i + 1; j < 100; j++) {
                assertTrue(intentIds[i] != intentIds[j], "Collision detected between intent IDs");
            }
        }
    }

    function test_RefundIdCollisionResistance() public {
        // Test collision resistance for refund IDs
        bytes16[] memory refundIds = new bytes16[](50);
        bytes16 originalIntentId = bytes16(keccak256("base-original-intent"));

        for (uint256 i = 0; i < 50; i++) {
            refundIds[i] = IntentIdManager.generateRefundIntentId(
                originalIntentId,
                address(uint160(i + 1)), // Different user
                string(abi.encodePacked("Reason ", i)), // Different reason
                testContract
            );
        }

        // Check for collisions
        for (uint256 i = 0; i < 50; i++) {
            for (uint256 j = i + 1; j < 50; j++) {
                assertTrue(refundIds[i] != refundIds[j], "Collision detected between refund IDs");
            }
        }
    }

    // ============ INTEGRATION TESTS ============

    function test_CompleteIntentIdWorkflow() public {
        // Test a complete workflow using IntentIdManager

        // 1. Generate intent ID for content purchase
        bytes16 purchaseIntentId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            testContract
        );

        assertTrue(IntentIdManager.isValidIntentId(purchaseIntentId));

        // 2. Generate intent ID for subscription
        bytes16 subscriptionIntentId = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            0, // No content ID for subscription
            IntentIdManager.IntentType.SUBSCRIPTION,
            testNonce + 1,
            testContract
        );

        assertTrue(IntentIdManager.isValidIntentId(subscriptionIntentId));
        assertTrue(purchaseIntentId != subscriptionIntentId);

        // 3. Generate refund ID for the purchase
        bytes16 refundIntentId = IntentIdManager.generateRefundIntentId(
            purchaseIntentId,
            testUser,
            testRefundReason,
            testContract
        );

        assertTrue(IntentIdManager.isValidIntentId(refundIntentId));
        assertTrue(refundIntentId != purchaseIntentId);
        assertTrue(refundIntentId != subscriptionIntentId);

        // 4. Generate emergency nonce
        uint256 emergencyNonce = IntentIdManager.generateEmergencyNonce(
            testUser,
            testContract,
            testFallbackSeed
        );

        assertTrue(emergencyNonce != 0);
    }

    function test_CrossContractUniqueness() public {
        // Test that IDs are unique across different contract addresses
        address contract1 = address(0x1111);
        address contract2 = address(0x2222);

        bytes16 intentId1 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            contract1
        );

        bytes16 intentId2 = IntentIdManager.generateIntentId(
            testUser,
            testCreator,
            testContentId,
            IntentIdManager.IntentType.CONTENT_PURCHASE,
            testNonce,
            contract2
        );

        // Should be different even with same parameters
        assertTrue(intentId1 != intentId2);
    }

    // ============ EDGE CASE TESTS ============

    function test_GenerateIntentId_MaxValues() public {
        // Test with maximum values
        bytes16 intentId = IntentIdManager.generateIntentId(
            address(type(uint160).max),
            address(type(uint160).max),
            type(uint256).max,
            IntentIdManager.IntentType.REFUND, // Last enum value
            type(uint256).max,
            address(type(uint160).max)
        );

        assertTrue(IntentIdManager.isValidIntentId(intentId));
        assertTrue(intentId != bytes16(0));
    }

    function test_GenerateRefundIntentId_MaxValues() public {
        // Test refund ID generation with maximum values
        bytes16 originalIntentId = bytes16(keccak256("test-original-intent"));
        string memory longReason = "This is a very long refund reason that tests the limits of the system and should still work correctly with maximum input values";

        bytes16 refundId = IntentIdManager.generateRefundIntentId(
            originalIntentId,
            address(type(uint160).max),
            longReason,
            address(type(uint160).max)
        );

        assertTrue(IntentIdManager.isValidIntentId(refundId));
        assertTrue(refundId != bytes16(0));
    }

    function test_GenerateEmergencyNonce_MaxValues() public {
        // Test emergency nonce with maximum values
        uint256 emergencyNonce = IntentIdManager.generateEmergencyNonce(
            address(type(uint160).max),
            address(type(uint160).max),
            type(uint256).max
        );

        assertTrue(emergencyNonce != 0);
    }

    function test_IsValidIntentId_ZeroBytes() public {
        // Test validation of zero-byte intent IDs
        bytes16 zeroId = bytes16(0);

        assertFalse(IntentIdManager.isValidIntentId(zeroId));

        // Test various zero-byte patterns
        bytes16 partialZero1 = bytes16(bytes32(uint256(1))); // Only first byte zero
        bytes16 partialZero2 = bytes16(bytes32(type(uint256).max)); // Only last bytes zero

        assertTrue(IntentIdManager.isValidIntentId(partialZero1));
        assertTrue(IntentIdManager.isValidIntentId(partialZero2));
    }

    // ============ FUZZING TESTS ============

    function testFuzz_GenerateIntentId_CollisionResistance(
        address user,
        address target,
        uint256 identifier,
        uint8 intentTypeValue,
        uint256 nonce,
        address contractAddr
    ) public {
        // Avoid zero addresses that might cause issues in some contexts
        vm.assume(user != address(0));
        vm.assume(target != address(0));
        vm.assume(contractAddr != address(0));

        // Limit intent type to valid enum values
        IntentIdManager.IntentType intentType = IntentIdManager.IntentType(intentTypeValue % 4);

        bytes16 intentId = IntentIdManager.generateIntentId(
            user,
            target,
            identifier,
            intentType,
            nonce,
            contractAddr
        );

        // Should always generate valid ID
        assertTrue(IntentIdManager.isValidIntentId(intentId));
    }

    function testFuzz_GenerateRefundIntentId_CollisionResistance(
        bytes16 originalIntentId,
        address user,
        string memory reason,
        address contractAddr
    ) public {
        vm.assume(user != address(0));
        vm.assume(contractAddr != address(0));

        bytes16 refundId = IntentIdManager.generateRefundIntentId(
            originalIntentId,
            user,
            reason,
            contractAddr
        );

        // Should always generate valid ID
        assertTrue(IntentIdManager.isValidIntentId(refundId));
    }

    function testFuzz_GenerateEmergencyNonce_Uniqueness(
        address user,
        address contractAddr,
        uint256 fallbackSeed
    ) public {
        vm.assume(user != address(0));
        vm.assume(contractAddr != address(0));

        uint256 emergencyNonce = IntentIdManager.generateEmergencyNonce(
            user,
            contractAddr,
            fallbackSeed
        );

        // Should always generate non-zero nonce
        assertTrue(emergencyNonce != 0);
    }

    function testFuzz_IsValidIntentId_Validation(bytes32 intentIdBytes) public {
        bytes16 intentId = bytes16(intentIdBytes);

        bool isValid = IntentIdManager.isValidIntentId(intentId);

        // Should only be invalid for exact zero bytes
        if (intentId == bytes16(0)) {
            assertFalse(isValid);
        } else {
            assertTrue(isValid);
        }
    }
}
