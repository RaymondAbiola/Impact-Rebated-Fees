import { addresses, hookAbi } from "./generated";

export const hook = { address: addresses.hook, abi: hookAbi } as const;

/** Receipt tuple as the public getter returns it, in declaration order. */
export type Receipt = {
  poolId: `0x${string}`;
  beneficiary: `0x${string}`;
  swapTimestamp: bigint;
  zeroForOne: boolean;
  settled: boolean;
  tickPost: number;
  tickCumulative: bigint;
  escrowAmount: bigint;
  escrowCurrency: `0x${string}`;
};

export function toReceipt(
  r: readonly [`0x${string}`, `0x${string}`, bigint, boolean, boolean, number, bigint, bigint, `0x${string}`],
): Receipt {
  return {
    poolId: r[0],
    beneficiary: r[1],
    swapTimestamp: r[2],
    zeroForOne: r[3],
    settled: r[4],
    tickPost: r[5],
    tickCumulative: r[6],
    escrowAmount: r[7],
    escrowCurrency: r[8],
  };
}

export type Verdict = "pending" | "benign" | "informed";

/** Mirrors the contract: informed when drift clears theta. */
export function verdictOf(settled: boolean, ready: boolean, drift: bigint, thetaBps: bigint): Verdict {
  if (!ready && !settled) return "pending";
  return drift > thetaBps ? "informed" : "benign";
}
