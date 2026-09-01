"use client";

import { useQuery } from "@tanstack/react-query";
import { parseAbiItem } from "viem";
import { usePublicClient } from "wagmi";
import { addresses, deployedAtBlock, maxLogSpan } from "./generated";

const settledEvent = parseAbiItem(
  "event ReceiptSettled(uint256 indexed receiptId, address indexed beneficiary, bool informed, int256 driftTicks, address currency, uint256 payout, uint256 bounty, bool expired)",
);

export type Settlement = {
  id: number;
  informed: boolean;
  drift: bigint;
  currency: `0x${string}`;
  payout: bigint;
  bounty: bigint;
  expired: boolean;
};

/**
 * The verdict for a settled receipt only exists in its event. driftOf keeps
 * recomputing against the current time, so reading it back later would show a
 * number that had nothing to do with how the escrow was actually paid out.
 *
 * The rpc refuses any getLogs span over 10k blocks, so page backwards from the
 * head to the deployment in chunks.
 */
export function useSettlements() {
  const client = usePublicClient();

  return useQuery({
    queryKey: ["settlements", addresses.hook],
    enabled: Boolean(client),
    refetchInterval: 8_000,
    queryFn: async (): Promise<Map<number, Settlement>> => {
      const head = await client!.getBlockNumber();
      const out = new Map<number, Settlement>();

      let to = head;
      while (to >= deployedAtBlock) {
        const from = to - maxLogSpan + 1n > deployedAtBlock ? to - maxLogSpan + 1n : deployedAtBlock;
        const logs = await client!.getLogs({
          address: addresses.hook,
          event: settledEvent,
          fromBlock: from,
          toBlock: to,
        });
        for (const l of logs) {
          const a = l.args;
          if (a.receiptId === undefined) continue;
          out.set(Number(a.receiptId), {
            id: Number(a.receiptId),
            informed: Boolean(a.informed),
            drift: a.driftTicks ?? 0n,
            currency: a.currency as `0x${string}`,
            payout: a.payout ?? 0n,
            bounty: a.bounty ?? 0n,
            expired: Boolean(a.expired),
          });
        }
        if (from === deployedAtBlock) break;
        to = from - 1n;
      }
      return out;
    },
  });
}
