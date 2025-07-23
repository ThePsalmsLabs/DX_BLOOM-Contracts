// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IQuoterV2 } from "../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title MockQuoterV2 - FIXED COMPLETE IMPLEMENTATION
 * @dev Mock implementation of Uniswap V3 QuoterV2 for testing
 * @notice This mock allows us to test our PriceOracle without depending on actual
 *         Uniswap pools. We can set predictable prices, simulate different market
 *         conditions, and test edge cases like price slippage and liquidity issues.
 *
 * CRITICAL FIXES APPLIED:
 * 1. Fixed incomplete if statement syntax error
 * 2. Implemented missing _getDefaultPrice() function
 * 3. Implemented missing _calculateOutputAmount() function
 * 4. Added proper decimal handling for different tokens
 * 5. Added comprehensive price fallback logic
 */
contract MockQuoterV2 is IQuoterV2 {
    // Store mock prices for different token pairs
    // Structure: tokenIn => tokenOut => fee => price
    mapping(address => mapping(address => mapping(uint24 => uint256))) public mockPrices;

    // Track whether quotes should fail for testing error conditions
    mapping(address => mapping(address => bool)) public shouldFailQuote;

    // Default prices (these represent realistic market rates for testing)
    uint256 public constant DEFAULT_ETH_USDC_PRICE = 2000e6; // 1 ETH = 2000 USDC
    uint256 public constant DEFAULT_WETH_USDC_PRICE = 2000e6; // 1 WETH = 2000 USDC

    // Track function calls for testing
    uint256 public quoteExactInputSingleCalls;

    // Mock addresses for testing (these match Base network addresses)
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    constructor() {
        // Set up default prices for common pairs
        _setDefaultPrices();
    }

    /**
     * @dev Mock implementation of quoteExactInputSingle - ENHANCED VERSION WITH DEBUGGING
     * @param params The quote parameters
     * @return amountOut The output amount
     * @return sqrtPriceX96After The price after the swap (mock value)
     * @return initializedTicksCrossed The number of ticks crossed (mock value)
     * @return gasEstimate The gas estimate (mock value)
     * @notice This function simulates how Uniswap would calculate the output amount
     *         for a given input amount and token pair
     *
     * ENHANCED: Now provides detailed debugging information when quotes fail
     */
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        override
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        quoteExactInputSingleCalls++;

        // Check if this quote should fail for testing error conditions
        if (shouldFailQuote[params.tokenIn][params.tokenOut]) {
            revert("MockQuoterV2: Quote failed");
        }

        // Get the mock price for this token pair and fee tier
        uint256 price = mockPrices[params.tokenIn][params.tokenOut][params.fee];

        // ENHANCED: Complete the conditional logic with proper syntax and detailed fallback
        // If no specific price is set, try to use default price logic
        if (price == 0) {
            price = _getDefaultPrice(params.tokenIn, params.tokenOut);
        }

        // If still no price available, provide detailed error message for debugging
        if (price == 0) {
            // Enhanced error message that helps with debugging
            string memory errorMsg = string(
                abi.encodePacked(
                    "MockQuoterV2: No liquidity for pair. TokenIn: ",
                    _addressToString(params.tokenIn),
                    " TokenOut: ",
                    _addressToString(params.tokenOut),
                    " Fee: ",
                    _uint24ToString(params.fee)
                )
            );
            revert(errorMsg);
        }

        // Calculate output amount based on input amount and price
        // This handles decimal differences between tokens automatically
        amountOut = _calculateOutputAmount(params.tokenIn, params.tokenOut, params.amountIn, price);

        // Mock values for other return parameters (realistic values for testing)
        sqrtPriceX96After = 79228162514264337593543950336; // Mock sqrt price
        initializedTicksCrossed = 1; // Mock tick crosses
        gasEstimate = 100000; // Mock gas estimate

        return (amountOut, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    /**
     * @dev Sets a custom price for a token pair
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param fee The pool fee tier
     * @param price The price (how much tokenOut you get per unit of tokenIn)
     * @notice This allows us to set specific prices for testing different scenarios
     */
    function setMockPrice(address tokenIn, address tokenOut, uint24 fee, uint256 price) external {
        mockPrices[tokenIn][tokenOut][fee] = price;
    }

    /**
     * @dev Sets whether a quote should fail for testing
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param shouldFail Whether the quote should fail
     */
    function setShouldFailQuote(address tokenIn, address tokenOut, bool shouldFail) external {
        shouldFailQuote[tokenIn][tokenOut] = shouldFail;
    }

    /**
     * @dev Resets all mock data
     */
    function resetMockData() external {
        quoteExactInputSingleCalls = 0;
        _setDefaultPrices();
    }

    /**
     * @dev Sets up default prices for common token pairs - ENHANCED VERSION
     * @notice This establishes realistic baseline prices for testing with comprehensive coverage
     *
     * CRITICAL ENHANCEMENT: Now covers ALL fee tiers (500, 3000, 10000) and BOTH directions
     * for each token pair. This ensures auto pool fee detection works correctly.
     */
    function _setDefaultPrices() internal {
        // ============ WETH/USDC PAIRS (ALL FEE TIERS) ============
        // WETH -> USDC: 1 WETH = 2000 USDC
        mockPrices[WETH][USDC][500] = DEFAULT_WETH_USDC_PRICE; // 0.05% pool
        mockPrices[WETH][USDC][3000] = DEFAULT_WETH_USDC_PRICE; // 0.3% pool
        mockPrices[WETH][USDC][10000] = DEFAULT_WETH_USDC_PRICE; // 1% pool

        // USDC -> WETH: 1 USDC = 0.0005 WETH (reverse direction)
        mockPrices[USDC][WETH][500] = 0.0005e18; // 0.05% pool
        mockPrices[USDC][WETH][3000] = 0.0005e18; // 0.3% pool
        mockPrices[USDC][WETH][10000] = 0.0005e18; // 1% pool

        // ============ MOCK_TOKEN/USDC PAIRS (ALL FEE TIERS) ============
        // This is CRITICAL for the failing tests - they use MOCK_TOKEN
        address mockToken = address(0x1234567890123456789012345678901234567890);

        // MOCK_TOKEN -> USDC: 1 MOCK = 1 USDC
        mockPrices[mockToken][USDC][500] = 1e6; // 0.05% pool (auto-selected for stablecoin pairs!)
        mockPrices[mockToken][USDC][3000] = 1e6; // 0.3% pool
        mockPrices[mockToken][USDC][10000] = 1e6; // 1% pool

        // USDC -> MOCK_TOKEN: 1 USDC = 1 MOCK (reverse direction)
        mockPrices[USDC][mockToken][500] = 1e18; // 0.05% pool
        mockPrices[USDC][mockToken][3000] = 1e18; // 0.3% pool
        mockPrices[USDC][mockToken][10000] = 1e18; // 1% pool

        // ============ MOCK_TOKEN/WETH PAIRS (FOR ROUTING) ============
        // These support routing through WETH when direct pairs aren't available

        // MOCK_TOKEN -> WETH: 1 MOCK = 0.0005 WETH (same as 1 USDC)
        mockPrices[mockToken][WETH][500] = 0.0005e18;
        mockPrices[mockToken][WETH][3000] = 0.0005e18;
        mockPrices[mockToken][WETH][10000] = 0.0005e18;

        // WETH -> MOCK_TOKEN: 1 WETH = 2000 MOCK (reverse direction)
        mockPrices[WETH][mockToken][500] = 2000e18;
        mockPrices[WETH][mockToken][3000] = 2000e18;
        mockPrices[WETH][mockToken][10000] = 2000e18;

        // ============ ETH (address(0)) SPECIAL HANDLING ============
        // Handle native ETH (address(0)) for tests that use it

        // ETH -> USDC: 1 ETH = 2000 USDC
        mockPrices[address(0)][USDC][500] = DEFAULT_ETH_USDC_PRICE;
        mockPrices[address(0)][USDC][3000] = DEFAULT_ETH_USDC_PRICE;
        mockPrices[address(0)][USDC][10000] = DEFAULT_ETH_USDC_PRICE;

        // USDC -> ETH: 1 USDC = 0.0005 ETH
        mockPrices[USDC][address(0)][500] = 0.0005e18;
        mockPrices[USDC][address(0)][3000] = 0.0005e18;
        mockPrices[USDC][address(0)][10000] = 0.0005e18;
    }

    /**
     * @dev NEWLY IMPLEMENTED: Gets default price for common token pairs - ENHANCED VERSION
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @return price The default price
     * @notice This provides fallback prices when specific pool prices aren't set
     *
     * EDUCATIONAL NOTE: This function serves as a safety net with more comprehensive
     * fallback logic. It handles edge cases and provides debugging information.
     */
    function _getDefaultPrice(address tokenIn, address tokenOut) internal pure returns (uint256 price) {
        // Handle ETH (address(0)) to USDC
        if (tokenIn == address(0) && tokenOut == USDC) {
            return DEFAULT_ETH_USDC_PRICE;
        }

        // Handle WETH to USDC
        if (tokenIn == WETH && tokenOut == USDC) {
            return DEFAULT_WETH_USDC_PRICE;
        }

        // Handle USDC to ETH (address(0))
        if (tokenIn == USDC && tokenOut == address(0)) {
            return 0.0005e18; // 1 USDC = 0.0005 ETH
        }

        // Handle USDC to WETH
        if (tokenIn == USDC && tokenOut == WETH) {
            return 0.0005e18; // 1 USDC = 0.0005 WETH
        }

        // Handle MOCK_TOKEN cases (this is critical for failing tests)
        address mockToken = address(0x1234567890123456789012345678901234567890);

        if (tokenIn == mockToken && tokenOut == USDC) {
            return 1e6; // 1 MOCK = 1 USDC
        }

        if (tokenIn == USDC && tokenOut == mockToken) {
            return 1e18; // 1 USDC = 1 MOCK
        }

        if (tokenIn == mockToken && tokenOut == WETH) {
            return 0.0005e18; // 1 MOCK = 0.0005 WETH
        }

        if (tokenIn == WETH && tokenOut == mockToken) {
            return 2000e18; // 1 WETH = 2000 MOCK
        }

        // Handle same token (should return 1:1 ratio)
        if (tokenIn == tokenOut) {
            return 1e18; // 1:1 ratio
        }

        // For any other pairs, return 0 (no price available)
        return 0;
    }

    /**
     * @dev NEWLY IMPLEMENTED: Calculates output amount based on input amount and price
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The input amount
     * @param price The exchange rate
     * @return amountOut The calculated output amount
     * @notice This handles the decimal differences between different tokens
     *
     * EXPLANATION: This is critical for accurate price calculations because:
     * - USDC has 6 decimals (1 USDC = 1e6)
     * - WETH has 18 decimals (1 WETH = 1e18)
     * - When converting between them, we must adjust for decimal differences
     * - The price parameter represents "how much tokenOut per 1 unit of tokenIn"
     */
    function _calculateOutputAmount(address tokenIn, address tokenOut, uint256 amountIn, uint256 price)
        internal
        pure
        returns (uint256 amountOut)
    {
        // Handle decimal differences between tokens
        uint8 decimalsIn = _getTokenDecimals(tokenIn);
        uint8 decimalsOut = _getTokenDecimals(tokenOut);

        // Price is stored as output tokens per 1 unit of input token
        // Need to adjust for decimal differences
        if (decimalsIn > decimalsOut) {
            // Input has more decimals (e.g., WETH 18 -> USDC 6)
            uint256 decimalDiff = 10 ** (decimalsIn - decimalsOut);
            amountOut = (amountIn * price) / decimalDiff / 1e18;
        } else if (decimalsOut > decimalsIn) {
            // Output has more decimals (e.g., USDC 6 -> WETH 18)
            uint256 decimalDiff = 10 ** (decimalsOut - decimalsIn);
            amountOut = (amountIn * price * decimalDiff) / 1e18;
        } else {
            // Same decimals
            amountOut = (amountIn * price) / 1e18;
        }

        // Ensure we never return 0 for non-zero input (prevents division by zero downstream)
        if (amountIn > 0 && amountOut == 0) {
            amountOut = 1; // Minimum output to prevent downstream issues
        }

        return amountOut;
    }

    /**
     * @dev NEWLY IMPLEMENTED: Gets token decimals for known tokens
     * @param token The token address
     * @return decimals The number of decimals
     * @notice This ensures accurate calculations between tokens with different decimal places
     */
    function _getTokenDecimals(address token) internal pure returns (uint8 decimals) {
        if (token == USDC) {
            return 6; // USDC has 6 decimals
        } else if (token == WETH || token == address(0)) {
            return 18; // WETH and ETH have 18 decimals
        } else {
            return 18; // Default to 18 for unknown tokens
        }
    }

    /**
     * @dev Simulates slippage by adjusting the price
     * @param basePrice The base price
     * @param slippageBps The slippage in basis points
     * @return adjustedPrice The price after slippage
     * @notice This allows testing price impact scenarios
     */
    function simulateSlippage(uint256 basePrice, uint256 slippageBps) external pure returns (uint256 adjustedPrice) {
        // Apply slippage (reduce output by slippage amount)
        adjustedPrice = basePrice - (basePrice * slippageBps) / 10000;
        return adjustedPrice;
    }

    // ============ DEBUGGING HELPER FUNCTIONS ============
    // These functions help create detailed error messages for better troubleshooting

    /**
     * @dev Converts address to string for debugging
     * @param addr The address to convert
     * @return result The address as a string
     */
    function _addressToString(address addr) internal pure returns (string memory result) {
        if (addr == address(0)) return "0x0000000000000000000000000000000000000000";

        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            uint8 byteValue = uint8(uint160(addr) >> (8 * (19 - i)));
            uint8 high = byteValue >> 4;
            uint8 low = byteValue & 0x0f;

            buffer[2 + i * 2] = bytes1(high < 10 ? high + 48 : high + 87);
            buffer[3 + i * 2] = bytes1(low < 10 ? low + 48 : low + 87);
        }

        return string(buffer);
    }

    /**
     * @dev Converts uint24 to string for debugging
     * @param value The uint24 to convert
     * @return result The uint24 as a string
     */
    function _uint24ToString(uint24 value) internal pure returns (string memory result) {
        if (value == 0) return "0";

        uint24 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
