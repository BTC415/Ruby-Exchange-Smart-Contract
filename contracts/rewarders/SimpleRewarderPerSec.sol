// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@boringcrypto/boring-solidity/contracts/BoringOwnable.sol";
import "../interfaces/IRubyMasterChefRewarder.sol";
import "../interfaces/IRubyMasterChef.sol";
import "../libraries/SafeERC20.sol";

/**
 * This is a sample contract to be used in the RubyMasterChef contract for partners to reward
 * stakers with their native token alongside RUBY.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the RUBY-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the rewards accordingly so it's fully distributed after 30 days.
 *
 */
contract SimpleRewarderPerSec is IRubyMasterChefRewarder, BoringOwnable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable override rewardToken;
    IERC20 public immutable lpToken;
    IRubyMasterChef public immutable rubyMasterChef;

    /// @notice Info of each rubyMasterChef user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    /// @notice Info of each rubyMasterChef poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public tokenPerSec;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyRubyMasterChef() {
        require(
            msg.sender == address(rubyMasterChef),
            "onlyRubyMasterChef: only RubyMasterChef can call this function"
        );
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint256 _tokenPerSec,
        IRubyMasterChef _rubyMasterChef
    ) public {
        require(Address.isContract(address(_rewardToken)), "constructor: reward token must be a valid contract");
        require(Address.isContract(address(_lpToken)), "constructor: LP token must be a valid contract");
        require(Address.isContract(address(_rubyMasterChef)), "constructor: RubyMasterChef must be a valid contract");

        rewardToken = _rewardToken;
        lpToken = _lpToken;
        tokenPerSec = _tokenPerSec;
        rubyMasterChef = _rubyMasterChef;
        poolInfo = PoolInfo({ lastRewardTimestamp: block.timestamp, accTokenPerShare: 0 });
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = lpToken.balanceOf(address(rubyMasterChef));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
                uint256 tokenReward = timeElapsed.mul(tokenPerSec);
                pool.accTokenPerShare = pool.accTokenPerShare.add((tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply));
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Function called by RubyMasterChef whenever staker claims Ruby harvest. 
    /// Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onRubyReward(address _user, uint256 _lpAmount) external override onlyRubyMasterChef {
        updatePool();
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        // if user had deposited
        if (user.amount > 0) {
            pending = (user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt);
            uint256 balance = rewardToken.balanceOf(address(this));
            if (pending > balance) {
                rewardToken.safeTransfer(_user, balance);
            } else {
                rewardToken.safeTransfer(_user, pending);
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION;

        emit OnReward(_user, pending);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = poolInfo.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(rubyMasterChef));

        if (block.timestamp > poolInfo.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp.sub(poolInfo.lastRewardTimestamp);
            uint256 tokenReward = timeElapsed.mul(tokenPerSec);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply);
        }

        pending = (user.amount.mul(accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt);
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
    }
}
