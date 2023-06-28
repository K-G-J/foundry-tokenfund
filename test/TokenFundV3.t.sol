// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TokenFundV3} from "../src/TokenFundV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * To run tests, you will need a MAINNET_RPC_URL set as an environment variable
 * command: forge test --match-contract TokenFundTestV3
 */

contract TokenFundV3Test is Test {
    /* ========== STATE VARIABLES ========== */

    // Mainnet token addresses
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Mainnet exchanges
    IQuoter private constant uniswapQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter private constant uniswapv3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router02 private constant sushiswap = IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // Address paths used for calculating SushiSwap swaps
    address[] daiPathToLink = [DAI, LINK];
    address[] daiPathToWeth = [DAI, WETH];
    address[] linkPathToDai = [LINK, DAI];
    address[] wethPathToDai = [WETH, DAI];
    address[] usdcPathToLink = [USDC, LINK];
    address[] usdcPathToWeth = [USDC, WETH];
    address[] linkPathToUsdc = [LINK, USDC];
    address[] wethPathToUsdc = [WETH, USDC];

    TokenFundV3 public tokenFundV3;
    uint256 public depositAmount = 1 ether;

    /* ========== EVENTS ========== */
    event Deposit(address indexed token, uint256 amountIn, uint256 linkAmountOut, uint256 wethAmountOut);
    event Withdraw(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        tokenFundV3 = new TokenFundV3(
            USDC,
            DAI,
            LINK,
            WETH,
            uniswapQuoter,
            uniswapv3,
            sushiswap
        );

        vm.label(address(tokenFundV3), "Token Fund V3");
        vm.label(address(uniswapv3), "UniswapV3 Router");
        vm.label(address(sushiswap), "SushiSwap Router");
        vm.label(address(this), "Test User");
        vm.label(USDC, "USDC");
        vm.label(DAI, "DAI");
        vm.label(LINK, "LINK");
        vm.label(WETH, "WETH");

        deal(DAI, address(this), 1 ether);
        deal(USDC, address(this), 1 ether);
    }

    /* ========== HELPER FUNCTIONS ========== */

    function getUniswapPrice(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        return uniswapQuoter.quoteExactInputSingle(_tokenIn, _tokenOut, 3000, _amountIn, 0);
    }

    function getSushiSwapPrice(uint256 _depositAmount, address[] memory _path) internal view returns (uint256) {
        return sushiswap.getAmountsOut(_depositAmount, _path)[1];
    }

    /* ========== deposit ========== */
    function test__depositInvalidTokenReverts() public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);

        vm.expectRevert(TokenFundV3.TokenFundV3__InvalidToken_Only_USDC_or_DAI_Allowed.selector);
        tokenFundV3.deposit(depositAmount, address(0x123));
    }

    function test__depositDai() public {
        uint256 half = depositAmount / 2;
        uint256 remaining = depositAmount - half;

        IERC20(DAI).approve(address(tokenFundV3), depositAmount);

        uint256 uniswapLinkAmount = getUniswapPrice(DAI, LINK, half);
        uint256 sushiswapLinkAmount = getSushiSwapPrice(half, daiPathToLink);
        uint256 uniswapWethAmount = getUniswapPrice(DAI, WETH, remaining);
        uint256 sushiswapWethAmount = getSushiSwapPrice(half, daiPathToWeth);

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);

        (uint256 linkAmount, uint256 wethAmount) = tokenFundV3.deposit(depositAmount, DAI);

        if (uniswapLinkAmount > sushiswapLinkAmount) {
            assertEq(linkAmount, uniswapLinkAmount);
            assertEq(IERC20(LINK).balanceOf(address(this)), uniswapLinkAmount);
        } else {
            assertEq(linkAmount, sushiswapLinkAmount);
            assertEq(IERC20(LINK).balanceOf(address(this)), sushiswapLinkAmount);
        }

        if (uniswapWethAmount > sushiswapWethAmount) {
            assertEq(wethAmount, uniswapWethAmount);
            assertEq(IERC20(WETH).balanceOf(address(this)), uniswapWethAmount);
        } else {
            assertEq(wethAmount, sushiswapWethAmount);
            assertEq(IERC20(WETH).balanceOf(address(this)), sushiswapWethAmount);
        }

        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
    }

    function test__depositUsdc() public {
        uint256 half = depositAmount / 2;
        uint256 remaining = depositAmount - half;

        IERC20(USDC).approve(address(tokenFundV3), depositAmount);

        uint256 uniswapLinkAmount = getUniswapPrice(USDC, LINK, half);
        uint256 sushiswapLinkAmount = getSushiSwapPrice(half, usdcPathToLink);
        uint256 uniswapWethAmount = getUniswapPrice(USDC, WETH, remaining);
        uint256 sushiswapWethAmount = getSushiSwapPrice(remaining, usdcPathToWeth);

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);

        (uint256 linkAmount, uint256 wethAmount) = tokenFundV3.deposit(depositAmount, USDC);

        if (uniswapLinkAmount > sushiswapLinkAmount) {
            assertEq(linkAmount, uniswapLinkAmount);
            assertEq(IERC20(LINK).balanceOf(address(this)), uniswapLinkAmount);
        } else {
            assertEq(linkAmount, sushiswapLinkAmount);
            assertEq(IERC20(LINK).balanceOf(address(this)), sushiswapLinkAmount);
        }

        if (uniswapWethAmount > sushiswapWethAmount) {
            assertEq(wethAmount, uniswapWethAmount);
            assertEq(IERC20(WETH).balanceOf(address(this)), uniswapWethAmount);
        } else {
            assertEq(wethAmount, sushiswapWethAmount);
            assertEq(IERC20(WETH).balanceOf(address(this)), sushiswapWethAmount);
        }

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
    }

    function test__depositEvent() public {
        uint256 half = depositAmount / 2;
        uint256 remaining = depositAmount - half;

        uint256 daiTolinkAmount;
        uint256 daiToWethAmount;
        uint256 usdcTolinkAmount;
        uint256 usdcToWethAmount;

        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        IERC20(USDC).approve(address(tokenFundV3), depositAmount);

        uint256 uniswapDaiLinkAmount = getUniswapPrice(DAI, LINK, half);
        uint256 sushiswapDaiLinkAmount = getSushiSwapPrice(half, daiPathToLink);
        uint256 uniswapDaiWethAmount = getUniswapPrice(DAI, WETH, remaining);
        uint256 sushiswapDaiWethAmount = getSushiSwapPrice(remaining, daiPathToWeth);

        if (uniswapDaiLinkAmount > sushiswapDaiLinkAmount) {
            daiTolinkAmount = uniswapDaiLinkAmount;
        } else {
            daiTolinkAmount = sushiswapDaiLinkAmount;
        }

        if (uniswapDaiWethAmount > sushiswapDaiWethAmount) {
            daiToWethAmount = uniswapDaiWethAmount;
        } else {
            daiToWethAmount = sushiswapDaiWethAmount;
        }

        uint256 uniswapUsdcLinkAmount = getUniswapPrice(USDC, LINK, half);
        uint256 sushiswapUsdcLinkAmount = getSushiSwapPrice(half, usdcPathToLink);
        uint256 uniswapUsdcWethAmount = getUniswapPrice(USDC, WETH, remaining);
        uint256 sushiswapUsdcWethAmount = getSushiSwapPrice(remaining, usdcPathToWeth);

        if (uniswapUsdcLinkAmount > sushiswapUsdcLinkAmount) {
            usdcTolinkAmount = uniswapUsdcLinkAmount;
        } else {
            usdcTolinkAmount = sushiswapUsdcLinkAmount;
        }

        if (uniswapUsdcWethAmount > sushiswapUsdcWethAmount) {
            usdcToWethAmount = uniswapUsdcWethAmount;
        } else {
            usdcToWethAmount = sushiswapUsdcWethAmount;
        }

        vm.expectEmit(true, false, false, true, address(tokenFundV3));
        emit Deposit(DAI, depositAmount, daiTolinkAmount, daiToWethAmount);
        (daiTolinkAmount, daiToWethAmount) = tokenFundV3.deposit(depositAmount, DAI);

        vm.expectEmit(true, false, false, true, address(tokenFundV3));
        emit Deposit(USDC, depositAmount, usdcTolinkAmount, usdcToWethAmount);
        (usdcTolinkAmount, usdcToWethAmount) = tokenFundV3.deposit(depositAmount, USDC);
    }

    /* ========== withdraw ========== */
    function test__withdrawInvalidTokenInReverts() public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        (uint256 linkAmount,) = tokenFundV3.deposit(depositAmount, DAI);

        IERC20(LINK).approve(address(tokenFundV3), linkAmount);
        vm.expectRevert(TokenFundV3.TokenFundV3__InvalidToken_Only_LINK_or_WETH_Allowed.selector);
        tokenFundV3.withdraw(linkAmount, address(0x123), DAI);
    }

    function test__withdrawInvalidTokenOutReverts() public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        (uint256 linkAmount,) = tokenFundV3.deposit(depositAmount, DAI);

        IERC20(LINK).approve(address(tokenFundV3), linkAmount);
        vm.expectRevert(TokenFundV3.TokenFundV3__InvalidToken_Only_USDC_or_DAI_Allowed.selector);
        tokenFundV3.withdraw(linkAmount, LINK, address(0x123));
    }

    function test__withdrawLinkDai() public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        (uint256 linkAmount,) = tokenFundV3.deposit(depositAmount, DAI);

        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
        assertEq(IERC20(LINK).balanceOf(address(this)), linkAmount);

        uint256 uniswapDaiAmount = getUniswapPrice(LINK, DAI, linkAmount);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(linkAmount, linkPathToDai);

        IERC20(LINK).approve(address(tokenFundV3), linkAmount);
        uint256 daiAmount = tokenFundV3.withdraw(linkAmount, LINK, DAI);

        if (uniswapDaiAmount > sushiswapDaiAmount) {
            assertEq(daiAmount, uniswapDaiAmount);
            assertEq(IERC20(DAI).balanceOf(address(this)), uniswapDaiAmount);
        } else {
            assertEq(daiAmount, sushiswapDaiAmount);
            assertEq(IERC20(DAI).balanceOf(address(this)), sushiswapDaiAmount);
        }

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
    }

    function test__withdrawWethDai() public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        (, uint256 wethAmount) = tokenFundV3.deposit(depositAmount, DAI);

        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), wethAmount);

        uint256 uniswapDaiAmount = getUniswapPrice(WETH, DAI, wethAmount);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(wethAmount, wethPathToDai);

        IERC20(WETH).approve(address(tokenFundV3), wethAmount);
        uint256 daiAmount = tokenFundV3.withdraw(wethAmount, WETH, DAI);

        if (uniswapDaiAmount > sushiswapDaiAmount) {
            assertEq(daiAmount, uniswapDaiAmount);
            assertEq(IERC20(DAI).balanceOf(address(this)), uniswapDaiAmount);
        } else {
            assertEq(daiAmount, sushiswapDaiAmount);
            assertEq(IERC20(DAI).balanceOf(address(this)), sushiswapDaiAmount);
        }

        assertEq(IERC20(WETH).balanceOf(address(this)), 0);
    }

    function test__withdrawLinkUsdc() public {
        IERC20(USDC).approve(address(tokenFundV3), depositAmount);
        (uint256 linkAmount,) = tokenFundV3.deposit(depositAmount, USDC);

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertEq(IERC20(LINK).balanceOf(address(this)), linkAmount);

        uint256 uniswapUsdcAmount = getUniswapPrice(LINK, USDC, linkAmount);
        uint256 sushiswapUsdcAmount = getSushiSwapPrice(linkAmount, linkPathToUsdc);

        IERC20(LINK).approve(address(tokenFundV3), linkAmount);
        uint256 usdcAmount = tokenFundV3.withdraw(linkAmount, LINK, USDC);

        if (uniswapUsdcAmount > sushiswapUsdcAmount) {
            assertEq(usdcAmount, uniswapUsdcAmount);
            assertEq(IERC20(USDC).balanceOf(address(this)), uniswapUsdcAmount);
        } else {
            assertEq(usdcAmount, sushiswapUsdcAmount);
            assertEq(IERC20(USDC).balanceOf(address(this)), sushiswapUsdcAmount);
        }

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
    }

    function test__withdrawWethUsdc() public {
        IERC20(USDC).approve(address(tokenFundV3), depositAmount);
        (, uint256 wethAmount) = tokenFundV3.deposit(depositAmount, USDC);

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), wethAmount);

        uint256 uniswapUsdcAmount = getUniswapPrice(WETH, USDC, wethAmount);
        uint256 sushiswapUsdcAmount = getSushiSwapPrice(wethAmount, wethPathToUsdc);

        IERC20(WETH).approve(address(tokenFundV3), wethAmount);
        uint256 usdcAmount = tokenFundV3.withdraw(wethAmount, WETH, USDC);

        if (uniswapUsdcAmount > sushiswapUsdcAmount) {
            assertEq(usdcAmount, uniswapUsdcAmount);
            assertEq(IERC20(USDC).balanceOf(address(this)), uniswapUsdcAmount);
        } else {
            assertEq(usdcAmount, sushiswapUsdcAmount);
            assertEq(IERC20(USDC).balanceOf(address(this)), sushiswapUsdcAmount);
        }

        assertEq(IERC20(WETH).balanceOf(address(this)), 0);
    }

    function test__withdrawEvent() public {
        uint256 daiAmount;
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        (uint256 linkAmount,) = tokenFundV3.deposit(depositAmount, DAI);

        uint256 uniswapDaiAmount = getUniswapPrice(LINK, DAI, linkAmount);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(linkAmount, linkPathToDai);

        if (uniswapDaiAmount > sushiswapDaiAmount) {
            daiAmount = uniswapDaiAmount;
        } else {
            daiAmount = sushiswapDaiAmount;
        }

        IERC20(LINK).approve(address(tokenFundV3), linkAmount);
        vm.expectEmit(true, true, false, true, address(tokenFundV3));
        emit Withdraw(LINK, DAI, linkAmount, daiAmount);
        tokenFundV3.withdraw(linkAmount, LINK, DAI);
    }

    /* ========== FUZZ TESTS ========== */

    function test__fuzz__depositDai(uint256 _depositAmount) public {
        vm.assume(_depositAmount > IERC20(DAI).balanceOf(address(this)));
        IERC20(DAI).approve(address(tokenFundV3), _depositAmount);
        vm.expectRevert("Dai/insufficient-balance");
        tokenFundV3.deposit(_depositAmount, DAI);
    }

    function test__fuzz__depositUsdc(uint256 _depositAmount) public {
        vm.assume(_depositAmount > IERC20(USDC).balanceOf(address(this)));
        IERC20(USDC).approve(address(tokenFundV3), _depositAmount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenFundV3.deposit(_depositAmount, USDC);
    }

    function test__fuzz__withdrawLinkDai(uint256 amount) public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        tokenFundV3.deposit(depositAmount, DAI);

        vm.assume(amount > IERC20(LINK).balanceOf(address(this)));

        IERC20(LINK).approve(address(tokenFundV3), amount);
        vm.expectRevert();
        tokenFundV3.withdraw(amount, LINK, DAI);
    }

    function test__fuzz__withdrawWethDai(uint256 amount) public {
        IERC20(DAI).approve(address(tokenFundV3), depositAmount);
        tokenFundV3.deposit(depositAmount, DAI);

        vm.assume(amount > IERC20(WETH).balanceOf(address(this)));

        IERC20(WETH).approve(address(tokenFundV3), amount);
        vm.expectRevert();
        tokenFundV3.withdraw(amount, WETH, DAI);
    }

    function test__fuzz__withdrawLinkUsdc(uint256 amount) public {
        IERC20(USDC).approve(address(tokenFundV3), depositAmount);
        tokenFundV3.deposit(depositAmount, USDC);

        vm.assume(amount > IERC20(LINK).balanceOf(address(this)));

        IERC20(LINK).approve(address(tokenFundV3), amount);
        vm.expectRevert();
        tokenFundV3.withdraw(amount, LINK, USDC);
    }

    function test__fuzz__withdrawWethUsdc(uint256 amount) public {
        IERC20(USDC).approve(address(tokenFundV3), depositAmount);
        tokenFundV3.deposit(depositAmount, USDC);

        vm.assume(amount > IERC20(WETH).balanceOf(address(this)));

        IERC20(WETH).approve(address(tokenFundV3), amount);
        vm.expectRevert();
        tokenFundV3.withdraw(amount, WETH, USDC);
    }
}
