// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title TokenFundV3
 * @author Kate Johnson
 * @notice This contract provides the same functionality as TokenFund, but uses UniswapV3. The contract allows users to deposit either DAI or USDC to be exchanged 50% for LINK and 50% for WETH. When user wants to withdraw, it converts the LINK or WETH tokens back to USDC or DAI. The contract is connected to UniswapV3 and SushiSwap to check which exchange will give the best price before performing the swap using the better exchange.
 *
 * @dev In production adjust amount out minimum params from 0 to a reasonable amount to prevent front running attacks.
 */

contract TokenFundV3 {
    /* ========== ERRORS ========== */
    error TokenFundV3__InvalidToken_Only_USDC_or_DAI_Allowed();
    error TokenFundV3__InvalidToken_Only_LINK_or_WETH_Allowed();

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
     * @notice UniswapV3 an SushiSwap exchanges
     */
    IQuoter private immutable uniswapQuoter;
    ISwapRouter private immutable uniswapv3;
    IUniswapV2Router02 private immutable sushiswap;

    /* ========== EVENTS ========== */
    event Deposit(address indexed token, uint256 amountIn, uint256 linkAmountOut, uint256 wethAmountOut);
    event Withdraw(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _usdc,
        address _dai,
        address _link,
        address _weth,
        IQuoter _uniswapQuoter,
        ISwapRouter _uniswapv3,
        IUniswapV2Router02 _sushiswap
    ) {
        USDC = _usdc;
        DAI = _dai;
        LINK = _link;
        WETH = _weth;
        uniswapQuoter = _uniswapQuoter;
        uniswapv3 = _uniswapv3;
        sushiswap = _sushiswap;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @dev Exchanges user stable coins 50% WETH and 50% LINK using either UniswapV3 or SushiSwap depending on which exchange gives a better rate
     * @param _amount - the amount of stable coins the user is depositing
     * @param _token - the address of the stable coin the user is exchanging for (must be USDC or DAI)
     * @return linkAmount - the amount of LINK tokens received after executing the exchange
     * @return wethAmount - the amount of WETH tokens received after executing the exchange
     */
    function deposit(uint256 _amount, address _token) external returns (uint256 linkAmount, uint256 wethAmount) {
        if (_token != USDC && _token != DAI) {
            revert TokenFundV3__InvalidToken_Only_USDC_or_DAI_Allowed();
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 half = _amount / 2;

        address[] memory pathToLink = new address[](2);
        address[] memory pathToWeth = new address[](2);

        pathToLink[0] = _token;
        pathToLink[1] = LINK;

        pathToWeth[0] = _token;
        pathToWeth[1] = WETH;

        // Swap half of the stable coin for LINK
        if (_getUniswapPrice(_token, LINK, half) > _getSushiswapPrice(half, pathToLink)) {
            // Use Uniswap to swap to LINK
            IERC20(_token).safeIncreaseAllowance(address(uniswapv3), half);
            linkAmount = _uniswapSwap(_token, LINK, msg.sender, half);
        } else {
            // Use SushiSwap to swap to LINK
            IERC20(_token).safeIncreaseAllowance(address(sushiswap), half);
            linkAmount = _sushiswapSwap(half, 0, pathToLink, msg.sender, block.timestamp + 600);
        }

        // Swap the other half of the stable coin for WETH
        uint256 remaining = _amount - half;

        if (_getUniswapPrice(_token, WETH, remaining) > _getSushiswapPrice(remaining, pathToWeth)) {
            // Use Uniswap to swap to WETH
            IERC20(_token).safeIncreaseAllowance(address(uniswapv3), remaining);
            wethAmount = _uniswapSwap(_token, WETH, msg.sender, remaining);
        } else {
            // Use SushiSwap to swap to WETH
            IERC20(_token).safeIncreaseAllowance(address(sushiswap), remaining);
            wethAmount = _sushiswapSwap(remaining, 0, pathToWeth, msg.sender, block.timestamp + 600);
        }

        emit Deposit(_token, _amount, linkAmount, wethAmount);

        return (linkAmount, wethAmount);
    }

    /**
     * @dev Exchanges LINK or WETH token back to stable coin using either UniswapV3 or SushiSwap depending on which exchange gives a better rate
     * @param _amount - the amount of LINK or WETH the user is exchanging for
     * @param _tokenIn - either LINK or WETH address to exchange for stable coin
     * @param _tokenOut - the desired stable coin to receive in exchange (must be USDC or DAI)
     * @return amountOut - the amount of stable coin received after executing the exchange
     */
    function withdraw(uint256 _amount, address _tokenIn, address _tokenOut) external returns (uint256 amountOut) {
        if (_tokenIn != LINK && _tokenIn != WETH) {
            revert TokenFundV3__InvalidToken_Only_LINK_or_WETH_Allowed();
        }
        if (_tokenOut != USDC && _tokenOut != DAI) {
            revert TokenFundV3__InvalidToken_Only_USDC_or_DAI_Allowed();
        }

        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amount);

        address[] memory path = new address[](2);

        path[0] = _tokenIn;
        path[1] = _tokenOut;

        if (_getUniswapPrice(_tokenIn, _tokenOut, _amount) > _getSushiswapPrice(_amount, path)) {
            // Use Uniswap to swap to stable coin
            IERC20(_tokenIn).safeIncreaseAllowance(address(uniswapv3), _amount);
            amountOut = _uniswapSwap(_tokenIn, _tokenOut, msg.sender, _amount);
        } else {
            // Use SushiSwap to swap to stable coin
            IERC20(_tokenIn).safeIncreaseAllowance(address(sushiswap), _amount);
            amountOut = _sushiswapSwap(_amount, 0, path, msg.sender, block.timestamp + 600);
        }

        emit Withdraw(_tokenIn, _tokenOut, _amount, amountOut);

        return amountOut;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    /**
     * @dev Internal function to get the amount of token out for a swap on UniswapV3
     * @param _tokenIn - the address of the token to exchange
     * @param _tokenOut - the address of the token to receive from exchange
     * @param _amountIn - the amount of _tokenIn being swapped
     * @return the amount of _tokenOut received after executing the exchange
     */
    function _getUniswapPrice(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        return uniswapQuoter.quoteExactInputSingle(_tokenIn, _tokenOut, 3000, _amountIn, 0);
    }

    /**
     * @dev Internal function to execute the exchange of one token for another on UniswapV3
     * @param _tokenIn - the address of the token to exchange
     * @param _tokenOut - the address of the token to receive from exchange
     * @param _recipient - recipient of the exchanged tokens
     * @param _amountIn - the amount of _tokenIn being swapped
     * @return - the amount of _tokenOut recieved after executing the exchange
     */
    function _uniswapSwap(address _tokenIn, address _tokenOut, address _recipient, uint256 _amountIn)
        internal
        returns (uint256)
    {
        return uniswapv3.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: 3000,
                recipient: _recipient,
                deadline: block.timestamp + 600,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /**
     * @dev Internal function to get the amount of token out for a swap on SushiSwap
     * @param _amount - the exact amount of input tokens to be spent
     * @param _path - array of token addresses. The swap is executed along this path. (index 0 = tokenIn, index 1 = tokenOut)
     * @return the amount of token out received after executing the exchange
     */
    function _getSushiswapPrice(uint256 _amount, address[] memory _path) internal view returns (uint256) {
        return sushiswap.getAmountsOut(_amount, _path)[1];
    }

    /**
     * @dev Internal function to execute the exchange of one token for another on SushiSwap
     * @param _amountIn - the exact amount of input tokens to be spent
     * @param _amountOutMin - the minimum amount of output tokens to be received. This can be used to prevent the transaction if slippage is too high.
     * @param _path - array of token addresses. The swap is executed along this path. (index 0 = tokenIn, index 1 = tokenOut)
     * @param _to - the address that will receive the output tokens
     * @param _deadline - timestamp after which the transaction will revert
     * @return - the amount of token out recieved after executing the exchange
     */
    function _sushiswapSwap(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal returns (uint256) {
        return sushiswap.swapExactTokensForTokens(_amountIn, _amountOutMin, _path, _to, _deadline)[1];
    }
}
