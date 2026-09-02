import { Queue } from "@/components/Queue";
import { Label } from "@/components/ui";

export default function QueuePage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-20">
      <Label>Settlement</Label>
      <h1 className="mt-5 text-3xl tracking-tight">Receipts waiting on a verdict</h1>
      <p className="mt-3 max-w-xl text-ink-dim">
        Every swap leaves a receipt. Sixty seconds later the pool&apos;s own price
        decides whether the escrow goes back to the trader or to the liquidity
        providers.
      </p>

      <div className="mt-10">
        <Queue />
      </div>
    </main>
  );
}
