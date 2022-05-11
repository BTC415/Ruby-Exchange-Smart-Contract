// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IRubyNFTAdmin {

    event MinterSet(address indexed minter, bool allowance);

    event FreeSwapNFTSet(address indexed freeSwapNFT);

    event RubyProfileNFTset(address indexed profileNFT);

    function profileNFT() external view returns (address);

    function freeSwapNFT() external view returns (address);

    function minters(address minter) external view returns (bool);

    function calculateAmmSwapFeeDeduction(address user) external view returns (uint256 feeMultiplier);

    function mintProfileNFT(address user) external;

    function setProfileNFT(address newProfileNFT) external;

    function setFreeSwapNFT(address newFreeSwapNFT) external;

    function setMinter(address minter, bool allowance) external;
}
