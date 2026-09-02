import { SwapCard } from "@/components/SwapCard";
import { Label } from "@/components/ui";

export default function SwapPage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-20">
      <Label>Swap</Label>
      <h1 className="mt-5 text-3xl tracking-tight">Trade the demo pool</h1>
      <p className="mt-3 max-w-lg text-ink-dim">
        A normal swap. The only difference is the line showing how much of the fee
        you are likely to get back.
      </p>

      <div className="mt-10 grid gap-4 lg:grid-cols-[minmax(0,26rem)_1fr]">
        <SwapCard />
        <div className="raised rounded-3xl p-6">
          <Label>What happens next</Label>
          <ol className="mt-4 space-y-4 text-sm text-ink-dim">
            <li>
              <span className="numeric text-accent">01</span> The swap executes
              immediately, at a price you can see before you sign.
            </li>
            <li>
              <span className="numeric text-accent">02</span> A receipt appears in the
              settlement queue with a countdown.
            </li>
            <li>
              <span className="numeric text-accent">03</span> When the window closes,
              anyone can settle it. The verdict comes from the pool&apos;s own price.
            </li>
          </ol>
        </div>
      </div>
    </main>
  );
}
