// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IQuoterV2} from "./interfaces/IPlatformInterfaces.sol";

/**
 * @title PriceOracle
 * @dev Uses Uniswap V3 Quoter for real-time price estimation
 * @notice This contract provides accurate price quotes for token swaps
 */
contract PriceOracle is Ownable {
    
    // Uniswap V3 Quoter contract on Base
    IQuoterV2 public constant QUOTER_V2 = IQuoterV2(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);
    
    // Token addresses on Base
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Default pool fees for common pairs
    uint24 public constant DEFAULT_POOL_FEE = 3000; // 0.3%
    uint24 public constant STABLE_POOL_FEE = 500;   // 0.05% for stablecoin pairs
    uint24 public constant HIGH_FEE = 10000;        // 1% for exotic pairs
    
    // Slippage tolerance in basis points (default 1% = 100)
    uint256 public defaultSlippage = 100;
    
    // Custom pool fees for specific token pairs
    mapping(address => mapping(address => uint24)) public customPoolFees;
    
    // Events
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    
    // Custom errors
    error InvalidSlippage();
    error InvalidPoolFee();
    error QuoteReverted();
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Gets the amount of tokenOut needed for a given tokenIn amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address  
     * @param amountIn Amount of input token
     * @param poolFee Pool fee tier (0 for auto-detect)
     * @return amountOut Amount of output token
     */
    function getTokenPrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 poolFee
    ) external returns (uint256 amountOut) {
        if (poolFee == 0) {
            poolFee = _getOptimalPoolFee(tokenIn, tokenOut);
        }
        
        try QUOTER_V2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                fee: poolFee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 _amountOut, uint160, uint32, uint256) {
            return _amountOut;
        } catch {
            revert QuoteReverted();
        }
    }
    
    /**
     * @dev Gets ETH amount needed for a specific USDC amount
     * @param usdcAmount USDC amount (6 decimals)
     * @return ethAmount ETH amount needed (18 decimals)
     */
    function getETHPrice(uint256 usdcAmount) external returns (uint256 ethAmount) {
        uint24 poolFee = _getOptimalPoolFee(WETH, USDC);
        
        try QUOTER_V2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                amountIn: 1e18, // 1 ETH
                fee: poolFee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 usdcPerEth, uint160, uint32, uint256) {
            // Calculate ETH needed: (usdcAmount * 1e18) / usdcPerEth
            return (usdcAmount * 1e18) / usdcPerEth;
        } catch {
            revert QuoteReverted();
        }
    }
    
    /**
     * @dev Gets token amount needed for a specific USDC amount
     * @param token Token address
     * @param usdcAmount USDC amount needed
     * @param poolFee Pool fee (0 for auto-detect)
     * @return tokenAmount Token amount needed
     */
    function getTokenAmountForUSDC(
        address token,
        uint256 usdcAmount,
        uint24 poolFee
    ) external returns (uint256 tokenAmount) {
        if (token == USDC) {
            return usdcAmount;
        }
        
        if (poolFee == 0) {
            poolFee = _getOptimalPoolFee(token, USDC);
        }
        
        uint8 tokenDecimals = _getTokenDecimals(token);
        uint256 baseAmount = 10**tokenDecimals;
        
        try QUOTER_V2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: token,
                tokenOut: USDC,
                amountIn: baseAmount,
                fee: poolFee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 usdcPerToken, uint160, uint32, uint256) {
            return (usdcAmount * baseAmount) / usdcPerToken;
        } catch {
            return _getTokenAmountViaWETH(token, usdcAmount, tokenDecimals);
        }
    }
    
    /**
     * @dev Gets token amount via WETH route (token -> WETH -> USDC)
     * @param token Token address
     * @param usdcAmount USDC amount needed
     * @param tokenDecimals Token decimals
     * @return tokenAmount Token amount needed
     */
    function _getTokenAmountViaWETH(
        address token,
        uint256 usdcAmount,
        uint8 tokenDecimals
    ) internal returns (uint256 tokenAmount) {
        uint256 wethNeeded = this.getETHPrice(usdcAmount);
        
        uint24 poolFee = _getOptimalPoolFee(token, WETH);
        uint256 baseAmount = 10**tokenDecimals;
        
        try QUOTER_V2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: token,
                tokenOut: WETH,
                amountIn: baseAmount,
                fee: poolFee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 wethPerToken, uint160, uint32, uint256) {
            return (wethNeeded * baseAmount) / wethPerToken;
        } catch {
            revert QuoteReverted();
        }
    }
    
    /**
     * @dev Applies slippage to a quote amount
     * @param amount Original amount
     * @param slippageBps Slippage in basis points (100 = 1%)
     * @return adjustedAmount Amount with slippage applied
     */
    function applySlippage(
        uint256 amount,
        uint256 slippageBps
    ) external pure returns (uint256 adjustedAmount) {
        if (slippageBps > 10000) revert InvalidSlippage(); // Max 100%
        return amount + (amount * slippageBps) / 10000;
    }
    
    /**
     * @dev Gets multiple price quotes for different pool fees
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return quotes Array of quotes [500, 3000, 10000] fee tiers
     */
    function getMultipleQuotes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256[3] memory quotes) {
        uint24[3] memory fees = [STABLE_POOL_FEE, DEFAULT_POOL_FEE, HIGH_FEE];
        
        for (uint i = 0; i < 3; i++) {
            try QUOTER_V2.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: fees[i],
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut, uint160, uint32, uint256) {
                quotes[i] = amountOut;
            } catch {
                quotes[i] = 0; // Pool doesn't exist for this fee
            }
        }
        
        return quotes;
    }
    
    /**
     * @dev Gets the optimal pool fee for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @return poolFee Optimal pool fee
     */
    function _getOptimalPoolFee(
        address tokenA,
        address tokenB
    ) internal view returns (uint24 poolFee) {
        // Check for custom pool fee
        poolFee = customPoolFees[tokenA][tokenB];
        if (poolFee != 0) return poolFee;
        
        poolFee = customPoolFees[tokenB][tokenA];
        if (poolFee != 0) return poolFee;
        
        // Use defaults based on token types
        if (_isStablecoin(tokenA) && _isStablecoin(tokenB)) {
            return STABLE_POOL_FEE;
        } else if (tokenA == WETH || tokenB == WETH) {
            return DEFAULT_POOL_FEE;
        } else {
            return HIGH_FEE;
        }
    }
    
    /**
     * @dev Checks if a token is a stablecoin
     * @param token Token address
     * @return bool True if stablecoin
     */
    function _isStablecoin(address token) internal pure returns (bool) {
        return token == USDC || 
               token == 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA || // USDbC
               token == 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;   // DAI
    }
    
    /**
     * @dev Sets custom pool fee for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @param poolFee Pool fee (500, 3000, or 10000)
     */
    function setCustomPoolFee(
        address tokenA,
        address tokenB,
        uint24 poolFee
    ) external onlyOwner {
        if (poolFee != 500 && poolFee != 3000 && poolFee != 10000) {
            revert InvalidPoolFee();
        }
        
        customPoolFees[tokenA][tokenB] = poolFee;
        emit CustomPoolFeeSet(tokenA, tokenB, poolFee);
    }
    
    /**
     * @dev Updates default slippage tolerance
     * @param newSlippage New slippage in basis points
     */
    function updateDefaultSlippage(uint256 newSlippage) external onlyOwner {
        if (newSlippage > 1000) revert InvalidSlippage(); // Max 10%
        
        uint256 oldSlippage = defaultSlippage;
        defaultSlippage = newSlippage;
        
        emit SlippageUpdated(oldSlippage, newSlippage);
    }

    /**
     * @dev COMPLETE: Get token decimals safely
     */
    function _getTokenDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) return 18;
        if (token == WETH) return 18;
        if (token == USDC) return 6;
        
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint8));
        }
        
        return 18;
    }
}