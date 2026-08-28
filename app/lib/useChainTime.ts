"use client";

import { useBlock } from "wagmi";

/**
 * Countdowns run off chain time, not the browser clock: the contract compares
 * block.timestamp, so a laptop a few seconds fast would show a receipt as ready
 * while settle() still reverts.
 *
 * Unichain produces a block a second, so watching the head is already
 * second-granularity. No local ticking, and it cannot drift.
 */
export function useChainTime(): number {
  const { data: block } = useBlock({ watch: true });
  return block?.timestamp ? Number(block.timestamp) : 0;
}
