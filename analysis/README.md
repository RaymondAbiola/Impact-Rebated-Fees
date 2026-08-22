# analysis

Offline replay of real swaps, used to pick the parameters before any of it goes
on chain. If the two populations do not separate here, the mechanism does not
work and the contract should not be written.

## Setup

```bash
cp .env.example .env      # add your Infura key
```

Stdlib only, nothing to install yet.

## Fetch

```bash
python3 analysis/fetch.py            # last 50k blocks (~7 days)
python3 analysis/fetch.py 200000     # ~1 month
```

Writes `fixtures/swaps_<start>_<end>.csv`. Only uses `eth_getLogs`, so a normal
Infura key is fine.

Each row is one Swap event from the v3 USDC/WETH 0.05% pool:

| column | use |
|---|---|
| `amount0`, `amount1` | signed, gives execution price and direction |
| `sqrt_price_x96` | builds the reference price series for settlement |
| `block` | settlement window, and time weighting |
| `sender`, `recipient` | sanity checks only, never used to classify |

Deliberately not used: sender address. Classifying by who is trading would be a
reputation system, which is a different project and one that has been built
already. The whole point is that the price path alone tells you.

## Gate output

Run `PYTHONPATH=analysis python3 analysis/gate.py` after a fixture exists. The
result in `out/gate.json` records markout, post-swap drift, shuffled-null
histograms, and lift for every tested window and threshold. The gate compares
drift: execution price already includes fee and own price impact, so comparing
execution-relative markout to a null creates a mechanical negative offset.
