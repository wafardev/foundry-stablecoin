// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__MoreThanZeroRequired();
    error DSCEngine__IsNotWhitelistedCollateral();
    error DSCEngine__WhitelistedTokenLengthNotMatchingPriceFeed();
    error DSCEngine__IsNotPriceFeed();
    error DSCEngine__TransferFailed();
    error DSCEngine__NotPriceFeed();
    error DSCEngine__BrokenHealthFactor(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__MintFailed();

    event CollateralDeposited(address indexed user, address indexed token, uint256 amountDeposited);
    event CollateralRedeemed(
        address indexed userFrom, address indexed userTo, address indexed token, uint256 amountRedeemed
    );

    DecentralizedStablecoin private i_dsc;

    mapping(address token => address priceFeed) private s_collateralTokenToPriceFeed;

    mapping(address user => mapping(address token => uint256 amountDeposited)) private s_depositedCollateral;

    mapping(address user => uint256 amountOfDscMinted) private s_amountOfDscMinted;

    address[] private s_whitelistedTokens;

    uint256 private constant DEFAULT_DECIMALS = 18;
    uint256 private constant PRECISION = 10 ** DEFAULT_DECIMALS;
    uint256 private constant LIQUIDATION_THRESHOLD = 66; // minimum approx 151,5% collateralization rate
    uint256 private constant LIQUIDATION_FEE_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // liquidator gets 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRICE_FEED_VERSION = 4;

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MoreThanZeroRequired();
        }
        _;
    }

    modifier isWhitelistedCollateral(address collateralToken) {
        if (s_collateralTokenToPriceFeed[collateralToken] == address(0)) {
            revert DSCEngine__IsNotWhitelistedCollateral();
        }
        _;
    }

    constructor(address[] memory whitelistedCoins, address[] memory priceFeeds, address dscAddress) {
        if (whitelistedCoins.length != priceFeeds.length) {
            revert DSCEngine__WhitelistedTokenLengthNotMatchingPriceFeed();
        }

        for (uint256 i; i < whitelistedCoins.length; i++) {
            address priceFeed = priceFeeds[i];
            if (!_isPriceFeed(priceFeed)) {
                revert DSCEngine__IsNotPriceFeed();
            }
            s_collateralTokenToPriceFeed[whitelistedCoins[i]] = priceFeed;
            s_whitelistedTokens.push(whitelistedCoins[i]);
        }
        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function depositCollateral(address collateralToken, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isWhitelistedCollateral(collateralToken)
        nonReentrant
    {
        s_depositedCollateral[msg.sender][collateralToken] += collateralAmount;
        emit CollateralDeposited(msg.sender, collateralToken, collateralAmount);
        bool success = IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_amountOfDscMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateralAndMintDsc(address collateralToken, uint256 collateralAmount, uint256 amountToMint)
        external
    {
        depositCollateral(collateralToken, collateralAmount);
        mintDsc(amountToMint);
    }

    function burnDsc(uint256 amountToBurn) public {
        _burnDsc(msg.sender, msg.sender, amountToBurn);
    }

    function redeemCollateral(address collateralToken, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isWhitelistedCollateral(collateralToken)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, collateralToken, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDsc(address collateralToken, uint256 collateralAmount, uint256 amountToBurn) external {
        burnDsc(amountToBurn);
        redeemCollateral(collateralToken, collateralAmount);
    }

    function liquidate(address collateralToken, address liquidatedUser, uint256 debtToLiquidate)
        external
        moreThanZero(debtToLiquidate)
        isWhitelistedCollateral(collateralToken)
    {
        uint256 currentUserHealthFactor = _healthFactor(liquidatedUser);

        if (currentUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountCoveredFromDebt = getTokenAmountFromDsc(collateralToken, debtToLiquidate);

        uint256 bonusCollateral = (tokenAmountCoveredFromDebt * LIQUIDATION_BONUS) / LIQUIDATION_FEE_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountCoveredFromDebt + bonusCollateral;

        _burnDsc(liquidatedUser, msg.sender, debtToLiquidate);
        _redeemCollateral(liquidatedUser, msg.sender, collateralToken, totalCollateralToRedeem);

        uint256 afterUserHealthFactor = _healthFactor(liquidatedUser);

        if (afterUserHealthFactor <= currentUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _redeemCollateral(address from, address to, address collateralToken, uint256 collateralAmount) private {
        s_depositedCollateral[from][collateralToken] -= collateralAmount;
        emit CollateralRedeemed(from, to, collateralToken, collateralAmount);
        bool success = IERC20(collateralToken).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountToBurn) private {
        s_amountOfDscMinted[onBehalfOf] -= amountToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountToBurn);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor == 0) {
            if (s_amountOfDscMinted[user] > 0) {
                revert DSCEngine__BrokenHealthFactor(userHealthFactor);
            }
        } else if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(userHealthFactor);
        }
    }

    function _isPriceFeed(address priceFeed) internal view returns (bool) {
        string memory priceFeedFunction = "version()";
        (bool success, bytes memory data) = priceFeed.staticcall(abi.encodeWithSignature(priceFeedFunction));

        if (success && data.length != 0 && abi.decode(data, (uint256)) == PRICE_FEED_VERSION) {
            return true;
        }
        return false;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_amountOfDscMinted[user];
        collateralValueInUsd = getAccountUsdCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        if (collateralValueInUsd == 0) {
            return 0;
        } else if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue =
            ((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_FEE_PRECISION) * PRECISION;

        return (adjustedCollateralValue / totalDscMinted);
    }

    function getAccountUsdCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i; i < s_whitelistedTokens.length; i++) {
            address whitelistedToken = s_whitelistedTokens[i];
            uint256 collateralAmount = s_depositedCollateral[user][whitelistedToken];
            totalCollateralValue += getUsdValue(whitelistedToken, collateralAmount);
        }
    }

    function getAccountCollateralValuePerToken(address user, address collateralToken)
        public
        view
        returns (uint256 collateralAmount)
    {
        collateralAmount = s_depositedCollateral[user][collateralToken];
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        address priceFeed = s_collateralTokenToPriceFeed[token];

        (, int256 answer,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        uint256 additionalFeePrecision = DEFAULT_DECIMALS - AggregatorV3Interface(priceFeed).decimals();

        return ((uint256(answer) * 10 ** additionalFeePrecision) * amount) / PRECISION;
    }

    function getTokenAmountFromDsc(address token, uint256 usdValueInWei) public view returns (uint256) {
        address priceFeed = s_collateralTokenToPriceFeed[token];

        (, int256 answer,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        uint256 additionalFeePrecision = DEFAULT_DECIMALS - AggregatorV3Interface(priceFeed).decimals();

        return (usdValueInWei * PRECISION) / (uint256(answer) * 10 ** additionalFeePrecision);
    }

    function getPriceFeed(address token) public view returns (address) {
        return s_collateralTokenToPriceFeed[token];
    }

    function getAllWhitelistedTokens() public view returns (address[] memory) {
        return s_whitelistedTokens;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getAmountOfDscMinted(address user) external view returns (uint256) {
        return s_amountOfDscMinted[user];
    }
}
