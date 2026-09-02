// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {SushiFlush} from "./SushiFlush.sol";
import {SushiFlushStaking} from "./SushiFlushStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

contract SushiFlushStakingTest is Test {
  SushiFlush token;
  SushiFlushStaking staking;

  // The test contract deploys everything, so it holds the full supply and
  // owns the staking contract (it is the reward funder).
  address owner = address(this);
  address alice = makeAddr("alice");
  address bob = makeAddr("bob");

  uint256 constant STAKE = 1_000e18;
  uint256 constant REWARD = 100e18;
  uint256 constant DURATION = 100; // seconds, so rewardRate is exactly 1e18/s

  uint256 start;

  function setUp() public {
    token = new SushiFlush();
    staking = new SushiFlushStaking(IERC20(address(token)), owner);

    token.transfer(alice, 10_000e18);
    token.transfer(bob, 10_000e18);

    vm.prank(alice);
    token.approve(address(staking), type(uint256).max);
    vm.prank(bob);
    token.approve(address(staking), type(uint256).max);
    token.approve(address(staking), type(uint256).max);

    start = block.timestamp;
  }

  function _fund() internal {
    staking.notifyRewardAmount(REWARD, DURATION);
  }

  // --- staking mechanics -------------------------------------------------

  function test_StakeUpdatesBalances() public {
    vm.prank(alice);
    staking.stake(STAKE);

    assertEq(staking.balanceOf(alice), STAKE);
    assertEq(staking.totalStaked(), STAKE);
    assertEq(token.balanceOf(address(staking)), STAKE);
  }

  function test_StakeZeroReverts() public {
    vm.prank(alice);
    vm.expectRevert(SushiFlushStaking.ZeroAmount.selector);
    staking.stake(0);
  }

  function test_WithdrawMoreThanStakedReverts() public {
    vm.prank(alice);
    staking.stake(STAKE);

    vm.prank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(SushiFlushStaking.InsufficientStake.selector, STAKE, STAKE + 1)
    );
    staking.withdraw(STAKE + 1);
  }

  function test_WithdrawReturnsPrincipal() public {
    uint256 before = token.balanceOf(alice);

    vm.prank(alice);
    staking.stake(STAKE);
    vm.prank(alice);
    staking.withdraw(STAKE);

    assertEq(token.balanceOf(alice), before);
    assertEq(staking.totalStaked(), 0);
  }

  // --- reward accrual ----------------------------------------------------

  function test_SingleStakerEarnsFullReward() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION);

    assertApproxEqAbs(staking.earned(alice), REWARD, 1e6);
  }

  function test_TwoEqualStakersSplitEvenly() public {
    vm.prank(alice);
    staking.stake(STAKE);
    vm.prank(bob);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION);

    assertApproxEqAbs(staking.earned(alice), REWARD / 2, 1e6);
    assertApproxEqAbs(staking.earned(bob), REWARD / 2, 1e6);
  }

  /// Alice stakes for the whole period, Bob joins at the halfway point with an
  /// equal stake. Alice should earn the first half alone, then split the second.
  function test_LateStakerEarnsProportionally() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION / 2);
    vm.prank(bob);
    staking.stake(STAKE);

    vm.warp(start + DURATION);

    // alice: 50 (alone) + 25 (half of second half) = 75
    assertApproxEqAbs(staking.earned(alice), 75e18, 1e6);
    assertApproxEqAbs(staking.earned(bob), 25e18, 1e6);
  }

  function test_RewardsStopAtPeriodFinish() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION);
    uint256 atFinish = staking.earned(alice);

    vm.warp(start + DURATION * 10);
    assertEq(staking.earned(alice), atFinish, "rewards accrued past periodFinish");
  }

  function test_NoRewardsAccrueWithNothingStaked() public {
    _fund();
    vm.warp(start + DURATION);

    // Alice stakes only after the period ended; she earns nothing.
    vm.prank(alice);
    staking.stake(STAKE);
    vm.warp(start + DURATION * 2);

    assertEq(staking.earned(alice), 0);
  }

  // --- claiming ----------------------------------------------------------

  function test_GetRewardTransfersTokens() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();
    vm.warp(start + DURATION);

    uint256 before = token.balanceOf(alice);
    uint256 owed = staking.earned(alice);

    vm.prank(alice);
    staking.getReward();

    assertEq(token.balanceOf(alice), before + owed);
    assertEq(staking.earned(alice), 0);
  }

  function test_ExitReturnsPrincipalAndReward() public {
    uint256 before = token.balanceOf(alice);

    vm.prank(alice);
    staking.stake(STAKE);
    _fund();
    vm.warp(start + DURATION);

    vm.prank(alice);
    staking.exit();

    assertEq(staking.balanceOf(alice), 0);
    assertEq(staking.earned(alice), 0);
    assertApproxEqAbs(token.balanceOf(alice), before + REWARD, 1e6);
  }

  // --- funding -----------------------------------------------------------

  function test_NotifyOnlyOwner() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    staking.notifyRewardAmount(REWARD, DURATION);
  }

  function test_NotifyZeroAmountReverts() public {
    vm.expectRevert(SushiFlushStaking.ZeroAmount.selector);
    staking.notifyRewardAmount(0, DURATION);
  }

  function test_NotifyZeroDurationReverts() public {
    vm.expectRevert(SushiFlushStaking.ZeroDuration.selector);
    staking.notifyRewardAmount(REWARD, 0);
  }

  /// Topping up mid-period must fold the unvested remainder into the new rate
  /// rather than discarding it.
  function test_TopUpMidPeriodRollsOverLeftover() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION / 2); // 50 distributed, 50 unvested
    staking.notifyRewardAmount(REWARD, DURATION);

    // 50 leftover + 100 new = 150 over the next DURATION seconds.
    vm.warp(start + DURATION / 2 + DURATION);

    assertApproxEqAbs(staking.earned(alice), 50e18 + 150e18, 1e6);
  }

  /// Staked principal must stay withdrawable in full even after every reward
  /// has been claimed, which is what ring-fencing `totalStaked` guarantees.
  function test_PrincipalSurvivesFullRewardClaim() public {
    uint256 aliceBefore = token.balanceOf(alice);
    uint256 bobBefore = token.balanceOf(bob);

    vm.prank(alice);
    staking.stake(STAKE);
    vm.prank(bob);
    staking.stake(STAKE);
    _fund();

    vm.warp(start + DURATION);

    // Both drain their rewards first.
    vm.prank(alice);
    staking.getReward();
    vm.prank(bob);
    staking.getReward();

    // Principal must still be fully withdrawable for both.
    vm.prank(alice);
    staking.withdraw(STAKE);
    vm.prank(bob);
    staking.withdraw(STAKE);

    assertEq(staking.totalStaked(), 0);
    assertGe(token.balanceOf(alice), aliceBefore, "alice lost principal");
    assertGe(token.balanceOf(bob), bobBefore, "bob lost principal");
    assertApproxEqAbs(token.balanceOf(alice), aliceBefore + REWARD / 2, 1e6);
  }

  function test_WithdrawZeroReverts() public {
    vm.prank(alice);
    staking.stake(STAKE);

    vm.prank(alice);
    vm.expectRevert(SushiFlushStaking.ZeroAmount.selector);
    staking.withdraw(0);
  }

  function test_GetRewardWithNothingEarnedIsNoop() public {
    uint256 before = token.balanceOf(alice);

    vm.prank(alice);
    staking.getReward();

    assertEq(token.balanceOf(alice), before);
  }

  function test_RemainingRewardTracksStream() public {
    vm.prank(alice);
    staking.stake(STAKE);
    _fund();

    assertApproxEqAbs(staking.remainingReward(), REWARD, 1e6);

    vm.warp(start + DURATION / 2);
    assertApproxEqAbs(staking.remainingReward(), REWARD / 2, 1e6);

    vm.warp(start + DURATION);
    assertEq(staking.remainingReward(), 0);
  }

  // --- solvency invariant ------------------------------------------------

  /// The contract must never owe more than it holds: staked principal plus
  /// outstanding rewards can never exceed its token balance.
  function testFuzz_NeverPaysOutMoreThanFunded(uint96 aliceStake, uint96 bobStake, uint32 elapsed)
    public
  {
    uint256 a = bound(aliceStake, 1e18, 5_000e18);
    uint256 b = bound(bobStake, 1e18, 5_000e18);
    uint256 t = bound(elapsed, 0, DURATION * 3);

    vm.prank(alice);
    staking.stake(a);
    vm.prank(bob);
    staking.stake(b);
    _fund();

    vm.warp(start + t);

    uint256 owed = staking.totalStaked() + staking.earned(alice) + staking.earned(bob);
    assertLe(owed, token.balanceOf(address(staking)), "contract owes more than it holds");
  }
}
