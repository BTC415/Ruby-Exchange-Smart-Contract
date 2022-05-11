// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.2;

import "./IUniswapV2Router01.sol";
import "../../interfaces/IRubyNFTAdmin.sol";

interface IUniswapV2Router02 is IUniswapV2Router01 {

    event FactorySet(address indexed newFactory);

    event NFTAdminSet(address indexed newNftAdmin);

    function nftAdmin() external pure returns (IRubyNFTAdmin);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function setFactory(address newFactory) external;

    function setNftAdmin(IRubyNFTAdmin newNftAdmin) external;
}
