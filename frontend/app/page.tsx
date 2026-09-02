import econ from "@/data/economics.json";
import { HowItWorks } from "@/components/HowItWorks";
import { Compare } from "@/components/Compare";
import { DriftHistogram } from "@/components/DriftHistogram";
import { TradeoffChart, type Cell } from "@/components/TradeoffChart";
import { Card, Label } from "@/components/ui";

export default function Home() {
  const chosen = econ.chosen as Cell & {
    recovery_pct: number;
    extracted_usd: number;
    informed_pct: number;
  };
  const hist = econ.drift_histogram;

  return (
    <main className="mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-20">
      <Label>Unichain Sepolia · live</Label>
      <h1 className="mt-6 max-w-3xl text-4xl leading-[1.08] tracking-tight sm:text-5xl lg:text-6xl">
        A security deposit
        <br />
        on every swap.
      </h1>
      <p className="mt-6 max-w-2xl text-ink-dim">
        Someone swapping five hundred dollars pays the same fee as a bot that just
        took money off the pool. A pool has one fee and no way to tell them apart,
        so it charges everyone enough to survive the bot.
      </p>
      <p className="mt-4 max-w-2xl text-ink-dim">
        This hook charges a deposit on every swap and gives it back sixty seconds
        later, unless the price kept drifting your way and the pool was still
        mispriced after you left.
      </p>

      <div className="mt-12 grid gap-4 sm:grid-cols-3">
        <Card className="p-5">
          <Label>Uninformed trader pays</Label>
          <p className="numeric mt-3 text-3xl">
            +{chosen.uninformed_overcharge_bps.toFixed(2)}
          </p>
          <p className="mt-1 text-sm text-ink-dim">bps over the base fee</p>
        </Card>
        <Card className="p-5">
          <Label>LP revenue</Label>
          <p className="numeric mt-3 text-3xl text-benign">
            +{chosen.lp_uplift_pct.toFixed(1)}%
          </p>
          <p className="mt-1 text-sm text-ink-dim">over base fee alone</p>
        </Card>
        <Card className="p-5">
          <Label>Flagged as informed</Label>
          <p className="numeric mt-3 text-3xl text-informed">
            {chosen.informed_pct.toFixed(1)}%
          </p>
          <p className="mt-1 text-sm text-ink-dim">
            of {econ.trades.toLocaleString()} real swaps
          </p>
        </Card>
      </div>

      <div className="mt-4 grid gap-4">
        <DriftHistogram
          edges={hist.edges_bps}
          counts={hist.counts}
          theta={hist.theta_bps}
        />
        <TradeoffChart grid={econ.grid as Cell[]} chosen={chosen} />
      </div>

      <p className="mt-4 max-w-2xl text-sm leading-relaxed text-ink-faint">
        Replayed from {econ.trades.toLocaleString()} real USDC/WETH swaps on mainnet,
        fixture {econ.fixture}. The escrow recovers{" "}
        <span className="numeric">{chosen.recovery_pct.toFixed(0)}%</span> of what
        informed flow captured. Charging the full rate that would recover all of it
        also doubles what ordinary traders pay, so the gap is deliberate.
      </p>

      <HowItWorks />
      <Compare />
    </main>
  );
}
