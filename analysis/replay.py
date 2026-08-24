"""Build a replay fixture the Solidity tests can check themselves against.

Uses the real tick column from the fetched swaps and computes the expected
drift with the same integer arithmetic the contract uses, so a mismatch means
the Solidity accumulator is wrong rather than the model being different.

The slice is chosen to contain both verdicts. A quiet stretch would make every
case benign and leave the informed branch untested, which is exactly the branch
that moves money to the LPs.
"""

import csv
import json

import config

SAMPLE = 400
WINDOW = config.K_SECONDS
THETA = config.THETA_BPS


def build(rows):
    base = rows[0]["block"]
    obs = {}
    for r in rows:
        obs[(r["block"] - base) * config.BLOCK_SECONDS] = r["tick"]
    series = sorted(obs.items())
    if len(series) < 4:
        return None, None

    # mirror of the contract: cumulative carries the previous tick forward
    cum, last_t, last_tick = 0, None, None
    snap = {}
    for t, tick in series:
        if last_t is not None:
            cum += last_tick * (t - last_t)
        snap[t] = cum
        last_t, last_tick = t, tick

    def cumulative_at(target):
        c, pt, ptick = 0, None, None
        for ts, tick in series:
            if ts > target:
                break
            if pt is not None:
                c += ptick * (ts - pt)
            pt, ptick = ts, tick
        if pt is not None and target > pt:
            c += ptick * (target - pt)
        return c

    cases = []
    for t, tick in series:
        settle_at = t + WINDOW
        if settle_at > series[-1][0]:
            break
        mean = (cumulative_at(settle_at) - snap[t]) // (settle_at - t)
        for zero_for_one in (True, False):
            drift = (tick - mean) if zero_for_one else (mean - tick)
            cases.append({
                "swapTimestamp": t, "tickPost": tick, "zeroForOne": zero_for_one,
                "settleAt": settle_at, "expectedDrift": drift,
                "expectedInformed": drift > THETA,
            })
    return series, cases


def main():
    config.load_dotenv()
    paths = sorted(config.FIXTURES.glob("swaps_*.csv"))
    if not paths:
        raise SystemExit("no fixture, run: python3 analysis/fetch.py")

    rows = []
    with paths[-1].open() as f:
        for r in csv.DictReader(f):
            rows.append({"block": int(r["block"]), "tick": int(r["tick"])})

    # informed cases are only a few percent of flow, so a blind scan of slices
    # usually finds none. Anchor the search on the sharpest moves instead.
    per = {}
    for r in rows:
        per[r["block"]] = r["tick"]
    blocks = sorted(per)
    w = max(1, config.K_BLOCKS)
    hot = sorted(
        ((abs(per[blocks[i + w]] - per[blocks[i]]), i) for i in range(len(blocks) - w)),
        reverse=True,
    )[:40]
    starts = set()
    for _, i in hot:
        b = blocks[max(0, i - SAMPLE // 2)]
        starts.add(next(j for j, r in enumerate(rows) if r["block"] >= b))

    best = None
    for i in sorted(starts):
        series, cases = build(rows[i:i + SAMPLE])
        if not cases:
            continue
        informed = sum(1 for c in cases if c["expectedInformed"])
        score = min(informed, len(cases) - informed)
        if best is None or score > best[0]:
            best = (score, i, series, cases)

    if not best or best[0] == 0:
        raise SystemExit(f"no slice produces both verdicts at theta={THETA}, window={WINDOW}s")

    score, at, series, cases = best
    cases = cases[:200]
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
    print(f"slice at swap {at}, {len(series)} observations, {len(cases)} cases")
    print(f"informed {sum(out['caseExpectedInformed'])}/{len(cases)} -> {path.relative_to(config.ROOT.parent)}")


if __name__ == "__main__":
    main()
