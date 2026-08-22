"""Pull Uniswap v3 Swap logs into a csv fixture.

Only needs eth_getLogs, so a normal Infura key works, no archive plan required.
Everything the classifier needs is in the event itself: signed amounts give the
execution price and direction, sqrtPriceX96 gives the price series.
"""

import csv
import json
import sys
import urllib.error
import urllib.request

import config

MAX_SPAN = 2000
MIN_SPAN = 25


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    req = urllib.request.Request(
        config.rpc_url(),
        data=body.encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        payload = json.loads(r.read())
    if "error" in payload:
        raise RuntimeError(payload["error"].get("message", payload["error"]))
    return payload["result"]


def latest_block():
    return int(rpc("eth_blockNumber", []), 16)


def to_int(word, signed=False, bits=256):
    v = int(word, 16)
    if signed and v >= 1 << (bits - 1):
        v -= 1 << bits
    return v


def decode_swap(log):
    data = log["data"][2:]
    words = ["0x" + data[i : i + 64] for i in range(0, len(data), 64)]
    if len(words) < 5:
        raise ValueError("unexpected swap payload")
    return {
        "block": int(log["blockNumber"], 16),
        "tx": log["transactionHash"],
        "log_index": int(log["logIndex"], 16),
        "sender": "0x" + log["topics"][1][-40:],
        "recipient": "0x" + log["topics"][2][-40:],
        "amount0": to_int(words[0], signed=True),
        "amount1": to_int(words[1], signed=True),
        "sqrt_price_x96": to_int(words[2]),
        "liquidity": to_int(words[3]),
        "tick": to_int(words[4], signed=True, bits=24),
    }


def fetch_range(start, end):
    """Walk the range in chunks, shrinking on provider limits."""
    out = []
    span = MAX_SPAN
    cursor = start
    while cursor <= end:
        stop = min(cursor + span - 1, end)
        try:
            logs = rpc(
                "eth_getLogs",
                [
                    {
                        "address": config.POOL,
                        "topics": [config.SWAP_TOPIC],
                        "fromBlock": hex(cursor),
                        "toBlock": hex(stop),
                    }
                ],
            )
        except (RuntimeError, urllib.error.URLError) as e:
            if span > MIN_SPAN:
                span = max(MIN_SPAN, span // 2)
                continue
            raise SystemExit(f"failed at block {cursor}: {e}")

        out.extend(decode_swap(l) for l in logs)
        pct = (stop - start + 1) / max(1, end - start + 1) * 100
        print(f"\r  {stop - start + 1}/{end - start + 1} blocks ({pct:.0f}%)  {len(out)} swaps", end="", file=sys.stderr)
        cursor = stop + 1
        if span < MAX_SPAN and len(logs) < 500:
            span = min(MAX_SPAN, span * 2)
    print(file=sys.stderr)
    return out


FIELDS = [
    "block", "tx", "log_index", "sender", "recipient",
    "amount0", "amount1", "sqrt_price_x96", "liquidity", "tick",
]


def main():
    config.load_dotenv()

    blocks = int(sys.argv[1]) if len(sys.argv) > 1 else 50_000
    end = latest_block()
    # stay a little behind the tip so the settlement window has room
    end -= 200
    start = end - blocks + 1

    print(f"pool  {config.POOL}", file=sys.stderr)
    print(f"range {start} to {end}", file=sys.stderr)

    swaps = fetch_range(start, end)
    swaps.sort(key=lambda s: (s["block"], s["log_index"]))

    config.FIXTURES.mkdir(exist_ok=True)
    path = config.FIXTURES / f"swaps_{start}_{end}.csv"
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(swaps)

    print(f"{len(swaps)} swaps -> {path.relative_to(config.ROOT.parent)}", file=sys.stderr)


if __name__ == "__main__":
    main()
