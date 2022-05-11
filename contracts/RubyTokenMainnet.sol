// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";

/**
 * @title Ruby token on mainnet
 */
contract RubyTokenMainnet is ERC20Capped {
    /// @notice Total number of tokens
    uint256 public constant MAX_SUPPLY = 200_000_000e18; // 200 million Ruby

    constructor() public ERC20("RubyToken", "RUBY") ERC20Capped(MAX_SUPPLY) {
        _mint(msg.sender, MAX_SUPPLY);
    }
}
