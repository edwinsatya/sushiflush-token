import { network } from "hardhat";
import { formatUnits, parseUnits } from "viem";

/// Deployed on Sepolia. See README.
const TOKEN = "0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12";
const STAKING = "0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094";

const REWARD = parseUnits("10000", 18); // SFLUSH streamed as rewards
const STAKE = parseUnits("1000", 18); // SFLUSH staked
const DURATION = 604800n; // 7 days, in seconds

const fmt = (v: bigint) => `${formatUnits(v, 18)} SFLUSH`;

const { viem } = await network.create();
const publicClient = await viem.getPublicClient();
const [wallet] = await viem.getWalletClients();
const me = wallet.account.address;

const token = await viem.getContractAt("SushiFlush", TOKEN);
const staking = await viem.getContractAt("SushiFlushStaking", STAKING);

/**
 * Gas estimates are taken against current state, but the transaction executes
 * against whatever state exists when it is mined. A storage slot that was zero
 * at estimation time but non-zero at execution costs 20,000 gas more, which is
 * enough to run a tightly-estimated transaction out of gas. Pad every estimate.
 */
function withBuffer(estimate: bigint) {
  return (estimate * 130n) / 100n;
}

/** Send a write, wait for it to be mined, and fail loudly if it reverted. */
async function send(label: string, hash: `0x${string}`) {
  console.log(`   tx ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    throw new Error(`${label} reverted in block ${receipt.blockNumber}`);
  }
  console.log(`   mined in block ${receipt.blockNumber} (gas ${receipt.gasUsed})\n`);
}

console.log(`account      ${me}`);
console.log(`token        ${TOKEN}`);
console.log(`staking      ${STAKING}\n`);

const owner = await staking.read.owner();
if (owner.toLowerCase() !== me.toLowerCase()) {
  throw new Error(`not the staking owner: contract owner is ${owner}`);
}

const balance = await token.read.balanceOf([me]);
console.log(`SFLUSH balance ${fmt(balance)}`);
if (balance < REWARD + STAKE) {
  throw new Error(`need ${fmt(REWARD + STAKE)}, have ${fmt(balance)}`);
}

// Decide up front whether a reward period still needs funding, so the approval
// covers exactly the transfers that will actually happen.
const periodFinish = await staking.read.periodFinish();
const now = BigInt(Math.floor(Date.now() / 1000));
const willNotify = periodFinish <= now;

const needed = (willNotify ? REWARD : 0n) + STAKE;

// 1. Approve the staking contract to pull what the remaining steps require.
const allowance = await token.read.allowance([me, STAKING]);
if (allowance < needed) {
  console.log(`\n1. approve ${fmt(needed)}`);
  const gas = withBuffer(
    await publicClient.estimateContractGas({
      address: TOKEN,
      abi: token.abi,
      functionName: "approve",
      args: [STAKING, needed],
      account: me,
    }),
  );
  await send("approve", await token.write.approve([STAKING, needed], { gas }));
} else {
  console.log(`\n1. approve — allowance ${fmt(allowance)} already covers ${fmt(needed)}, skipping\n`);
}

// 2. Fund a reward period. Owner-only.
if (!willNotify) {
  console.log(`2. notifyRewardAmount — period already active until ${periodFinish}, skipping\n`);
} else {
  console.log(`2. notifyRewardAmount ${fmt(REWARD)} over ${DURATION}s`);
  const gas = withBuffer(
    await publicClient.estimateContractGas({
      address: STAKING,
      abi: staking.abi,
      functionName: "notifyRewardAmount",
      args: [REWARD, DURATION],
      account: me,
    }),
  );
  await send(
    "notifyRewardAmount",
    await staking.write.notifyRewardAmount([REWARD, DURATION], { gas }),
  );
}

// 3. Stake.
console.log(`3. stake ${fmt(STAKE)}`);
const stakeGas = withBuffer(
  await publicClient.estimateContractGas({
    address: STAKING,
    abi: staking.abi,
    functionName: "stake",
    args: [STAKE],
    account: me,
  }),
);
await send("stake", await staking.write.stake([STAKE], { gas: stakeGas }));

// Report resulting on-chain state.
const [staked, total, rate, finish, earned] = await Promise.all([
  staking.read.balanceOf([me]),
  staking.read.totalStaked(),
  staking.read.rewardRate(),
  staking.read.periodFinish(),
  staking.read.earned([me]),
]);

console.log("--- state ---");
console.log(`your stake     ${fmt(staked)}`);
console.log(`total staked   ${fmt(total)}`);
console.log(`reward rate    ${formatUnits(rate, 18)} SFLUSH/sec`);
console.log(`period ends    ${new Date(Number(finish) * 1000).toISOString()}`);
console.log(`earned so far  ${fmt(earned)}`);
