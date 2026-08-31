import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, parseUnits } from "viem";

const TOTAL_SUPPLY = parseUnits("1000000", 18);

describe("SushiFlush", async function () {
  const { viem, networkHelpers } = await network.create();

  // loadFixture snapshots the chain after this runs, so later tests restore
  // the snapshot instead of redeploying. Must be a named function.
  async function deploySushiFlush() {
    const [deployer, alice, bob] = await viem.getWalletClients();
    const token = await viem.deployContract("SushiFlush");

    return { token, deployer, alice, bob };
  }

  it("exposes the expected metadata", async function () {
    const { token } = await networkHelpers.loadFixture(deploySushiFlush);

    assert.equal(await token.read.name(), "SushiFlush");
    assert.equal(await token.read.symbol(), "SFLUSH");
    assert.equal(await token.read.decimals(), 18);
  });

  it("mints the full supply to the deployer", async function () {
    const { token, deployer } = await networkHelpers.loadFixture(deploySushiFlush);

    assert.equal(await token.read.totalSupply(), TOTAL_SUPPLY);
    assert.equal(
      await token.read.balanceOf([deployer.account.address]),
      TOTAL_SUPPLY,
    );
  });

  it("emits a Transfer event when tokens move", async function () {
    const { token, deployer, alice } =
      await networkHelpers.loadFixture(deploySushiFlush);
    const amount = parseUnits("100", 18);

    await viem.assertions.emitWithArgs(
      token.write.transfer([alice.account.address, amount]),
      token,
      "Transfer",
      [
        getAddress(deployer.account.address),
        getAddress(alice.account.address),
        amount,
      ],
    );

    assert.equal(await token.read.balanceOf([alice.account.address]), amount);
  });

  it("lets a spender move tokens via approve + transferFrom", async function () {
    const { token, deployer, alice, bob } =
      await networkHelpers.loadFixture(deploySushiFlush);
    const allowance = parseUnits("500", 18);
    const spend = parseUnits("200", 18);

    await token.write.approve([alice.account.address, allowance]);

    // alice sends the transaction, moving the deployer's tokens to bob.
    await token.write.transferFrom(
      [deployer.account.address, bob.account.address, spend],
      { account: alice.account },
    );

    assert.equal(await token.read.balanceOf([bob.account.address]), spend);
    assert.equal(
      await token.read.allowance([deployer.account.address, alice.account.address]),
      allowance - spend,
    );
  });

  it("reverts when the sender has no balance", async function () {
    const { token, alice, bob } =
      await networkHelpers.loadFixture(deploySushiFlush);

    await viem.assertions.revertWithCustomErrorWithArgs(
      token.write.transfer([bob.account.address, 1n], { account: alice.account }),
      token,
      "ERC20InsufficientBalance",
      [getAddress(alice.account.address), 0n, 1n],
    );
  });
});
