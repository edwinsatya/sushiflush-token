import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/// The SushiFlush token already deployed on Sepolia. Override with the
/// `stakingToken` module parameter to point at a different deployment.
const SUSHIFLUSH_SEPOLIA = "0xeB45F6b8Cbfe0B988a22a98C750CeFfe1f875b12";

export default buildModule("SushiFlushStakingModule", (m) => {
  const stakingToken = m.getParameter("stakingToken", SUSHIFLUSH_SEPOLIA);

  // The deploying account owns the staking contract and funds reward periods.
  const initialOwner = m.getAccount(0);

  const staking = m.contract("SushiFlushStaking", [stakingToken, initialOwner]);

  return { staking };
});
