"""Split the markout into the part that is structural and the part that is
information.

The gate came back with negative lift in every cell, and the reason is in the
definition rather than in the data. Markout measured from execution price
against a mid-price reference carries a fixed drag: the trader paid the fee and
crossed their own impact, so P_exec is already worse than mid before any
information has a chance to show up. The shuffled null carries no such drag,
because averaging raw moves over both directions cancels it. Real therefore
sits a few bps to the left of null by construction, and lift is negative at
every positive threshold whether information exists or not.

Same number, two pieces:

    drag  = sign * (mid_post  - exec)     / exec        fee, spread, own impact
    drift = sign * (mid_after - mid_post) / mid_post    everything after
    markout ~= drag + drift

drag is fully known at swap time and says nothing about the future. drift is
the only place information can live, so drift is what has to be tested against
the null. If drift is flat too, the mechanism is dead and no threshold saves it.
"""

import random
import sys

import classify
import config

Q96 = 1 << 96
WINDOWS = [30, 120, 480]
PCTS = (0.01, 0.05, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)


def prepare(rows, min_swap_usd=None):
    """Like classify.prepare but keeps the post-swap mid from each event."""
    min_swap_usd = config.MIN_SWAP_USD if min_swap_usd is None else min_swap_usd
    lo, hi, prefix = classify.build_price_series(rows)
    trades = []
    for r in rows:
        a0, a1 = r["amount0"], r["amount1"]
        if a0 == 0 or a1 == 0:
            continue
        usd = abs(a0) / classify.DEC0
        if usd < min_swap_usd:
            continue
        trades.append({
            "block": r["block"],
            "usd": usd,
            "exec_price": usd / (abs(a1) / classify.DEC1),
            "mid_post": classify.pool_price(r["sqrt_price_x96"]),
            "sign": 1.0 if a0 > 0 else -1.0,
        })
    return (lo, hi, prefix), trades


def decompose(series, trades, k_blocks):
    """Per trade: (drag, drift, markout) in bps, or None outside the window."""
    lo, _, prefix = series
    out = []
    for t in trades:
        after = classify.window_mean(lo, prefix, t["block"] + 1, t["block"] + k_blocks)
        if after is None:
            out.append(None)
            continue
        drag = t["sign"] * (t["mid_post"] - t["exec_price"]) / t["exec_price"] * 10_000
        drift = t["sign"] * (after - t["mid_post"]) / t["mid_post"] * 10_000
        markout = t["sign"] * (after - t["exec_price"]) / t["exec_price"] * 10_000
        out.append((drag, drift, markout))
    return out


def null_of(trades, parts, rnd):
    """Shuffle only the unsigned forward move. Direction, drag and the pairing
    of a trade with its own size all stay real."""
    pool = [p[1] / t["sign"] for t, p in zip(trades, parts) if p is not None]
    rnd.shuffle(pool)
    it = iter(pool)
    return [None if p is None else t["sign"] * next(it)
            for t, p in zip(trades, parts)]


def stats(a):
    a = sorted(a)
    n = len(a)
    return {"n": n, "mean": sum(a) / n, "q": {p: a[int(p * n)] for p in PCTS}}


def col(name, s):
    q = s["q"]
    return (f"  {name:<8s}" + "".join(f"{q[p]:9.2f}" for p in PCTS)
            + f"{s['mean']:9.2f}")


def tail_table(label, real, null, n):
    print(f"  {label} right tail")
    for th in (0, 2, 5, 10, 20, 40):
        r = sum(1 for m in real if m > th) / n * 100
        u = sum(1 for m in null if m > th) / len(null) * 100
        flag = "  <-- lift" if r - u > 0.5 else ""
        print(f"    >{th:3d}bps  real {r:6.2f}%  null {u:6.2f}%  lift {r - u:+6.2f}{flag}")


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: python3 analysis/fetch.py")

    rows = classify.load_fixture(paths[-1])
    series, trades = prepare(rows)
    rnd = random.Random(7)
    print(f"{len(trades)} trades usable from {paths[-1].name}\n")

    for secs in WINDOWS:
        kb = max(1, round(secs / config.BLOCK_SECONDS))
        parts = decompose(series, trades, kb)
        keep = [(t, p) for t, p in zip(trades, parts) if p is not None]
        drag = [p[0] for _, p in keep]
        drift = [p[1] for _, p in keep]
        markout = [p[2] for _, p in keep]
        dnull = [m for m in null_of(trades, parts, rnd) if m is not None]
        n = len(keep)

        print(f"=== window {secs}s ({kb} blocks)  n={n} ===")
        print("  " + " " * 8 + "".join(f"{p * 100:8.0f}%" for p in PCTS) + f"{'mean':>9s}")
        print(col("drag", stats(drag)))
        print(col("drift", stats(drift)))
        print(col("markout", stats(markout)))
        print(col("null", stats(dnull)))
        print()
        tail_table("drift", drift, dnull, n)
        print()

        # the economic question, independent of any threshold: does knowing the
        # direction predict the forward move at all
        m_real = sum(drift) / n
        m_null = sum(dnull) / len(dnull)
        var = sum((x - m_real) ** 2 for x in drift) / (n - 1)
        se = (var / n) ** 0.5
        print(f"  mean drift {m_real:+.3f} bps  se {se:.3f}  t {m_real / se:+.2f}"
              f"   (null {m_null:+.3f})")
        print(f"  mean drag  {sum(drag) / n:+.3f} bps   <- this is the whole real-vs-null gap")
        print()

        # size conditioning. informed flow should be concentrated in big tickets
        buckets = [(0, 1e4), (1e4, 1e5), (1e5, 1e6), (1e6, 1e12)]
        print(f"  {'size':>18s} {'n':>7s} {'drag':>8s} {'drift':>8s} {'markout':>8s} {'>10bps':>8s}")
        for a, b in buckets:
            sel = [p for t, p in keep if a <= t["usd"] < b]
            if not sel:
                continue
            hit = sum(1 for p in sel if p[1] > 10) / len(sel) * 100
            print(f"  ${a:>7,.0f}-${b:>8,.0f} {len(sel):7d} "
                  f"{sum(p[0] for p in sel) / len(sel):8.2f} "
                  f"{sum(p[1] for p in sel) / len(sel):8.2f} "
                  f"{sum(p[2] for p in sel) / len(sel):8.2f} {hit:7.2f}%")
        print()


if __name__ == "__main__":
    main()
