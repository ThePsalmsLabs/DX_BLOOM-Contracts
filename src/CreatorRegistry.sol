// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract CreatorRegistry is Ownable {
    mapping(address => uint256) public creatorSubscriptions;
    event CreatorRegistered(address creator, uint256 subscriptionPrice);
    event SubscriptionPriceUpdated(address creator, uint256 newPrice);

    constructor() Ownable(msg.sender) {}

    function registerCreator(uint256 subscriptionPrice) external {
        require(subscriptionPrice > 0, "Price must be greater than zero");
        creatorSubscriptions[msg.sender] = subscriptionPrice;
        emit CreatorRegistered(msg.sender, subscriptionPrice);
    }

    function updateSubscriptionPrice(uint256 newPrice) external {
        require(creatorSubscriptions[msg.sender] > 0, "Creator not registered");
        require(newPrice > 0, "Price must be greater than zero");
        creatorSubscriptions[msg.sender] = newPrice;
        emit SubscriptionPriceUpdated(msg.sender, newPrice);
    }
}