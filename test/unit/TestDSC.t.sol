// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";

contract TestDSC is Test {
    DecentralizedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address weth;
    address wethPriceFeed;

    address public USER = makeAddr("USER");
    uint256 constant STARTING_USER_BALANCE = 10 ether;

    modifier dscEnginePrank() {
        vm.prank(address(dscEngine));
        _;
    }

    modifier userPranked() {
        vm.prank(USER);
        _;
    }

    function setUp() external {
        DeployDSC deployDSC = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployDSC.run();

        (wethPriceFeed,, weth,,) = helperConfig.activeConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
    }

    function testCantMintZero() external dscEnginePrank {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__MustBeMoreThanZero.selector);

        dsc.mint(address(1), 0);
    }

    function testCantBurnZero() external dscEnginePrank {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__MustBeMoreThanZero.selector);

        dsc.burn(0);
    }

    function testOnlyOwnerCanBurn() external userPranked {
        vm.expectRevert( /*Ownable.OwnableUnauthorizedAccount.selector*/ );

        dsc.burn(10);
    }

    function testOnlyOwnerCanMint() external {
        vm.expectRevert();

        dsc.mint(msg.sender, 0);
    }
}
