// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SushiFlushStaking
/// @notice Stake SFLUSH to earn SFLUSH. Rewards are funded by the owner and
///         stream linearly to stakers over a fixed duration, split in
///         proportion to each staker's share of the pool.
/// @dev Implements the Synthetix `StakingRewards` accumulator: rewards are
///      tracked with a single global `rewardPerTokenStored` running total, so
///      every operation is O(1) no matter how many stakers exist. Looping over
///      stakers would eventually exceed the block gas limit and brick the
///      contract, so no loop is ever used.
contract SushiFlushStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Fixed-point scale for `rewardPerToken` accounting.
    uint256 private constant PRECISION = 1e18;

    /// @notice The token that is both staked and paid out as rewards.
    IERC20 public immutable stakingToken;

    /// @notice Reward tokens distributed per second during an active period.
    uint256 public rewardRate;

    /// @notice Timestamp at which the current reward period ends.
    uint256 public periodFinish;

    /// @notice Last time reward accounting was brought up to date.
    uint256 public lastUpdateTime;

    /// @notice Accumulated reward per staked token, scaled by PRECISION.
    uint256 public rewardPerTokenStored;

    /// @notice Total tokens staked. Tracked separately from the contract's
    ///         balance because stake and reward are the same token: without
    ///         this, staked principal could be paid out as rewards.
    uint256 public totalStaked;

    /// @notice Each account's staked balance.
    mapping(address account => uint256 amount) public balanceOf;

    /// @notice `rewardPerTokenStored` at each account's last interaction.
    mapping(address account => uint256 checkpoint) public userRewardPerTokenPaid;

    /// @notice Rewards already accrued and owed to each account.
    mapping(address account => uint256 amount) public rewards;

    event Staked(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardPaid(address indexed account, uint256 reward);
    event RewardAdded(uint256 reward, uint256 duration, uint256 rewardRate, uint256 periodFinish);

    error ZeroAmount();
    error ZeroDuration();
    error InsufficientStake(uint256 staked, uint256 requested);
    error InsufficientRewardBalance(uint256 available, uint256 required);

    /// @param stakingToken_ The ERC-20 staked and paid out (SushiFlush).
    /// @param initialOwner  Account allowed to fund reward periods.
    constructor(IERC20 stakingToken_, address initialOwner) Ownable(initialOwner) {
        stakingToken = stakingToken_;
    }

    /// @dev Settles global reward accounting, then the caller's share of it.
    ///      Every state-changing entry point uses this so an account's owed
    ///      rewards are banked before its stake changes.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice The later of now and the end of the reward period, so rewards
    ///         stop accruing once the period is over.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Cumulative reward owed per token staked, scaled by PRECISION.
    /// @dev Grows by (elapsed * rewardRate) spread across the staked pool. When
    ///      nothing is staked it does not grow at all, so rewards for an empty
    ///      pool are not lost, just not yet distributed.
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalStaked;
    }

    /// @notice Rewards `account` can currently claim.
    /// @dev The difference between the global accumulator and the account's
    ///      checkpoint is exactly what accrued while it was staked.
    function earned(address account) public view returns (uint256) {
        uint256 delta = rewardPerToken() - userRewardPerTokenPaid[account];
        return rewards[account] + (balanceOf[account] * delta) / PRECISION;
    }

    /// @notice Total rewards payable across the remainder of the current period.
    function remainingReward() public view returns (uint256) {
        if (block.timestamp >= periodFinish) {
            return 0;
        }
        return (periodFinish - block.timestamp) * rewardRate;
    }

    /// @notice Stake `amount` tokens. Requires prior `approve`.
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        // Measure what actually arrived rather than trusting `amount`, so a
        // fee-on-transfer token cannot credit more than the contract received.
        uint256 before = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = stakingToken.balanceOf(address(this)) - before;

        totalStaked += received;
        balanceOf[msg.sender] += received;

        emit Staked(msg.sender, received);
    }

    /// @notice Withdraw `amount` of staked tokens, leaving rewards unclaimed.
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        uint256 staked = balanceOf[msg.sender];
        if (amount > staked) revert InsufficientStake(staked, amount);

        // Effects before interaction.
        totalStaked -= amount;
        balanceOf[msg.sender] = staked - amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim accrued rewards without touching the staked balance.
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) {
            return;
        }

        rewards[msg.sender] = 0;
        stakingToken.safeTransfer(msg.sender, reward);

        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Withdraw the full stake and claim rewards in one transaction.
    function exit() external {
        uint256 staked = balanceOf[msg.sender];
        if (staked > 0) {
            withdraw(staked);
        }
        getReward();
    }

    /// @notice Owner: fund `reward` tokens and stream them over `duration`.
    /// @dev Unvested rewards from an in-flight period are folded into the new
    ///      rate, so topping up mid-period never strands value.
    function notifyRewardAmount(uint256 reward, uint256 duration)
        external
        onlyOwner
        nonReentrant
        updateReward(address(0))
    {
        if (reward == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();

        uint256 before = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), reward);
        uint256 received = stakingToken.balanceOf(address(this)) - before;

        if (block.timestamp >= periodFinish) {
            rewardRate = received / duration;
        } else {
            uint256 leftover = (periodFinish - block.timestamp) * rewardRate;
            rewardRate = (received + leftover) / duration;
        }

        // Guard against promising more than the contract can pay. Staked
        // principal is excluded, so rewards can never be funded out of it.
        uint256 available = stakingToken.balanceOf(address(this)) - totalStaked;
        uint256 required = rewardRate * duration;
        if (required > available) revert InsufficientRewardBalance(available, required);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;

        emit RewardAdded(received, duration, rewardRate, periodFinish);
    }
}
