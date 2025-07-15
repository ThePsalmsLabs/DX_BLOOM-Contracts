// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./ContentRegistry.sol";

contract PayPerView is ReentrancyGuard {
    ContentRegistry public contentRegistry;
    mapping(address => mapping(uint256 => bool)) public hasPurchased;

    event ContentPurchased(address user, uint256 contentId, uint256 price);

    constructor(address _contentRegistry) {
        contentRegistry = ContentRegistry(_contentRegistry);
    }

    function purchaseContent(uint256 contentId) external payable nonReentrant {
        ContentRegistry.Content memory content = contentRegistry.contents(contentId);
        require(content.payPerViewPrice > 0, "Content not found");
        require(msg.value >= content.payPerViewPrice, "Insufficient payment");
        hasPurchased[msg.sender][contentId] = true;
        payable(content.creator).transfer(msg.value);
        emit ContentPurchased(msg.sender, contentId, msg.value);
    }

    function hasAccess(uint256 contentId, address user) external view returns (bool) {
        return hasPurchased[user][contentId];
    }
}