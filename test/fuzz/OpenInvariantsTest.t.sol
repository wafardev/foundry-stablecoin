// SPDX-License-Identifier: MIT

/*pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployDSC;
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address weth;
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;

    function setUp() external {
        deployDSC = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployDSC.run();
        console.log(address(dscEngine));

        (,, weth, wbtc,) = helperConfig.activeConfig();

        targetContract(address(dscEngine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsc));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsc));
        uint256 dscTotalSupply = dsc.totalSupply();

        uint256 totalWethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(totalWethValue + totalWbtcValue >= dscTotalSupply);
    }
}*/
