// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStablecoin dsc;
    address weth;
    address wbtc;

    uint256 private constant LIQUIDATION_THRESHOLD = 66;
    uint256 private constant LIQUIDATION_FEE_PRECISION = 100;
    uint96 constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStablecoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory whitelistedTokens = dscEngine.getAllWhitelistedTokens();
        weth = whitelistedTokens[0];
        wbtc = whitelistedTokens[1];
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) external {
        ERC20Mock collateralToken = ERC20Mock(_getCollateralAddressFromSeed(collateralSeed));
        uint256 amountToDeposit = bound(amount, 1, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountToDeposit);
        collateralToken.approve(address(dscEngine), type(uint256).max);
        dscEngine.depositCollateral(address(collateralToken), amountToDeposit);
        vm.stopPrank();
    }

    /*function redeemCollateral(uint256 collateralSeed, uint256 redeemedAmount) external {
        address collateralToken = _getCollateralAddressFromSeed(collateralSeed);
        uint256 maxCollateralAmount = dscEngine.getAccountCollateralValuePerToken(msg.sender, collateralToken);
        if (maxCollateralAmount == 0) {
            return;
        }
        redeemedAmount = bound(redeemedAmount, 1, MAX_DEPOSIT_AMOUNT);
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateralToken), redeemedAmount);
    }*/

    function mintDsc(uint256 amountToMint) external {
        //amount = bound(amount, 1, MAX_DEPOSIT_AMOUNT);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(msg.sender);

        uint256 maxMintableAmount = ((LIQUIDATION_THRESHOLD * collateralValueInUsd) / LIQUIDATION_FEE_PRECISION);

        int256 onlyPossibleMint = int256(maxMintableAmount) - int256(totalDscMinted);

        if (onlyPossibleMint <= 0) {
            return;
        }

        amountToMint = bound(amountToMint, 1, uint256(onlyPossibleMint));
        vm.prank(msg.sender);

        dscEngine.mintDsc(amountToMint);
    }

    function _getCollateralAddressFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) return weth;
        return wbtc;
    }
}
