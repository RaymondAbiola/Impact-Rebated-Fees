const states = [
  { label: "Benign", note: "refunded to the trader", tone: "benign", drift: "-3" },
  { label: "Informed", note: "paid to the LPs", tone: "informed", drift: "+100" },
  { label: "Settling", note: "41s remaining", tone: "pending", drift: "—" },
] as const;

const tone = {
  benign: "bg-benign-soft text-benign",
  informed: "bg-informed-soft text-informed",
  pending: "bg-pending-soft text-pending",
};

export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-24">
      <p className="numeric text-xs uppercase tracking-[0.2em] text-ink-faint">
        Unichain Sepolia
      </p>
      <h1 className="mt-6 max-w-3xl text-5xl leading-[1.05] tracking-tight sm:text-6xl">
        A security deposit
        <br />
        on every swap.
      </h1>
      <p className="mt-6 max-w-xl text-ink-dim">
        Every trade pays the full fee up front. Sixty seconds later the pool
        checks whether the price kept moving in your favour. If it did not, you
        get most of it back.
      </p>

      <div className="mt-14 grid gap-4 sm:grid-cols-3">
        {states.map((s) => (
          <div key={s.label} className="raised rounded-3xl p-5">
            <div className="flex items-center justify-between">
              <span className={`rounded-full px-3 py-1 text-sm ${tone[s.tone]}`}>
                {s.label}
              </span>
              <span className="numeric text-sm text-ink-faint">{s.drift}</span>
            </div>
            <p className="mt-4 text-sm text-ink-dim">{s.note}</p>
          </div>
        ))}
      </div>

      <div className="inset mt-4 rounded-3xl p-5">
        <p className="numeric text-xs uppercase tracking-[0.18em] text-ink-faint">
          escrow held
        </p>
        <p className="numeric mt-2 text-3xl">0.031 062</p>
      </div>
    </main>
  );
}
