// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./IRandomNumberGenerator.sol";

contract RNG_Test is IRandomNumberGenerator {
    constructor() public {}

    uint256[] data = [
        126009,
        5533037,
        9311954,
        5319410,
        9952834,
        3396771,
        5720753,
        3437222,
        2943607,
        1768660,
        5293500,
        4718982,
        9098328,
        5960290,
        8030194,
        9164690,
        8416997,
        660076,
        3930837,
        4118553
    ];

    function getRandomNumber(uint256 lotterySize, uint256 count)
        public
        view
        override
        returns (uint256[] memory randomness)
    {
        randomness = new uint256[](count);
        for (uint256 i = 0; i < count; i++) randomness[i] = data[i] % uint256(10)**lotterySize;
        return randomness;
    }
}
