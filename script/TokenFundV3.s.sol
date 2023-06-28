// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {TokenFundV3} from "../src/TokenFundV3.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * To run deploy script, you will need an account PRIVATE_KEY, GOERLI_RPC_URL, and ETHERSCAN_API_KEY set as an environment variable
 * command: forge script script/TokenFundV3.s.sol:TokenFundV3DeployScript --rpc-url $GOERLI_RPC_URL --broadcast --verify -vvvv
 */

contract TokenFundV3DeployScript is Script {
    // Goerli token addresses (note: not official DAI and WETH addresses)
    address private constant USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address private constant DAI = 0x73967c6a0904aA032C103b4104747E88c566B1A2;
    address private constant LINK = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address private constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    // Goerli exchanges
    IQuoter private constant UNISWAPV3_QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter private constant UNISWAPV3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router02 private constant SUSHISWAP = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    TokenFundV3 public tokenFundV3;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        tokenFundV3 = new TokenFundV3(
            USDC,
            DAI,
            LINK,
            WETH,
            UNISWAPV3_QUOTER,
            UNISWAPV3,
            SUSHISWAP
        );

        vm.stopBroadcast();
    }
}
