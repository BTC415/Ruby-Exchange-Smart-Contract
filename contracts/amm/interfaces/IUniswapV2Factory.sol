// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IUniswapV2Factory {

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event AdminSet(address indexed newAdmin);
    event FeeToRecipientSet(address indexed newFeeTo);
    event PairCreatorSet(address indexed pairCreator, bool allowance);
    event FeeDecutionSwapperSet(address indexed swapper, bool allowance);

    function feeTo() external view returns (address);

    function admin() external view returns (address);

    function pairCreators(address) external view returns (bool);

    function feeDeductionSwappers(address) external view returns (bool);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address newFeeTo) external;

    function setPairCreator(address pairCreator, bool allowance) external;

    function setFeeDeductionSwapper(address feeDeductionSwapper, bool allowance) external;

    function setAdmin(address newAdmin) external;
}
