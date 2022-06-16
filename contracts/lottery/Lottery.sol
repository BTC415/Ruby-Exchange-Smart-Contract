// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./IRandomNumberGenerator.sol";
import "../interfaces/IRubyNFT.sol";

// import "hardhat/console.sol";

contract Lottery is Ownable, Pausable {
    // Libraries
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 private constant MAX_WINNERS = 10;

    address private treasury; // Address to send
    address private burn; // Address to send

    IERC20 private ruby; // Instance of erc20 token (collateral currency for lotto).
    IRandomNumberGenerator internal RNG; // Instance of Random Number Generator.
    address private nft; // Address of instance of IRubyNFT (or 0)

    uint256 private ID; // ID of this lottery
    uint256 private bonusTokenId; // ID of NFT for lottery reward.
    uint256 private startingTimestamp; // Block timestamp for start of lottery.
    uint256 private closingTimestamp; // Block timestamp for end of lottery.
    uint256 private lotterySize; // Digit count of ticket.
    uint256 private winnersSize; // The number of winners for reward.
    uint256 private rubyTotal; // Total prize pool.
    uint256[] private winners; // The winning numbers.
    uint256 private ticketPrice; // Cost per ticket in $ruby.
    uint256[] private prizeDistribution; // An array defining the distribution of the prize pool.
    uint256 private numTicketsSold;

    mapping(uint256 => address) private ticketsToPerson;
    mapping(address => uint256[]) private personToTickets;
    mapping(address => bool) private claimed;

    event NewTickets(address who, uint256 ticketSize);
    event DrewWinningNumber(uint256 lotteryID, uint256 nwinners, address[] winnerAddresses);
    event RewardClaimed(address to, uint256 amount, address collateral, address nft, uint256 nftid);

    constructor(
        uint256 _ID,
        address _ruby,
        address _nft,
        uint256 _bonusTokenId,
        uint256 _lotterySize,
        uint256 _ticketPrice,
        uint256[] memory _prizeDistribution, /*first, second, ..., last, burn, treasury*/
        address _burn,
        address _treasury,
        uint256 _duration,
        address _RNG
    ) public {
        require(_ruby != address(0), "Lottery: Ruby cannot be 0 address");
        require(_RNG != address(0), "Lottery: Random Number Generator cannot be 0 address");
        require(_treasury != address(0), "Lottery: Treasury cannot be 0 address");
        require(_burn != address(0), "Lottery: Burn cannot be 0 address");
        require(_prizeDistribution.length >= 3, "Lottery: Invalid distribution");
        require(_prizeDistribution.length <= MAX_WINNERS + 2, "Lottery: Invalid distribution");
        winnersSize = uint256(_prizeDistribution.length - 2);
        uint256 prizeDistributionTotal = 0;
        for (uint256 j = 0; j < _prizeDistribution.length; j++) {
            prizeDistributionTotal = prizeDistributionTotal.add(uint256(_prizeDistribution[j]));
        }
        // Ensuring that prize distribution total is 100%
        require(prizeDistributionTotal == 100, "Lottery: Prize distribution is not 100%");
        require(_duration > 60, "Lottery: min duration 1 minute");
        require(_duration < (60*60*24*30), "Lottery: max duration 1 month");
        require(_lotterySize <= 5, "Lottery: max 100k tickets");

        ruby = IERC20(_ruby);
        RNG = IRandomNumberGenerator(_RNG);

        // both can be 0 if no NFT prize
        ID = _ID;    // can be 0
        nft = _nft;  // can be 0

        bonusTokenId = _bonusTokenId;
        treasury = _treasury;
        burn = _burn;
        ticketPrice = _ticketPrice;
        lotterySize = _lotterySize;
        startingTimestamp = getCurrentTime();
        closingTimestamp = startingTimestamp.add(_duration);
        prizeDistribution = _prizeDistribution;
    }

    modifier opened() {
        require(getCurrentTime() >= startingTimestamp, "Lottery: Ticket selling is not yet started");
        require(getCurrentTime() < closingTimestamp, "Lottery: Ticket selling is closed");
        _;
    }
    modifier closed() {
        require(getCurrentTime() >= closingTimestamp, "Lottery: Ticket selling is not yet closed");
        _;
    }
    modifier drew() {
        require(winners.length == winnersSize, "Lottery: Winning Numbers not chosen yet");
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function stop() external onlyOwner {
        closingTimestamp = getCurrentTime();
    }

    /// @notice Buy ticket for lottery.
    /// @param _ticketSize The number of tickets to buy.
    /// @param _choosenTicketNumbers An array containing the ticket numbers to buy.
    function buyTicket(uint256 _ticketSize, uint256[] calldata _choosenTicketNumbers) external opened whenNotPaused {
        // Ensuring that there are the right amount of chosen numbers
        require(_choosenTicketNumbers.length == _ticketSize, "Lottery: Invalid chosen numbers");

        uint256 numOkTickets = 0;
        for (uint256 i = 0; i < _choosenTicketNumbers.length; i++) {
            require(_choosenTicketNumbers[i] < uint256(10)**lotterySize, "Lottery: Ticket Number is out of range");
            if (ticketsToPerson[_choosenTicketNumbers[i]] == address(0)) {
                numOkTickets += 1;
                ticketsToPerson[_choosenTicketNumbers[i]] = msg.sender;
                personToTickets[msg.sender].push(_choosenTicketNumbers[i]);
            }
        }

        uint256 totalCost = uint256(numOkTickets).mul(ticketPrice);
        ruby.safeTransferFrom(msg.sender, address(this), totalCost);
        rubyTotal = rubyTotal.add(totalCost);
        numTicketsSold = numTicketsSold.add(numOkTickets);

        emit NewTickets(msg.sender, numOkTickets);
    }

    /// @notice Draw winning numbers.
    function drawWinningNumbers() external closed onlyOwner {
        require(winners.length == 0, "Lottery: Have already drawn the winning number");
        winners = RNG.getRandomNumber(lotterySize, winnersSize);

        // percentage to treasury
        if (prizeDistribution[prizeDistribution.length - 1] > 0) {
            ruby.safeTransfer(treasury, rubyTotal.mul(prizeDistribution[prizeDistribution.length - 1]).div(100));
        }
        // percentage to burn
        if (prizeDistribution[prizeDistribution.length - 2] > 0) {
            ruby.safeTransfer(burn, rubyTotal.mul(prizeDistribution[prizeDistribution.length - 2]).div(100));
        }

        uint256 nwinners = 0;

        // any un-won collateral goes to treasury
        uint256 unwon = 0;
        for (uint256 i = 0; i < winnersSize; i++) {
            address winAddress = ticketsToPerson[winners[i]];
            if (winAddress == address(0)) {
              unwon = unwon.add(rubyTotal.mul(prizeDistribution[i]).div(100));
            } else {
              nwinners += 1;
            }
        }
        ruby.safeTransfer(treasury, unwon);

        // emit all winning addresses
        address[] memory winningAddresses = getWinningAddresses();
        emit DrewWinningNumber(ID, nwinners, winningAddresses);
    }

    function withdraw(uint256 _amount) external closed onlyOwner {
        ruby.safeTransfer(msg.sender, _amount);
        if (nft != address(0)) {
            IRubyNFT(nft).safeTransferFrom(address(this), msg.sender, bonusTokenId);
        }
    }

    /// @notice Claim rewards to caller if he/she bought winning ticket
    function claimReward() external closed drew {
        uint256 prize = 0;
        address nftAddress = address(0);
        uint256 nftid = 0;
        require(claimed[msg.sender] == false, "Lottery: Already Claimed");
        if (ticketsToPerson[winners[0]] == msg.sender) {
            if (nft != address(0)) {
                IRubyNFT(nft).safeTransferFrom(address(this), msg.sender, bonusTokenId);
                nftAddress = nft;
                nftid = bonusTokenId;
            }
        }
        for (uint256 i = 0; i < winnersSize; i++) {
            uint256 winner = winners[i];
            address winAddress = ticketsToPerson[winner];
            if (winAddress == msg.sender) {
                prize = prize.add(rubyTotal.mul(prizeDistribution[i]).div(100));
            }
        }
        ruby.safeTransfer(address(msg.sender), prize);
        claimed[msg.sender] = true;
        emit RewardClaimed(msg.sender, prize, address(ruby), nftAddress, nftid);
    }

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------
    function getCurrentTime() internal view returns (uint256) {
        return block.timestamp;
    }

    /// @notice Check the reward amount.
    /// @param to The address where you want to check the reward amount.
    function getRewardAmount(address to) public view drew returns (uint256) {
        uint256 prize = 0;
        for (uint256 i = 0; i < winnersSize; i++) {
            uint256 winner = winners[i];
            address winAddress = ticketsToPerson[winner];
            if (winAddress == to) {
              prize = prize.add(rubyTotal.mul(prizeDistribution[i]).div(100));
            }
        }
        return prize;
    }

    /// @notice Check the reward NFT.
    /// @param to The address where you want to check the reward NFT.
    function getRewardNFT(address to) public view drew returns (bool) {
        if ((ticketsToPerson[winners[0]] == to) && (nft != address(0))) {
            return true;
        }
        return false;
    }

    /// @notice Cost to buy tickets in $ruby.
    /// @param _ticketSize The number of tickets to buy.
    function costToBuyTickets(uint256 _ticketSize) external view returns (uint256) {
        return ticketPrice.mul(_ticketSize);
    }

    function getWinningAddresses() public view drew returns (address[] memory) {
        address[] memory winnerAddresses = new address[](winnersSize);
        for (uint256 i = 0; i < winnersSize; i++) {
            uint256 winner = winners[i];
            winnerAddresses[i] = ticketsToPerson[winner];
        }
        return winnerAddresses;
    }

    function hasNFTPrize() external view returns (bool) {
        return nft != address(0);
    }

    function isTicketAvailable(uint256 ticket) external view returns (bool) {
        return ticketsToPerson[ticket] == address(0);
    }

    function areTicketsAvailable(uint256[] calldata tickets) external view returns (bool[] memory) {
        bool[] memory available = new bool[](tickets.length);
        for (uint256 i = 0; i < tickets.length; i++) {
            available[i] = ticketsToPerson[tickets[i]] == address(0);
        }
        return available;
    }

    function getWinningNumbers() external view drew returns (uint256[] memory) {
        return winners;
    }

    function getStartingTimestamp() external view returns (uint256) {
        return startingTimestamp;
    }

    function getClosingTimestamp() external view returns (uint256) {
        return closingTimestamp;
    }

    function getTickets(address person) external view returns (uint256[] memory) {
        return personToTickets[person];
    }

    /// @notice Number of digits of the ticket, e.g. 4 = 10**4 = 10000 tickets
    function getLotterySize() external view returns (uint256) {
        return lotterySize;
    }

    function getNumTicketsSold() external view returns (uint256) {
        return numTicketsSold;
    }

    function getTicketsRemaining() external view returns (uint256) {
        return uint256(10**lotterySize).sub(numTicketsSold);
    }

    function getTotalRuby() external view returns (uint256) {
        return rubyTotal;
    }

    function getDistibution() external view returns (uint256[] memory) {
        return prizeDistribution;
    }

    function getBonusNFT() external view returns (address) {
        return nft;
    }

    function getBonusId() external view returns (uint256) {
        return bonusTokenId;
    }

    function getNftDescription() external view returns (string memory) {
        if (nft == address(0)) {
            return "{}";
        }
        return IRubyNFT(nft).description();
    }

    function getVisualAppearance() external view returns (string memory) {
        if (nft == address(0)) {
            return "{}";
        }
        return IRubyNFT(nft).visualAppearance();
    }

    function isOpened() external view returns (bool) {
        return getCurrentTime() >= startingTimestamp && getCurrentTime() < closingTimestamp;
    }

    function isClosed() external view returns (bool) {
        return getCurrentTime() >= closingTimestamp;
    }

    function isDrawn() external view returns (bool) {
        return winners.length == winnersSize;
    }

    function getClaimed(address who) external view returns (bool) {
        return claimed[who];
    }

    function getTicketPrice() external view returns (uint256) {
        return ticketPrice;
    }

    function getTicketERC20() external view returns (address) {
        return address(ruby);
    }

    function getTicketERC20Symbol() external view returns (string memory) {
        return ERC20(address(ruby)).symbol();
    }

    function getTicketERC20Decimals() external view returns (uint8) {
        return ERC20(address(ruby)).decimals();
    }

    function getID() external view returns (uint256) {
        return ID;
    }
}
