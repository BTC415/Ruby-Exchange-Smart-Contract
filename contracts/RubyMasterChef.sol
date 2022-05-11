// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRubyMasterChefRewarder.sol";
import "./interfaces/IRubyMasterChef.sol";
import "./interfaces/IRubyStaker.sol";
import "./token_mappings/RubyToken.sol";
import "./libraries/BoringERC20.sol";

// MasterChef copied from https://github.com/traderjoe-xyz/joe-core/blob/main/contracts/MasterChefJoeV2.sol
// Combines single and double rewards
contract RubyMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. , any point in time, the amount of RUBYs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRubyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRubyPerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. RUBYs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that RUBYs distribution occurs.
        uint256 accRubyPerShare; // Accumulated RUBYs per share, times 1e12. See below.
        IRubyMasterChefRewarder rewarder;
    }

    // The RUBY TOKEN!
    IERC20 public immutable RUBY;

    IRubyStaker public rubyStaker;

    // Treasury address.
    address public treasuryAddr;
    // RUBY tokens created per second.
    uint256 public rubyPerSec;
    // Percentage of pool rewards that goes to the treasury.
    uint256 public treasuryPercent;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    // The timestamp when RUBY mining starts.
    uint256 public startTimestamp;

    event AddPool(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken,
        IRubyMasterChefRewarder indexed rewarder
    );
    event SetPool(uint256 indexed pid, uint256 allocPoint, IRubyMasterChefRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accRubyPerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event MultiHarvest(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetTreasuryAddress(address indexed oldAddress, address indexed newAddress);
    event SetTreasuryPercent(uint256 newPercent);
    event SetRubyStaker(address indexed newRubyStaker);
    event UpdateEmissionRate(address indexed user, uint256 _rubyPerSec);
    event RubyTokenEmergencyWithdrawal(address indexed to, uint256 amount);

    constructor(
        address _ruby,
        address _rubyStaker,
        address _treasuryAddr,
        uint256 _rubyPerSec,
        uint256 _startTimestamp,
        uint256 _treasuryPercent
    ) public {
        require(_ruby != address(0), "RubyMasterChef: Invalid RubyToken address.");
        require(_rubyStaker != address(0), "RubyMasterChef: Invalid RubyStaker address.");
        require(_treasuryAddr != address(0), "RubyMasterChef: Invalid treasury address.");
        require(_rubyPerSec != 0, "RubyMasterChef: Invalid emission rate amount.");
        require(0 <= _treasuryPercent && _treasuryPercent <= 1000, "RubyMasterChef: invalid treasury percent value.");

        RUBY = IERC20(_ruby);
        rubyStaker = IRubyStaker(_rubyStaker);
        treasuryAddr = _treasuryAddr;
        rubyPerSec = _rubyPerSec;
        startTimestamp = _startTimestamp;
        treasuryPercent = _treasuryPercent;
        totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRubyMasterChefRewarder _rewarder
    ) public onlyOwner {
        require(Address.isContract(address(_lpToken)), "add: LP token must be a valid contract");
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "add: rewarder must be contract or zero"
        );
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accRubyPerShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit AddPool(poolInfo.length.sub(1), _allocPoint, _lpToken, _rewarder);
    }

    // Update the given pool's RUBY allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRubyMasterChefRewarder _rewarder,
        bool overwrite
    ) public onlyOwner {
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "set: rewarder must be contract or zero"
        );
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) {
            poolInfo[_pid].rewarder = _rewarder;
        }
        emit SetPool(_pid, _allocPoint, overwrite ? _rewarder : poolInfo[_pid].rewarder, overwrite);
    }

    // View function to see pending RUBYs on frontend.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingRuby,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRubyPerShare = pool.accRubyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 lpPercent = 1000 - treasuryPercent;
            uint256 rubyReward = multiplier
                .mul(rubyPerSec)
                .mul(pool.allocPoint)
                .div(totalAllocPoint)
                .mul(lpPercent)
                .div(1000);
            accRubyPerShare = accRubyPerShare.add(rubyReward.mul(ACC_TOKEN_PRECISION).div(lpSupply));
        }
        pendingRuby = user.amount.mul(accRubyPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddress, bonusTokenSymbol) = rewarderBonusTokenInfo(_pid);
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    // Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    function rewarderBonusTokenInfo(uint256 _pid)
        public
        view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol)
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20(pool.rewarder.rewardToken()).safeSymbol();
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
        uint256 rewardAmount = multiplier.mul(rubyPerSec).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 lpPercent = 1000 - treasuryPercent;

        RUBY.safeTransfer(treasuryAddr, rewardAmount.mul(treasuryPercent).div(1000));

        pool.accRubyPerShare = pool.accRubyPerShare.add(
            rewardAmount.mul(ACC_TOKEN_PRECISION).div(lpSupply).mul(lpPercent).div(1000)
        );
        pool.lastRewardTimestamp = block.timestamp;
        emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accRubyPerShare);
    }

    // Deposit LP tokens to MasterChef for RUBY allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            // Harvest accRubyPerShare
            uint256 pending = user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);
            _mintRubyRewards(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION);

        IRubyMasterChefRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onRubyReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        // Harvest RUBY
        uint256 pending = user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);
        if (pending > 0) {
            _mintRubyRewards(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION);

        IRubyMasterChefRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onRubyReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claim(uint256[] calldata _pids) external {
        massUpdatePools();
        uint256 pending;
        for (uint256 i = 0; i < _pids.length; i++) {
            PoolInfo storage pool = poolInfo[_pids[i]];
            UserInfo storage user = userInfo[_pids[i]][msg.sender];
            pending = pending.add(user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt));
            user.rewardDebt = user.amount.mul(pool.accRubyPerShare).div(ACC_TOKEN_PRECISION);
        }
        if (pending > 0) {
            _mintRubyRewards(msg.sender, pending);
        }
        emit MultiHarvest(msg.sender, pending);
    }

    // Mint ruby rewards and transfers toekns to rubyStaker
    function _mintRubyRewards(address _account, uint256 _amount) internal {
        rubyStaker.mint(_account, _amount);
        RUBY.safeTransfer(address(rubyStaker), _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Update treasury address by the previous treasury.
    function setTreasuryAddr(address _treasuryAddr) public {
        require(msg.sender == treasuryAddr, "setTreasuryAddr: not enough permissions to execute this action");
        treasuryAddr = _treasuryAddr;
        emit SetTreasuryAddress(msg.sender, _treasuryAddr);
    }

    function setTreasuryPercent(uint256 _newTreasuryPercent) public onlyOwner {
        require(0 <= _newTreasuryPercent && _newTreasuryPercent <= 1000, "setTreasuryPercent: invalid percent value");
        treasuryPercent = _newTreasuryPercent;
        emit SetTreasuryPercent(_newTreasuryPercent);
    }

    function setRubyStaker(address _newRubyStaker) public onlyOwner {
        require(_newRubyStaker != address(0), "setRubyStaker: invalid ruby minter address");
        rubyStaker = IRubyStaker(_newRubyStaker);
        emit SetRubyStaker(_newRubyStaker);
    }

    function updateEmissionRate(uint256 _rubyPerSec) public onlyOwner {
        massUpdatePools();
        rubyPerSec = _rubyPerSec;
        emit UpdateEmissionRate(msg.sender, _rubyPerSec);
    }

    /**
     * @notice Owner should be able to withdraw all the Reward tokens in case of emergency.
     * The owner should be able to withdraw the tokens to himself or another address
     * The RubyMasterChef contract will be placed behind a timelock, and the owner/deployer will be a multisig,
     * so this should not raise trust concerns.
     * This function is needed because the RubyMasterChef will be pre-fed with all of the
     * reward tokens (RUBY) tokens dedicated for liquidity mining incentives, and in case
     * of unfortunate situation they should be retreived.
     */
    function emergencyWithdrawRubyTokens(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "RubyMasterChef: Invalid withdrawal address.");
        require(_amount != 0, "RubyMasterChef: Invalid withdrawal amount.");
        require(RUBY.balanceOf(address(this)) >= _amount, "RubyMasterChef: Not enough balance to withdraw.");
        RUBY.safeTransfer(_receiver, _amount);
        emit RubyTokenEmergencyWithdrawal(_receiver, _amount);
    }
}
