// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {SushiFlush} from "./SushiFlush.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Test} from "forge-std/Test.sol";

contract SushiFlushTest is Test {
  SushiFlush token;

  // The test contract deploys the token, so it is the deployer and holds
  // the entire initial supply.
  address deployer = address(this);
  address alice = makeAddr("alice");
  address bob = makeAddr("bob");

  uint256 constant TOTAL_SUPPLY = 1_000_000 * 10 ** 18;

  function setUp() public {
    token = new SushiFlush();
  }

  function test_Metadata() public view {
    require(
      keccak256(bytes(token.name())) == keccak256("SushiFlush"),
      "Name should be SushiFlush"
    );
    require(
      keccak256(bytes(token.symbol())) == keccak256("SFLUSH"),
      "Symbol should be SFLUSH"
    );
    require(token.decimals() == 18, "Decimals should be 18");
  }

  function test_MintsFullSupplyToDeployer() public view {
    assertEq(token.totalSupply(), TOTAL_SUPPLY);
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);
  }

  function test_Transfer() public {
    token.transfer(alice, 100e18);

    assertEq(token.balanceOf(alice), 100e18);
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY - 100e18);
    assertEq(token.totalSupply(), TOTAL_SUPPLY);
  }

  function test_TransferRevertsOnInsufficientBalance() public {
    // alice holds nothing, so any transfer from her must revert.
    vm.prank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientBalance.selector,
        alice,
        0,
        1
      )
    );
    token.transfer(bob, 1);
  }

  function test_TransferRevertsOnZeroAddress() public {
    vm.expectRevert(
      abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
    );
    token.transfer(address(0), 1);
  }

  function test_ApproveAndTransferFrom() public {
    token.approve(alice, 500e18);
    assertEq(token.allowance(deployer, alice), 500e18);

    // alice spends part of her allowance on the deployer's behalf.
    vm.prank(alice);
    token.transferFrom(deployer, bob, 200e18);

    assertEq(token.balanceOf(bob), 200e18);
    assertEq(token.allowance(deployer, alice), 300e18);
  }

  function test_TransferFromRevertsBeyondAllowance() public {
    token.approve(alice, 100e18);

    vm.prank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        alice,
        100e18,
        101e18
      )
    );
    token.transferFrom(deployer, bob, 101e18);
  }

  // Supply is fixed at deployment: no amount of moving tokens around
  // should ever change totalSupply.
  function testFuzz_TransferPreservesTotalSupply(uint256 amount) public {
    amount = bound(amount, 0, TOTAL_SUPPLY);

    token.transfer(alice, amount);

    assertEq(token.balanceOf(alice), amount);
    assertEq(token.balanceOf(deployer), TOTAL_SUPPLY - amount);
    assertEq(token.totalSupply(), TOTAL_SUPPLY);
  }
}
