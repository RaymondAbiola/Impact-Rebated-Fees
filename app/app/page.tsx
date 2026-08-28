export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-24">
      <p className="numeric text-xs uppercase tracking-[0.18em] text-ink-faint">
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

      <div className="mt-12 flex flex-wrap gap-3">
        <span className="rounded-full bg-benign-soft px-3 py-1.5 text-sm text-benign">
          Benign, refunded
        </span>
        <span className="rounded-full bg-informed-soft px-3 py-1.5 text-sm text-informed">
          Informed, paid to LPs
        </span>
        <span className="numeric rounded-full border border-line px-3 py-1.5 text-sm text-ink-faint">
          settling in 41s
        </span>
      </div>
    </main>
  );
}
