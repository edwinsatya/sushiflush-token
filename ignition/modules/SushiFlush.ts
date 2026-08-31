import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SushiFlushModule", (m) => {
  // No constructor arguments: the whole supply is minted to whichever
  // account sends this deployment transaction.
  const sushiFlush = m.contract("SushiFlush");

  return { sushiFlush };
});
