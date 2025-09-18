// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { Pausable } from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
// Removed ICommercePaymentsProtocol import - no longer needed with new Base Commerce Protocol architecture
import { PayPerView } from "./PayPerView.sol";
import { SubscriptionManager } from "./SubscriptionManager.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AdminManager
 * @dev Manages administrative functions for the Commerce Protocol Integration
 * @notice This contract handles all admin operations to reduce main contract size
 */
contract AdminManager is Ownable, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");

    // Commerce Protocol integration - removed old interface reference
    // Now using BaseCommerceIntegration for real Base Commerce Protocol integration
    address public operatorFeeDestination;
    address public operatorSigner;
    uint256 public operatorFeeRate = 50; // 0.5% operator fee in basis points

    // Contract references
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;

    // Authorized signers mapping
    mapping(address => bool) public authorizedSigners;

    // ============ EVENTS ============

    event ContractAddressUpdated(string contractName, address oldAddress, address newAddress);
    event OperatorFeeUpdated(uint256 oldRate, uint256 newRate);
    event OperatorFeeDestinationUpdated(address oldDestination, address newDestination);
    event OperatorSignerUpdated(address oldSigner, address newSigner);
    event AuthorizedSignerAdded(address signer);
    event AuthorizedSignerRemoved(address signer);
    event PaymentMonitorRoleGranted(address monitor);
    event OperatorFeesWithdrawn(address token, uint256 amount);
    event OperatorRegistered(address operator, address feeDestination);
    event OperatorUnregistered(address operator);
    event EmergencyTokenRecovered(address token, uint256 amount);

    // ============ CONSTRUCTOR ============

    constructor(
        address _operatorFeeDestination,
        address _operatorSigner
    ) Ownable(msg.sender) {
        require(_operatorFeeDestination != address(0), "Invalid fee destination");
        require(_operatorSigner != address(0), "Invalid operator signer");

        operatorFeeDestination = _operatorFeeDestination;
        operatorSigner = _operatorSigner;
    }

    // ============ CONTRACT MANAGEMENT ============

    /**
     * @dev Sets the PayPerView contract address
     */
    function setPayPerView(address _payPerView) external onlyOwner {
        require(_payPerView != address(0), "Invalid address");
        address oldAddress = address(payPerView);
        payPerView = PayPerView(_payPerView);
        emit ContractAddressUpdated("PayPerView", oldAddress, _payPerView);
    }

    /**
     * @dev Sets the SubscriptionManager contract address
     */
    function setSubscriptionManager(address _subscriptionManager) external onlyOwner {
        require(_subscriptionManager != address(0), "Invalid address");
        address oldAddress = address(subscriptionManager);
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        emit ContractAddressUpdated("SubscriptionManager", oldAddress, _subscriptionManager);
    }

    // ============ OPERATOR MANAGEMENT ============

    /**
     * @dev Registers our platform as an operator in the Commerce Protocol
     * @notice This function is now handled through BaseCommerceIntegration
     */
    function registerAsOperator() external onlyOwner {
        // Registration is now handled through BaseCommerceIntegration contract
        // which interfaces with the real Base Commerce Protocol
        emit OperatorRegistered(address(this), operatorFeeDestination);
    }

    /**
     * @dev Alternative registration method without specifying fee destination
     * @notice This function is now handled through BaseCommerceIntegration
     */
    function registerAsOperatorSimple() external onlyOwner {
        // Registration is now handled through BaseCommerceIntegration contract
        emit OperatorRegistered(address(this), operatorFeeDestination);
    }

    /**
     * @dev Unregisters our platform as an operator
     * @notice This function is now handled through BaseCommerceIntegration
     */
    function unregisterAsOperator() external onlyOwner {
        // Unregistration is now handled through BaseCommerceIntegration contract
        emit OperatorUnregistered(address(this));
    }

    // ============ FEE MANAGEMENT ============

    /**
     * @dev Updates operator fee rate
     */
    function updateOperatorFeeRate(uint256 newRate) external onlyOwner {
        require(newRate <= 500, "Fee rate too high"); // Max 5%
        uint256 oldRate = operatorFeeRate;
        operatorFeeRate = newRate;
        emit OperatorFeeUpdated(oldRate, newRate);
    }

    /**
     * @dev Updates operator fee destination
     */
    function updateOperatorFeeDestination(address newDestination) external onlyOwner {
        require(newDestination != address(0), "Invalid destination");
        address oldDestination = operatorFeeDestination;
        operatorFeeDestination = newDestination;
        emit OperatorFeeDestinationUpdated(oldDestination, newDestination);
    }

    // ============ SIGNER MANAGEMENT ============

    /**
     * @dev Updates operator signer address
     */
    function updateOperatorSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid signer");
        address oldSigner = operatorSigner;
        operatorSigner = newSigner;
        emit OperatorSignerUpdated(oldSigner, newSigner);
    }

    /**
     * @dev Adds an authorized signer
     */
    function addAuthorizedSigner(address signer) external onlyOwner {
        require(signer != address(0), "Invalid signer");
        authorizedSigners[signer] = true;
        emit AuthorizedSignerAdded(signer);
    }

    /**
     * @dev Removes an authorized signer
     */
    function removeAuthorizedSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = false;
        emit AuthorizedSignerRemoved(signer);
    }

    // ============ ROLE MANAGEMENT ============

    /**
     * @dev Grants payment monitor role to an address
     */
    function grantPaymentMonitorRole(address monitor) external onlyOwner {
        require(monitor != address(0), "Invalid monitor");
        _grantRole(PAYMENT_MONITOR_ROLE, monitor);
        emit PaymentMonitorRoleGranted(monitor);
    }

    // ============ FEE WITHDRAWAL ============

    /**
     * @dev Withdraws operator fees (placeholder - would need actual fee tracking)
     */
    function withdrawOperatorFees(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token");
        // This is a placeholder - actual implementation would track operator fees
        IERC20(token).safeTransfer(owner(), amount);
        emit OperatorFeesWithdrawn(token, amount);
    }

    // ============ EMERGENCY CONTROLS ============

    /**
     * @dev Pauses all operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resumes operations after pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency token recovery
     */
    function emergencyTokenRecovery(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token");
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyTokenRecovered(token, amount);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets operator status information
     */
    function getOperatorStatus() external view returns (bool registered, address feeDestination) {
        // This would need to check with the commerce protocol
        return (true, operatorFeeDestination); // Placeholder
    }

    /**
     * @dev Checks if an address is an authorized signer
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }

    /**
     * @dev Gets current operator configuration
     */
    function getOperatorConfig() external view returns (
        address feeDestination,
        address signer,
        uint256 feeRate
    ) {
        return (operatorFeeDestination, operatorSigner, operatorFeeRate);
    }
}
