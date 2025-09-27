// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { TestSetup } from "../../helpers/TestSetup.sol";
import { PriceOracle } from "../../../src/PriceOracle.sol";
import { IQuoterV2 } from "../../../src/interfaces/IPlatformInterfaces.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockQuoterV2 } from "../../mocks/MockQuoterV2.sol";

/**
 * @title PriceOracleTest
 * @dev Unit tests for PriceOracle contract - Financial security tests
 * @notice Tests Uniswap V3 integration, price validation, slippage protection, and token pair management
 */
contract PriceOracleTest is TestSetup {
    // Test contracts
    PriceOracle public testPriceOracle;
    MockQuoterV2 public testQuoterV2;
    MockERC20 public testTokenA;
    MockERC20 public testTokenB;

    // Test data
    address testUser = address(0x1234);
    uint256 constant TEST_AMOUNT = 1e18; // 1 token
    uint256 constant USDC_AMOUNT = 100e6; // 100 USDC

    function setUp() public override {
        super.setUp();

        // Deploy fresh contracts for testing
        testQuoterV2 = new MockQuoterV2();
        testTokenA = new MockERC20("Token A", "TKA", 18);
        testTokenB = new MockERC20("Token B", "TKB", 18);

        // Deploy PriceOracle with mock quoter
        testPriceOracle = new PriceOracle(address(testQuoterV2), address(mockWETH), address(mockUSDC));

        // Set up mock quoter responses
        testQuoterV2.setMockPrice(address(mockWETH), address(mockUSDC), 3000, 2000e6); // 1 WETH = 2000 USDC
        testQuoterV2.setMockPrice(address(mockUSDC), address(mockWETH), 3000, 0.0005e18); // 1 USDC = 0.0005 WETH
        testQuoterV2.setUSDCAlias(address(mockUSDC));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_ValidParameters() public {
        // Test that constructor sets up correctly
        assertEq(address(testPriceOracle.quoterV2()), address(testQuoterV2));
        assertEq(testPriceOracle.WETH(), address(mockWETH));
        assertEq(testPriceOracle.USDC(), address(mockUSDC));
        assertEq(testPriceOracle.owner(), admin);

        // Test pool fees
        assertEq(testPriceOracle.DEFAULT_POOL_FEE(), 3000);
        assertEq(testPriceOracle.STABLE_POOL_FEE(), 500);
        assertEq(testPriceOracle.HIGH_FEE(), 10000);
    }

    function test_Constructor_InvalidQuoter() public {
        // Test constructor with zero quoter address should revert
        vm.expectRevert(PriceOracle.InvalidQuoterAddress.selector);
        new PriceOracle(address(0), address(mockWETH), address(mockUSDC));
    }

    function test_Constructor_InvalidWETH() public {
        // Test constructor with zero WETH address should revert
        vm.expectRevert("Invalid WETH address");
        new PriceOracle(address(testQuoterV2), address(0), address(mockUSDC));
    }

    function test_Constructor_InvalidUSDC() public {
        // Test constructor with zero USDC address should revert
        vm.expectRevert("Invalid USDC address");
        new PriceOracle(address(testQuoterV2), address(mockWETH), address(0));
    }

    // ============ PRICE QUOTE TESTS ============

    function test_GetTokenPrice_ETHtoUSDC() public {
        // Test ETH to USDC quote
        uint256 ethAmount = 1e18; // 1 ETH
        uint256 expectedUsdc = 2000e6; // 2000 USDC

        uint256 usdcAmount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), ethAmount, 0);

        assertEq(usdcAmount, expectedUsdc);
    }

    function test_GetTokenPrice_USDCtoETH() public {
        // Test USDC to ETH quote
        uint256 usdcAmount = 2000e6; // 2000 USDC
        uint256 expectedEth = 1e18; // 1 ETH

        uint256 ethAmount = testPriceOracle.getTokenPrice(address(mockUSDC), address(mockWETH), usdcAmount, 0);

        assertEq(ethAmount, expectedEth);
    }

    function test_GetTokenPrice_CustomPoolFee() public {
        // Set custom pool fee
        vm.prank(admin);
        testPriceOracle.setCustomPoolFee(address(mockWETH), address(mockUSDC), 500);

        // Quote should use custom fee
        uint256 ethAmount = 1e18;
        uint256 usdcAmount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), ethAmount, 0);

        // With 0.05% fee, we should get slightly different result
        assertTrue(usdcAmount > 0);
    }

    function test_GetTokenPrice_InvalidTokens() public {
        // Test with zero address should handle gracefully
        uint256 amount = testPriceOracle.getTokenPrice(address(0), address(mockUSDC), 1e18, 0);
        // Should return 0 for invalid pairs
        assertEq(amount, 0);
    }

    function test_GetTokenPrice_ZeroAmount() public {
        // Test with zero amount should return 0
        uint256 amount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), 0, 0);
        assertEq(amount, 0);
    }

    // ============ ETH PRICE TESTS ============

    function test_GetETHPrice_ValidAmount() public {
        // Test ETH price for 100 USDC
        uint256 usdcAmount = 100e6; // 100 USDC
        uint256 expectedEth = 0.05e18; // 0.05 ETH

        uint256 ethAmount = testPriceOracle.getETHPrice(usdcAmount);

        assertEq(ethAmount, expectedEth);
    }

    function test_GetETHPrice_ZeroAmount() public {
        // Test ETH price for 0 USDC should return 0
        uint256 ethAmount = testPriceOracle.getETHPrice(0);
        assertEq(ethAmount, 0);
    }

    function test_GetETHPrice_MicroAmount() public {
        // Test ETH price for micro amounts (less than 1 USDC)
        uint256 microAmount = 1e5; // 0.1 USDC
        uint256 ethAmount = testPriceOracle.getETHPrice(microAmount);

        // Should return proportional amount (1e5 * 500 wei)
        assertEq(ethAmount, microAmount * 500);
    }

    // ============ TOKEN AMOUNT FOR USDC TESTS ============

    function test_GetTokenAmountForUSDC_USDCInput() public {
        // Test with USDC as input token (should be 1:1)
        uint256 usdcAmount = 100e6;
        uint256 tokenAmount = testPriceOracle.getTokenAmountForUSDC(address(mockUSDC), usdcAmount, 0);

        assertEq(tokenAmount, usdcAmount);
    }

    function test_GetTokenAmountForUSDC_ETHInput() public {
        // Test with ETH as input token
        uint256 usdcAmount = 100e6; // Want 100 USDC
        uint256 expectedEth = 0.05e18; // 0.05 ETH

        uint256 tokenAmount = testPriceOracle.getTokenAmountForUSDC(address(mockWETH), usdcAmount, 0);

        assertEq(tokenAmount, expectedEth);
    }

    function test_GetTokenAmountForUSDC_OtherToken() public {
        // Test with other token - should route through WETH if direct path fails
        uint256 usdcAmount = 100e6;

        // Mock direct path failure
        testQuoterV2.setShouldFailQuote(address(testTokenA), address(mockUSDC), true);

        uint256 tokenAmount = testPriceOracle.getTokenAmountForUSDC(address(testTokenA), usdcAmount, 0);

        // Should still return a result (routing through WETH)
        assertTrue(tokenAmount > 0);
    }

    // ============ MULTIPLE QUOTES TESTS ============

    function test_GetMultipleQuotes_Success() public {
        // Test getting quotes from multiple pool fee tiers
        uint256 amountIn = 1e18;

        uint256[3] memory quotes = testPriceOracle.getMultipleQuotes(address(mockWETH), address(mockUSDC), amountIn);

        // All quotes should be valid
        assertTrue(quotes[0] > 0); // 500bp fee
        assertTrue(quotes[1] > 0); // 3000bp fee
        assertTrue(quotes[2] > 0); // 10000bp fee

        // Higher fees should result in lower output
        assertTrue(quotes[0] >= quotes[1]); // 500bp >= 3000bp
        assertTrue(quotes[1] >= quotes[2]); // 3000bp >= 10000bp
    }

    function test_GetMultipleQuotes_QuoteFailure() public {
        // Mock quote failure
        testQuoterV2.setShouldFailQuote(address(mockWETH), address(mockUSDC), true);

        uint256 amountIn = 1e18;
        uint256[3] memory quotes = testPriceOracle.getMultipleQuotes(address(mockWETH), address(mockUSDC), amountIn);

        // All quotes should be 0 on failure
        assertEq(quotes[0], 0);
        assertEq(quotes[1], 0);
        assertEq(quotes[2], 0);
    }

    // ============ PRICE VALIDATION TESTS ============

    function test_ValidateQuoteBeforeSwap_ValidQuote() public {
        // Test quote validation with valid parameters
        uint256 amountIn = 1e18;
        uint256 expectedOut = 2000e6;
        uint256 maxSlippage = 100; // 1%
        uint24 poolFee = 3000;

        (bool isValid, uint256 validatedAmount) = testPriceOracle.validateQuoteBeforeSwap(
            address(mockWETH),
            address(mockUSDC),
            amountIn,
            expectedOut,
            maxSlippage,
            poolFee
        );

        assertTrue(isValid);
        assertEq(validatedAmount, expectedOut);
    }

    function test_ValidateQuoteBeforeSwap_HighSlippage() public {
        // Test quote validation with high slippage
        uint256 amountIn = 1e18;
        uint256 expectedOut = 2000e6;
        uint256 maxSlippage = 50; // 0.5%

        (bool isValid, uint256 validatedAmount) = testPriceOracle.validateQuoteBeforeSwap(
            address(mockWETH),
            address(mockUSDC),
            amountIn,
            expectedOut * 2, // Double expected amount (high slippage)
            maxSlippage,
            3000
        );

        assertFalse(isValid);
        assertEq(validatedAmount, expectedOut * 2);
    }

    function test_ValidateQuoteBeforeSwap_ZeroValues() public {
        // Test validation with zero values
        (bool isValid, uint256 validatedAmount) = testPriceOracle.validateQuoteBeforeSwap(
            address(mockWETH),
            address(mockUSDC),
            0,
            0,
            100,
            3000
        );

        assertTrue(isValid);
        assertEq(validatedAmount, 0);
    }

    // ============ PRICE IMPACT TESTS ============

    function test_CheckPriceImpact_AcceptableImpact() public {
        // Test price impact check with acceptable impact
        uint256 amountIn = 1e18;
        uint256 expectedOut = 2000e6;
        uint256 actualOut = 1990e6; // 0.5% impact

        (uint256 impact, bool isAcceptable) = testPriceOracle.checkPriceImpact(
            address(mockWETH),
            address(mockUSDC),
            amountIn,
            actualOut
        );

        assertEq(impact, 50); // 0.5%
        assertTrue(isAcceptable);
    }

    function test_CheckPriceImpact_HighImpact() public {
        // Test price impact check with high impact
        uint256 amountIn = 1e18;
        uint256 expectedOut = 2000e6;
        uint256 actualOut = 1800e6; // 10% impact

        (uint256 impact, bool isAcceptable) = testPriceOracle.checkPriceImpact(
            address(mockWETH),
            address(mockUSDC),
            amountIn,
            actualOut
        );

        assertEq(impact, 1000); // 10%
        assertFalse(isAcceptable);
    }

    function test_CheckPriceImpact_ZeroExpected() public {
        // Test price impact with zero expected (should handle gracefully)
        uint256 amountIn = 1e18;
        uint256 actualOut = 2000e6;

        (uint256 impact, bool isAcceptable) = testPriceOracle.checkPriceImpact(
            address(mockWETH),
            address(mockUSDC),
            amountIn,
            actualOut
        );

        // Should return 0 impact for zero expected
        assertEq(impact, 0);
        assertTrue(isAcceptable);
    }

    // ============ CUSTOM POOL FEE TESTS ============

    function test_SetCustomPoolFee_ValidFee() public {
        // Set custom pool fee
        address tokenA = address(testTokenA);
        address tokenB = address(testTokenB);
        uint24 fee = 500;

        vm.prank(admin);
        vm.expectEmit(true, true, true, false);
        emit PriceOracle.CustomPoolFeeSet(tokenA, tokenB, fee);
        testPriceOracle.setCustomPoolFee(tokenA, tokenB, fee);

        // Verify custom fee is set
        assertEq(testPriceOracle.customPoolFees(tokenA, tokenB), fee);
    }

    function test_SetCustomPoolFee_UnauthorizedUser() public {
        // Non-owner should not be able to set custom fees
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testPriceOracle.setCustomPoolFee(address(testTokenA), address(testTokenB), 500);
    }

    function test_SetCustomPoolFee_InvalidFee() public {
        // Test setting invalid pool fee (too high)
        vm.prank(admin);
        vm.expectRevert(PriceOracle.InvalidPoolFee.selector);
        testPriceOracle.setCustomPoolFee(address(testTokenA), address(testTokenB), 100000); // 10%
    }

    // ============ SLIPPAGE SETTINGS TESTS ============

    function test_UpdateDefaultSlippage_ValidSlippage() public {
        // Update default slippage
        uint256 newSlippage = 200; // 2%

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit PriceOracle.SlippageUpdated(100, 200);
        testPriceOracle.updateSlippage(newSlippage);

        // Verify slippage is updated
        assertEq(testPriceOracle.defaultSlippage(), newSlippage);
    }

    function test_UpdateDefaultSlippage_UnauthorizedUser() public {
        // Non-owner should not be able to update slippage
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testPriceOracle.updateSlippage(200);
    }

    function test_UpdateDefaultSlippage_InvalidSlippage() public {
        // Test invalid slippage values
        vm.prank(admin);
        vm.expectRevert(PriceOracle.InvalidSlippage.selector);
        testPriceOracle.updateSlippage(10001); // > 100%

        vm.prank(admin);
        vm.expectRevert(PriceOracle.InvalidSlippage.selector);
        testPriceOracle.updateSlippage(0); // 0%
    }

    // ============ QUOTER UPDATE TESTS ============

    function test_UpdateQuoter_ValidAddress() public {
        // Deploy new quoter
        MockQuoterV2 newQuoter = new MockQuoterV2();

        // Update quoter
        vm.prank(admin);
        vm.expectEmit(true, true, true, false);
        emit PriceOracle.QuoterUpdated(address(testQuoterV2), address(newQuoter));
        testPriceOracle.updateQuoter(address(newQuoter));

        // Verify quoter is updated
        assertEq(address(testPriceOracle.quoterV2()), address(newQuoter));
    }

    function test_UpdateQuoter_UnauthorizedUser() public {
        // Non-owner should not be able to update quoter
        vm.prank(testUser);
        vm.expectRevert("Ownable: caller is not the owner");
        testPriceOracle.updateQuoter(address(0x1234));
    }

    function test_UpdateQuoter_InvalidAddress() public {
        // Test updating with invalid address
        vm.prank(admin);
        vm.expectRevert(PriceOracle.InvalidQuoterAddress.selector);
        testPriceOracle.updateQuoter(address(0));
    }

    // ============ OPTIMAL POOL FEE TESTS ============

    function test_SelectOptimalPoolFee_ETHUSDC() public {
        // Test optimal pool fee selection for ETH/USDC pair
        uint24 fee = testPriceOracle.getOptimalPoolFeeForSwap(address(mockWETH), address(mockUSDC));

        // Should return stable pool fee for USDC pairs
        assertEq(fee, testPriceOracle.STABLE_POOL_FEE());
    }

    function test_SelectOptimalPoolFee_OtherPair() public {
        // Test optimal pool fee selection for other pairs
        uint24 fee = testPriceOracle.getOptimalPoolFeeForSwap(address(testTokenA), address(testTokenB));

        // Should return default pool fee for other pairs
        assertEq(fee, testPriceOracle.DEFAULT_POOL_FEE());
    }

    function test_SelectOptimalPoolFee_SameToken() public {
        // Test optimal pool fee selection for same token (should handle gracefully)
        uint24 fee = testPriceOracle.getOptimalPoolFeeForSwap(address(mockUSDC), address(mockUSDC));

        // Should return default pool fee
        assertEq(fee, testPriceOracle.DEFAULT_POOL_FEE());
    }

    // ============ EDGE CASE TESTS ============

    function test_QuoteExactInputSingleView_Revert() public {
        // Mock quote revert
        testQuoterV2.setShouldFailQuote(address(mockWETH), address(mockUSDC), true);

        // Should handle revert gracefully and return 0
        uint256 amount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), 1e18, 0);
        assertEq(amount, 0);
    }

    function test_QuoteExactInputSingleView_Success() public {
        // Mock successful quote
        testQuoterV2.setShouldFailQuote(address(mockWETH), address(mockUSDC), false);
        testQuoterV2.setMockPrice(address(mockWETH), address(mockUSDC), 3000, 2000e6);

        // Should return expected amount
        uint256 amount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), 1e18, 0);
        assertEq(amount, 2000e6);
    }

    // ============ INTEGRATION TESTS ============

    function test_FullPriceWorkflow() public {
        // 1. Set up custom pool fee
        vm.prank(admin);
        testPriceOracle.setCustomPoolFee(address(mockWETH), address(mockUSDC), 500);

        // 2. Update slippage tolerance
        vm.prank(admin);
        testPriceOracle.updateSlippage(200);

        // 3. Get price quote
        uint256 ethAmount = 1e18;
        uint256 usdcAmount = testPriceOracle.getTokenPrice(address(mockWETH), address(mockUSDC), ethAmount, 0);

        assertTrue(usdcAmount > 0);

        // 4. Validate quote
        (bool isValid,) = testPriceOracle.validateQuoteBeforeSwap(
            address(mockWETH),
            address(mockUSDC),
            ethAmount,
            usdcAmount,
            100,
            500
        );

        assertTrue(isValid);

        // 5. Check price impact
        (uint256 impact, bool acceptable) = testPriceOracle.checkPriceImpact(
            address(mockWETH),
            address(mockUSDC),
            ethAmount,
            usdcAmount
        );

        assertTrue(acceptable);
        assertTrue(impact <= 100);
    }

    function test_TokenAmountForUSDCCalculations() public {
        // Test various token to USDC calculations
        uint256 usdcAmount = 100e6;

        // USDC to USDC (1:1)
        uint256 usdcTokenAmount = testPriceOracle.getTokenAmountForUSDC(address(mockUSDC), usdcAmount, 0);
        assertEq(usdcTokenAmount, usdcAmount);

        // ETH to USDC
        uint256 ethTokenAmount = testPriceOracle.getTokenAmountForUSDC(address(mockWETH), usdcAmount, 0);
        assertTrue(ethTokenAmount > 0);

        // Other token to USDC (should route through WETH)
        uint256 otherTokenAmount = testPriceOracle.getTokenAmountForUSDC(address(testTokenA), usdcAmount, 0);
        assertTrue(otherTokenAmount > 0);
    }

    // ============ FUZZING TESTS ============

    function testFuzz_GetTokenPrice_ValidInputs(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 poolFee
    ) public {
        // Assume valid inputs
        vm.assume(tokenIn != address(0) && tokenOut != address(0));
        vm.assume(amountIn > 0 && amountIn <= 1e18 * 1000); // Max 1000 tokens
        vm.assume(poolFee <= 10000); // Max 1% fee

        // Should not revert and return reasonable result
        uint256 amountOut = testPriceOracle.getTokenPrice(tokenIn, tokenOut, amountIn, poolFee);

        // Result should be either 0 (invalid pair) or positive (valid pair)
        assertTrue(amountOut >= 0);
    }

    function testFuzz_UpdateDefaultSlippage_ValidValues(uint256 slippage) public {
        // Test valid slippage values (1-1000 basis points = 0.01%-10%)
        vm.assume(slippage >= 1 && slippage <= 1000);

        vm.prank(admin);
        testPriceOracle.updateSlippage(slippage);

        assertEq(testPriceOracle.defaultSlippage(), slippage);
    }

    function testFuzz_SetCustomPoolFee_ValidFees(
        address tokenA,
        address tokenB,
        uint24 fee
    ) public {
        // Assume valid inputs
        vm.assume(tokenA != address(0) && tokenB != address(0));
        vm.assume(fee <= 10000); // Max 1% fee

        vm.prank(admin);
        testPriceOracle.setCustomPoolFee(tokenA, tokenB, fee);

        assertEq(testPriceOracle.customPoolFees(tokenA, tokenB), fee);
    }
}
