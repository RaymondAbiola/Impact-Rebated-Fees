"""Markout classifier.

Implements the rule in docs/SPEC.md. A trade is informed if the price kept
moving the way it was positioned for, measured from the price the trade
actually got.

Note what classify() does not take: any address. Deciding a fee from who is
trading is a reputation system, which is a different mechanism with a sybil
problem. The whole claim here is that the price path alone is enough.
"""

import csv
import sys
from bisect import bisect_right

import config

Q96 = 1 << 96
DEC0 = 10 ** config.TOKEN0["decimals"]
DEC1 = 10 ** config.TOKEN1["decimals"]


def pool_price(sqrt_price_x96: int) -> float:
    """USDC per WETH implied by the pool."""
    r = (sqrt_price_x96 / Q96) ** 2  # token1 per token0, raw units
    return (1.0 / r) * DEC1 / DEC0


def load_fixture(path):
    with open(path) as f:
        return [
            {
                "block": int(r["block"]),
                "tx": r["tx"],
                "amount0": int(r["amount0"]),
                "amount1": int(r["amount1"]),
                "sqrt_price_x96": int(r["sqrt_price_x96"]),
            }
            for r in csv.DictReader(f)
        ]


def build_price_series(rows):
    """Forward-filled pool price per block, plus prefix sums for window means."""
    lo, hi = rows[0]["block"], rows[-1]["block"]
    n = hi - lo + 1

    marks = {}
    for r in rows:
        marks[r["block"]] = r["sqrt_price_x96"]  # last swap in the block wins

    prices = [0.0] * n
    last = pool_price(rows[0]["sqrt_price_x96"])
    for i in range(n):
        b = lo + i
        if b in marks:
            last = pool_price(marks[b])
        prices[i] = last

    prefix = [0.0] * (n + 1)
    for i, p in enumerate(prices):
        prefix[i + 1] = prefix[i] + p

    return lo, hi, prefix


def window_mean(lo, prefix, start_block, end_block):
    """Time-weighted mean price over [start_block, end_block]. Blocks are a
    fixed 12s post-merge so block weighting is time weighting."""
    a = start_block - lo
    b = end_block - lo + 1
    if a < 0 or b > len(prefix) - 1 or b <= a:
        return None
    return (prefix[b] - prefix[a]) / (b - a)


def classify(exec_price: float, acquired_volatile: bool, price_after: float, theta_bps: int):
    """Returns (is_informed, markout_bps). No identity involved, by design."""
    sign = 1.0 if acquired_volatile else -1.0
    markout_bps = sign * (price_after - exec_price) / exec_price * 10_000
    return markout_bps > theta_bps, markout_bps


def prepare(rows, min_swap_usd=None):
    """One pass over the fixture: price series plus the per-swap facts that
    do not depend on K or theta."""
    min_swap_usd = min_swap_usd if min_swap_usd is not None else config.MIN_SWAP_USD
    lo, hi, prefix = build_price_series(rows)
    trades, skipped = [], {"dust": 0, "degenerate": 0}
    for r in rows:
        a0, a1 = r["amount0"], r["amount1"]
        if a0 == 0 or a1 == 0:
            skipped["degenerate"] += 1
            continue
        usd = abs(a0) / DEC0
        if usd < min_swap_usd:
            skipped["dust"] += 1
            continue
        trades.append({
            "block": r["block"], "tx": r["tx"], "usd": usd,
            "exec_price": usd / (abs(a1) / DEC1),
            "acquired_volatile": a0 > 0,
        })
    return (lo, hi, prefix), trades, skipped


def run(rows, k=None, theta_bps=None, min_swap_usd=None):
    k = k if k is not None else config.K_BLOCKS
    theta_bps = theta_bps if theta_bps is not None else config.THETA_BPS
    min_swap_usd = min_swap_usd if min_swap_usd is not None else config.MIN_SWAP_USD

    lo, hi, prefix = build_price_series(rows)
    results, skipped = [], {"dust": 0, "no_window": 0, "degenerate": 0}

    for r in rows:
        a0, a1 = r["amount0"], r["amount1"]
        if a0 == 0 or a1 == 0:
            skipped["degenerate"] += 1
            continue

        usd = abs(a0) / DEC0
        if usd < min_swap_usd:
            skipped["dust"] += 1
            continue

        exec_price = usd / (abs(a1) / DEC1)
        acquired_volatile = a0 > 0  # sent USDC in, took WETH out

        after = window_mean(lo, prefix, r["block"] + 1, r["block"] + k)
        if after is None:
            skipped["no_window"] += 1
            continue

        informed, markout = classify(exec_price, acquired_volatile, after, theta_bps)
        results.append(
            {
                "block": r["block"],
                "tx": r["tx"],
                "usd": usd,
                "exec_price": exec_price,
                "price_after": after,
                "acquired_volatile": acquired_volatile,
                "markout_bps": markout,
                "informed": informed,
                "fee_bps": config.BASE_FEE_BPS + (config.ESCROW_FEE_BPS if informed else 0),
            }
        )

    return results, skipped


def summarise(results, skipped, k, theta_bps):
    n = len(results)
    if not n:
        raise SystemExit("nothing classified")

    informed = [r for r in results if r["informed"]]
    benign = [r for r in results if not r["informed"]]
    vol_i = sum(r["usd"] for r in informed)
    vol_b = sum(r["usd"] for r in benign)
    vol = vol_i + vol_b

    hook = sum(r["usd"] * r["fee_bps"] / 10_000 for r in results)

    print(f"K={k} blocks  theta={theta_bps} bps  min_swap=${config.MIN_SWAP_USD}")
    print(f"classified {n}   skipped {skipped}")
    print()
    print(f"  informed  {len(informed):6d}  {len(informed)/n*100:5.1f}% of swaps   "
          f"${vol_i/1e6:7.1f}m  {vol_i/vol*100:4.1f}% of volume   avg ${vol_i/max(1,len(informed)):,.0f}")
    print(f"  benign    {len(benign):6d}  {len(benign)/n*100:5.1f}% of swaps   "
          f"${vol_b/1e6:7.1f}m  {vol_b/vol*100:4.1f}% of volume   avg ${vol_b/max(1,len(benign)):,.0f}")
    print()
    print("  LP fee revenue over this window")
    for flat in (5, 30):
        base = vol * flat / 10_000
        delta = (hook / base - 1) * 100 if base else 0
        print(f"    flat {flat:2d} bps : ${base:12,.0f}    hook: ${hook:12,.0f}   {delta:+6.1f}%")
    print()
    print(f"  benign traders pay {config.BASE_FEE_BPS} bps, "
          f"informed pay {config.BASE_FEE_BPS + config.ESCROW_FEE_BPS} bps")


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: npm run fetch")

    rows = load_fixture(paths[-1])
    k = int(sys.argv[1]) if len(sys.argv) > 1 else config.K_BLOCKS
    theta = int(sys.argv[2]) if len(sys.argv) > 2 else config.THETA_BPS

    results, skipped = run(rows, k, theta)
    summarise(results, skipped, k, theta)


if __name__ == "__main__":
    main()
