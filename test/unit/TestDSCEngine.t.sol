// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {IERC20Errors} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestDSCEngine is Test {
    DeployDSC private deployDSC;
    DSCEngine private dscEngine;
    DecentralizedStablecoin private dsc;
    HelperConfig private helperConfig;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amountDeposited);
    event CollateralRedeemed(
        address indexed userFrom, address indexed userTo, address indexed token, uint256 amountRedeemed
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    uint8 constant DECIMALS = 18;
    uint256 constant PRECISION = 10 ** DECIMALS;
    uint256 constant MIN_HEALTH_FACTOR = PRECISION;
    uint256 constant LIQUIDATION_THRESHOLD = 66;
    uint256 constant LIQUIDATION_PRECISION = 100;
    uint256 constant LIQUIDATION_BONUS = 10;
    int256 constant WBTC_PRICE = 60000e18;
    int256 constant ETH_PRICE = 3000e18;
    int256 constant DOUBLE_ETH_PRICE = ETH_PRICE * 2;
    int256 constant HALF_ETH_PRICE = ETH_PRICE / 2;
    uint256 constant ANVIL_CHAIN_ID = 31337;

    address[] private realTokens;
    address[] private realPriceFeeds;

    address public DEPOSITOR = makeAddr("DEPOSITOR");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");

    address[] private onlyDepositor = [DEPOSITOR];
    address[] private depositorAndLiquidator = [DEPOSITOR, LIQUIDATOR];

    uint256 constant STARTING_USER_BALANCE = 10 ether;
    uint256 constant TOKENS_TO_DEPOSIT = 0.1 ether;

    modifier userPranked(address user) {
        vm.prank(user);
        _;
    }

    modifier usersDeposited(address[] memory users) {
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            ERC20Mock(weth).approve(address(dscEngine), STARTING_USER_BALANCE);
            dscEngine.depositCollateral(weth, TOKENS_TO_DEPOSIT);
            vm.stopPrank();
        }
        _;
    }

    modifier usersMinted(address[] memory users) {
        for (uint256 i; i < users.length; i++) {
            vm.startPrank(users[i]);
            uint256 maxMintableAmountInDsc = (LIQUIDATION_THRESHOLD * (uint256(ETH_PRICE) / 10)) / LIQUIDATION_PRECISION;
            dscEngine.mintDsc(maxMintableAmountInDsc);
            vm.stopPrank();
        }
        _;
    }

    modifier ethPriceUpdated(int256 newEthPrice) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            return;
        }
        MockV3Aggregator(wethPriceFeed).updateAnswer(newEthPrice);
        _;
    }

    function setUp() external {
        deployDSC = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployDSC.run();

        (wethPriceFeed, wbtcPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeConfig();

        realTokens = [weth, wbtc];
        realPriceFeeds = [wethPriceFeed, wbtcPriceFeed];

        ERC20Mock(weth).mint(DEPOSITOR, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(DEPOSITOR, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(LIQUIDATOR, STARTING_USER_BALANCE);
        vm.deal(DEPOSITOR, STARTING_USER_BALANCE);
        vm.deal(LIQUIDATOR, STARTING_USER_BALANCE);
    }

    /////////////////////////
    //  Constructor Tests ///
    /////////////////////////

    address[] private testTokens;
    address[] private testPriceFeeds;

    function testCantDeployIfTokensAndPriceFeedsNotSameLength() external {
        testTokens.push(address(0));
        vm.expectRevert(DSCEngine.DSCEngine__WhitelistedTokenLengthNotMatchingPriceFeed.selector);
        new DSCEngine(testTokens, testPriceFeeds, address(dsc));
    }

    function testIsNotPriceFeed() external {
        testTokens.push(address(0));
        testPriceFeeds.push(address(0));
        console.log(testTokens.length);
        console.log(testPriceFeeds.length);
        vm.expectRevert(DSCEngine.DSCEngine__IsNotPriceFeed.selector);
        new DSCEngine(testTokens, testPriceFeeds, address(dsc));
    }

    function testMappedPriceFeedCorrectly() external view {
        address priceFeed = dscEngine.getPriceFeed(realTokens[0]);
        address priceFeed2 = dscEngine.getPriceFeed(address(0));
        assert(priceFeed == wethPriceFeed);
        assert(priceFeed2 == address(0));
    }

    function testWhitelistedTokensAreCorrect() external view {
        address[] memory whitelistedTokens = dscEngine.getAllWhitelistedTokens();

        assert(keccak256(abi.encodePacked(whitelistedTokens)) == keccak256(abi.encodePacked(realTokens)));
    }

    /////////////////////////
    //  Pricing Tests     ///
    /////////////////////////

    function testUsdPriceDisplayedCorrectly() external view {
        uint256 amount = 1 ether;

        uint256 usdAmount = dscEngine.getUsdValue(weth, amount);

        uint256 additionalPrecisionDecimals = 18 - DECIMALS;

        uint256 expectedUsdAmount = uint256(ETH_PRICE) * 10 ** additionalPrecisionDecimals;

        assert(usdAmount == expectedUsdAmount);
    }

    function testEthAmountDisplayedCorrectly() external view {
        uint256 dscAmount = 1500 ether;

        uint256 ethAmount = dscEngine.getTokenAmountFromDsc(weth, dscAmount);

        uint256 expectedEthAmount = 0.5 ether;

        assert(ethAmount == expectedEthAmount);
    }

    /////////////////////////
    //  MintDsc Tests     ///
    /////////////////////////

    function testCannotMintZeroTokens() external {
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);
        dscEngine.mintDsc(0);
    }

    ////////////////////////////////////
    //  Deposit Collateral Tests     ///
    ////////////////////////////////////

    function testCannotDepositNotWhitelistedToken() external userPranked(DEPOSITOR) {
        vm.expectRevert(DSCEngine.DSCEngine__IsNotWhitelistedCollateral.selector);

        dscEngine.depositCollateral(address(0), 10);
    }

    function testCannotDepositZeroTokens() external userPranked(DEPOSITOR) {
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);

        dscEngine.depositCollateral(weth, 0);
    }

    function testCantDepositTokensIfNotAllowed() external {
        uint256 randomNumber = 10;
        uint256 approvedNumber = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(dscEngine), approvedNumber, randomNumber
            )
        );
        vm.prank(DEPOSITOR);
        dscEngine.depositCollateral(weth, randomNumber);
    }

    function testCanDepositTokensIfAllowed() external userPranked(DEPOSITOR) {
        ERC20Mock(weth).approve(address(dscEngine), STARTING_USER_BALANCE);
        vm.prank(DEPOSITOR);
        vm.expectEmit(true, true, false, true, address(dscEngine));
        emit CollateralDeposited(DEPOSITOR, weth, TOKENS_TO_DEPOSIT);
        dscEngine.depositCollateral(weth, TOKENS_TO_DEPOSIT);

        console.log(dscEngine.getAccountUsdCollateralValue(DEPOSITOR));

        assert(dscEngine.getAccountUsdCollateralValue(DEPOSITOR) == uint256(ETH_PRICE) / 10);
    }

    /////////////////////////////////////////////
    //  Deposit Collateral and MintDsc Tests  ///
    /////////////////////////////////////////////

    function testCanDepositCollateralAndMintDsc() external userPranked(DEPOSITOR) {
        ERC20Mock(weth).approve(address(dscEngine), STARTING_USER_BALANCE);
        uint256 dscAmountToMint = 100e18;
        vm.expectEmit(true, true, false, true, address(dscEngine));
        emit CollateralDeposited(DEPOSITOR, weth, TOKENS_TO_DEPOSIT);
        vm.expectEmit(true, true, false, true, address(dsc));
        emit Transfer(address(0), DEPOSITOR, dscAmountToMint);
        vm.prank(DEPOSITOR);
        dscEngine.depositCollateralAndMintDsc(weth, TOKENS_TO_DEPOSIT, dscAmountToMint);

        assert(dscEngine.getHealthFactor(DEPOSITOR) > 1);
        assert(dscEngine.getAccountUsdCollateralValue(DEPOSITOR) == uint256(ETH_PRICE) / 10);
    }

    ////////////////////////////////////
    //     Collateral Info Tests     ///
    ////////////////////////////////////

    function testGetUserInfoAfterDeposit() external usersDeposited(onlyDepositor) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(DEPOSITOR);
        uint256 expectedEthAmountDeposited = dscEngine.getTokenAmountFromDsc(address(weth), collateralValueInUsd);

        uint256 expectedTotalDscMinted = 0;

        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(address(weth), TOKENS_TO_DEPOSIT);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(TOKENS_TO_DEPOSIT, expectedEthAmountDeposited);
    }

    ////////////////////////////////////
    //     Health Factor Tests       ///
    ////////////////////////////////////

    function testNullHealthFactor(address user) external {
        uint256 currentUserHealthFactor = dscEngine.getHealthFactor(user);
        assertEq(currentUserHealthFactor, 0);
    }

    function testExtremeHealthFactor() external usersDeposited(onlyDepositor) {
        uint256 currentUserHealthFactor = dscEngine.getHealthFactor(DEPOSITOR);
        assertEq(currentUserHealthFactor, type(uint256).max);
    }

    function testMinimumHealthFactor() external usersDeposited(onlyDepositor) userPranked(DEPOSITOR) {
        uint256 depositedAmount = uint256(ETH_PRICE) / 10;
        uint256 maxMintableAmountInDsc = (LIQUIDATION_THRESHOLD * depositedAmount) / LIQUIDATION_PRECISION;
        dscEngine.mintDsc(maxMintableAmountInDsc);
        uint256 currentUserHealthFactor = dscEngine.getHealthFactor(DEPOSITOR);
        uint256 expectedHealthFactor = MIN_HEALTH_FACTOR;
        assertEq(currentUserHealthFactor, expectedHealthFactor);
    }

    function testBelowMinimumHealthFactorReverts()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        userPranked(DEPOSITOR)
    {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, MIN_HEALTH_FACTOR - 1));
        dscEngine.mintDsc(1);
    }

    function testHealthFactorGetsBelowMinimum()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(ETH_PRICE - 1)
    {
        assert(dscEngine.getHealthFactor(DEPOSITOR) < MIN_HEALTH_FACTOR);
    }

    function testHealthFactorGetsAboveMinimum() external usersDeposited(onlyDepositor) usersMinted(onlyDepositor) {
        console.log(dscEngine.getHealthFactor(DEPOSITOR));

        assert(dscEngine.getHealthFactor(DEPOSITOR) == MIN_HEALTH_FACTOR);

        MockV3Aggregator(wethPriceFeed).updateAnswer(DOUBLE_ETH_PRICE);

        assert(dscEngine.getHealthFactor(DEPOSITOR) > MIN_HEALTH_FACTOR);
    }

    function testCanMintMoreIfHealthImproves()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(DOUBLE_ETH_PRICE)
    {
        uint256 additionalDscMintNumber = uint256(ETH_PRICE) / 100;

        console.log(dscEngine.getHealthFactor(DEPOSITOR));
        vm.prank(DEPOSITOR);
        dscEngine.mintDsc(additionalDscMintNumber);
    }

    ////////////////////////////////////
    //     Liquidate Tests           ///
    ////////////////////////////////////

    function testCannotLiquidateZeroAmount() external usersDeposited(onlyDepositor) usersMinted(onlyDepositor) {
        vm.prank(LIQUIDATOR);

        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);

        dscEngine.liquidate(weth, DEPOSITOR, 0);
    }

    function testCannotLiquidateHealthyUser() external usersDeposited(onlyDepositor) usersMinted(onlyDepositor) {
        uint256 mintedDsc = dscEngine.getAmountOfDscMinted(DEPOSITOR);

        vm.prank(LIQUIDATOR);

        console.log(dscEngine.getHealthFactor(DEPOSITOR));

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);

        dscEngine.liquidate(weth, DEPOSITOR, mintedDsc);
    }

    function testCannotLiquidateUnhealthyUserIfLiquidatorHasZeroTokens()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(HALF_ETH_PRICE)
    {
        vm.startPrank(LIQUIDATOR);
        uint256 mintedDsc = dscEngine.getAmountOfDscMinted(DEPOSITOR);
        uint256 liquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);

        console.log(dscEngine.getHealthFactor(DEPOSITOR));

        dsc.approve(address(dscEngine), type(uint256).max);

        vm.expectRevert( /* ERC20InsufficientBalance */ );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, LIQUIDATOR, liquidatorDscBalance, mintedDsc
            )
        );

        dscEngine.liquidate(weth, DEPOSITOR, mintedDsc);
        vm.stopPrank();
    }

    function testCannotLiquidateTooUnhealthyUser()
        external
        usersDeposited(depositorAndLiquidator)
        usersMinted(depositorAndLiquidator)
        ethPriceUpdated(HALF_ETH_PRICE)
    {
        vm.startPrank(LIQUIDATOR);
        uint256 mintedDsc = dscEngine.getAmountOfDscMinted(DEPOSITOR);

        console.log(dscEngine.getHealthFactor(DEPOSITOR));

        dsc.approve(address(dscEngine), type(uint256).max);

        vm.expectRevert(); // can't get the 10% liquidation bonus due to undercollateralization
        dscEngine.liquidate(weth, DEPOSITOR, mintedDsc);
    }

    function testCannotLiquidateUnhealthyUserIfLiquiadatorIsUnhealthy()
        external
        usersDeposited(depositorAndLiquidator)
        usersMinted(depositorAndLiquidator)
        ethPriceUpdated(ETH_PRICE - 1)
    {
        vm.startPrank(LIQUIDATOR);
        uint256 mintedDsc = dscEngine.getAmountOfDscMinted(DEPOSITOR);

        console.log(dscEngine.getHealthFactor(DEPOSITOR));

        dsc.approve(address(dscEngine), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, MIN_HEALTH_FACTOR - 1));
        dscEngine.liquidate(weth, DEPOSITOR, mintedDsc);
        vm.stopPrank();
    }

    /**
     * @dev since the depositor has no more "minted" tokens and still
     *  has leftover collateral (since the Liqidator took from 150%
     *  collateralisation rate 110%, there is still some left, which
     *  makes the health factor maximum, not 0. If the user has been
     *  completely liquidated, via for example a treasury that takes
     *  the remaining collateral, then the health factor would be 0.
     */
    function testCanLiquidateUnhealthyUserIfLiquidatorIsHealthy()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(ETH_PRICE - 1)
    {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wbtc).approve(address(dscEngine), type(uint256).max);
        dscEngine.depositCollateral(wbtc, TOKENS_TO_DEPOSIT);
        uint256 maxMintableAmountInDsc = (LIQUIDATION_THRESHOLD * (uint256(WBTC_PRICE) / 10)) / LIQUIDATION_PRECISION;
        dscEngine.mintDsc(maxMintableAmountInDsc);

        uint256 wethBalanceBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 mintedDsc = dscEngine.getAmountOfDscMinted(DEPOSITOR);
        uint256 tokenAmountCoveredFromDebt = dscEngine.getTokenAmountFromDsc(weth, mintedDsc);
        uint256 bonusCollateral = (tokenAmountCoveredFromDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        dsc.approve(address(dscEngine), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(dsc));
        emit Transfer(LIQUIDATOR, address(dscEngine), mintedDsc);
        emit Transfer(address(dscEngine), address(0), mintedDsc);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(DEPOSITOR, LIQUIDATOR, weth, tokenAmountCoveredFromDebt + bonusCollateral);

        dscEngine.liquidate(weth, DEPOSITOR, mintedDsc);
        uint256 currentWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        vm.stopPrank();
        assertEq(wethBalanceBefore + tokenAmountCoveredFromDebt + bonusCollateral, currentWethBalance);
        assert(dscEngine.getHealthFactor(DEPOSITOR) == type(uint256).max);
    }

    ////////////////////////////////////
    //     Redeem Collateral Tests   ///
    ////////////////////////////////////

    function testCannotRedeemZeroAmount() external {
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZeroRequired.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testCannotRedeemNotWhitelistedToken() external {
        vm.expectRevert(DSCEngine.DSCEngine__IsNotWhitelistedCollateral.selector);
        dscEngine.redeemCollateral(address(0), 10);
    }

    function testCanRedeemCollateral() external usersDeposited(onlyDepositor) {
        uint256 preRedeemWethBalance = ERC20Mock(weth).balanceOf(DEPOSITOR);
        uint256 collateralAmount = dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth);
        console.log(collateralAmount);

        vm.prank(DEPOSITOR);

        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(DEPOSITOR, DEPOSITOR, weth, collateralAmount);
        dscEngine.redeemCollateral(weth, collateralAmount);
        assertEq(ERC20Mock(weth).balanceOf(DEPOSITOR), preRedeemWethBalance + collateralAmount);
        assertEq(dscEngine.getHealthFactor(DEPOSITOR), 0);
    }

    function testCanPartiallyRedeemCollateral()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(DOUBLE_ETH_PRICE)
    {
        uint256 preRedeemWethBalance = ERC20Mock(weth).balanceOf(DEPOSITOR);
        uint256 collateralAmount = (dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth)) / 2;
        console.log(collateralAmount);

        vm.prank(DEPOSITOR);

        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(DEPOSITOR, DEPOSITOR, weth, collateralAmount);
        dscEngine.redeemCollateral(weth, collateralAmount);
        assertEq(dscEngine.getHealthFactor(DEPOSITOR), MIN_HEALTH_FACTOR);
        assertEq(dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth), collateralAmount);
        assertEq(ERC20Mock(weth).balanceOf(DEPOSITOR), preRedeemWethBalance + collateralAmount);
    }

    function testCannotRedeemNonExistentCollateral() external usersDeposited(onlyDepositor) {
        uint256 collateralAmount = dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth);
        console.log(collateralAmount);

        vm.prank(DEPOSITOR);

        vm.expectRevert(); // underflow

        dscEngine.redeemCollateral(wbtc, collateralAmount); // tries to redeem wbtc instead of weth
    }

    function testCannotRedeemCollateralIfHealthFactorGetsUndercollateralized()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
    {
        uint256 expectedHealthFactorAfter = 0;
        uint256 collateralAmount = dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth);
        console.log(collateralAmount);

        vm.prank(DEPOSITOR);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, expectedHealthFactorAfter)
        );

        dscEngine.redeemCollateral(weth, collateralAmount);
    }

    function testCannotRedeemCollateralIfHealthFactorGetsUndercollateralizedByPrice()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        ethPriceUpdated(HALF_ETH_PRICE)
    {
        uint256 healthCorrection = 5;
        vm.prank(DEPOSITOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BrokenHealthFactor.selector, (MIN_HEALTH_FACTOR / 2) - healthCorrection
            )
        );

        dscEngine.redeemCollateral(weth, 1);
    }

    ////////////////////////////////////////////
    //     Redeem Collateral For Dsc Tests   ///
    ////////////////////////////////////////////

    function testCannotRedeemForDscIfUserHasZeroDsc() external usersDeposited(onlyDepositor) {
        uint256 collateralAmount = dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth);
        vm.expectRevert(); // underflow
        dscEngine.redeemCollateralForDsc(weth, collateralAmount, 1);
    }

    function testCanRedeemForDsc()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        userPranked(DEPOSITOR)
    {
        dsc.approve(address(dscEngine), type(uint256).max);
        uint256 mintedDscAmount = dsc.balanceOf(DEPOSITOR);
        uint256 wethBalanceBefore = ERC20Mock(weth).balanceOf(DEPOSITOR);
        uint256 collateralAmount = dscEngine.getAccountCollateralValuePerToken(DEPOSITOR, weth);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(DEPOSITOR, DEPOSITOR, weth, collateralAmount);
        vm.prank(DEPOSITOR);
        dscEngine.redeemCollateralForDsc(weth, collateralAmount, mintedDscAmount);
        uint256 dscbalanceAfter = dsc.balanceOf(DEPOSITOR);
        uint256 wethBalanceAfter = ERC20Mock(weth).balanceOf(DEPOSITOR);

        assertEq(dscbalanceAfter, 0);
        assertEq(wethBalanceAfter, wethBalanceBefore + collateralAmount);
    }

    ////////////////////////////////////
    //     Burn Dsc Tests            ///
    ////////////////////////////////////

    function testCannotBurnZeroAmount() external {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__MustBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testCannotBurnOverCurrentBalance() external {
        vm.expectRevert(); // underflow
        dscEngine.burnDsc(10);
    }

    function testCannotBurnBalanceIfNotApproved() external usersDeposited(onlyDepositor) usersMinted(onlyDepositor) {
        uint256 userBalance = dsc.balanceOf(DEPOSITOR);
        uint256 approvedNumber = 0;
        vm.prank(DEPOSITOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(dscEngine), approvedNumber, userBalance
            )
        );
        dscEngine.burnDsc(userBalance);
    }

    function testCanBurnCurrentBalance()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
        userPranked(DEPOSITOR)
    {
        dsc.approve(address(dscEngine), type(uint256).max);
        uint256 userBalance = dsc.balanceOf(DEPOSITOR);
        vm.expectEmit(true, true, false, true, address(dsc));
        emit Transfer(DEPOSITOR, address(dscEngine), userBalance);
        vm.expectEmit(true, true, false, true, address(dsc));
        emit Transfer(address(dscEngine), address(0), userBalance);
        vm.prank(DEPOSITOR);
        dscEngine.burnDsc(userBalance);

        assertEq(dsc.balanceOf(DEPOSITOR), 0);
    }

    function testCannotBurnIfAddressReceivedDscNotMinted()
        external
        usersDeposited(onlyDepositor)
        usersMinted(onlyDepositor)
    {
        // bug that needs to be fixed or not
        uint256 mintedDscByUser = dsc.balanceOf(DEPOSITOR);
        vm.prank(DEPOSITOR);
        dsc.transfer(address(LIQUIDATOR), mintedDscByUser);
        uint256 receivedDscBySecondUser = dsc.balanceOf(LIQUIDATOR);
        assertEq(mintedDscByUser, receivedDscBySecondUser);
        vm.prank(LIQUIDATOR);
        vm.expectRevert(); // underflow cause second user didn't mint any tokens
        dscEngine.burnDsc(receivedDscBySecondUser);
    }
}
