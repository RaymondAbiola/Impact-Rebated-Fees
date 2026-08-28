"""Pick the settlement parameters on economics rather than on hit rate.

Two numbers decide it:

  recovery   what share of the value informed flow captured comes back to LPs
  overcharge what a genuinely uninformed trader pays on top of the base fee,
             estimated from the null: a trade with no information still trips
             the threshold at the null rate, and pays the escrow when it does

A cell that recovers a lot but overcharges ordinary traders breaks the promise
the mechanism is built on, so it is not a win.
"""

import json
import random

import classify
import config
import diagnose

WINDOWS = [30, 60, 120, 240, 480, 960]
THETAS = [5, 10, 20, 40, 80, 160]


def evaluate(trades, drift, theta, escrow_bps):
    inf_vol = ben_vol = extracted = 0.0
    inf_n = n = 0
    for t, d in zip(trades, drift):
        if d is None:
            continue
        n += 1
        if d > theta:
            inf_n += 1
            inf_vol += t["usd"]
            extracted += t["usd"] * d / 10_000
        else:
            ben_vol += t["usd"]
    if not n or inf_vol == 0:
        return None
    return {
        "n": n,
        "informed_pct": inf_n / n * 100,
        "informed_vol": inf_vol,
        "benign_vol": ben_vol,
        "extracted": extracted,
        "recovered": inf_vol * escrow_bps / 10_000,
        "fair_escrow_bps": extracted / inf_vol * 10_000,
    }


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    rows = classify.load_fixture(paths[-1])
    series, trades = diagnose.prepare(rows)
    rnd = random.Random(11)

    print(f"{len(trades)} trades, base fee {config.BASE_FEE_BPS} bps, escrow {config.ESCROW_FEE_BPS} bps\n")
    print(f"{'win':>5s} {'theta':>6s} {'inf%':>6s} {'null%':>6s} {'fair esc':>9s} "
          f"{'recov%':>7s} {'LP+':>7s} {'overchg':>8s} {'net':>8s}")

    grid = []
    best = None
    for secs in WINDOWS:
        kb = max(1, round(secs / config.BLOCK_SECONDS))
        parts = diagnose.decompose(series, trades, kb)
        drift = [None if p is None else p[1] for p in parts]
        null = diagnose.null_of(trades, parts, rnd)

        for th in THETAS:
            r = evaluate(trades, drift, th, config.ESCROW_FEE_BPS)
            nl = evaluate(trades, null, th, config.ESCROW_FEE_BPS)
            if not r or not nl:
                continue

            vol = r["informed_vol"] + r["benign_vol"]
            base_rev = vol * config.BASE_FEE_BPS / 10_000
            lp_uplift = r["recovered"] / base_rev * 100

            # a trade carrying no information still trips the threshold at the
            # null rate, and pays the escrow when it does
            overcharge_bps = nl["informed_pct"] / 100 * config.ESCROW_FEE_BPS
            recovery = r["recovered"] / r["extracted"] * 100 if r["extracted"] > 0 else 0

            # LP gain net of what was taken from traders who did nothing wrong
            net = r["recovered"] - (r["benign_vol"] * overcharge_bps / 10_000)

            print(f"{secs:5d} {th:6d} {r['informed_pct']:6.2f} {nl['informed_pct']:6.2f} "
                  f"{r['fair_escrow_bps']:8.1f}b {recovery:7.1f} {lp_uplift:6.1f}% "
                  f"{overcharge_bps:7.2f}b {net:8,.0f}")

            grid.append({
                "window_seconds": secs,
                "theta_bps": th,
                "informed_pct": r["informed_pct"],
                "null_informed_pct": nl["informed_pct"],
                "informed_volume_usd": r["informed_vol"],
                "benign_volume_usd": r["benign_vol"],
                "extracted_usd": r["extracted"],
                "recovered_usd": r["recovered"],
                "recovery_pct": recovery,
                "fair_escrow_bps": r["fair_escrow_bps"],
                "lp_uplift_pct": lp_uplift,
                "uninformed_overcharge_bps": overcharge_bps,
                "net_usd": net,
            })

            if overcharge_bps <= 1.0 and (best is None or net > best[0]):
                best = (net, secs, th, r, nl, overcharge_bps, recovery, lp_uplift)

    if best:
        _, secs, th, r, nl, over, recovery, uplift = best
        print(f"\nbest cell holding overcharge under 1 bp:")
        print(f"  window {secs}s   theta {th} bps")
        print(f"  flags {r['informed_pct']:.2f}% of trades (null {nl['informed_pct']:.2f}%)")
        print(f"  informed flow captured ${r['extracted']:,.0f}, escrow recovers ${r['recovered']:,.0f} "
              f"({recovery:.0f}%)")
        print(f"  fair escrow at this theta would be {r['fair_escrow_bps']:.0f} bps")
        print(f"  LP revenue +{uplift:.1f}% over base fee alone")
        print(f"  uninformed trader pays +{over:.2f} bps in expectation")

    chosen = next(
        (g for g in grid if g["window_seconds"] == config.K_SECONDS and g["theta_bps"] == config.THETA_BPS),
        None,
    )
    config.OUT.mkdir(exist_ok=True)
    path = config.OUT / "economics.json"
    path.write_text(json.dumps({
        "fixture": sorted(config.FIXTURES.glob("swaps_*.csv"))[-1].name,
        "trades": len(trades),
        "escrow_fee_bps": config.ESCROW_FEE_BPS,
        "min_swap_usd": config.MIN_SWAP_USD,
        "chosen": chosen,
        "grid": grid,
    }, indent=2))
    print(f"\n-> {path.relative_to(config.ROOT.parent)}")


if __name__ == "__main__":
    main()
