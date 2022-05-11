// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRubyStaker {
    function mint(address _receiver, uint256 _amount) external;

    function notifyRewardAmount(uint256 rewardId, uint256 reward) external;
}
