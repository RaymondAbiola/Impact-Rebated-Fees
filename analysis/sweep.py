"""Grid search over the settlement window and the markout threshold.

The window is expressed in seconds, not blocks. The fixture is mainnet at 12s
per block, the hook will run on Unichain at 1s, so anything measured in blocks
here would be wrong by an order of magnitude at deploy time.

Also runs a null model. Each trade keeps its real direction but is paired with
another trade's forward price move, which preserves both distributions and
destroys only the link between them. If the real informed rate is not clearly
above the null, direction carries no information and the mechanism is dead.

Randomising the direction instead would be the wrong null: it makes the
distribution symmetric and flags half of everything by construction.
"""

import json
import random

import classify
import config

K_SECONDS = [30, 60, 120, 240, 480, 960, 1800]
THETAS = [0, 2, 5, 10, 20, 40]


def raw_moves(series, trades, k_blocks):
    """Unsigned forward price move per trade, in bps."""
    lo, _, prefix = series
    out = []
    for t in trades:
        after = classify.window_mean(lo, prefix, t["block"] + 1, t["block"] + k_blocks)
        out.append(None if after is None
                   else (after - t["exec_price"]) / t["exec_price"] * 10_000)
    return out


def signed(trades, moves):
    return [None if m is None else (1.0 if t["acquired_volatile"] else -1.0) * m
            for t, m in zip(trades, moves)]


def shuffled_null(trades, moves, rnd):
    """Real directions, other trades' price moves."""
    valid = [m for m in moves if m is not None]
    rnd.shuffle(valid)
    it = iter(valid)
    swapped = [None if m is None else next(it) for m in moves]
    return signed(trades, swapped)


def score(trades, mk, theta, base_fee, escrow_fee):
    n = i_n = 0
    vol = i_vol = 0.0
    extracted = recovered = 0.0
    i_size = b_size = 0.0

    for t, m in zip(trades, mk):
        if m is None:
            continue
        n += 1
        vol += t["usd"]
        if m > theta:
            i_n += 1
            i_vol += t["usd"]
            i_size += t["usd"]
            extracted += t["usd"] * m / 10_000
            recovered += t["usd"] * escrow_fee / 10_000
        else:
            b_size += t["usd"]

    if not n:
        return None
    b_n = n - i_n
    hook_rev = vol * base_fee / 10_000 + recovered
    flat_rev = vol * base_fee / 10_000

    return {
        "n": n,
        "informed_pct": i_n / n * 100,
        "informed_vol_pct": i_vol / vol * 100 if vol else 0,
        "size_ratio": (i_size / i_n) / (b_size / b_n) if i_n and b_n else 0,
        "extracted_usd": extracted,
        "recovered_usd": recovered,
        "recovery_pct": recovered / extracted * 100 if extracted > 0 else 0,
        "lp_uplift_pct": (hook_rev / flat_rev - 1) * 100 if flat_rev else 0,
    }


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: npm run fetch")

    rows = classify.load_fixture(paths[-1])
    series, trades, skipped = classify.prepare(rows)
    print(f"{len(trades)} trades usable, skipped {skipped}\n")

    rnd = random.Random(1)

    grid = []
    print(f"{'window':>9s} {'blk':>5s} {'theta':>6s} {'inf%':>6s} {'vol%':>6s} "
          f"{'size x':>7s} {'extracted':>11s} {'recovered':>11s} {'rec%':>6s} {'LP+':>7s} {'null%':>6s} {'lift':>6s}")
    for secs in K_SECONDS:
        kb = max(1, round(secs / config.BLOCK_SECONDS))
        moves = raw_moves(series, trades, kb)
        mk = signed(trades, moves)
        mk_null = shuffled_null(trades, moves, rnd)
        for th in THETAS:
            s = score(trades, mk, th, config.BASE_FEE_BPS, config.ESCROW_FEE_BPS)
            null = score(trades, mk_null, th, config.BASE_FEE_BPS, config.ESCROW_FEE_BPS)
            if not s:
                continue
            s.update(window_seconds=secs, mainnet_blocks=kb, theta_bps=th,
                     null_informed_pct=null["informed_pct"], lift=s["informed_pct"] - null["informed_pct"])
            grid.append(s)
            print(f"{secs:8d}s {kb:5d} {th:6d} {s['informed_pct']:6.1f} {s['informed_vol_pct']:6.1f} "
                  f"{s['size_ratio']:7.2f} {s['extracted_usd']:11,.0f} {s['recovered_usd']:11,.0f} "
                  f"{s['recovery_pct']:6.1f} {s['lp_uplift_pct']:6.1f}% {null['informed_pct']:6.1f} {s['informed_pct']-null['informed_pct']:+6.1f}")

    config.OUT.mkdir(exist_ok=True)
    with (config.OUT / "sweep.json").open("w") as f:
        json.dump({"grid": grid, "block_seconds": config.BLOCK_SECONDS,
                   "base_fee_bps": config.BASE_FEE_BPS, "escrow_fee_bps": config.ESCROW_FEE_BPS}, f, indent=2)
    print(f"\n-> {(config.OUT / 'sweep.json').relative_to(config.ROOT.parent)}")


if __name__ == "__main__":
    main()
