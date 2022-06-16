// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../token_mappings/RubyToken.sol";

contract LotteryBurner is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public rubyToken;
    uint256 public burned;

    function initialize(address _owner, address _rubyToken) public initializer {
        require(_owner != address(0), "LotteryBurner: Invalid owner address");
        require(_rubyToken != address(0), "LotteryBurner: Invalid rubyToken address.");

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        rubyToken = _rubyToken;
        burned = 0;
    }

    function burn() external onlyOwner {
        uint256 toburn = IERC20(rubyToken).balanceOf(address(this));
        RubyToken(rubyToken).burn(toburn);
        burned += toburn;
    }
}
