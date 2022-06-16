// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IRandomNumberGenerator {
    function getRandomNumber(uint256 lotterySize, uint256 count) external view returns (uint256[] memory randomness);
}
