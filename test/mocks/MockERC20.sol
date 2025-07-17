// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing purposes
 * @notice This contract simulates USDC behavior for our tests. We create our own
 *         mock instead of using the real USDC contract because we need full control
 *         over minting, balances, and behavior to create comprehensive test scenarios.
 */
contract MockERC20 is ERC20, Ownable {
    
    // The number of decimal places this token uses (USDC uses 6 decimals)
    uint8 private _decimals;
    
    // Track whether transfers should fail (for testing error conditions)
    bool public transfersShouldFail;
    
    // Track transfer attempts for testing
    uint256 public transferAttempts;
    
    /**
     * @dev Constructor sets up the mock token with custom decimals
     * @param name The name of the token (e.g., "Mock USDC")
     * @param symbol The symbol of the token (e.g., "USDC")
     * @param decimals_ The number of decimal places (6 for USDC)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_;
    }
    
    /**
     * @dev Returns the number of decimals the token uses
     * @return The number of decimal places
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Mints tokens to a specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint (in the token's smallest unit)
     * @notice This function allows us to give test users the exact amount of tokens
     *         they need for each test scenario
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens from a specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     * @notice This function allows us to simulate scenarios where users lose tokens
     *         or where we need to reduce the total supply
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
    
    /**
     * @dev Sets whether transfers should fail (for testing error conditions)
     * @param shouldFail Whether transfers should fail
     * @notice This allows us to test how our contracts handle failed token transfers
     */
    function setTransfersShouldFail(bool shouldFail) external onlyOwner {
        transfersShouldFail = shouldFail;
    }
    
    /**
     * @dev Override transfer to allow testing of failed transfers
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transfer(address to, uint256 amount) public override returns (bool success) {
        transferAttempts++;
        
        if (transfersShouldFail) {
            return false;
        }
        
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Override transferFrom to allow testing of failed transfers
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     * @return success Whether the transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool success) {
        transferAttempts++;
        
        if (transfersShouldFail) {
            return false;
        }
        
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Resets the transfer attempts counter
     * @notice This helps us verify that the expected number of transfers occurred
     */
    function resetTransferAttempts() external onlyOwner {
        transferAttempts = 0;
    }
    
    /**
     * @dev Allows the owner to force a balance for testing
     * @param account The account to set balance for
     * @param newBalance The new balance to set
     * @notice This is useful for testing edge cases where balances change unexpectedly
     */
    function forceBalance(address account, uint256 newBalance) external onlyOwner {
        uint256 currentBalance = balanceOf(account);
        
        if (newBalance > currentBalance) {
            _mint(account, newBalance - currentBalance);
        } else if (newBalance < currentBalance) {
            _burn(account, currentBalance - newBalance);
        }
    }
}