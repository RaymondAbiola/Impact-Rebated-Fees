import { HowItWorks } from "@/components/HowItWorks";
import { Card, Chip, Label, Well } from "@/components/ui";

export default function Home() {
  return (
    <main className="mx-auto max-w-6xl px-6 py-20">
      <Label>Unichain Sepolia · live</Label>
      <h1 className="mt-6 max-w-3xl text-5xl leading-[1.05] tracking-tight sm:text-6xl">
        A security deposit
        <br />
        on every swap.
      </h1>
      <p className="mt-6 max-w-xl text-ink-dim">
        Every trade pays the full fee up front. Sixty seconds later the pool checks
        whether the price kept moving in your favour. If it did not, you get most of
        it back.
      </p>

      <div className="mt-12 grid gap-4 sm:grid-cols-3">
        <Card className="p-5">
          <Label>Uninformed trader pays</Label>
          <p className="numeric mt-3 text-3xl">+0.71</p>
          <p className="mt-1 text-sm text-ink-dim">bps over the base fee</p>
        </Card>
        <Card className="p-5">
          <Label>LP revenue</Label>
          <p className="numeric mt-3 text-3xl text-benign">+32.7%</p>
          <p className="mt-1 text-sm text-ink-dim">over base fee alone</p>
        </Card>
        <Card className="p-5">
          <Label>Flagged as informed</Label>
          <p className="numeric mt-3 text-3xl text-informed">3.2%</p>
          <p className="mt-1 text-sm text-ink-dim">of 26,209 real swaps</p>
        </Card>
      </div>

      <Well className="mt-4 flex flex-wrap items-center gap-3 p-5">
        <Chip tone="benign">Benign · refunded</Chip>
        <Chip tone="informed">Informed · paid to LPs</Chip>
        <Chip tone="pending">Settling</Chip>
        <span className="numeric ml-auto text-sm text-ink-faint">
          window 60s · theta 20 bps
        </span>
      </Well>

      <HowItWorks />
    </main>
  );
}
