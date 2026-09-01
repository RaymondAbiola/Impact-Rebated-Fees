import { Label } from "./ui";

const steps = [
  {
    n: "01",
    title: "Pay up front",
    body: "The pool charges its usual fee. The hook takes another 25 bps and holds it as a claim inside the singleton.",
  },
  {
    n: "02",
    title: "Wait sixty seconds",
    body: "The hook records where the swap left the price, then keeps a time-weighted average of everything that happens next.",
  },
  {
    n: "03",
    title: "Settle on what happened",
    body: "Price kept drifting your way past 20 bps and the escrow goes to the LPs. Otherwise it comes back to you.",
  },
];

export function HowItWorks() {
  return (
    <section className="mt-20 border-t border-line-soft pt-10">
      <Label>How it works</Label>
      <div className="mt-6 grid gap-8 sm:grid-cols-3">
        {steps.map((s) => (
          <div key={s.n}>
            <p className="numeric text-sm text-accent">{s.n}</p>
            <p className="mt-3">{s.title}</p>
            <p className="mt-2 text-sm leading-relaxed text-ink-dim">{s.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
