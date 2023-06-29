// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title TokenFund
 * @author Kate Johnson
 * @notice This contract allows users to deposit either DAI or USDC to be exchanged 50% for LINK and 50% for WETH. When user wants to withdraw, it converts the LINK or WETH tokens back to USDC or DAI. The contract is connected to UniswapV2 and SushiSwap to check which exchange will give the best price before performing the swap using the better exchange.
 *
 *  @dev Allows for 2% slippage on exchanges when conducting a swap.
 */

contract TokenFund {
    /* ========== ERRORS ========== */
    error TokenFund_Invalid_Token_Only_USDC_or_DAI_Allowed();
    error TokenFund_Invalid_Token_Only_LINK_or_WETH_Allowed();

    /* ========== STATE VARIABLES ========== */
    using SafeERC20 for IERC20;
    /**
     * @notice Token addresses
     */

    address private immutable USDC;
    address private immutable DAI;
    address private immutable LINK;
    address private immutable WETH;

    /**
     * @notice UniswapV2 an SushiSwap exchanges
     */
    address private immutable uniswapv2;
    address private immutable sushiswap;

    /**
     * @notice Allow for 2% slippage on exchanges
     */
    uint256 private constant SLIPPAGE = 98;
    uint256 private constant SLIPPAGE_DECIMALS = 100;

    /* ========== EVENTS ========== */
    event Deposit(address indexed token, uint256 amountIn, uint256 linkAmountOut, uint256 wethAmountOut);
    event Withdraw(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /* ========== CONSTRUCTOR ========== */

    constructor(address _usdc, address _dai, address _link, address _weth, address _uniswapv2, address _sushiswap) {
        USDC = _usdc;
        DAI = _dai;
        LINK = _link;
        WETH = _weth;
        uniswapv2 = _uniswapv2;
        sushiswap = _sushiswap;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @dev Exchanges user stable coins 50% WETH and 50% LINK using either UniswapV2 or SushiSwap depending on which exchange gives a better rate
     * @param _amount - the amount of stable coins the user is depositing
     * @param _token - the address of the stable coin the user is exchanging for (must be USDC or DAI)
     * @return linkAmount - the amount of LINK tokens received after executing the exchange
     * @return wethAmount - the amount of WETH tokens received after executing the exchange
     */
    function deposit(uint256 _amount, address _token) external returns (uint256 linkAmount, uint256 wethAmount) {
        if (_token != USDC && _token != DAI) {
            revert TokenFund_Invalid_Token_Only_USDC_or_DAI_Allowed();
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 half = _amount / 2;

        address[] memory pathToLink = new address[](2);
        address[] memory pathToWeth = new address[](2);

        pathToLink[0] = _token;
        pathToLink[1] = LINK;

        pathToWeth[0] = _token;
        pathToWeth[1] = WETH;

        uint256 uniswapv2LinkAmount = _getPrice(uniswapv2, half, pathToLink);
        uint256 sushiswapLinkAmount = _getPrice(sushiswap, half, pathToLink);

        // Swap half of the stable coin for LINK
        if (uniswapv2LinkAmount > sushiswapLinkAmount) {
            // Use Uniswap to swap to LINK
            uint256 amountOutmin = (uniswapv2LinkAmount * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_token).safeIncreaseAllowance(uniswapv2, half);
            linkAmount = _swap(uniswapv2, half, amountOutmin, pathToLink, msg.sender, block.timestamp + 600);
        } else {
            // Use SushiSwap to swap to LINK
            uint256 amountOutMin = (sushiswapLinkAmount * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_token).safeIncreaseAllowance(sushiswap, half);
            linkAmount = _swap(sushiswap, half, amountOutMin, pathToLink, msg.sender, block.timestamp + 600);
        }

        // Swap the other half of the stable coin for WETH
        uint256 remaining = _amount - half;
        uint256 uniswapv2WethAmount = _getPrice(uniswapv2, remaining, pathToWeth);
        uint256 sushiswapWethAmount = _getPrice(sushiswap, remaining, pathToWeth);

        if (uniswapv2WethAmount > sushiswapWethAmount) {
            // Use Uniswap to swap to WETH
            uint256 amountOutMin = (uniswapv2WethAmount * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_token).safeIncreaseAllowance(uniswapv2, remaining);
            wethAmount = _swap(uniswapv2, remaining, amountOutMin, pathToWeth, msg.sender, block.timestamp + 600);
        } else {
            // Use SushiSwap to swap to WETH
            uint256 amountOutMin = (sushiswapWethAmount * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_token).safeIncreaseAllowance(sushiswap, remaining);
            wethAmount = _swap(sushiswap, remaining, amountOutMin, pathToWeth, msg.sender, block.timestamp + 600);
        }

        emit Deposit(_token, _amount, linkAmount, wethAmount);

        return (linkAmount, wethAmount);
    }

    /**
     * @dev Exchanges LINK or WETH token back to stable coin using either UniswapV2 or SushiSwap depending on which exchange gives a better rate
     * @param _amount - the amount of LINK or WETH the user is exchanging for
     * @param _tokenIn - either LINK or WETH address to exchange for stable coin
     * @param _tokenOut - the desired stable coin to receive in exchange (must be USDC or DAI)
     * @return amountOut - the amount of stable coin received after executing the exchange
     */
    function withdraw(uint256 _amount, address _tokenIn, address _tokenOut) external returns (uint256 amountOut) {
        if (_tokenIn != LINK && _tokenIn != WETH) {
            revert TokenFund_Invalid_Token_Only_LINK_or_WETH_Allowed();
        }
        if (_tokenOut != USDC && _tokenOut != DAI) {
            revert TokenFund_Invalid_Token_Only_USDC_or_DAI_Allowed();
        }

        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);

        address[] memory path = new address[](2);

        path[0] = _tokenIn;
        path[1] = _tokenOut;

        uint256 uniswapv2AmountOut = _getPrice(uniswapv2, _amount, path);
        uint256 sushiswapAmountOut = _getPrice(sushiswap, _amount, path);

        if (uniswapv2AmountOut > sushiswapAmountOut) {
            // Use Uniswap to swap to stable coin
            uint256 amountOutMin = (uniswapv2AmountOut * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_tokenIn).safeIncreaseAllowance(uniswapv2, _amount);
            amountOut = _swap(uniswapv2, _amount, amountOutMin, path, msg.sender, block.timestamp + 600);
        } else {
            // Use SushiSwap to swap to stable coin
            uint256 amountOutMin = (sushiswapAmountOut * SLIPPAGE) / SLIPPAGE_DECIMALS;
            IERC20(_tokenIn).safeIncreaseAllowance(sushiswap, _amount);
            amountOut = _swap(sushiswap, _amount, amountOutMin, path, msg.sender, block.timestamp + 600);
        }

        emit Withdraw(_tokenIn, _tokenOut, _amount, amountOut);

        return amountOut;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    /**
     * @dev Internal function to get the amount of token out for a swap on specified router
     * @param _router - address of exchange (either uniswapv2 or sushiswap)
     * @param _amount - the exact amount of input tokens to be spent
     * @param _path - array of token addresses. The swap is executed along this path. (index 0 = tokenIn, index 1 = tokenOut)
     * @return the amount of token out received after executing the exchange
     */
    function _getPrice(address _router, uint256 _amount, address[] memory _path) internal view returns (uint256) {
        return IUniswapV2Router02(_router).getAmountsOut(_amount, _path)[1];
    }

    /**
     * @dev Internal function to execute the exchange of one token for another on either UniswapV2 or SushiSwap
     * @param _router - address of exchange (either uniswapv2 or sushiswap)
     * @param _amountIn - the exact amount of input tokens to be spent
     * @param _amountOutMin - the minimum amount of output tokens to be received. This can be used to prevent the transaction if slippage is too high.
     * @param _path - array of token addresses. The swap is executed along this path. (index 0 = tokenIn, index 1 = tokenOut)
     * @param _to - the address that will receive the output tokens
     * @param _deadline - timestamp after which the transaction will revert
     * @return - the amount of token out recieved after executing the exchange
     */
    function _swap(
        address _router,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal returns (uint256) {
        return IUniswapV2Router02(_router).swapExactTokensForTokens(_amountIn, _amountOutMin, _path, _to, _deadline)[1];
    }
}
