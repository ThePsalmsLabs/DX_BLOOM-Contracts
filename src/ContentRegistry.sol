// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ContentRegistry is Ownable {
    struct Content {
        string ipfsHash;
        uint256 payPerViewPrice;
        address creator;
    }
    mapping(uint256 => Content) public contents;
    uint256 public contentCount;

    event ContentRegistered(uint256 contentId, string ipfsHash, uint256 payPerViewPrice, address creator);

    constructor() Ownable(msg.sender) {}

    function registerContent(string memory ipfsHash, uint256 payPerViewPrice) external {
        require(bytes(ipfsHash).length > 0, "IPFS hash required");
        contents[contentCount] = Content(ipfsHash, payPerViewPrice, msg.sender);
        emit ContentRegistered(contentCount, ipfsHash, payPerViewPrice, msg.sender);
        contentCount++;
    }
}