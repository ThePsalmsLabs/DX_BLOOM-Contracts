// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./CreatorRegistry.sol";

contract SubscriptionManager is ReentrancyGuard {
    CreatorRegistry public creatorRegistry;
    mapping(address => mapping(address => uint256)) public subscriptions; // user => creator => expiry

    event Subscribed(address user, address creator, uint256 expiry);

    constructor(address _creatorRegistry) {
        creatorRegistry = CreatorRegistry(_creatorRegistry);
    }

    function subscribeToCreator(address creator) external payable nonReentrant {
        uint256 price = creatorRegistry.creatorSubscriptions(creator);
        require(price > 0, "Creator not registered");
        require(msg.value >= price, "Insufficient payment");
        subscriptions[msg.sender][creator] = block.timestamp + 30 days;
        payable(creator).transfer(msg.value);
        emit Subscribed(msg.sender, creator, block.timestamp + 30 days);
    }

    function isSubscribed(address user, address creator) external view returns (bool) {
        return subscriptions[user][creator] > block.timestamp;
    }
}