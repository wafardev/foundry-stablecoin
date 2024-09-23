// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function deployDSCConfig() public returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethPriceFeed, address wbtcPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin dsc = new DecentralizedStablecoin();
        vm.stopBroadcast();

        return deployDSC(tokenAddresses, priceFeedAddresses, dsc, helperConfig);
    }

    function deployDSC(
        address[] memory tokenArray,
        address[] memory priceFeedArray,
        DecentralizedStablecoin dscToken,
        HelperConfig helperConfig
    ) public returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        (,,,, uint256 deployerKey) = helperConfig.activeConfig();
        vm.startBroadcast(deployerKey);
        DSCEngine dscEngine = new DSCEngine(tokenArray, priceFeedArray, address(dscToken));

        dscToken.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dscToken, dscEngine, helperConfig);
    }

    function run() external returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        return deployDSCConfig();
    }
}
