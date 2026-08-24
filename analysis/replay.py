"""Build a replay fixture the Solidity tests can check themselves against.

Uses the real tick column from the fetched swaps, and computes the expected
drift with the same integer arithmetic the contract uses, so a mismatch means
the Solidity accumulator is wrong rather than the model being different.
"""

import json

import classify
import config

SAMPLE = 400
WINDOW = config.K_BLOCKS * config.BLOCK_SECONDS
THETA = config.THETA_BPS


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: python3 analysis/fetch.py")

    rows = []
    with paths[-1].open() as f:
        import csv
        for r in csv.DictReader(f):
            rows.append({"block": int(r["block"]), "tick": int(r["tick"]), "amount0": int(r["amount0"])})
    # pick the most volatile contiguous slice, otherwise a quiet stretch gives
    # every case the same verdict and the informed branch never runs
    best, best_span = 0, -1
    for i in range(0, max(1, len(rows) - SAMPLE), SAMPLE // 4):
        window = rows[i:i + SAMPLE]
        span = max(r["tick"] for r in window) - min(r["tick"] for r in window)
        if span > best_span:
            best, best_span = i, span
    rows = rows[best:best + SAMPLE]
    base = rows[0]["block"]
    print(f"slice at swap {best}, tick span {best_span}")

    # one observation per block, last swap in the block wins, exactly as the hook
    obs = {}
    for r in rows:
        obs[(r["block"] - base) * config.BLOCK_SECONDS] = r["tick"]
    series = sorted(obs.items())

    # mirror of the contract: cumulative carries the previous tick forward
    cum, last_t, last_tick = 0, None, None
    snapshots = {}
    for t, tick in series:
        if last_t is not None:
            cum += last_tick * (t - last_t)
        snapshots[t] = cum
        last_t, last_tick = t, tick

    def cumulative_at(t):
        c, pt, ptick = 0, None, None
        for ts, tick in series:
            if ts > t:
                break
            if pt is not None:
                c += ptick * (ts - pt)
            pt, ptick = ts, tick
        if pt is not None and t > pt:
            c += ptick * (t - pt)
        return c

    cases = []
    for t, tick in series:
        settle_at = t + WINDOW
        if settle_at > series[-1][0]:
            break
        elapsed = settle_at - t
        mean = (cumulative_at(settle_at) - snapshots[t]) // elapsed
        for zero_for_one in (True, False):
            drift = (tick - mean) if zero_for_one else (mean - tick)
            cases.append({
                "swapTimestamp": t,
                "tickPost": tick,
                "zeroForOne": zero_for_one,
                "settleAt": settle_at,
                "expectedDrift": drift,
                "expectedInformed": drift > THETA,
            })

    cases = cases[:120]
    # flat arrays: forge parses these without struct field-order games
    out = {
        "windowSeconds": WINDOW,
        "thetaBps": THETA,
        "seriesTimestamp": [t for t, _ in series],
        "seriesTick": [tick for _, tick in series],
        "caseSwapTimestamp": [c["swapTimestamp"] for c in cases],
        "caseTickPost": [c["tickPost"] for c in cases],
        "caseZeroForOne": [1 if c["zeroForOne"] else 0 for c in cases],
        "caseSettleAt": [c["settleAt"] for c in cases],
        "caseExpectedDrift": [c["expectedDrift"] for c in cases],
        "caseExpectedInformed": [1 if c["expectedInformed"] else 0 for c in cases],
    }
    config.OUT.mkdir(exist_ok=True)
    path = config.OUT / "replay.json"
    path.write_text(json.dumps(out, indent=2))
    print(f"{len(series)} observations, {len(cases)} cases -> {path.relative_to(config.ROOT.parent)}")
    print(f"informed in sample: {sum(out['caseExpectedInformed'])}/{len(cases)}")


if __name__ == "__main__":
    main()
