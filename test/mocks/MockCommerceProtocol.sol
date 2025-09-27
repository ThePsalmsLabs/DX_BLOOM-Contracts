// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { IBaseCommerceIntegration, ISignatureTransfer } from "../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title MockCommerceProtocol
 * @dev Mock implementation of BaseCommerceProtocol for testing
 * @notice This contract simulates the BaseCommerceIntegration contract functionality
 */
contract MockCommerceProtocol is IBaseCommerceIntegration, ISignatureTransfer {
    using stdStorage for StdStorage;

    // Mock state
    mapping(address => bool) public registeredOperators;
    mapping(address => uint256) public operatorFees;
    mapping(address => address) public operatorFeeDestinations;

    // Events for testing
    event OperatorRegistered(address operator, address feeDestination);
    event PaymentExecuted(address from, address to, uint256 amount, bytes32 paymentHash);
    event TransferFailed(address from, address to, uint256 amount, string reason);

    // Mock data
    bool public shouldFailTransfers = false;
    bool public shouldFailRegistrations = false;
    bool public escrowPaymentSuccess = true;

    // Track payment attempts
    uint256 public paymentAttempts;
    uint256 public successfulPayments;

    /**
     * @dev Mock operator registration
     * @param feeDestination Where to send operator fees
     * @return operatorId The operator ID
     * @notice This function doesn't have an 'operator' parameter
     */
    function registerOperator(address feeDestination)
        external
        returns (bytes32 operatorId)
    {
        if (shouldFailRegistrations) {
            revert("MockCommerceProtocol: Registration failed");
        }

        registeredOperators[msg.sender] = true;
        operatorFeeDestinations[msg.sender] = feeDestination;
        operatorId = keccak256(abi.encodePacked(msg.sender, feeDestination, block.timestamp));

        emit OperatorRegistered(msg.sender, feeDestination);
    }

    /**
     * @dev Mock check if operator is registered
     * @param operator The operator address
     * @return registered Whether the operator is registered
     */
    function isOperatorRegistered(address operator) external view returns (bool) {
        return registeredOperators[operator];
    }

    /**
     * @dev Mock get operator fee destination
     * @return destination The fee destination address for the caller
     * @notice Uses msg.sender to determine the operator
     */
    function operatorFeeDestination() external view returns (address) {
        return operatorFeeDestinations[msg.sender];
    }

    /**
     * @dev Mock execute escrow payment
     * @param params The payment parameters
     * @return paymentHash The payment hash
     */
    function executeEscrowPayment(IBaseCommerceIntegration.EscrowPaymentParams memory params)
        external
        returns (bytes32 paymentHash)
    {
        paymentAttempts++;

        if (shouldFailTransfers || !escrowPaymentSuccess) {
            emit TransferFailed(params.payer, params.receiver, params.amount, "Mock transfer failure");
            revert("MockCommerceProtocol: Transfer failed");
        }

        paymentHash = keccak256(abi.encodePacked(
            params.payer,
            params.receiver,
            params.amount,
            params.paymentType,
            block.timestamp
        ));

        successfulPayments++;
        emit PaymentExecuted(params.payer, params.receiver, params.amount, paymentHash);
    }

    /**
     * @dev Mock batch payment execution
     * @param params Array of payment parameters
     * @return paymentHashes Array of payment hashes
     */
    function executeBatchEscrowPayment(IBaseCommerceIntegration.EscrowPaymentParams[] memory params)
        external
        returns (bytes32[] memory paymentHashes)
    {
        paymentHashes = new bytes32[](params.length);

        for (uint256 i = 0; i < params.length; i++) {
            paymentAttempts++;

            if (shouldFailTransfers || !escrowPaymentSuccess) {
                emit TransferFailed(params[i].payer, params[i].receiver, params[i].amount, "Mock batch transfer failure");
                revert("MockCommerceProtocol: Batch transfer failed");
            }

            paymentHashes[i] = keccak256(abi.encodePacked(
                params[i].payer,
                params[i].receiver,
                params[i].amount,
                params[i].paymentType,
                block.timestamp,
                i
            ));

            successfulPayments++;
            emit PaymentExecuted(params[i].payer, params[i].receiver, params[i].amount, paymentHashes[i]);
        }
    }

    /**
     * @dev Mock token transfer
     * @param token The token address
     * @param signature The signature data
     * @return success Whether the transfer was successful
     */
    function transferToken(address token, bytes memory signature) external returns (bool success) {
        paymentAttempts++;

        if (shouldFailTransfers) {
            return false;
        }

        successfulPayments++;
        return true;
    }

    /**
     * @dev Mock get protocol fee rate
     * @return feeRate The protocol fee rate in basis points
     */
    function getProtocolFeeRate() external pure returns (uint256 feeRate) {
        return 50; // 0.5% protocol fee
    }

    /**
     * @dev Mock get operator fee
     * @param operator The operator address
     * @return feeAmount The operator fee amount
     */
    function getOperatorFee(address operator) external view returns (uint256 feeAmount) {
        return operatorFees[operator];
    }

    /**
     * @dev Mock set operator fee
     * @param operator The operator address
     * @param amount The fee amount
     */
    function setOperatorFee(address operator, uint256 amount) external {
        operatorFees[operator] = amount;
    }

    // Configuration functions for testing

    /**
     * @dev Set whether transfers should fail
     * @param shouldFail Whether transfers should fail
     */
    function setShouldFailTransfers(bool shouldFail) external {
        shouldFailTransfers = shouldFail;
    }

    /**
     * @dev Set whether registrations should fail
     * @param shouldFail Whether registrations should fail
     */
    function setShouldFailRegistrations(bool shouldFail) external {
        shouldFailRegistrations = shouldFail;
    }

    /**
     * @dev Set escrow payment success state
     * @param success Whether escrow payments should succeed
     */
    function setEscrowPaymentSuccess(bool success) external {
        escrowPaymentSuccess = success;
    }

    /**
     * @dev Get payment statistics
     * @return attempts Number of payment attempts
     * @return successful Number of successful payments
     */
    function getPaymentStats() external view returns (uint256 attempts, uint256 successful) {
        return (paymentAttempts, successfulPayments);
    }

    /**
     * @dev Reset all mock data
     */
    function resetMockData() external {
        paymentAttempts = 0;
        successfulPayments = 0;
        shouldFailTransfers = false;
        shouldFailRegistrations = false;
        escrowPaymentSuccess = true;

        // Clear mappings - simplified for testing
        registeredOperators[msg.sender] = false;
        nonces[msg.sender] = 0;
    }

    /**
     * @dev Mock domain separator for permit functionality
     * @return separator The domain separator
     */
    function getDomainSeparator() external pure returns (bytes32 separator) {
        return keccak256("MockCommerceProtocolDomain");
    }

    // Mock nonce for ISignatureTransfer interface
    mapping(address => uint256) public nonces;

    /**
     * @dev Mock nonce getter for ISignatureTransfer interface
     * @param owner The owner address
     * @return nonce The nonce for the owner
     */
    function nonce(address owner) external view returns (uint256) {
        return nonces[owner];
    }

    /**
     * @dev Mock set nonce for testing
     * @param owner The owner address
     * @param _nonce The nonce value
     */
    function setNonce(address owner, uint256 _nonce) external {
        nonces[owner] = _nonce;
    }

    // Mock Permit2 functionality for ISignatureTransfer interface
    struct MockTokenPermissions {
        address token;
        uint256 amount;
    }

    struct MockPermitTransferFrom {
        MockTokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct MockSignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    bytes32 public constant DOMAIN_SEPARATOR = keccak256("MockCommerceProtocolDomain");

    /**
     * @dev Mock permitTransferFrom for ISignatureTransfer interface
     */
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom calldata /* permit */,
        ISignatureTransfer.SignatureTransferDetails calldata /* transferDetails */,
        address /* owner */,
        bytes calldata /* signature */
    ) external {
        // Mock implementation - always succeeds
    }
}