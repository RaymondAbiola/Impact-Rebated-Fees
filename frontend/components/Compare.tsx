import { Label } from "./ui";

const priorArt = ["PegGuard", "TRIDENT", "DAMM", "Nezlobin Directional Fee", "Arb Controller"];

export function Compare() {
  return (
    <section className="mt-20 border-t border-line-soft pt-10">
      <Label>How this compares</Label>
      <p className="mt-4 max-w-2xl text-ink-dim">
        Charging informed traders more than retail is a known goal. Uniswap has an
        open request for it and several teams have built one. Every existing
        design makes the same choice, and it is the opposite of ours.
      </p>

      <div className="mt-8 grid gap-4 md:grid-cols-2">
        <div className="raised rounded-3xl p-6">
          <p className="numeric text-xs uppercase tracking-[0.2em] text-ink-faint">
            Everyone else
          </p>
          <p className="mt-4 text-2xl tracking-tight">Decides before the swap</p>
          <ul className="mt-4 space-y-2 text-sm text-ink-dim">
            <li>Guesses from volatility, or a gap against an oracle</li>
            <li>Needs a price feed it has to trust and pay for</li>
            <li>Overcharges ordinary traders who arrive in a volatile minute</li>
          </ul>
          <p className="mt-5 text-xs text-ink-faint">
            {priorArt.join(" · ")}
          </p>
        </div>

        <div className="raised rounded-3xl p-6 ring-1 ring-accent/30">
          <p className="numeric text-xs uppercase tracking-[0.2em] text-accent">
            This hook
          </p>
          <p className="mt-4 text-2xl tracking-tight">Decides after the swap</p>
          <ul className="mt-4 space-y-2 text-sm text-ink-dim">
            <li>Reads what the price actually did in the next sixty seconds</li>
            <li>No oracle, no off chain service, no keeper network</li>
            <li>Observes the outcome instead of forecasting it</li>
          </ul>
          <p className="mt-5 text-xs text-ink-faint">
            The pool&apos;s own price is the entire signal
          </p>
        </div>
      </div>
    </section>
  );
}
