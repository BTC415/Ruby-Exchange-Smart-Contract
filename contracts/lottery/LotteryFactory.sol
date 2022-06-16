// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Lottery.sol";
import "../interfaces/IRubyNFT.sol";

// import "hardhat/console.sol";

contract LotteryFactory is OwnableUpgradeable {
    using SafeMath for uint256;

    address private RNG;
    address private treasury;
    address private burn;

    uint256 private constant MAX_WINNERS = 10;

    mapping(uint256 => Lottery) private allLotteries;
    uint256 private lotteryId;

    event LotteryCreated(uint256 _lotteryId, address _lottery, address _collateral, address _nft);

    //-------------------------------------------------------------------------
    // initializer
    //-------------------------------------------------------------------------
    function initialize(
        address _randomNumberGenerator,
        address _treasury,
        address _burn
    ) public initializer {
        require(_randomNumberGenerator != address(0), "LotteryFactory: randomNumberGenerator cannot be 0 address");
        require(_treasury != address(0), "LotteryFactory: Treasury cannot be 0 address");
        require(_burn != address(0), "LotteryFactory: Burn cannot be 0 address");
        RNG = _randomNumberGenerator;
        treasury = _treasury;
        burn = _burn;

        OwnableUpgradeable.__Ownable_init();
    }

    /// @notice Create a new Lottery instance.
    /// @param _collateral The ERC20 address for token to buy tickets
    /// @param _nft The NFT address for bonus (can be zero for no nft prize)
    /// @param _tokenId The Bonus NFT ID
    /// @param _lotterySize Digit count of ticket (e.g. 4 = 10^4 = 10000 tickets)
    /// @param _ticketPrice Cost per ticket in collateral tokens
    /// @param _distribution An array defining the distribution of the prize pool.
    /// @param _duration The duration until no more tickets will be sold for the lottery from now.
    function createNewLotto(
        address _collateral,
        address _nft,
        uint256 _tokenId,
        uint256 _lotterySize,
        uint256 _ticketPrice,
        uint256[] calldata _distribution,
        uint256 _duration
    ) external onlyOwner {
        require(_collateral != address(0), "LotteryFactory: Collateral cannot be 0 address");
        require(_distribution.length > 2, "LotteryFactory: Invalid distribution");
        require(_distribution.length <= MAX_WINNERS + 2, "LotteryFactory: Invalid distribution");
        if (_nft != address(0)) {
            require(IRubyNFT(_nft).ownerOf(_tokenId) == msg.sender, "LotteryFactory: Owner of NFT is invalid");
        }

        lotteryId++;
        allLotteries[lotteryId] = new Lottery(
            lotteryId,
            _collateral,
            _nft,
            _tokenId,
            _lotterySize,
            _ticketPrice,
            _distribution,
            burn,
            treasury,
            _duration,
            RNG
        );

        Lottery(allLotteries[lotteryId]).transferOwnership(owner());

        if (_nft != address(0)) {
            IRubyNFT(_nft).transferFrom(msg.sender, address(allLotteries[lotteryId]), _tokenId);
        }

        emit LotteryCreated(lotteryId, address(allLotteries[lotteryId]), _collateral, _nft);
    }

    function getCurrentLotto() public view returns (address) {
        return address(allLotteries[lotteryId]);
    }

    function getLotto(uint256 _lotteryId) external view returns (address) {
        return address(allLotteries[_lotteryId]);
    }

    function getCurrentLottoryId() external view returns (uint256) {
        return lotteryId;
    }

    function setRNG(address _RNG) external onlyOwner {
        require(_RNG != address(0), "LotteryFactory: RNG cannot be 0 address");
        RNG = _RNG;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "LotteryFactory: Treasury cannot be 0 address");
        treasury = _treasury;
    }

    function setBurn(address _burn) external onlyOwner {
        require(_burn != address(0), "LotteryFactory: Burn cannot be 0 address");
        burn = _burn;
    }

    function getRNG() external view returns (address) {
        return address(RNG);
    }

    function getTreasury() external view returns (address) {
        return treasury;
    }

    function getBurn() external view returns (address) {
        return burn;
    }

    function costToBuyTickets(uint256 _ticketSize) external view returns (uint256) {
        return Lottery(getCurrentLotto()).costToBuyTickets(_ticketSize);
    }

    function getWinningNumbers() external view returns (uint256[] memory) {
        return Lottery(getCurrentLotto()).getWinningNumbers();
    }
}
