// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { AccessControl } from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { PayPerView } from "./PayPerView.sol";
import { SubscriptionManager } from "./SubscriptionManager.sol";
import { ISharedTypes } from "./interfaces/ISharedTypes.sol";

/**
 * @title RefundManager
 * @dev Manages refund operations for failed payments
 * @notice This contract handles all refund-related operations to reduce main contract size
 */
contract RefundManager is Ownable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant PAYMENT_MONITOR_ROLE = keccak256("PAYMENT_MONITOR_ROLE");

    // Refund state
    mapping(bytes16 => RefundRequest) public refundRequests;
    mapping(address => uint256) public pendingRefunds; // User -> USDC amount

    // Contract references
    PayPerView public payPerView;
    SubscriptionManager public subscriptionManager;
    IERC20 public usdcToken;

    // Metrics
    uint256 public totalRefundsProcessed;

    // Events
    event RefundRequested(bytes16 indexed intentId, address indexed user, uint256 amount, string reason);
    event RefundProcessed(bytes16 indexed intentId, address indexed user, uint256 amount);
    event ContractAddressUpdated(string contractName, address oldAddress, address newAddress);

    // Refund request structure
    struct RefundRequest {
        bytes16 originalIntentId;
        address user;
        uint256 amount;
        string reason;
        uint256 requestTime;
        bool processed;
    }

    constructor(
        address _payPerView,
        address _subscriptionManager,
        address _usdcToken
    ) Ownable(msg.sender) {
        require(_usdcToken != address(0), "Invalid USDC token");

        payPerView = PayPerView(_payPerView);
        subscriptionManager = SubscriptionManager(_subscriptionManager);
        usdcToken = IERC20(_usdcToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_MONITOR_ROLE, msg.sender);
    }

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

    /**
     * @dev Requests a refund for a failed or disputed payment
     */
    function requestRefund(
        bytes16 intentId,
        address user,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        ISharedTypes.PaymentType paymentType,
        string memory reason
    ) external {
        require(user == msg.sender, "Not payment creator");

        // Check if refund already requested
        if (refundRequests[intentId].requestTime != 0) revert("Refund already requested");

        // Calculate refund amount (full payment including fees)
        uint256 refundAmount = creatorAmount + platformFee + operatorFee;

        // Create refund request
        refundRequests[intentId] = RefundRequest({
            originalIntentId: intentId,
            user: msg.sender,
            amount: refundAmount,
            reason: reason,
            requestTime: block.timestamp,
            processed: false
        });

        // Add to pending refunds
        pendingRefunds[msg.sender] += refundAmount;

        emit RefundRequested(intentId, msg.sender, refundAmount, reason);
    }

    /**
     * @dev Processes a refund payout to user
     */
    function processRefund(bytes16 intentId) external onlyRole(PAYMENT_MONITOR_ROLE) {
        RefundRequest storage refund = refundRequests[intentId];
        require(refund.requestTime != 0, "Refund not requested");
        require(!refund.processed, "Already processed");

        refund.processed = true;

        // Update pending refunds
        if (pendingRefunds[refund.user] >= refund.amount) {
            pendingRefunds[refund.user] -= refund.amount;
        } else {
            pendingRefunds[refund.user] = 0;
        }

        // Transfer USDC refund
        usdcToken.safeTransfer(refund.user, refund.amount);

        totalRefundsProcessed += refund.amount;

        emit RefundProcessed(intentId, refund.user, refund.amount);
    }

    /**
     * @dev Processes refund with coordination between contracts
     */
    function processRefundWithCoordination(
        bytes16 intentId,
        ISharedTypes.PaymentType paymentType,
        uint256 contentId,
        address creator
    ) external onlyRole(PAYMENT_MONITOR_ROLE) {
        RefundRequest storage refund = refundRequests[intentId];
        require(refund.requestTime != 0, "Refund not requested");
        require(!refund.processed, "Already processed");

        refund.processed = true;

        if (paymentType == ISharedTypes.PaymentType.PayPerView && address(payPerView) != address(0)) {
            try payPerView.handleExternalRefund(intentId, refund.user, contentId) { } catch { }
        } else if ((paymentType == ISharedTypes.PaymentType.Subscription) && address(subscriptionManager) != address(0)) {
            try subscriptionManager.handleExternalRefund(intentId, refund.user, creator) { } catch { }
        }

        if (pendingRefunds[refund.user] >= refund.amount) {
            pendingRefunds[refund.user] -= refund.amount;
        } else {
            pendingRefunds[refund.user] = 0;
        }

        usdcToken.safeTransfer(refund.user, refund.amount);
        totalRefundsProcessed += refund.amount;

        emit RefundProcessed(intentId, refund.user, refund.amount);
    }

    /**
     * @dev Handles failed payment and prepares for refund
     */
    function handleFailedPayment(
        bytes16 intentId,
        address user,
        address creator,
        uint256 creatorAmount,
        uint256 platformFee,
        uint256 operatorFee,
        ISharedTypes.PaymentType paymentType,
        string memory reason
    ) external {
        // Calculate refund amount
        uint256 refundAmount = creatorAmount + platformFee + operatorFee;

        // Use standardized refund intent ID
        bytes16 refundIntentId = _generateRefundIntentId(intentId, user, reason);

        refundRequests[refundIntentId] = RefundRequest({
            originalIntentId: intentId,
            user: user,
            amount: refundAmount,
            reason: reason,
            requestTime: block.timestamp,
            processed: false
        });

        pendingRefunds[user] += refundAmount;

        emit RefundRequested(refundIntentId, user, refundAmount, reason);
    }

    /**
     * @dev Generates a standardized refund intent ID
     */
    function _generateRefundIntentId(bytes16 originalIntentId, address user, string memory reason)
        internal
        pure
        returns (bytes16)
    {
        return bytes16(keccak256(abi.encodePacked(originalIntentId, user, reason, "refund")));
    }

    /**
     * @dev Gets refund request details
     */
    function getRefundRequest(bytes16 intentId) external view returns (RefundRequest memory) {
        return refundRequests[intentId];
    }

    /**
     * @dev Gets pending refund amount for a user
     */
    function getPendingRefund(address user) external view returns (uint256) {
        return pendingRefunds[user];
    }

    /**
     * @dev Gets refund metrics
     */
    function getRefundMetrics() external view returns (uint256 totalRefunds) {
        return totalRefundsProcessed;
    }
}


