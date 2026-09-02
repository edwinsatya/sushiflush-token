# SushiFlush (SFLUSH)

> **Testnet learning project.** A personal project for learning Solidity and the
> EVM. Nothing here is audited, none of it has been deployed to mainnet, and none
> of it is intended to be. The token has no value.

A fixed-supply ERC-20 token and a staking contract that pays rewards in that same
token, built with [Hardhat 3](https://hardhat.org/),
[OpenZeppelin Contracts](https://www.openzeppelin.com/contracts), TypeScript and
[viem](https://viem.sh/).

## Deployed on Sepolia

| Contract | Address | Verified |
| --- | --- | --- |
| `SushiFlush` | [`0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12`](https://sepolia.etherscan.io/address/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12#code) | [Etherscan](https://sepolia.etherscan.io/address/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12#code) · [Blockscout](https://eth-sepolia.blockscout.com/address/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12#code) · [Sourcify](https://sourcify.dev/server/repo-ui/11155111/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12) |
| `SushiFlushStaking` | [`0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094`](https://sepolia.etherscan.io/address/0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094#code) | [Etherscan](https://sepolia.etherscan.io/address/0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094#code) · [Blockscout](https://eth-sepolia.blockscout.com/address/0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094#code) · [Sourcify](https://sourcify.dev/server/repo-ui/11155111/0x9aBB85C136FE4F7bd827d7957f91D5A80C65c094) |

Chain ID `11155111`. The full 1,000,000 SFLUSH supply was minted to the deploying
account at construction.

## The token

[`contracts/SushiFlush.sol`](contracts/SushiFlush.sol) mints the entire supply to
the deployer in its constructor and does nothing else.

| | |
| --- | --- |
| Name | SushiFlush |
| Symbol | SFLUSH |
| Decimals | 18 |
| Total supply | 1,000,000 SFLUSH (fixed) |

There is no `mint()` and no `Ownable`. `_mint` is called once, from the
constructor, so supply is fixed permanently at deployment and the deployer holds
no special privileges afterwards.

## The staking contract

[`contracts/SushiFlushStaking.sol`](contracts/SushiFlushStaking.sol) lets holders
stake SFLUSH and earn SFLUSH. The owner funds a reward pool that streams to
stakers linearly over a fixed duration, split in proportion to each staker's
share of the pool.

| Function | Who | What it does |
| --- | --- | --- |
| `stake(amount)` | anyone | Deposit SFLUSH (requires prior `approve`) |
| `withdraw(amount)` | staker | Take back principal, leaving rewards unclaimed |
| `getReward()` | staker | Claim accrued rewards only |
| `exit()` | staker | Withdraw everything and claim in one transaction |
| `notifyRewardAmount(reward, duration)` | owner | Fund a reward period |
| `earned(account)` | view | Rewards claimable right now |
| `remainingReward()` | view | Rewards still to be distributed this period |

### How rewards are calculated

Rewards use the Synthetix `StakingRewards` accumulator. A single global running
total, `rewardPerTokenStored`, tracks rewards owed per staked token; each account
records the value of that counter at its last interaction. The difference between
the two is exactly what accrued while that account was staked:

```
earned = rewards[a] + balanceOf[a] * (rewardPerToken() - userRewardPerTokenPaid[a]) / 1e18
```

This makes every operation **O(1)** regardless of how many stakers exist. Looping
over stakers to distribute rewards would eventually exceed the block gas limit and
permanently brick the contract, so no loop is ever used.

### Design notes

- **Principal is ring-fenced.** Stake and reward are the same token, so
  `totalStaked` is tracked separately from the contract's balance. Rewards can
  only be paid from tokens the owner explicitly deposited as rewards, never from
  another user's principal.
- **Deposits measure what actually arrived** rather than trusting the requested
  amount, so a fee-on-transfer token cannot credit more than was received.
- **Effects precede interactions**, and every state-changing external function is
  `nonReentrant`.
- **Mid-period top-ups roll over.** Funding while a period is live folds the
  unvested remainder into the new rate, so no value is stranded.
- **Rewards do not accrue while nothing is staked**, so an empty pool defers
  distribution rather than losing it.

## Stack

- Hardhat 3 with `@nomicfoundation/hardhat-toolbox-viem`
- Solidity 0.8.34
- OpenZeppelin Contracts 5.x
- Node.js test runner (`node:test`) + viem, chosen so a future frontend can share
  viem types
- `forge-std` for Solidity unit tests and fuzzing

## Usage

```shell
npm install
npm test           # all tests
npm run compile    # compile contracts
npm run typecheck  # build, then tsc --noEmit
```

Run one test layer at a time:

```shell
npx hardhat test solidity
npx hardhat test nodejs
npx hardhat test --coverage
```

## Tests

33 tests. Line coverage: 100% for the token, 98.25% for the staking contract.

| File | Layer | Covers |
| --- | --- | --- |
| [`contracts/SushiFlush.t.sol`](contracts/SushiFlush.t.sol) | Solidity | Metadata, initial supply, transfer, `approve`/`transferFrom`, revert paths, and a fuzz test asserting transfers never change total supply |
| [`contracts/SushiFlushStaking.t.sol`](contracts/SushiFlushStaking.t.sol) | Solidity | Staking mechanics, proportional reward accrual over time, period expiry, mid-period top-up rollover, principal ring-fencing, and a fuzzed solvency invariant |
| [`test/SushiFlush.ts`](test/SushiFlush.ts) | TypeScript + viem | The token flows end to end, as a script or frontend would drive them |

Contract logic is tested in Solidity, which runs in-EVM with no RPC round-trips
and can jump through time with `vm.warp` — essential for the time-dependent
reward math. The TypeScript suite covers the viem call path the frontend uses.

The fuzzed solvency invariant is the one that matters most:

```
totalStaked + earned(alice) + earned(bob)  ≤  token.balanceOf(staking)
```

The contract must never owe more than it holds.

One line is deliberately uncovered: the `InsufficientRewardBalance` guard in
`notifyRewardAmount` is unreachable through normal flow, since `rewardRate` is
derived from tokens the contract actually received. It is a defensive check
against a future change breaking that assumption.

## Deployment

### Configuration

Three secrets are read through Hardhat's `configVariable`, which resolves from the
encrypted keystore (stored outside the repo) or from an environment variable.
Hardhat 3 does **not** read `.env` files.

```shell
npx hardhat keystore set SEPOLIA_RPC_URL       # https://eth-sepolia.g.alchemy.com/v2/<key>
npx hardhat keystore set SEPOLIA_PRIVATE_KEY   # 0x + 64 hex chars
npx hardhat keystore set ETHERSCAN_API_KEY
npx hardhat keystore list                      # prints names only, never values
```

Use a throwaway development wallet. Never a wallet holding real funds.

### Deploying

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/SushiFlush.ts
npx hardhat ignition deploy --network sepolia ignition/modules/SushiFlushStaking.ts
```

The staking module takes the token address as a module parameter, defaulting to
the Sepolia deployment above, and passes the deploying account as the owner.

Ignition records addresses and a resumable journal under
`ignition/deployments/chain-11155111/`. Rerunning a deployment resumes it instead
of deploying a second contract.

### Verifying

```shell
npx hardhat ignition verify --network sepolia chain-11155111
```

This reads constructor arguments from the deployment journal, so they do not need
to be supplied by hand. To verify a single address instead:

```shell
npx hardhat verify --network sepolia --build-profile production <address>
```

**`--build-profile production` matters.** Ignition deploys to real networks using
the `production` profile (optimizer enabled, 200 runs), while `verify` defaults to
the `default` profile (optimizer off). Without it, verification compares against
unoptimized bytecode — 3,554 bytes rather than the deployed 1,764 for the token —
and fails with:

```
HHE80009: The address contains a contract whose bytecode does not match any of your local contracts.
```

## Scripts

[`scripts/setup-staking.ts`](scripts/setup-staking.ts) approves, funds a reward
period, and stakes, in one run:

```shell
npx hardhat run --network sepolia scripts/setup-staking.ts
```

It is safe to rerun: it verifies ownership and balance first, skips `approve` when
the allowance already covers what remains, and skips funding while a reward period
is still active. Each transaction waits for its receipt and throws if the receipt
status is not `success` — a reverted transaction is still mined and still costs
gas, so the status must be checked explicitly.

Gas estimates are padded by 30%. An estimate is a snapshot of current state, but
the transaction executes against whatever state exists when it is mined; a storage
slot that was zero at estimation time and non-zero at execution costs 20,000 gas
more, which is enough to run a tightly-estimated transaction out of gas.

## License

MIT
