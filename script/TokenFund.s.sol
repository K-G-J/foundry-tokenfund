// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {TokenFund} from "../src/TokenFund.sol";

/**
 * To run deploy script, you will need an account PRIVATE_KEY, GOERLI_RPC_URL, and ETHERSCAN_API_KEY set as an environment variable
 * command: forge script script/TokenFund.s.sol:TokenFundDeployScript --rpc-url $GOERLI_RPC_URL --broadcast --verify -vvvv
 */

contract TokenFundDeployScript is Script {
    // Goerli token addresses (note: not official DAI and WETH addresses)
    address private constant USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address private constant DAI = 0x73967c6a0904aA032C103b4104747E88c566B1A2;
    address private constant LINK = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address private constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    // Goerli exchanges
    address private constant UNISWAP =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHISWAP =
        0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    TokenFund public tokenFund;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        tokenFund = new TokenFund(USDC, DAI, LINK, WETH, UNISWAP, SUSHISWAP);

        vm.stopBroadcast();
    }
}
