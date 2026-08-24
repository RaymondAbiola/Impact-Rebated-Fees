# Impact Rebated Fees

A Uniswap v4 hook that charges every swap a high fee up front, holds most of it
in escrow, then settles it a short while later based on whether the trade
actually cost the pool's liquidity providers anything.

Arbitrageurs forfeit the escrowed portion to LPs. Everyone else gets it back.

> Think of it as a security deposit on a swap. Everyone pays it, and you get it
> back if you were not the problem.

## Why

Pools charge every trader the same fee, but a small group of arbitrage bots is
responsible for most of what LPs lose. Ordinary traders pay a high fee to cover
damage they never caused, which is why fees stay high and why volatile pairs are
so hard to provide liquidity for.

The loss has a name in the literature: LVR, also called adverse selection or
toxic flow. Milionis et al. show it is the dominant drain on LPs, and Fritsch &
Canidio find that swap fees fail to cover arbitrage losses in most major Uniswap
pools.

## How

1. A swap executes normally. The pool keeps charging its usual LP fee and the
   hook takes an additional 25 bps for itself.
2. The 25 bps sits in escrow as ERC-6909 claims inside the PoolManager. The
   hook records the price the swap actually got.
3. After 60 seconds, anyone can call `settle()`. The hook compares the pool's
   time-weighted price since the swap against where the swap left it.
   - Price kept drifting in the trader's favour by more than 20 bps: they were
     informed. The escrow is donated to the LPs.
   - It did not: the escrow is refunded to the trader.

The swap itself stays instant and atomic, so routers and aggregators are
unaffected. Only the rebate is deferred.

No oracle. The pool's own price path is the signal.

On a week of real USDC/WETH flow this flags 3.2% of trades, lifts LP revenue
about a third over the base fee alone, and costs a trade carrying no
information 0.71 bps in expectation. The base fee is deliberately left at
whatever the pool already charges, so no ordinary trader pays more than they do
today and the gain comes out of arbitrage. Numbers from `analysis/economics.py`.

See [docs/SPEC.md](docs/SPEC.md) for the exact classification rule and
parameters.

## What is actually new here

Charging arbitrageurs more than retail is a well-known goal. Uniswap has an open
request for it (v4-periphery issue #40) and many teams have attempted it:

| Project | Signal | Decides |
|---|---|---|
| PegGuard | Trailing basis EMA vs Pyth | Before the swap |
| TRIDENT | Oracle gap | Before the swap |
| Yield-Subsidized Directional | Fee scaling by direction | Before the swap |
| DAMM | Revealed fee preference | Before the swap |
| Nezlobin Directional Fee | Prior-block price direction | Before the swap |
| Arb Controller | Prior-block price direction | Before the swap |
| **This** | **The swap's own realised markout** | **After the swap** |

Every prior design classifies a trade before it executes, which means it is
predicting. A fee set in advance has to be conservative: it overtaxes benign
flow that happens to arrive during volatility, and undertaxes toxic patterns its
signal was not built for. Settling after the fact has no classification error on
the charging side, because it observes the outcome instead of forecasting it.

The research literature has proposed *linking* fee levels to markout. Using each
swap's own markout to settle that swap's own fee is the part that has not been
built.

## Layout

```
contracts/   foundry project, the hook and its tests
app/         next.js frontend
analysis/    offline classifier and historical replay
scripts/     demo seeding
docs/        mechanism spec
```

## Development

```bash
npm test          # forge test
npm run analyze   # offline classifier over historical swaps
npm run dev       # frontend
npm run check     # tests + build
```

Contracts target solc 0.8.26 on the cancun EVM. v4-core, v4-periphery and
uniswap-hooks are pinned to matching recent commits rather than tags, because
`BaseHook` moved out of v4-periphery into OpenZeppelin's uniswap-hooks and the
tagged v4-core release predates the types that depends on.

## Status

Work in progress. Not audited. Do not use with real funds.
