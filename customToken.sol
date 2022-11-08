// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CustomToken is ERC20 {
    uint8 public __decimals;

    constructor(
        string memory name, 
        string memory symbol, 
        uint8 _decimals
    ) ERC20(name, symbol) {
        _mint(msg.sender, 100000000 * 10 ** _decimals);
        __decimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return __decimals;
    }
}
