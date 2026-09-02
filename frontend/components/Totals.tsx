"use client";

import type { ReceiptView } from "@/lib/hooks";
import { addresses } from "@/lib/generated";
import { fmtUnits } from "@/lib/format";
import { Label } from "./ui";

function sumBy(rs: ReceiptView[], informed: boolean) {
  return rs.reduce((acc, r) => {
    const s = r.settlement;
    if (!s || s.informed !== informed) return acc;
    const key = s.currency.toLowerCase() === addresses.currency0.toLowerCase() ? "iUSD" : "iETH";
    acc[key] = (acc[key] ?? 0n) + s.payout;
    return acc;
  }, {} as Record<string, bigint>);
}

export function Totals({ receipts }: { receipts: ReceiptView[] }) {
  const settled = receipts.filter((r) => r.settlement);
  const refunded = sumBy(receipts, false);
  const toLps = sumBy(receipts, true);
  const bounty = settled.reduce((a, r) => a + (r.settlement?.bounty ?? 0n), 0n);
  const informedCount = settled.filter((r) => r.settlement?.informed).length;

  const render = (m: Record<string, bigint>) =>
    Object.keys(m).length === 0
      ? "—"
      : Object.entries(m)
          .map(([k, v]) => `${fmtUnits(v, 18, 5)} ${k}`)
          .join("  ·  ");

  return (
    <div className="grid gap-4 sm:grid-cols-3">
      <div className="raised rounded-3xl p-5">
        <Label>Refunded to traders</Label>
        <p className="numeric mt-3 break-words text-base text-benign sm:text-lg">{render(refunded)}</p>
        <p className="mt-1 text-xs text-ink-faint">
          {settled.length - informedCount} of {settled.length} settled
        </p>
      </div>
      <div className="raised rounded-3xl p-5">
        <Label>Paid to LPs</Label>
        <p className="numeric mt-3 break-words text-base text-informed sm:text-lg">{render(toLps)}</p>
        <p className="mt-1 text-xs text-ink-faint">
          {informedCount} flagged informed
        </p>
      </div>
      <div className="raised rounded-3xl p-5">
        <Label>Keeper bounties</Label>
        <p className="numeric mt-3 break-words text-base text-ink-dim sm:text-lg">{fmtUnits(bounty, 18, 6)}</p>
        <p className="mt-1 text-xs text-ink-faint">2% of each escrow</p>
      </div>
    </div>
  );
}
