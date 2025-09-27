// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

/**
 * @title SimpleEnumTest
 * @dev Simple test to verify basic functionality works
 */
contract SimpleEnumTest is Test {
    function test_SimpleMath() public {
        uint256 a = 1;
        uint256 b = 2;
        uint256 c = a + b;
        assertEq(c, 3);
    }

    function test_SimpleString() public {
        string memory test = "hello";
        assertEq(bytes(test).length, 5);
    }
}
