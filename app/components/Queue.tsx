"use client";

import { useChainTime } from "@/lib/useChainTime";
import { useReceiptCount, useReceipts } from "@/lib/hooks";
import { Label } from "./ui";
import { QueueRow } from "./QueueRow";

export function Queue() {
  const now = useChainTime();
  const { data: count } = useReceiptCount();
  const { receipts, isLoading } = useReceipts(count as bigint | undefined);

  return (
    <div className="raised overflow-hidden rounded-3xl">
      <div className="flex items-center justify-between border-b border-line-soft px-5 py-4">
        <Label>Receipts</Label>
        <span className="numeric text-xs text-ink-faint">
          {count !== undefined ? `${count} total` : "—"}
        </span>
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
        receipts.map((r) => <QueueRow key={r.id} r={r} now={now} />)
      )}
    </div>
  );
}
