"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { hook, toReceipt, verdictOf, type Verdict } from "./contracts";
import { useSettlements, type Settlement } from "./useSettlements";

export function useReceiptCount() {
  return useReadContract({ ...hook, functionName: "nextReceiptId" });
}

export type ReceiptView = {
  id: number;
  beneficiary: `0x${string}`;
  swapTimestamp: number;
  zeroForOne: boolean;
  settled: boolean;
  escrowAmount: bigint;
  escrowCurrency: `0x${string}`;
  drift: bigint;
  ready: boolean;
  verdict: Verdict;
  /** present once the receipt has actually been paid out */
  settlement?: Settlement;
};

/** Reads the newest `limit` receipts along with their live drift. */
export function useReceipts(count: bigint | undefined, limit = 25) {
  const { data: settlements } = useSettlements();
  const n = Number(count ?? 0n);
  const ids = Array.from({ length: Math.min(n, limit) }, (_, i) => n - 1 - i).filter((i) => i >= 0);

  const { data, ...rest } = useReadContracts({
    query: { enabled: ids.length > 0, refetchInterval: 4_000 },
    contracts: ids.flatMap((id) => [
      { ...hook, functionName: "receipts", args: [BigInt(id)] } as const,
      { ...hook, functionName: "driftOf", args: [BigInt(id)] } as const,
    ]),
  });

  const receipts: ReceiptView[] = [];
  if (data) {
    ids.forEach((id, i) => {
      const r = data[i * 2];
      const d = data[i * 2 + 1];
      if (r?.status !== "success" || d?.status !== "success") return;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rec = toReceipt(r.result as any);
      const [drift, ready] = d.result as readonly [bigint, boolean];
      const settlement = settlements?.get(id);
      receipts.push({
        id,
        beneficiary: rec.beneficiary,
        swapTimestamp: Number(rec.swapTimestamp),
        zeroForOne: rec.zeroForOne,
        settled: rec.settled,
        escrowAmount: rec.escrowAmount,
        escrowCurrency: rec.escrowCurrency,
        drift,
        ready,
        // a settled receipt's verdict lives in its event, not in a fresh
        // driftOf call, which keeps moving after the payout
        verdict: settlement
          ? settlement.informed
            ? "informed"
            : "benign"
          : verdictOf(rec.settled, ready, drift, THETA_BPS),
        settlement,
      });
    });
  }
  return { receipts, ...rest };
}

/** Kept in step with contracts/src/Params.sol. */
export const THETA_BPS = 20n;
export const SETTLEMENT_WINDOW_SECONDS = 60;
export const ESCROW_FEE_BPS = 25n;
export const BOUNTY_BPS = 200n;
