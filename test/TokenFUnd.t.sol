// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {TokenFund} from "../src/TokenFund.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * To run tests, you will need a MAINNET_RPC_URL set as an environment variable
 * command: forge test --match-contract TokenFundTest
 */

contract TokenFundTest is Test {
    /* ========== STATE VARIABLES ========== */

    // Mainnet token addresses
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Mainnet exchanges
    IUniswapV2Router02 private constant uniswapv2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2Router02 private constant sushiswap = IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // Address paths used for calculating swaps
    address[] daiPathToLink = [DAI, LINK];
    address[] daiPathToWeth = [DAI, WETH];
    address[] linkPathToDai = [LINK, DAI];
    address[] wethPathToDai = [WETH, DAI];
    address[] usdcPathToLink = [USDC, LINK];
    address[] usdcPathToWeth = [USDC, WETH];
    address[] linkPathToUsdc = [LINK, USDC];
    address[] wethPathToUsdc = [WETH, USDC];

    TokenFund public tokenFund;
    uint256 public depositAmount = 1 ether;

    /* ========== EVENTS ========== */
    event Deposit(address indexed token, uint256 amountIn, uint256 linkAmountOut, uint256 wethAmountOut);
    event Withdraw(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        tokenFund = new TokenFund(
            USDC,
            DAI,
            LINK,
            WETH,
            address(uniswapv2),
            address(sushiswap)
        );

        vm.label(address(tokenFund), "Token Fund");
        vm.label(address(uniswapv2), "UniswapV2 Router");
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

    function getUniswapPrice(uint256 _depositAmount, address[] memory _path) internal view returns (uint256) {
        return uniswapv2.getAmountsOut(_depositAmount, _path)[1];
    }

    function getSushiSwapPrice(uint256 _depositAmount, address[] memory _path) internal view returns (uint256) {
        return sushiswap.getAmountsOut(_depositAmount, _path)[1];
    }

    /* ========== deposit ========== */
    function test__depositInvalidTokenReverts() public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);

        vm.expectRevert(TokenFund.TokenFund_Invalid_Token_Only_USDC_or_DAI_Allowed.selector);
        tokenFund.deposit(depositAmount, address(0x123));
    }

    function test__depositDai() public {
        uint256 half = depositAmount / 2;
        uint256 remaining = depositAmount - half;

        IERC20(DAI).approve(address(tokenFund), depositAmount);

        uint256 uniswapLinkAmount = getUniswapPrice(half, daiPathToLink);
        uint256 sushiswapLinkAmount = getSushiSwapPrice(half, daiPathToLink);
        uint256 uniswapWethAmount = getUniswapPrice(remaining, daiPathToWeth);
        uint256 sushiswapWethAmount = getSushiSwapPrice(remaining, daiPathToWeth);

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);

        (uint256 linkAmount, uint256 wethAmount) = tokenFund.deposit(depositAmount, DAI);

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
        IERC20(USDC).approve(address(tokenFund), depositAmount);

        uint256 uniswapLinkAmount = getUniswapPrice(half, usdcPathToLink);
        uint256 sushiswapLinkAmount = getSushiSwapPrice(half, usdcPathToLink);
        uint256 uniswapWethAmount = getUniswapPrice(remaining, usdcPathToWeth);
        uint256 sushiswapWethAmount = getSushiSwapPrice(remaining, usdcPathToWeth);

        assertEq(IERC20(LINK).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), 0);

        (uint256 linkAmount, uint256 wethAmount) = tokenFund.deposit(depositAmount, USDC);

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

        IERC20(DAI).approve(address(tokenFund), depositAmount);
        IERC20(USDC).approve(address(tokenFund), depositAmount);

        uint256 uniswapDaiLinkAmount = getUniswapPrice(half, daiPathToLink);
        uint256 sushiswapDaiLinkAmount = getSushiSwapPrice(half, daiPathToLink);
        uint256 uniswapDaiWethAmount = getUniswapPrice(remaining, daiPathToWeth);
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

        uint256 uniswapUsdcLinkAmount = getUniswapPrice(half, usdcPathToLink);
        uint256 sushiswapUsdcLinkAmount = getSushiSwapPrice(half, usdcPathToLink);
        uint256 uniswapUsdcWethAmount = getUniswapPrice(remaining, usdcPathToWeth);
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

        vm.expectEmit(true, false, false, true, address(tokenFund));
        emit Deposit(DAI, depositAmount, daiTolinkAmount, daiToWethAmount);
        (daiTolinkAmount, daiToWethAmount) = tokenFund.deposit(depositAmount, DAI);

        vm.expectEmit(true, false, false, true, address(tokenFund));
        emit Deposit(USDC, depositAmount, usdcTolinkAmount, usdcToWethAmount);
        (usdcTolinkAmount, usdcToWethAmount) = tokenFund.deposit(depositAmount, USDC);
    }

    /* ========== withdraw ========== */
    function test__withdrawInvalidTokenInReverts() public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        (uint256 linkAmount,) = tokenFund.deposit(depositAmount, DAI);

        IERC20(LINK).approve(address(tokenFund), linkAmount);
        vm.expectRevert(TokenFund.TokenFund_Invalid_Token_Only_LINK_or_WETH_Allowed.selector);
        tokenFund.withdraw(linkAmount, address(0x123), DAI);
    }

    function test__withdrawInvalidTokenOutReverts() public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        (uint256 linkAmount,) = tokenFund.deposit(depositAmount, DAI);

        IERC20(LINK).approve(address(tokenFund), linkAmount);
        vm.expectRevert(TokenFund.TokenFund_Invalid_Token_Only_USDC_or_DAI_Allowed.selector);
        tokenFund.withdraw(linkAmount, LINK, address(0x123));
    }

    function test__withdrawLinkDai() public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        (uint256 linkAmount,) = tokenFund.deposit(depositAmount, DAI);

        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
        assertEq(IERC20(LINK).balanceOf(address(this)), linkAmount);

        uint256 uniswapDaiAmount = getUniswapPrice(linkAmount, linkPathToDai);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(linkAmount, linkPathToDai);

        IERC20(LINK).approve(address(tokenFund), linkAmount);
        uint256 daiAmount = tokenFund.withdraw(linkAmount, LINK, DAI);

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
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        (, uint256 wethAmount) = tokenFund.deposit(depositAmount, DAI);

        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), wethAmount);

        uint256 uniswapDaiAmount = getUniswapPrice(wethAmount, wethPathToDai);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(wethAmount, wethPathToDai);

        IERC20(WETH).approve(address(tokenFund), wethAmount);
        uint256 daiAmount = tokenFund.withdraw(wethAmount, WETH, DAI);

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
        IERC20(USDC).approve(address(tokenFund), depositAmount);
        (uint256 linkAmount,) = tokenFund.deposit(depositAmount, USDC);

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertEq(IERC20(LINK).balanceOf(address(this)), linkAmount);

        uint256 uniswapUsdcAmount = getUniswapPrice(linkAmount, linkPathToUsdc);
        uint256 sushiswapUsdcAmount = getSushiSwapPrice(linkAmount, linkPathToUsdc);

        IERC20(LINK).approve(address(tokenFund), linkAmount);
        uint256 usdcAmount = tokenFund.withdraw(linkAmount, LINK, USDC);

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
        IERC20(USDC).approve(address(tokenFund), depositAmount);
        (, uint256 wethAmount) = tokenFund.deposit(depositAmount, USDC);

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), wethAmount);

        uint256 uniswapUsdcAmount = getUniswapPrice(wethAmount, wethPathToUsdc);
        uint256 sushiswapUsdcAmount = getSushiSwapPrice(wethAmount, wethPathToUsdc);

        IERC20(WETH).approve(address(tokenFund), wethAmount);
        uint256 usdcAmount = tokenFund.withdraw(wethAmount, WETH, USDC);

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
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        (uint256 linkAmount,) = tokenFund.deposit(depositAmount, DAI);

        uint256 uniswapDaiAmount = getUniswapPrice(linkAmount, linkPathToDai);
        uint256 sushiswapDaiAmount = getSushiSwapPrice(linkAmount, linkPathToDai);

        if (uniswapDaiAmount > sushiswapDaiAmount) {
            daiAmount = uniswapDaiAmount;
        } else {
            daiAmount = sushiswapDaiAmount;
        }

        IERC20(LINK).approve(address(tokenFund), linkAmount);
        vm.expectEmit(true, true, false, true, address(tokenFund));
        emit Withdraw(LINK, DAI, linkAmount, daiAmount);
        tokenFund.withdraw(linkAmount, LINK, DAI);
    }

    /* ========== FUZZ TESTS ========== */

    function test__fuzz__depositDai(uint256 _depositAmount) public {
        vm.assume(_depositAmount > IERC20(DAI).balanceOf(address(this)));
        IERC20(DAI).approve(address(tokenFund), _depositAmount);
        vm.expectRevert("Dai/insufficient-balance");
        tokenFund.deposit(_depositAmount, DAI);
    }

    function test__fuzz__depositUsdc(uint256 _depositAmount) public {
        vm.assume(_depositAmount > IERC20(USDC).balanceOf(address(this)));
        IERC20(USDC).approve(address(tokenFund), _depositAmount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenFund.deposit(_depositAmount, USDC);
    }

    function test__fuzz__withdrawLinkDai(uint256 amount) public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        tokenFund.deposit(depositAmount, DAI);

        vm.assume(amount > IERC20(LINK).balanceOf(address(this)));

        IERC20(LINK).approve(address(tokenFund), amount);
        vm.expectRevert();
        tokenFund.withdraw(amount, LINK, DAI);
    }

    function test__fuzz__withdrawWethDai(uint256 amount) public {
        IERC20(DAI).approve(address(tokenFund), depositAmount);
        tokenFund.deposit(depositAmount, DAI);

        vm.assume(amount > IERC20(WETH).balanceOf(address(this)));

        IERC20(WETH).approve(address(tokenFund), amount);
        vm.expectRevert();
        tokenFund.withdraw(amount, WETH, DAI);
    }

    function test__fuzz__withdrawLinkUsdc(uint256 amount) public {
        IERC20(USDC).approve(address(tokenFund), depositAmount);
        tokenFund.deposit(depositAmount, USDC);

        vm.assume(amount > IERC20(LINK).balanceOf(address(this)));

        IERC20(LINK).approve(address(tokenFund), amount);
        vm.expectRevert();
        tokenFund.withdraw(amount, LINK, USDC);
    }

    function test__fuzz__withdrawWethUsdc(uint256 amount) public {
        IERC20(USDC).approve(address(tokenFund), depositAmount);
        tokenFund.deposit(depositAmount, USDC);

        vm.assume(amount > IERC20(WETH).balanceOf(address(this)));

        IERC20(WETH).approve(address(tokenFund), amount);
        vm.expectRevert();
        tokenFund.withdraw(amount, WETH, USDC);
    }
}
