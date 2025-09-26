// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import { ISharedTypes } from "../../src/interfaces/ISharedTypes.sol";

/**
 * @title TestUtils
 * @dev Utility functions for testing
 * @notice Provides common testing utilities and helpers
 */
library TestUtils {
    // ============ VALIDATION HELPERS ============

    function assertPaymentRequest(
        Test test,
        ISharedTypes.PlatformPaymentRequest memory request,
        ISharedTypes.PaymentType expectedType,
        address expectedCreator,
        uint256 expectedContentId
    ) internal pure {
        require(uint8(request.paymentType) == uint8(expectedType), "Payment type mismatch");
        require(request.creator == expectedCreator, "Creator mismatch");
        require(request.contentId == expectedContentId, "Content ID mismatch");
        require(request.deadline > 0, "Invalid deadline");
    }

    function assertPaymentContext(
        Test test,
        ISharedTypes.PaymentContext memory context,
        address expectedUser,
        address expectedCreator,
        ISharedTypes.PaymentType expectedType,
        uint256 expectedAmount
    ) internal pure {
        require(context.user == expectedUser, "User mismatch");
        require(context.creator == expectedCreator, "Creator mismatch");
        require(uint8(context.paymentType) == uint8(expectedType), "Payment type mismatch");
        require(context.expectedAmount == expectedAmount, "Amount mismatch");
        require(!context.processed, "Context already processed");
    }

    // ============ SIGNATURE HELPERS ============

    function createSignature(
        Vm vm,
        bytes32 hash,
        address signer
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), hash);
        return abi.encodePacked(r, s, v);
    }

    function createSignatureFromPrivateKey(
        Vm vm,
        bytes32 hash,
        uint256 privateKey
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function assertWithinRange(
        Test test,
        uint256 value,
        uint256 min,
        uint256 max,
        string memory message
    ) internal pure {
        require(value >= min && value <= max, message);
    }

    function assertNotZero(
        Test test,
        uint256 value,
        string memory message
    ) internal pure {
        require(value > 0, message);
    }

    function assertNotEmpty(
        Test test,
        string memory str,
        string memory message
    ) internal pure {
        require(bytes(str).length > 0, message);
    }

    function assertValidAddress(
        Test test,
        address addr,
        string memory message
    ) internal pure {
        require(addr != address(0), message);
    }

    // ============ CALCULATION HELPERS ============

    function calculateExpectedAmount(
        uint256 baseAmount,
        uint256 platformFeeRate,
        uint256 operatorFeeRate
    ) internal pure returns (uint256) {
        uint256 platformFee = (baseAmount * platformFeeRate) / 10000;
        uint256 operatorFee = (baseAmount * operatorFeeRate) / 10000;
        return baseAmount + platformFee + operatorFee;
    }

    function calculateCreatorAmount(
        uint256 totalAmount,
        uint256 platformFeeRate,
        uint256 operatorFeeRate
    ) internal pure returns (uint256) {
        uint256 platformFee = (totalAmount * platformFeeRate) / 10000;
        uint256 operatorFee = (totalAmount * operatorFeeRate) / 10000;
        return totalAmount - platformFee - operatorFee;
    }

    // ============ STRING HELPERS ============

    function stringToBytes32(string memory str) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(str));
    }


    // ============ ARRAY HELPERS ============

    function createStringArray(
        string memory str1,
        string memory str2
    ) internal pure returns (string[] memory) {
        string[] memory arr = new string[](2);
        arr[0] = str1;
        arr[1] = str2;
        return arr;
    }

    function createStringArray(
        string memory str1,
        string memory str2,
        string memory str3
    ) internal pure returns (string[] memory) {
        string[] memory arr = new string[](3);
        arr[0] = str1;
        arr[1] = str2;
        arr[2] = str3;
        return arr;
    }

    // ============ ENCODING HELPERS ============

    function encodePaymentRequest(
        ISharedTypes.PlatformPaymentRequest memory request
    ) internal pure returns (bytes memory) {
        return abi.encode(request);
    }

    function encodePaymentContext(
        ISharedTypes.PaymentContext memory context
    ) internal pure returns (bytes memory) {
        return abi.encode(context);
    }

    // ============ MATH HELPERS ============

    function percentageOf(
        uint256 amount,
        uint256 percentage
    ) internal pure returns (uint256) {
        return (amount * percentage) / 100;
    }

    function basisPointsOf(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        return (amount * basisPoints) / 10000;
    }

    // ============ TIME HELPERS ============

    function futureDeadline(
        uint256 secondsFromNow
    ) internal view returns (uint256) {
        return block.timestamp + secondsFromNow;
    }

    function pastDeadline(
        uint256 secondsAgo
    ) internal view returns (uint256) {
        return block.timestamp - secondsAgo;
    }

}
