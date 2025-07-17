// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
        _setupDecimals(decimals_);
    }
    function _setupDecimals(uint8 decimals_) internal {
        // For OpenZeppelin >=4.5, decimals is immutable, so override if needed for your OZ version
        assembly { sstore(0x0, decimals_) }
    }
} 