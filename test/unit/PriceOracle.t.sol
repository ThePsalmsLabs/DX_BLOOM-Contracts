// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TestSetup} from "../helpers/TestSetup.sol";
import {PriceOracle} from "../../src/PriceOracle.sol";
import {IQuoterV2} from "../../src/interfaces/IPlatformInterfaces.sol";

/**
 * @title PriceOracleTest
 * @dev Comprehensive unit tests for the PriceOracle contract
 * @notice This test suite covers all price estimation functionality including ETH/USDC prices,
 *         token swaps, slippage calculations, and multi-pool fee tier support. The PriceOracle
 *         is critical for our multi-token payment system - it ensures users can pay with any
 *         supported token while creators receive USDC at fair market rates.
 *
 * We test both happy path scenarios and edge cases like failed quotes, missing liquidity,
 * and various token decimal configurations to ensure robust price discovery.
 */
contract PriceOracleTest is TestSetup {
    // Mock token addresses for testing (matching Base network)
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant MOCK_TOKEN = 0x1234567890123456789012345678901234567890;

    // Events we'll test for proper emission
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);

    /**
     * @dev Test setup specific to PriceOracle tests
     * @notice This runs before each test to set up mock price data
     */
    function setUp() public override {
        super.setUp();

        // Set up mock prices in our MockQuoterV2 for testing
        // These prices simulate realistic market conditions
        mockQuoter.setMockPrice(WETH, USDC, 3000, 2000e6); // 1 WETH = 2000 USDC
        mockQuoter.setMockPrice(USDC, WETH, 3000, 0.0005e18); // 1 USDC = 0.0005 WETH
        mockQuoter.setMockPrice(MOCK_TOKEN, USDC, 3000, 1e6); // 1 MOCK = 1 USDC
    }

    // ============ ETH PRICE ESTIMATION TESTS ============

    /**
     * @dev Tests getting ETH price for USDC amount
     * @notice This is crucial for users paying with ETH - they need to know exactly
     *         how much ETH to send to purchase content priced in USDC
     */
    function test_GetETHPrice_Success() public {
        // Arrange: Set up a USDC amount to convert to ETH
        uint256 usdcAmount = 100e6; // $100 USDC

        // Act: Get ETH price for the USDC amount
        uint256 ethAmount = priceOracle.getETHPrice(usdcAmount);

        // Assert: Verify the calculation is correct
        // With mock price of 1 ETH = 2000 USDC, $100 should equal 0.05 ETH
        uint256 expectedEthAmount = 0.05e18; // 0.05 ETH
        assertEq(ethAmount, expectedEthAmount);

        // Verify the mock quoter was called
        // assertEq(mockQuoter.quoteExactInputSingleCalls(), 1); // No such function in mock
    }

    /**
     * @dev Tests ETH price calculation with different amounts
     * @notice This tests various price points to ensure scaling works correctly
     */
    function test_GetETHPrice_DifferentAmounts() public {
        // Test with various USDC amounts
        uint256[] memory usdcAmounts = new uint256[](4);
        usdcAmounts[0] = 1e6; // $1
        usdcAmounts[1] = 10e6; // $10
        usdcAmounts[2] = 100e6; // $100
        usdcAmounts[3] = 1000e6; // $1000

        uint256[] memory expectedEthAmounts = new uint256[](4);
        expectedEthAmounts[0] = 0.0005e18; // 0.0005 ETH
        expectedEthAmounts[1] = 0.005e18; // 0.005 ETH
        expectedEthAmounts[2] = 0.05e18; // 0.05 ETH
        expectedEthAmounts[3] = 0.5e18; // 0.5 ETH

        // Test each amount
        for (uint256 i = 0; i < usdcAmounts.length; i++) {
            uint256 ethAmount = priceOracle.getETHPrice(usdcAmounts[i]);
            assertEq(ethAmount, expectedEthAmounts[i]);
        }
    }

    /**
     * @dev Tests ETH price when quoter fails
     * @notice This tests our error handling when price feeds are unavailable
     */
    function test_GetETHPrice_QuoterFails() public {
        // Arrange: Set up the mock quoter to fail
        mockQuoter.setShouldFailQuote(WETH, USDC, true);

        // Act & Assert: Expect the function to revert
        vm.expectRevert("MockQuoterV2: Quote failed");
        priceOracle.getETHPrice(100e6);
    }

    // ============ TOKEN PRICE ESTIMATION TESTS ============

    /**
     * @dev Tests getting token amount for USDC
     * @notice This tests our general token price estimation functionality
     */
    function test_GetTokenAmountForUSDC_Success() public {
        // Arrange: Set up a USDC amount to convert to tokens
        uint256 usdcAmount = 50e6; // $50 USDC
        uint24 poolFee = 3000; // 0.3% pool fee

        // Act: Get token amount for the USDC amount
        uint256 tokenAmount = priceOracle.getTokenAmountForUSDC(MOCK_TOKEN, usdcAmount, poolFee);

        // Assert: Verify the calculation is correct
        // With mock price of 1 MOCK = 1 USDC, $50 should equal 50 MOCK tokens
        uint256 expectedTokenAmount = 50e18; // 50 MOCK (18 decimals)
        assertEq(tokenAmount, expectedTokenAmount);
    }

    /**
     * @dev Tests token amount calculation with USDC input
     * @notice This tests the special case where input token is USDC
     */
    function test_GetTokenAmountForUSDC_USDCInput() public {
        // Arrange: Use USDC as both input and output
        uint256 usdcAmount = 100e6; // $100 USDC

        // Act: Get USDC amount for USDC (should be 1:1)
        uint256 result = priceOracle.getTokenAmountForUSDC(USDC, usdcAmount, 0);

        // Assert: Should return the same amount
        assertEq(result, usdcAmount);
    }

    /**
     * @dev Tests token amount calculation with auto-detected pool fee
     * @notice This tests our automatic pool fee detection logic
     */
    function test_GetTokenAmountForUSDC_AutoPoolFee() public {
        // Arrange: Set up a USDC amount with auto-detected pool fee
        uint256 usdcAmount = 25e6; // $25 USDC
        uint24 poolFee = 0; // Auto-detect pool fee

        // Act: Get token amount with auto-detected pool fee
        uint256 tokenAmount = priceOracle.getTokenAmountForUSDC(MOCK_TOKEN, usdcAmount, poolFee);

        // Assert: Verify the calculation works with auto-detected fee
        uint256 expectedTokenAmount = 25e18; // 25 MOCK tokens
        assertEq(tokenAmount, expectedTokenAmount);
    }

    /**
     * @dev Tests token amount calculation via WETH route
     * @notice This tests our fallback routing through WETH when direct pairs don't exist
     */
    function test_GetTokenAmountForUSDC_ViaWETHRoute() public {
        // Arrange: Set up a token that doesn't have direct USDC pair
        address unknownToken = address(0x5555);

        // Set up the mock quoter to fail for direct route but succeed for WETH route
        mockQuoter.setShouldFailQuote(unknownToken, USDC, true);
        mockQuoter.setMockPrice(unknownToken, WETH, 3000, 0.001e18); // 1 UNKNOWN = 0.001 WETH

        uint256 usdcAmount = 2e6; // $2 USDC

        // Act: Get token amount via WETH route
        uint256 tokenAmount = priceOracle.getTokenAmountForUSDC(unknownToken, usdcAmount, 0);

        // Assert: Verify the calculation works via WETH
        // $2 USDC = 0.001 ETH, 0.001 ETH = 1 UNKNOWN token
        uint256 expectedTokenAmount = 1e18; // 1 UNKNOWN token
        assertEq(tokenAmount, expectedTokenAmount);
    }

    // ============ GENERAL TOKEN PRICE TESTS ============

    /**
     * @dev Tests general token price calculation
     * @notice This tests our core price calculation functionality
     */
    function test_GetTokenPrice_Success() public {
        // Arrange: Set up token pair and amount
        address tokenIn = WETH;
        address tokenOut = USDC;
        uint256 amountIn = 1e18; // 1 WETH
        uint24 poolFee = 3000;

        // Act: Get token price
        uint256 amountOut = priceOracle.getTokenPrice(tokenIn, tokenOut, amountIn, poolFee);

        // Assert: Verify the price is correct
        // With mock price of 1 WETH = 2000 USDC
        uint256 expectedAmountOut = 2000e6; // 2000 USDC
        assertEq(amountOut, expectedAmountOut);
    }

    /**
     * @dev Tests token price with auto-detected pool fee
     * @notice This tests our automatic pool fee detection
     */
    function test_GetTokenPrice_AutoPoolFee() public {
        // Arrange: Set up token pair with auto-detected pool fee
        address tokenIn = WETH;
        address tokenOut = USDC;
        uint256 amountIn = 0.5e18; // 0.5 WETH
        uint24 poolFee = 0; // Auto-detect

        // Act: Get token price with auto-detected pool fee
        uint256 amountOut = priceOracle.getTokenPrice(tokenIn, tokenOut, amountIn, poolFee);

        // Assert: Verify the price is correct
        uint256 expectedAmountOut = 1000e6; // 1000 USDC (0.5 * 2000)
        assertEq(amountOut, expectedAmountOut);
    }

    /**
     * @dev Tests token price when quoter fails
     * @notice This tests our error handling for failed price queries
     */
    function test_GetTokenPrice_QuoterFails() public {
        // Arrange: Set up the mock quoter to fail
        mockQuoter.setShouldFailQuote(WETH, USDC, true);

        // Act & Assert: Expect the function to revert
        vm.expectRevert("MockQuoterV2: Quote failed");
        priceOracle.getTokenPrice(WETH, USDC, 1e18, 3000);
    }

    // ============ SLIPPAGE CALCULATION TESTS ============

    /**
     * @dev Tests applying slippage to a quote
     * @notice This tests our slippage protection functionality
     */
    function test_ApplySlippage_Success() public {
        // Arrange: Set up a base amount and slippage
        uint256 baseAmount = 1000e6; // $1000
        uint256 slippageBps = 100; // 1% slippage

        // Act: Apply slippage to the amount
        uint256 adjustedAmount = priceOracle.applySlippage(baseAmount, slippageBps);

        // Assert: Verify slippage was applied correctly
        // $1000 + 1% = $1010
        uint256 expectedAmount = 1010e6;
        assertEq(adjustedAmount, expectedAmount);
    }

    /**
     * @dev Tests applying various slippage percentages
     * @notice This tests different slippage scenarios
     */
    function test_ApplySlippage_DifferentPercentages() public {
        uint256 baseAmount = 1000e6; // $1000

        // Test different slippage percentages
        uint256[] memory slippages = new uint256[](4);
        slippages[0] = 10; // 0.1%
        slippages[1] = 50; // 0.5%
        slippages[2] = 100; // 1%
        slippages[3] = 500; // 5%

        uint256[] memory expectedAmounts = new uint256[](4);
        expectedAmounts[0] = 1001e6; // $1001
        expectedAmounts[1] = 1005e6; // $1005
        expectedAmounts[2] = 1010e6; // $1010
        expectedAmounts[3] = 1050e6; // $1050

        for (uint256 i = 0; i < slippages.length; i++) {
            uint256 adjustedAmount = priceOracle.applySlippage(baseAmount, slippages[i]);
            assertEq(adjustedAmount, expectedAmounts[i]);
        }
    }

    /**
     * @dev Tests slippage validation
     * @notice This tests that excessive slippage is rejected
     */
    function test_ApplySlippage_ExcessiveSlippage() public {
        // Arrange: Set up excessive slippage (over 100%)
        uint256 baseAmount = 1000e6;
        uint256 excessiveSlippage = 10001; // 100.01%

        // Act & Assert: Expect the function to revert
        vm.expectRevert(PriceOracle.InvalidSlippage.selector);
        priceOracle.applySlippage(baseAmount, excessiveSlippage);
    }

    // ============ MULTIPLE QUOTES TESTS ============

    /**
     * @dev Tests getting multiple quotes for different fee tiers
     * @notice This tests our multi-pool quote functionality
     */
    function test_GetMultipleQuotes_Success() public {
        // Arrange: Set up mock prices for different fee tiers
        mockQuoter.setMockPrice(WETH, USDC, 500, 1995e6); // 0.05% pool: slightly worse price
        mockQuoter.setMockPrice(WETH, USDC, 3000, 2000e6); // 0.3% pool: best price
        mockQuoter.setMockPrice(WETH, USDC, 10000, 1990e6); // 1% pool: worst price

        // Act: Get multiple quotes
        uint256[3] memory quotes = priceOracle.getMultipleQuotes(WETH, USDC, 1e18);

        // Assert: Verify all quotes are returned
        assertEq(quotes[0], 1995e6); // 0.05% pool
        assertEq(quotes[1], 2000e6); // 0.3% pool
        assertEq(quotes[2], 1990e6); // 1% pool
    }

    /**
     * @dev Tests multiple quotes with missing pools
     * @notice This tests handling of non-existent pools
     */
    function test_GetMultipleQuotes_MissingPools() public {
        // Arrange: Set up the mock quoter to fail for some pools
        mockQuoter.setShouldFailQuote(MOCK_TOKEN, USDC, true);

        // Only set up one pool
        mockQuoter.setMockPrice(MOCK_TOKEN, USDC, 3000, 1e6);

        // Act: Get multiple quotes
        uint256[3] memory quotes = priceOracle.getMultipleQuotes(MOCK_TOKEN, USDC, 1e18);

        // Assert: Verify only available pool returns a quote
        assertEq(quotes[0], 0); // 0.05% pool: not available
        assertEq(quotes[1], 1e6); // 0.3% pool: available
        assertEq(quotes[2], 0); // 1% pool: not available
    }

    // ============ CUSTOM POOL FEE TESTS ============

    /**
     * @dev Tests setting custom pool fees
     * @notice This tests our custom pool fee configuration
     */
    function test_SetCustomPoolFee_Success() public {
        // Arrange: Set up custom pool fee
        address tokenA = WETH;
        address tokenB = USDC;
        uint24 customFee = 500; // 0.05%

        // Act: Set custom pool fee as admin
        vm.startPrank(admin);

        // Expect the CustomPoolFeeSet event
        vm.expectEmit(true, true, false, true);
        emit CustomPoolFeeSet(tokenA, tokenB, customFee);

        priceOracle.setCustomPoolFee(tokenA, tokenB, customFee);
        vm.stopPrank();

        // Assert: Verify the custom fee is used
        // Set up mock price for the custom fee
        mockQuoter.setMockPrice(tokenA, tokenB, customFee, 2010e6);

        uint256 amountOut = priceOracle.getTokenPrice(tokenA, tokenB, 1e18, 0);
        assertEq(amountOut, 2010e6); // Should use custom fee pool
    }

    /**
     * @dev Tests setting invalid custom pool fee
     * @notice This tests validation of custom pool fees
     */
    function test_SetCustomPoolFee_InvalidFee() public {
        // Arrange: Set up invalid pool fee
        address tokenA = WETH;
        address tokenB = USDC;
        uint24 invalidFee = 1000; // Not a valid Uniswap fee

        // Act & Assert: Expect the function to revert
        vm.startPrank(admin);
        vm.expectRevert(PriceOracle.InvalidPoolFee.selector);
        priceOracle.setCustomPoolFee(tokenA, tokenB, invalidFee);
        vm.stopPrank();
    }

    /**
     * @dev Tests that only owner can set custom pool fees
     * @notice This tests our access control
     */
    function test_SetCustomPoolFee_OnlyOwner() public {
        // Arrange: Set up custom pool fee
        address tokenA = WETH;
        address tokenB = USDC;
        uint24 customFee = 500;

        // Act & Assert: Try to set custom fee as non-owner
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to Ownable restriction
        priceOracle.setCustomPoolFee(tokenA, tokenB, customFee);
        vm.stopPrank();
    }

    // ============ SLIPPAGE SETTINGS TESTS ============

    /**
     * @dev Tests updating default slippage
     * @notice This tests our slippage configuration functionality
     */
    function test_UpdateDefaultSlippage_Success() public {
        // Arrange: Set up new default slippage
        uint256 oldSlippage = 100; // Current default (1%)
        uint256 newSlippage = 150; // New default (1.5%)

        // Act: Update default slippage as admin
        vm.startPrank(admin);

        // Expect the SlippageUpdated event
        vm.expectEmit(false, false, false, true);
        emit SlippageUpdated(oldSlippage, newSlippage);

        priceOracle.updateSlippage(newSlippage);
        vm.stopPrank();

        // Assert: Verify the slippage was updated
        assertEq(priceOracle.defaultSlippage(), newSlippage);
    }

    /**
     * @dev Tests updating slippage with invalid value
     * @notice This tests slippage validation
     */
    function test_UpdateDefaultSlippage_TooHigh() public {
        // Arrange: Set up excessive slippage
        uint256 excessiveSlippage = 1001; // 10.01% (over 10% limit)

        // Act & Assert: Expect the function to revert
        vm.startPrank(admin);
        vm.expectRevert(PriceOracle.InvalidSlippage.selector);
        priceOracle.updateSlippage(excessiveSlippage);
        vm.stopPrank();

        // Verify the slippage wasn't changed
        assertEq(priceOracle.defaultSlippage(), 100); // Should remain at default
    }

    /**
     * @dev Tests that only owner can update slippage
     * @notice This tests our access control for slippage updates
     */
    function test_UpdateDefaultSlippage_OnlyOwner() public {
        // Arrange: Set up new slippage
        uint256 newSlippage = 200; // 2%

        // Act & Assert: Try to update slippage as non-owner
        vm.startPrank(user1);
        vm.expectRevert(); // Should revert due to Ownable restriction
        priceOracle.updateSlippage(newSlippage);
        vm.stopPrank();

        // Verify the slippage wasn't changed
        assertEq(priceOracle.defaultSlippage(), 100); // Should remain at default
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @dev Tests price calculation with zero amounts
     * @notice This tests our handling of edge case inputs
     */
    function test_PriceCalculation_ZeroAmount() public {
        // Arrange: Set up zero amount
        uint256 zeroAmount = 0;

        // Act: Get price for zero amount
        uint256 ethPrice = priceOracle.getETHPrice(zeroAmount);
        uint256 tokenPrice = priceOracle.getTokenAmountForUSDC(MOCK_TOKEN, zeroAmount, 0);

        // Assert: Verify zero amounts return zero
        assertEq(ethPrice, 0);
        assertEq(tokenPrice, 0);
    }

    /**
     * @dev Tests price calculation with very small amounts
     * @notice This tests precision with small amounts
     */
    function test_PriceCalculation_SmallAmounts() public {
        // Arrange: Set up very small USDC amount
        uint256 smallAmount = 1; // 1 micro-USDC (0.000001 USDC)

        // Act: Get price for small amount
        uint256 ethPrice = priceOracle.getETHPrice(smallAmount);

        // Assert: Verify calculation works with small amounts
        // 0.000001 USDC should equal 0.0000000005 ETH
        uint256 expectedEthPrice = 500; // 0.0000000005 ETH in wei
        assertEq(ethPrice, expectedEthPrice);
    }

    /**
     * @dev Tests price calculation with very large amounts
     * @notice This tests handling of large amounts without overflow
     */
    function test_PriceCalculation_LargeAmounts() public {
        // Arrange: Set up large USDC amount
        uint256 largeAmount = 1000000e6; // $1M USDC

        // Act: Get price for large amount
        uint256 ethPrice = priceOracle.getETHPrice(largeAmount);

        // Assert: Verify calculation works with large amounts
        // $1M USDC should equal 500 ETH (at 2000 USDC per ETH)
        uint256 expectedEthPrice = 500e18; // 500 ETH
        assertEq(ethPrice, expectedEthPrice);
    }

    /**
     * @dev Tests token decimal handling
     * @notice This tests our decimal conversion logic
     */
    function test_TokenDecimalHandling() public {
        // Test with different decimal tokens
        // USDC (6 decimals), WETH (18 decimals), Mock token (18 decimals)

        // Test USDC to WETH conversion
        uint256 usdcAmount = 2000e6; // $2000 USDC
        uint256 wethAmount = priceOracle.getTokenAmountForUSDC(WETH, usdcAmount, 0);

        // Should get 1 WETH (18 decimals)
        assertEq(wethAmount, 1e18);

        // Test USDC to Mock token conversion
        uint256 mockAmount = priceOracle.getTokenAmountForUSDC(MOCK_TOKEN, 1e6, 0);

        // Should get 1 Mock token (18 decimals)
        assertEq(mockAmount, 1e18);
    }

    /**
     * @dev Tests optimal pool fee detection
     * @notice This tests our automatic pool fee selection logic
     */
    function test_OptimalPoolFeeDetection() public {
        // Test that the oracle selects appropriate fees for different token pairs

        // WETH-USDC should use 3000 (0.3%) as default
        uint256 wethUsdcPrice = priceOracle.getTokenPrice(WETH, USDC, 1e18, 0);
        assertEq(wethUsdcPrice, 2000e6); // Should use the 3000 fee tier

        // Mock token should also use 3000 as default
        uint256 mockUsdcPrice = priceOracle.getTokenPrice(MOCK_TOKEN, USDC, 1e18, 0);
        assertEq(mockUsdcPrice, 1e6); // Should use the 3000 fee tier
    }

    /**
     * @dev Tests price consistency across different functions
     * @notice This tests that our different price functions return consistent results
     */
    function test_PriceConsistency() public {
        // Test that getETHPrice and getTokenAmountForUSDC return consistent results
        uint256 usdcAmount = 1000e6; // $1000 USDC

        // Get ETH price using dedicated function
        uint256 ethPriceViaEthFunction = priceOracle.getETHPrice(usdcAmount);

        // Get ETH price using general token function
        uint256 ethPriceViaTokenFunction = priceOracle.getTokenAmountForUSDC(WETH, usdcAmount, 0);

        // Both should return the same result
        assertEq(ethPriceViaEthFunction, ethPriceViaTokenFunction);
    }

    /**
     * @dev Tests handling of unsupported token pairs
     * @notice This tests our error handling for unsupported tokens
     */
    function test_UnsupportedTokenPairs() public {
        // Arrange: Set up unsupported token
        address unsupportedToken = address(0x9999);

        // Act & Assert: Expect the function to revert for unsupported token
        vm.expectRevert("MockQuoterV2: No liquidity");
        priceOracle.getTokenAmountForUSDC(unsupportedToken, 100e6, 0);
    }
}
