// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

interface IRubyNFT is IERC721Upgradeable {

    event MinterSet(address indexed minter, bool allowance);

    event DescriptionSet(string newDescription);

    event VisualAppearanceSet(string newVisualAppearance);

    function nftIds() external view returns (uint256);

    function minters(address minter) external view returns (bool);

    function description() external view returns (string memory);

    function visualAppearance() external view returns (string memory);

    function mint(address to) external;

    function setMinter(address minter, bool allowance) external;

    function setDescription(string memory _description) external;

    function setVisualAppearance(string memory _visualAppearance) external;
}
