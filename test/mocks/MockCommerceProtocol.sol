// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ICommercePaymentsProtocol } from "../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title MockCommerceProtocol
 * @dev Mock implementation of the Base Commerce Payments Protocol
 * @notice This mock allows us to test our Commerce Protocol integration without
 *         depending on the actual deployed protocol. We can control exactly how
 *         it behaves, simulate different scenarios, and test edge cases.
 */
contract MockCommerceProtocol is ICommercePaymentsProtocol {
    // Track registered operators for testing
    mapping(address => bool) public registeredOperators;
    mapping(address => address) public operatorFeeDestinationsMap;

    // Track processed intents to prevent double-processing
    mapping(bytes16 => bool) public processedIntents;

    // Settings to control mock behavior
    bool public shouldFailTransfers;
    bool public shouldFailRegistration;
    uint256 public transferDelay;

    // Track function calls for testing
    uint256 public registerOperatorCalls;
    uint256 public transferCalls;
    uint256 public swapCalls;

    // Events (inherited from interface)

    /**
     * @dev Registers an operator without fee destination
     * @notice This simulates the real protocol's simple operator registration
     */
    function registerOperator() external override {
        registerOperatorCalls++;

        if (shouldFailRegistration) {
            revert("MockCommerceProtocol: Registration failed");
        }

        registeredOperators[msg.sender] = true;
        operatorFeeDestinationsMap[msg.sender] = msg.sender; // Default to operator address

        emit OperatorRegistered(msg.sender, msg.sender);
    }

    /**
     * @dev Registers an operator with specific fee destination
     * @param _feeDestination Where operator fees should be sent
     * @notice This simulates the real protocol's operator registration process
     */
    function registerOperatorWithFeeDestination(address _feeDestination) external override {
        registerOperatorCalls++;

        if (shouldFailRegistration) {
            revert("MockCommerceProtocol: Registration failed");
        }

        registeredOperators[msg.sender] = true;
        operatorFeeDestinationsMap[msg.sender] = _feeDestination;

        emit OperatorRegistered(msg.sender, _feeDestination);
    }

    /**
     * @dev Unregisters an operator
     * @notice This simulates the real protocol's operator unregistration
     */
    function unregisterOperator() external override {
        registeredOperators[msg.sender] = false;
        operatorFeeDestinationsMap[msg.sender] = address(0);
    }

    /**
     * @dev Mock implementation of native currency transfer
     * @param intent The transfer intent to execute
     * @notice This simulates ETH payments being processed by the protocol
     */
    function transferNative(TransferIntent calldata intent) external payable override {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of token transfer with Permit2
     * @param intent The transfer intent to execute
     * @param signatureTransferData The Permit2 signature data
     */
    function transferToken(TransferIntent calldata intent, Permit2SignatureTransferData calldata signatureTransferData)
        external
        override
    {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of pre-approved token transfer
     * @param intent The transfer intent to execute
     */
    function transferTokenPreApproved(TransferIntent calldata intent) external override {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of ETH to token swap and transfer
     * @param intent The transfer intent to execute
     * @param poolFeesTier The Uniswap pool fee tier
     */
    function swapAndTransferUniswapV3Native(TransferIntent calldata intent, uint24 poolFeesTier)
        external
        payable
        override
    {
        swapCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of token to token swap and transfer
     * @param intent The transfer intent to execute
     * @param signatureTransferData The Permit2 signature data
     * @param poolFeesTier The Uniswap pool fee tier
     */
    function swapAndTransferUniswapV3Token(
        TransferIntent calldata intent,
        Permit2SignatureTransferData calldata signatureTransferData,
        uint24 poolFeesTier
    ) external override {
        swapCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of pre-approved token swap and transfer
     * @param intent The transfer intent to execute
     * @param poolFeesTier The Uniswap pool fee tier
     */
    function swapAndTransferUniswapV3TokenPreApproved(TransferIntent calldata intent, uint24 poolFeesTier)
        external
        override
    {
        swapCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of ETH wrapping and transfer
     * @param intent The transfer intent to execute
     */
    function wrapAndTransfer(TransferIntent calldata intent) external payable override {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of WETH unwrapping and transfer
     * @param intent The transfer intent to execute
     */
    function unwrapAndTransfer(
        TransferIntent calldata intent,
        Permit2SignatureTransferData calldata signatureTransferData
    ) external override {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Mock implementation of pre-approved WETH unwrapping and transfer
     * @param intent The transfer intent to execute
     */
    function unwrapAndTransferPreApproved(TransferIntent calldata intent) external override {
        transferCalls++;
        _executeTransfer(intent);
    }

    /**
     * @dev Checks if an operator is registered
     * @param operator The operator address to check
     * @return Whether the operator is registered
     */
    function isOperatorRegistered(address operator) external view override returns (bool) {
        return registeredOperators[operator];
    }

    /**
     * @dev Gets the fee destination for an operator
     * @param operator The operator address
     * @return The fee destination address
     */
    function getOperatorFeeDestination(address operator) external view override returns (address) {
        return operatorFeeDestinationsMap[operator];
    }

    /**
     * @dev New interface function - checks if operator is registered
     * @param operator The operator address to check
     * @return Whether the operator is registered
     */
    function operators(address operator) external view override returns (bool) {
        return registeredOperators[operator];
    }

    /**
     * @dev New interface function - gets operator fee destinations
     * @param operator The operator address
     * @return The fee destination address
     */
    function operatorFeeDestinations(address operator) external view override returns (address) {
        return operatorFeeDestinationsMap[operator];
    }

    /**
     * @dev Internal function to execute a transfer
     * @param intent The transfer intent to execute
     * @notice This is where we simulate the actual payment processing
     */
    function _executeTransfer(TransferIntent calldata intent) internal {
        // Check if this intent has already been processed
        if (processedIntents[intent.id]) {
            revert AlreadyProcessed();
        }

        // Check if the intent has expired
        if (block.timestamp > intent.deadline) {
            revert ExpiredIntent();
        }

        // Check if the operator is registered
        if (!registeredOperators[intent.operator]) {
            revert OperatorNotRegistered();
        }

        // Simulate failure if configured to do so
        if (shouldFailTransfers) {
            revert("MockCommerceProtocol: Transfer failed");
        }

        // Mark intent as processed
        processedIntents[intent.id] = true;

        // Simulate transfer delay if configured
        if (transferDelay > 0) {
            // In a real test, we would advance time here
            // For now, we just track that a delay should occur
        }

        // Calculate the spent amount (this would be the actual amount paid)
        uint256 spentAmount = intent.recipientAmount + intent.feeAmount;

        // Emit the transfer event
        emit Transferred(
            intent.operator, intent.id, intent.recipient, msg.sender, spentAmount, intent.recipientCurrency
        );
    }

    // ============ MOCK CONFIGURATION FUNCTIONS ============

    /**
     * @dev Configure whether transfers should fail
     * @param shouldFail Whether transfers should fail
     */
    function setShouldFailTransfers(bool shouldFail) external {
        shouldFailTransfers = shouldFail;
    }

    /**
     * @dev Configure whether operator registration should fail
     * @param shouldFail Whether registration should fail
     */
    function setShouldFailRegistration(bool shouldFail) external {
        shouldFailRegistration = shouldFail;
    }

    /**
     * @dev Configure transfer delay for testing
     * @param delay The delay in seconds
     */
    function setTransferDelay(uint256 delay) external {
        transferDelay = delay;
    }

    /**
     * @dev Reset all call counters
     */
    function resetCounters() external {
        registerOperatorCalls = 0;
        transferCalls = 0;
        swapCalls = 0;
    }

    /**
     * @dev Reset processed intents (for testing)
     */
    function resetProcessedIntents() external {
        // In a real implementation, we'd clear the mapping
        // For testing, we'll just track that this was called
    }

    /**
     * @dev Manually mark an intent as processed (for testing)
     * @param intentId The intent ID to mark as processed
     */
    function markIntentAsProcessed(bytes16 intentId) external {
        processedIntents[intentId] = true;
    }
}
