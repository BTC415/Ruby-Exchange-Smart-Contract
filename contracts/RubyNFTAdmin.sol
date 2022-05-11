// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IRubyNFTAdmin.sol";
import "./interfaces/IRubyNFT.sol";

contract RubyNFTAdmin is IRubyNFTAdmin, OwnableUpgradeable {
    address public override profileNFT;
    address public override freeSwapNFT;

    // profile NFT minters
    mapping(address => bool) public override minters;

    modifier onylMinter() {
        require(minters[msg.sender], "RubyNFTAdmin: Minting not allowed");
        _;
    }

    function initialize(address _owner, address _profileNFT, address _freeSwapNFT) public initializer {
        require(_owner != address(0), "RubyNFTAdmin: Invalid owner address");
        require(_profileNFT != address(0), "RubyNFTAdmin: Invalid RUBY profile NFT");
        require(_freeSwapNFT != address(0), "RubyNFTAdmin: Invalid RUBY free swap NFT");
        profileNFT = _profileNFT;
        freeSwapNFT = _freeSwapNFT;

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
    }

    /**
        @notice Calculate the fee multiplier that needs to be applied in the 
        AMM swapping calculations. The fee deduction is dependent on the
        `user`. The fee multiplier is determined by internal rules. Currently the 
        single rule is having balance of at least 1 at the RubyProfileNFT contract.
        In the future more rules should be added.
        The `feeMultiplier` is in range of [997, 1000]: 
            - 997 means fee of 30 basis points
            - 1000 means fee of 0 basis points
        @param user - the address of the user
     */
    function calculateAmmSwapFeeDeduction(address user) external view override returns (uint256 feeMultiplier) {
        if (IRubyNFT(freeSwapNFT).balanceOf(user) > 0) {
            return 1000; // no fee
        }

        return 997; // 30 bps fee
    }

    // function calculateLPFeeDeduction(address user) public view returns (uint256 feeAmount) {

    // }

    // Mint profile NFT if the user has no profile NFTs
    // The exploitability of this is a feature. Users can mint multiple profile NFTs by design
    // Example: User can do a swap, have NFT minted, then he can transfer the NFT, do another 
    // swap and get another NFT - this is not a bug but a feature.
    function mintProfileNFT(address user) external override onylMinter {
        if (IRubyNFT(profileNFT).balanceOf(user) == 0) {
            IRubyNFT(profileNFT).mint(user);
        }
    }


    function setProfileNFT(address newProfileNFT) external override onlyOwner {
        require(newProfileNFT != address(0), "RubyNFTAdmin: Invalid profile NFT");
        profileNFT = newProfileNFT;
        emit RubyProfileNFTset(profileNFT);
    }

    function setFreeSwapNFT(address newFreeSwapNFT) external override onlyOwner {
        require(newFreeSwapNFT != address(0), "RubyNFTAdmin: Invalid free swap NFT");
        freeSwapNFT = newFreeSwapNFT;
        emit FreeSwapNFTSet(freeSwapNFT);
    }

    function setMinter(address minter, bool allowance) external override onlyOwner {
        require(minter != address(0), "RubyNFTAdmin: Invalid minter address");
        minters[minter] = allowance;
        emit MinterSet(minter, allowance);
    }


}
