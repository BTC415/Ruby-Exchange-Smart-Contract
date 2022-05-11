// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRubyStaker.sol";
import "./token_mappings/RubyToken.sol";
import "./libraries/BoringERC20.sol";

import "hardhat/console.sol";

// RubyStaker based on EpsStaker.sol from Ellipsis finance
// (https://github.com/ellipsis-finance/ellipsis/blob/master/contracts/EpsStaker.sol)
contract RubyStaker is Ownable, ReentrancyGuard, IRubyStaker {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event RewardMinterSet(address indexed newRewardMinter);
    event RewardDistributorSet(address indexed rewardDistributor);
    event RewardDataRegistered(address indexed rewardToken, address indexed distributor);
    event RewardDistributorApproved(address indexed rewardToken, address indexed distributor, bool approved);
    event RubyTokenEmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event ExpiredLocksWithdrawal(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event Recovered(address token, uint256 amount);

    /* ========== STATE VARIABLES ========== */

    struct Reward {
        address rewardToken;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
    }
    struct Balances {
        uint256 total;
        uint256 unlocked;
        uint256 locked;
        uint256 earned;
    }
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }

    struct RewardData {
        address token;
        uint256 amount;
    }

    IERC20 public rubyToken;
    address public rewardMinter; // RubyMasterChef


    // rewardTypeId => rewardDistributor => bool
    // RubyMaker and RubyFeeSwapper (for Stable pool fees in the future)
    mapping(uint256 => mapping(address => bool)) public rewardDistributors; 

    // registered reward tokens
    mapping(address => bool) public registeredRewardTokens;

    // maximum number of rewards, excluding the locked token rewards
    // for example, if maxNumRewards == 5, then 5 reward tokens can be added (numRewards can be maximum 5)
    // the 0th reward token is the locked token rewards
    uint256 public maxNumRewards;

    uint256 public numRewards;
    // rewardId => Reward
    mapping(uint256 => Reward) public rewardData;

    // Duration that rewards are streamed over
    uint256 public constant rewardsDuration = 86400 * 7;

    // Duration of lock/earned penalty period
    uint256 public constant lockDuration = rewardsDuration * 13;

    // user -> rewardTypeId -> amount
    mapping(address => mapping(uint256 => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(uint256 => uint256)) public rewards;

    uint256 public totalSupply;
    uint256 public lockedSupply;

    // Private mappings for balance data
    mapping(address => Balances) private balances;
    mapping(address => LockedBalance[]) private userLocks;
    mapping(address => LockedBalance[]) private userEarnings;

    /* ========== MODIFIERS ========== */

    modifier onlyRewardMinter() {
        require(msg.sender == rewardMinter, "RubyStaker: Only reward minter can execute this action.");
        _;
    }

    modifier onlyRewardDistributor(uint256 rewardId) {
        require(
            rewardDistributors[rewardId][msg.sender],
            "RubyStaker: Only reward distributor can execute this action."
        );
        _;
    }

    modifier updateReward(address account) {
        uint256 balance;
        uint256 supply = lockedSupply;
        rewardData[0].rewardPerTokenStored = _rewardPerToken(0, supply);
        rewardData[0].lastUpdateTime = lastTimeRewardApplicable(0);
        if (account != address(0)) {
            // Special case, use the locked balances and supply for stakingReward rewards
            rewards[account][0] = _earned(account, 0, balances[account].locked, supply);
            userRewardPerTokenPaid[account][0] = rewardData[0].rewardPerTokenStored;
            balance = balances[account].total;
        }

        supply = totalSupply;
        for (uint256 i = 1; i <= numRewards; i++) {
            rewardData[i].rewardPerTokenStored = _rewardPerToken(i, supply);
            rewardData[i].lastUpdateTime = lastTimeRewardApplicable(i);
            if (account != address(0)) {
                rewards[account][i] = _earned(account, i, balance, supply);
                userRewardPerTokenPaid[account][i] = rewardData[i].rewardPerTokenStored;
            }
        }
        _;
    }

    constructor(address _rubyToken, uint256 _maxNumRewards) public {
        require(_rubyToken != address(0), "RubyStaker: Invalid ruby token.");
        require(_maxNumRewards <= 10, "RubyStaker: Invalid maximum number of rewards.");
        rubyToken = IERC20(_rubyToken);
        // set reward data
        uint256 rubyLockedRewardsId = numRewards;
        rewardData[rubyLockedRewardsId].rewardToken = _rubyToken;
        rewardData[rubyLockedRewardsId].lastUpdateTime = block.timestamp;
        numRewards++;

        maxNumRewards = _maxNumRewards;
    }

    /* ========== ADMIN CONFIGURATION ========== */

    function setRewardMinter(address _rewardMinter) external onlyOwner {
        require(_rewardMinter != address(0), "RubyStaker: Invalid new reward minter.");
        rewardMinter = _rewardMinter;
        emit RewardMinterSet(rewardMinter);
    }

    // Add a new reward token to be distributed to stakers
    function addReward(address _rewardsToken, address _distributor) public onlyOwner {
        require(!registeredRewardTokens[_rewardsToken], "RubyStaker: Rewards token already registered.");
        require(numRewards <= maxNumRewards, "RubyStaker: Maximum number of rewards already registered.");
        registeredRewardTokens[_rewardsToken] = true;

        uint256 rewardTokenId = numRewards;
        rewardData[rewardTokenId].lastUpdateTime = block.timestamp;
        rewardData[rewardTokenId].periodFinish = block.timestamp;
        rewardData[rewardTokenId].rewardToken = _rewardsToken;
        rewardDistributors[rewardTokenId][_distributor] = true;

        numRewards++;

        emit RewardDataRegistered(_rewardsToken, _distributor);

    }

    // Modify approval for an address to call notifyRewardAmount
    function approveRewardDistributor(
        uint256 _rewardId,
        address _distributor,
        bool _approved
    ) external onlyOwner {
        require(_rewardId > 0, "RubyStaker: Invalid rewardId.");
        require(rewardData[_rewardId].lastUpdateTime > 0, "RubyStaker: Invalid reward distributor approval request");
        rewardDistributors[_rewardId][_distributor] = _approved;
        emit RewardDistributorApproved(rewardData[_rewardId].rewardToken, _distributor, _approved);

    }

    /* ========== VIEW FUNCTIONS ========== */

    function _rewardPerToken(uint256 _rewardId, uint256 _supply) internal view returns (uint256) {
        if (_supply == 0) {
            return rewardData[_rewardId].rewardPerTokenStored;
        }
        return
            rewardData[_rewardId].rewardPerTokenStored.add(
                lastTimeRewardApplicable(_rewardId)
                    .sub(rewardData[_rewardId].lastUpdateTime)
                    .mul(rewardData[_rewardId].rewardRate)
                    .mul(1e18)
                    .div(_supply)
            );
    }

    function _earned(
        address _user,
        uint256 _rewardId,
        uint256 _balance,
        uint256 supply
    ) internal view returns (uint256) {
        return
            _balance
                .mul(_rewardPerToken(_rewardId, supply).sub(userRewardPerTokenPaid[_user][_rewardId]))
                .div(1e18)
                .add(rewards[_user][_rewardId]);
    }

    function lastTimeRewardApplicable(uint256 _rewardId) public view returns (uint256) {
        return Math.min(block.timestamp, rewardData[_rewardId].periodFinish);
    }

    function rewardPerToken(uint256 _rewardId) external view returns (uint256) {
        uint256 supply = _rewardId == 0 ? lockedSupply : totalSupply;
        return _rewardPerToken(_rewardId, supply);
    }

    function getRewardForDuration(uint256 _rewardId) external view returns (uint256) {
        return rewardData[_rewardId].rewardRate.mul(rewardsDuration);
    }

    // Address and claimable amount of all reward tokens for the given account
    function claimableRewards(address account) external view returns (RewardData[] memory userRewards) {
        userRewards = new RewardData[](numRewards + 1);
        for (uint256 i = 0; i <= numRewards; i++) {
            // If i == 0 this is the stakingReward, distribution is based on locked balances
            uint256 balance = i == 0 ? balances[account].locked : balances[account].total;
            uint256 supply = i == 0 ? lockedSupply : totalSupply;
            userRewards[i].token = rewardData[i].rewardToken;
            userRewards[i].amount = _earned(account, i, balance, supply);
        }
        return userRewards;
    }

    // Total balance of an account, including unlocked, locked and earned tokens
    function totalBalance(address user) external view returns (uint256 amount) {
        return balances[user].total;
    }

    // Total withdrawable balance for an account to which no penalty is applied
    function unlockedBalance(address user) external view returns (uint256 amount) {
        amount = balances[user].unlocked;
        LockedBalance[] storage earnings = userEarnings[user];
        for (uint256 i = 0; i < earnings.length; i++) {
            if (earnings[i].unlockTime > block.timestamp) {
                break;
            }
            amount = amount.add(earnings[i].amount);
        }
        return amount;
    }

    // Information on the "earned" balances of a user
    // Earned balances may be withdrawn immediately for a 50% penalty
    function earnedBalances(address user) external view returns (uint256 total, LockedBalance[] memory earningsData) {
        LockedBalance[] storage earnings = userEarnings[user];
        uint256 idx;
        for (uint256 i = 0; i < earnings.length; i++) {
            if (earnings[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    earningsData = new LockedBalance[](earnings.length - i);
                }
                earningsData[idx] = earnings[i];
                idx++;
                total = total.add(earnings[i].amount);
            }
        }
        return (total, earningsData);
    }

    // Information on a user's locked balances
    function lockedBalances(address user)
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            LockedBalance[] memory lockData
        )
    {
        LockedBalance[] storage locks = userLocks[user];
        uint256 idx;
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    lockData = new LockedBalance[](locks.length - i);
                }
                lockData[idx] = locks[i];
                idx++;
                locked = locked.add(locks[i].amount);
            } else {
                unlockable = unlockable.add(locks[i].amount);
            }
        }
        return (balances[user].locked, unlockable, locked, lockData);
    }

    // Final balance received and penalty balance paid by user upon calling exit
    function withdrawableBalance(address user) public view returns (uint256 amount, uint256 penaltyAmount) {
        Balances storage bal = balances[user];
        if (bal.earned > 0) {
            uint256 amountWithoutPenalty;
            uint256 length = userEarnings[user].length;
            for (uint256 i = 0; i < length; i++) {
                uint256 earnedAmount = userEarnings[user][i].amount;
                if (earnedAmount == 0) continue;
                if (userEarnings[user][i].unlockTime > block.timestamp) {
                    break;
                }
                amountWithoutPenalty = amountWithoutPenalty.add(earnedAmount);
            }

            penaltyAmount = bal.earned.sub(amountWithoutPenalty).div(2);
        }
        amount = bal.unlocked.add(bal.earned).sub(penaltyAmount);
        return (amount, penaltyAmount);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // Lock tokens to receive fees from penalties
    // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
    function stake(uint256 amount, bool lock) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "RubyStaker: Invalid staking amount");
        totalSupply = totalSupply.add(amount);
        Balances storage bal = balances[msg.sender];
        bal.total = bal.total.add(amount);
        if (lock) {
            lockedSupply = lockedSupply.add(amount);
            bal.locked = bal.locked.add(amount);
            uint256 unlockTime = block.timestamp.div(rewardsDuration).mul(rewardsDuration).add(lockDuration);
            uint256 idx = userLocks[msg.sender].length;
            if (idx == 0 || userLocks[msg.sender][idx - 1].unlockTime < unlockTime) {
                userLocks[msg.sender].push(LockedBalance({ amount: amount, unlockTime: unlockTime }));
            } else {
                userLocks[msg.sender][idx - 1].amount = userLocks[msg.sender][idx - 1].amount.add(amount);
            }
        } else {
            bal.unlocked = bal.unlocked.add(amount);
        }
        rubyToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    // Mint new tokens
    // Minted tokens receive rewards normally but incur a 50% penalty when
    // withdrawn before lockDuration has passed.
    function mint(address user, uint256 amount) external override onlyRewardMinter updateReward(user) {
        totalSupply = totalSupply.add(amount);
        Balances storage bal = balances[user];
        bal.total = bal.total.add(amount);
        bal.earned = bal.earned.add(amount);
        uint256 unlockTime = block.timestamp.div(rewardsDuration).mul(rewardsDuration).add(lockDuration);
        LockedBalance[] storage earnings = userEarnings[user];
        uint256 idx = earnings.length;

        if (idx == 0 || earnings[idx - 1].unlockTime < unlockTime) {
            earnings.push(LockedBalance({ amount: amount, unlockTime: unlockTime }));
        } else {
            earnings[idx - 1].amount = earnings[idx - 1].amount.add(amount);
        }
        emit Staked(user, amount);
    }

    // Withdraw locked tokens
    // First withdraws unlocked tokens, then earned tokens. Withdrawing earned tokens
    // incurs a 50% penalty which is distributed based on locked balances.
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "RubyStaker: Invalid withdraw amount.");
        Balances storage bal = balances[msg.sender];
        uint256 penaltyAmount;

        if (amount <= bal.unlocked) {
            bal.unlocked = bal.unlocked.sub(amount);
        } else {
            uint256 remaining = amount.sub(bal.unlocked);
            require(bal.earned >= remaining, "RubyStaker: Insufficient unlocked balance");
            bal.unlocked = 0;
            bal.earned = bal.earned.sub(remaining);
            for (uint256 i = 0; ; i++) {
                uint256 earnedAmount = userEarnings[msg.sender][i].amount;
                if (earnedAmount == 0) continue;
                if (penaltyAmount == 0 && userEarnings[msg.sender][i].unlockTime > block.timestamp) {
                    penaltyAmount = remaining;
                    require(bal.earned >= remaining, "RubyStaker: Insufficient balance after penalty");
                    bal.earned = bal.earned.sub(remaining);
                    if (bal.earned == 0) {
                        delete userEarnings[msg.sender];
                        break;
                    }
                    remaining = remaining.mul(2);
                }
                if (remaining <= earnedAmount) {
                    userEarnings[msg.sender][i].amount = earnedAmount.sub(remaining);
                    break;
                } else {
                    delete userEarnings[msg.sender][i];
                    remaining = remaining.sub(earnedAmount);
                }
            }
        }

        uint256 adjustedAmount = amount.add(penaltyAmount);
        bal.total = bal.total.sub(adjustedAmount);
        totalSupply = totalSupply.sub(adjustedAmount);
        rubyToken.safeTransfer(msg.sender, amount);
        if (penaltyAmount > 0) {
            _notifyReward(0, penaltyAmount);
        }
        emit Withdrawal(msg.sender, amount);
    }

    // Claim all pending staking rewards
    function getReward() public nonReentrant updateReward(msg.sender) {
        for (uint256 i; i <= numRewards; i++) {
            address _rewardsToken = rewardData[i].rewardToken;

            uint256 reward = rewards[msg.sender][i];

            if (reward > 0) {
                rewards[msg.sender][i] = 0;
                IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, _rewardsToken, reward);
            }
        }
    }

    // Withdraw full unlocked balance and claim pending rewards
    function exit() external updateReward(msg.sender) {
        (uint256 amount, uint256 penaltyAmount) = withdrawableBalance(msg.sender);
        delete userEarnings[msg.sender];
        Balances storage bal = balances[msg.sender];
        bal.total = bal.total.sub(bal.unlocked).sub(bal.earned);
        bal.unlocked = 0;
        bal.earned = 0;

        totalSupply = totalSupply.sub(amount.add(penaltyAmount));
        rubyToken.safeTransfer(msg.sender, amount);
        if (penaltyAmount > 0) {
            _notifyReward(0, penaltyAmount);
        }
        getReward();
    }

    // Withdraw all currently locked tokens where the unlock time has passed
    function withdrawExpiredLocks() external {
        LockedBalance[] storage locks = userLocks[msg.sender];
        Balances storage bal = balances[msg.sender];
        uint256 amount;
        uint256 length = locks.length;
        if (locks[length - 1].unlockTime <= block.timestamp) {
            amount = bal.locked;
            delete userLocks[msg.sender];
        } else {
            for (uint256 i = 0; i < length; i++) {
                if (locks[i].unlockTime > block.timestamp) break;
                amount = amount.add(locks[i].amount);
                delete locks[i];
            }
        }
        bal.locked = bal.locked.sub(amount);
        bal.total = bal.total.sub(amount);
        totalSupply = totalSupply.sub(amount);
        lockedSupply = lockedSupply.sub(amount);
        rubyToken.safeTransfer(msg.sender, amount);
        emit ExpiredLocksWithdrawal(msg.sender, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function _notifyReward(uint256 _rewardId, uint256 reward) internal {
        if (block.timestamp >= rewardData[_rewardId].periodFinish) {
            rewardData[_rewardId].rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = rewardData[_rewardId].periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardData[_rewardId].rewardRate);
            rewardData[_rewardId].rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        rewardData[_rewardId].lastUpdateTime = block.timestamp;
        rewardData[_rewardId].periodFinish = block.timestamp.add(rewardsDuration);
    }

    function notifyRewardAmount(uint256 rewardId, uint256 reward)
        external
        override
        onlyRewardDistributor(rewardId)
        updateReward(address(0))
    {
        require(reward > 0, "RubyStaking: No reward.");
        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        address rewardToken = rewardData[rewardId].rewardToken;
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), reward);

        // Staking rewards
        _notifyReward(rewardId, reward);
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(rubyToken), "RubyStaker: Cannot withdraw staking token");
        require(!registeredRewardTokens[tokenAddress], "RubyStaker: Cannot withdraw reward token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
