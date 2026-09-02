"use client";

import { SETTLEMENT_WINDOW_SECONDS, type ReceiptView } from "@/lib/hooks";
import { addresses } from "@/lib/generated";
import { fmtUnits, short } from "@/lib/format";
import { Chip } from "./ui";
import { useSettle } from "@/lib/useSettle";

const tokenOf = (c: string) =>
  c.toLowerCase() === addresses.currency0.toLowerCase() ? "iUSD" : "iETH";

export function QueueRow({
  r,
  now,
  settleOne,
  busy,
}: {
  r: ReceiptView;
  now: number;
  settleOne: ReturnType<typeof useSettle>["settleOne"];
  busy: ReturnType<typeof useSettle>["busy"];
}) {
  // now is 0 until the first block lands; treat that as still waiting
  const elapsed = now === 0 ? 0 : now - r.swapTimestamp;
  const remaining = Math.max(0, SETTLEMENT_WINDOW_SECONDS - elapsed);
  const progress = Math.min(1, Math.max(0, elapsed / SETTLEMENT_WINDOW_SECONDS));
  const waiting = !r.settled && remaining > 0;

  return (
    <div className="grid grid-cols-[2rem_1fr_auto] items-center gap-3 border-b border-line-soft px-4 py-4 last:border-0 sm:grid-cols-[3rem_1fr_auto] sm:gap-4 sm:px-5">
      <span className="numeric text-sm text-ink-faint">#{r.id}</span>

      <div className="min-w-0">
        <p className="numeric truncate text-sm">
          {r.zeroForOne ? "iUSD → iETH" : "iETH → iUSD"}
          <span className="ml-3 text-ink-faint">
            {fmtUnits(r.escrowAmount, 18, 6)} {tokenOf(r.escrowCurrency)} held
          </span>
        </p>

        {waiting ? (
          <div className="mt-2 flex items-center gap-3">
            <div className="h-1 w-24 overflow-hidden rounded-full bg-ground sm:w-40">
              <div
                className="h-full rounded-full bg-pending transition-[width] duration-1000 ease-linear"
                style={{ width: `${progress * 100}%` }}
              />
            </div>
            <span className="numeric text-xs text-pending">{remaining}s</span>
          </div>
        ) : (
          <p className="numeric mt-2 text-xs text-ink-faint">
            drift {r.drift > 0n ? "+" : ""}
            {r.drift.toString()} ticks · to {short(r.beneficiary)}
          </p>
        )}
      </div>

      <div className="text-right">
        {waiting ? (
          <Chip tone="pending">Settling</Chip>
        ) : r.verdict === "informed" ? (
          <Chip tone="informed">Informed</Chip>
        ) : (
          <Chip tone="benign">Benign</Chip>
        )}
        {r.settled ? (
          <p className="numeric mt-2 text-[0.68rem] text-ink-faint">
            {r.settlement?.expired ? "expired" : "settled"}
          </p>
        ) : (
          <button
            disabled={waiting || busy !== null}
            onClick={() => settleOne(r.id)}
            className="numeric mt-2 rounded-full border border-line px-3 py-1 text-[0.68rem] text-ink-dim transition-colors hover:text-ink disabled:opacity-40"
          >
            {busy === r.id ? "settling" : "settle"}
          </button>
        )}
      </div>
    </div>
  );
}
