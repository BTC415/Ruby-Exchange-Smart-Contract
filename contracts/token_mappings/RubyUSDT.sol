// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SkaleMappedERC20Token.sol";

contract RubyUSDT is SkaleMappedERC20Token("Tether USD", "USDT", 6) {}
