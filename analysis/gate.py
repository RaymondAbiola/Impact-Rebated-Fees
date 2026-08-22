"""Export the evidence used to choose settlement parameters."""

import json
import random

import classify
import config
import diagnose

WINDOWS = [30, 60, 120, 240, 480]
THETAS = [0, 2, 5, 10, 20, 40]
BUCKETS = [-200, -100, -50, -25, -10, -5, 0, 5, 10, 25, 50, 100, 200]


def histogram(values):
    counts = [0] * (len(BUCKETS) + 1)
    for value in values:
        i = 0
        while i < len(BUCKETS) and value >= BUCKETS[i]:
            i += 1
        counts[i] += 1
    return {"edges_bps": BUCKETS, "counts": counts}


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: python3 analysis/fetch.py")
    rows = classify.load_fixture(paths[-1])
    series, trades = diagnose.prepare(rows)
    rnd = random.Random(7)
    output = []
    for seconds in WINDOWS:
        blocks = max(1, round(seconds / config.BLOCK_SECONDS))
        parts = diagnose.decompose(series, trades, blocks)
        keep = [part for part in parts if part is not None]
        drift = [part[1] for part in keep]
        markout = [part[2] for part in keep]
        null = [move for move in diagnose.null_of(trades, parts, rnd) if move is not None]
        for theta in THETAS:
            informed = sum(value > theta for value in drift)
            null_informed = sum(value > theta for value in null)
            output.append({
                "window_seconds": seconds, "mainnet_blocks": blocks, "theta_bps": theta,
                "n": len(drift), "informed_pct": informed / len(drift) * 100,
                "null_informed_pct": null_informed / len(null) * 100,
                "lift_pct_points": informed / len(drift) * 100 - null_informed / len(null) * 100,
                "markout_histogram": histogram(markout),
                "drift_histogram": histogram(drift), "null_histogram": histogram(null),
                "base_fee_bps": config.BASE_FEE_BPS, "escrow_fee_bps": config.ESCROW_FEE_BPS,
            })
    config.OUT.mkdir(exist_ok=True)
    path = config.OUT / "gate.json"
    path.write_text(json.dumps({"fixture": paths[-1].name, "rows": output}, indent=2) + "\n")
    print(f"wrote {path.relative_to(config.ROOT.parent)} ({len(output)} cells)")


if __name__ == "__main__":
    main()
