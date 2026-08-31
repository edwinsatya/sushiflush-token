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

Not yet deployed. Sepolia deployment via Hardhat Ignition is the next step.

The private key for deployment is read through Hardhat's `configVariable`, which
resolves from either the encrypted keystore or an environment variable:

```shell
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
```

Use a throwaway development wallet. Never a wallet holding real funds.

## License

MIT
