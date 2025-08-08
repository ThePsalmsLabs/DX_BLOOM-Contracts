// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IQuoterV2 } from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title PriceOracle - FIXED VERSION
 * @dev Uses Uniswap V3 Quoter for real-time price estimation with configurable quoter
 * @notice This contract provides accurate price quotes for token swaps.
 *         CRITICAL FIX: Made quoter configurable for testing instead of hardcoded constant
 */
contract PriceOracle is Ownable {
    // ============ STATE VARIABLES ============

    // Configurable Uniswap V3 Quoter contract (FIXED: No longer constant)
    IQuoterV2 public quoterV2;

    // Token addresses on Base - these can remain constant as they're standard
    address public immutable WETH;
    address public immutable USDC;

    // Default pool fees for common pairs
    uint24 public constant DEFAULT_POOL_FEE = 3000; // 0.3%
    uint24 public constant STABLE_POOL_FEE = 500; // 0.05% for stablecoin pairs
    uint24 public constant HIGH_FEE = 10000; // 1% for exotic pairs

    // Slippage tolerance in basis points (default 1% = 100)
    uint256 public defaultSlippage = 100;

    // Custom pool fees for specific token pairs
    mapping(address => mapping(address => uint24)) public customPoolFees;

    // ============ EVENTS ============

    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event QuoterUpdated(address indexed oldQuoter, address indexed newQuoter);

    // ============ ERRORS ============

    error InvalidSlippage();
    error InvalidPoolFee();
    error QuoteReverted();
    error InvalidQuoterAddress();

    /**
     * @dev Constructor now accepts quoter address for maximum flexibility
     * @param _quoterV2 Address of the Uniswap V3 QuoterV2 contract
     * @notice For mainnet: 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a
     *         For testing: address of MockQuoterV2
     */
    constructor(address _quoterV2, address _weth, address _usdc) Ownable(msg.sender) {
        if (_quoterV2 == address(0)) revert InvalidQuoterAddress();
        if (_weth == address(0)) revert("Invalid WETH address");
        if (_usdc == address(0)) revert("Invalid USDC address");
        quoterV2 = IQuoterV2(_quoterV2);
        WETH = _weth;
        USDC = _usdc;
        emit QuoterUpdated(address(0), _quoterV2);
    }

    /**
     * @dev Admin function to update quoter address if needed
     * @param _newQuoter New quoter contract address
     * @notice This allows upgrading to new Uniswap versions or switching to mocks
     */
    function updateQuoter(address _newQuoter) external onlyOwner {
        if (_newQuoter == address(0)) revert InvalidQuoterAddress();
        address oldQuoter = address(quoterV2);
        quoterV2 = IQuoterV2(_newQuoter);
        emit QuoterUpdated(oldQuoter, _newQuoter);
    }

    /**
     * @dev Gets the amount of tokenOut needed for a given tokenIn amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token
     * @param poolFee Pool fee tier (0 for auto-detect)
     * @return amountOut Amount of output token
     */
    function getTokenPrice(address tokenIn, address tokenOut, uint256 amountIn, uint24 poolFee)
        external
        view
        returns (uint256 amountOut)
    {
        // Use custom pool fee if set, otherwise use provided fee or auto-detect
        uint24 fee = customPoolFees[tokenIn][tokenOut];
        if (fee == 0) {
            fee = poolFee == 0 ? _selectOptimalPoolFee(tokenIn, tokenOut) : poolFee;
        }

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            amountIn: amountIn,
            sqrtPriceLimitX96: 0
        });

        return _quoteExactInputSingleViewAmount(params);
    }

    /**
     * @dev Gets ETH price in USDC for a given USDC amount
     * @param usdcAmount Amount of USDC to get ETH price for
     * @return ethAmount Amount of ETH equivalent
     * @notice This is a specialized function for common ETH/USDC conversions
     */
    function getETHPrice(uint256 usdcAmount) external view returns (uint256 ethAmount) {
        // Always get ETH amount for 1 ETH first to calculate ratio
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: DEFAULT_POOL_FEE,
            amountIn: 1e18, // 1 ETH
            sqrtPriceLimitX96: 0
        });
        uint256 usdcPerEth = _quoteExactInputSingleViewAmount(params);
        return (usdcAmount * 1e18) / usdcPerEth;
    }

    /**
     * @dev Gets the amount of input token needed to get exact USDC output
     * @param tokenIn Input token address
     * @param usdcAmount Desired USDC amount
     * @param poolFee Pool fee tier (0 for auto-detect)
     * @return tokenAmount Amount of input token needed
     */
    function getTokenAmountForUSDC(address tokenIn, uint256 usdcAmount, uint24 poolFee)
        external
        view
        returns (uint256 tokenAmount)
    {
        uint24 fee = poolFee == 0 ? _selectOptimalPoolFee(tokenIn, USDC) : poolFee;

        // If token is already USDC, return 1:1
        if (tokenIn == USDC) {
            return usdcAmount;
        }

        // If token is WETH, use ETH price function
        if (tokenIn == WETH) {
            return this.getETHPrice(usdcAmount);
        }

        // For other tokens, first try direct path via staticcall; if it fails, route through WETH
        {
            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: USDC,
                fee: fee,
                amountIn: 1e18, // Use 1 token as base
                sqrtPriceLimitX96: 0
            });
            (bool ok, uint256 usdcPerToken) = _tryQuoteExactInputSingleViewAmount(params);
            if (ok) {
                return (usdcAmount * 1e18) / usdcPerToken;
            }
        }
        // If direct path fails, try routing through WETH
        return _getTokenAmountViaWETH(tokenIn, usdcAmount);
    }

    /**
     * @dev Gets quotes from multiple pool fee tiers for comparison
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return quotes Array of quotes [500bp, 3000bp, 10000bp]
     */
    function getMultipleQuotes(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256[3] memory quotes)
    {
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];

        for (uint256 i = 0; i < 3; i++) {
            try quoterV2.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fees[i],
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 outputAmount, uint160, uint32, uint256) {
                quotes[i] = outputAmount;
            } catch {
                quotes[i] = 0; // Mark as unavailable
            }
        }
    }

    /**
     * @dev Applies slippage tolerance to an amount
     * @param amount Base amount
     * @param slippageBps Slippage in basis points
     * @return adjustedAmount Amount with slippage applied
     */
    function applySlippage(uint256 amount, uint256 slippageBps) external pure returns (uint256 adjustedAmount) {
        if (slippageBps > 10000) revert InvalidSlippage(); // Max 100% slippage
        return amount + (amount * slippageBps) / 10000;
    }

    /**
     * @dev Sets custom pool fee for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @param fee Pool fee in basis points
     */
    function setCustomPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        if (fee != 500 && fee != 3000 && fee != 10000) revert InvalidPoolFee();

        customPoolFees[tokenA][tokenB] = fee;
        customPoolFees[tokenB][tokenA] = fee; // Set both directions

        emit CustomPoolFeeSet(tokenA, tokenB, fee);
    }

    /**
     * @dev Updates default slippage tolerance
     * @param newSlippage New slippage in basis points
     */
    function updateSlippage(uint256 newSlippage) external onlyOwner {
        if (newSlippage > 1000) revert InvalidSlippage(); // Max 10%
        uint256 oldSlippage = defaultSlippage;
        defaultSlippage = newSlippage;
        emit SlippageUpdated(oldSlippage, newSlippage);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Selects optimal pool fee based on token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @return fee Optimal pool fee
     */
    function _selectOptimalPoolFee(address tokenA, address tokenB) internal view returns (uint24 fee) {
        // Prefer 0.3% pool by default; only use 0.05% for explicit USDC<->USDC quotes
        if (tokenA == USDC && tokenB == USDC) {
            return STABLE_POOL_FEE;
        }

        // Use default fee for USDC pairs and WETH pairs
        if (tokenA == USDC || tokenB == USDC) {
            return DEFAULT_POOL_FEE;
        }
        if (tokenA == WETH || tokenB == WETH) {
            return DEFAULT_POOL_FEE;
        }

        // Use higher fee for exotic pairs
        return HIGH_FEE;
    }

    /**
     * @dev Gets token amount by routing through WETH
     * @param tokenIn Input token
     * @param usdcAmount Desired USDC amount
     * @return tokenAmount Required token amount
     */
    function _getTokenAmountViaWETH(address tokenIn, uint256 usdcAmount) internal view returns (uint256 tokenAmount) {
        // First get WETH amount needed for USDC
        uint256 wethNeeded = this.getETHPrice(usdcAmount);

        // Then get token amount needed for that WETH via staticcall
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: WETH,
            fee: DEFAULT_POOL_FEE,
            amountIn: 1e18,
            sqrtPriceLimitX96: 0
        });
        uint256 wethPerToken = _quoteExactInputSingleViewAmount(params);
        return (wethNeeded * 1e18) / wethPerToken;
    }

    // ============ INTERNAL VIEW HELPERS FOR QUOTER (STATICCALL) ============

    function _quoteExactInputSingleViewAmount(IQuoterV2.QuoteExactInputSingleParams memory params)
        internal
        view
        returns (uint256 amountOut)
    {
        (bool success, bytes memory result) = address(quoterV2).staticcall(
            abi.encodeWithSelector(IQuoterV2.quoteExactInputSingle.selector, params)
        );
        if (!success) {
            // bubble revert reason from mock or real quoter when available
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            }
            revert QuoteReverted();
        }
        (uint256 out,,,) = abi.decode(result, (uint256, uint160, uint32, uint256));
        return out;
    }

    function _tryQuoteExactInputSingleViewAmount(IQuoterV2.QuoteExactInputSingleParams memory params)
        internal
        view
        returns (bool success, uint256 amountOut)
    {
        (bool ok, bytes memory result) = address(quoterV2).staticcall(
            abi.encodeWithSelector(IQuoterV2.quoteExactInputSingle.selector, params)
        );
        if (!ok) {
            return (false, 0);
        }
        (uint256 out,,,) = abi.decode(result, (uint256, uint160, uint32, uint256));
        return (true, out);
    }
}
