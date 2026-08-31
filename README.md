# SushiFlush (SFLUSH)

> **Testnet learning project.** This is a personal project for learning Solidity
> and the EVM. The contract is not audited, has never been deployed to mainnet,
> and is not intended to be. It has no value.

A fixed-supply ERC-20 token built on [OpenZeppelin Contracts](https://www.openzeppelin.com/contracts)
with [Hardhat 3](https://hardhat.org/), TypeScript and [viem](https://viem.sh/).

## The contract

[`contracts/SushiFlush.sol`](contracts/SushiFlush.sol) mints **1,000,000 SFLUSH**
to the deployer in its constructor and nothing else:

| | |
| --- | --- |
| Name | SushiFlush |
| Symbol | SFLUSH |
| Decimals | 18 |
| Total supply | 1,000,000 SFLUSH (fixed) |

There is no `mint()` function and no `Ownable`. `_mint` is called once, from the
constructor, so total supply is fixed permanently at deployment and the deployer
holds no special privileges afterwards.

## Stack

- Hardhat 3 with `@nomicfoundation/hardhat-toolbox-viem`
- Solidity 0.8.34
- OpenZeppelin Contracts 5.x
- Node.js test runner (`node:test`) + viem, chosen so a future frontend can
  share viem types
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
```

## Tests

| File | Layer | Covers |
| --- | --- | --- |
| [`contracts/SushiFlush.t.sol`](contracts/SushiFlush.t.sol) | Solidity | Metadata, initial supply, transfer, approve/`transferFrom`, revert paths, plus a fuzz test asserting transfers never change total supply |
| [`test/SushiFlush.ts`](test/SushiFlush.ts) | TypeScript + viem | The same flows end to end, as a script or frontend would drive them |

Contract logic is tested in Solidity, which runs in-EVM with no RPC round-trips.
The TypeScript suite covers the viem call path that the frontend will later use.

## Deployment

Deployed to **Sepolia** testnet with Hardhat Ignition and verified on all three
explorers.

| | |
| --- | --- |
| Network | Sepolia (chain ID 11155111) |
| Address | `0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12` |
| Etherscan | [source](https://sepolia.etherscan.io/address/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12#code) |
| Blockscout | [source](https://eth-sepolia.blockscout.com/address/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12#code) |
| Sourcify | [source](https://sourcify.dev/server/repo-ui/11155111/0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12) |

The entire 1,000,000 SFLUSH supply was minted to the deploying account.

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
```

Ignition records the deployed address and a resumable journal under
`ignition/deployments/chain-11155111/`. Rerunning the same command resumes an
interrupted deployment instead of deploying a second contract.

### Verifying

```shell
npx hardhat verify --network sepolia --build-profile production <address>
```

**`--build-profile production` is required.** Ignition deploys to real networks
using the `production` profile (optimizer enabled, 200 runs), while `verify`
defaults to the `default` profile (optimizer off). Without the flag, verification
compares against unoptimized bytecode — 3,554 bytes rather than the deployed
1,764 — and fails with:

```
HHE80009: The address contains a contract whose bytecode does not match any of your local contracts.
```

## License

MIT
