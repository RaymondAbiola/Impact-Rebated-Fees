"use client";

import { useChainTime } from "@/lib/useChainTime";
import { useReceiptCount, useReceipts } from "@/lib/hooks";
import { Label } from "./ui";
import { QueueRow } from "./QueueRow";
import { Totals } from "./Totals";
import { useSettle } from "@/lib/useSettle";

export function Queue() {
  const now = useChainTime();
  const { data: count } = useReceiptCount();
  const { receipts, isLoading } = useReceipts(count as bigint | undefined);
  const { settleOne, settleMany, busy, error } = useSettle();

  const ready = receipts.filter((r) => !r.settled && r.ready).map((r) => r.id);

  return (
    <div className="space-y-4">
      <Totals receipts={receipts} />

      <div className="raised overflow-hidden rounded-3xl">
      <div className="flex items-center justify-between border-b border-line-soft px-5 py-4">
        <Label>Receipts</Label>
        <div className="flex items-center gap-3">
          <span className="numeric text-xs text-ink-faint">
            {count !== undefined ? `${count} total` : "—"}
          </span>
          {ready.length > 0 && (
            <button
              disabled={busy !== null}
              onClick={() => settleMany(ready)}
              className="rounded-full bg-accent px-3 py-1 text-xs text-ground transition-colors hover:bg-accent-hi disabled:opacity-50"
            >
              {busy === "batch" ? "settling" : `settle ${ready.length} ready`}
            </button>
          )}
        </div>
      </div>

      {isLoading && receipts.length === 0 ? (
        <p className="px-5 py-10 text-center text-sm text-ink-faint">Reading the chain…</p>
      ) : receipts.length === 0 ? (
        <div className="px-5 py-14 text-center">
          <p className="text-sm text-ink-dim">No receipts yet.</p>
          <p className="mt-1 text-xs text-ink-faint">
            Make a swap and one appears here with a sixty second countdown.
          </p>
        </div>
      ) : (
        receipts.map((r) => (
          <QueueRow key={r.id} r={r} now={now} settleOne={settleOne} busy={busy} />
        ))
      )}
      </div>

      {error && <p className="text-xs text-informed">{error}</p>}
    </div>
  );
}
