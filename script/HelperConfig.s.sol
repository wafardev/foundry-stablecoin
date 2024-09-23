// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethPriceFeed;
        address wbtcPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    MockV3Aggregator public wethV3aggregator;
    MockV3Aggregator public wbtcV3aggregator;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint8 public constant DECIMALS = 18;
    int256 public constant ETH_PRICE = 3000e18;
    int256 public constant BTC_PRICE = 60000e18;

    uint256 public constant ANVIL_DEFAULT_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeConfig;

    uint256 constant SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeConfig = getSepoliaNetworkConfig();
        } else {
            activeConfig = getOrCreateAnvilNetworkConfig();
        }
    }

    function getSepoliaNetworkConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wethPriceFeed: address(0),
            wbtcPriceFeed: address(0),
            weth: address(0),
            wbtc: address(0),
            deployerKey: 0
        });
    }

    function getOrCreateAnvilNetworkConfig() internal returns (NetworkConfig memory) {
        if (activeConfig.wethPriceFeed != address(0)) {
            return activeConfig;
        }
        vm.startBroadcast();
        wethV3aggregator = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        wbtcV3aggregator = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        weth = new ERC20Mock("Wrapped Ether", "WETH", 1000e18);
        wbtc = new ERC20Mock("Wrapped Bitcoin", "WBTC", 1000e18);
        vm.stopBroadcast();

        return NetworkConfig({
            wethPriceFeed: address(wethV3aggregator),
            wbtcPriceFeed: address(wbtcV3aggregator),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: ANVIL_DEFAULT_PRIVATE_KEY
        });
    }
}
