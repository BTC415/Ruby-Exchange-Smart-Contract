// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IRubyNFT.sol";

contract RubyNFT is ERC721Upgradeable, OwnableUpgradeable, IRubyNFT {
    uint256 public override nftIds;

    string public override description;

    string public override visualAppearance;

    mapping(address => bool) public override minters;

    modifier onlyMinter() {
        require(minters[msg.sender], "RubyNFT: Minting not allowed");
        _;
    } 

    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _description,
        string memory _visualAppearance
    ) external initializer {
        require(_owner != address(0), "RubyNFT: Invalid owner address");
        require(bytes(_description).length != 0, "RubyNFT: Invalid description");
        require(bytes(_visualAppearance).length != 0, "RubyNFT: Invalid visual appearance");
        ERC721Upgradeable.__ERC721_init(_name, _symbol);
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        description = _description;
        visualAppearance = _visualAppearance;
    }

    function mint(address to) external virtual override onlyMinter {
        require(to != address(0), "RubyNFT: Invalid Receiver");
        uint256 tokenId = nftIds;
        _safeMint(to, tokenId);
        nftIds = tokenId + 1;
    }

    function setMinter(address minter, bool allowance) external virtual override onlyOwner {
        require(minter != address(0), "RubyNFT: Invalid minter address");
        minters[minter] = allowance;
        emit MinterSet(minter, allowance);
    }


    function setDescription(string memory _description) external virtual override onlyOwner {
        require(bytes(_description).length != 0, "RubyNFT: Invalid description");
        description = _description;
        emit DescriptionSet(description);
    }

    function setVisualAppearance(string memory _visualAppearance) external virtual override onlyOwner {
        require(bytes(_visualAppearance).length != 0, "RubyNFT: Invalid visual appearance");
        visualAppearance = _visualAppearance;
        emit VisualAppearanceSet(visualAppearance);
    }

    // avoid storage collisions
    uint256[46] private __gap;
}