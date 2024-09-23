// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {DSCEngine} from "./DSCEngine.sol";

contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin__MustBeMoreThanZero();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__MintToZeroAddress();

    constructor() ERC20("DecentralizedStablecoin", "DST") Ownable(msg.sender) {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        } else if (amount > balance) {
            revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(address _to, uint256 amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin__MintToZeroAddress();
        } else if (amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }
        _mint(_to, amount);
        return true;
    }
}
