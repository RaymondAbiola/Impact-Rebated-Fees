# Impact Rebated Fees

A Uniswap v4 hook that charges every swap a deposit, holds it for sixty seconds,
then gives it back unless the pool was still mispriced after the trade finished.

> A security deposit on a swap. Everyone pays it. You get it back if you were not
> the problem.

Live on Unichain Sepolia. Hook at
[`0x7dEC15A39D42c9B5d41E0c351c0C9aDcbC8AC044`](https://sepolia.uniscan.xyz/address/0x7dEC15A39D42c9B5d41E0c351c0C9aDcbC8AC044).

## The problem

Liquidity providers lose money to traders who are ahead of price moves. When a
trade is followed by the price continuing in the same direction, it means the
pool was still quoting the wrong price after that trade finished. It is about to
be traded against again, at a price that is still stale.

Pools defend themselves by charging everyone the same fee, so ordinary traders
subsidise this. This hook charges the trades that leave the pool still
mispriced, instead of everyone.

## How it works

Everything happens in two transactions, sixty seconds apart.

**At the swap.** The pool charges its usual fee, untouched. The hook takes an
additional 25 bps and holds it as an ERC-6909 claim inside the PoolManager, so
the escrow never leaves Uniswap's own vault. It records where the swap left the
price, and a bookmark into a running total of price multiplied by time.

Every trader is charged identically here. The hook cannot know who is informed,
because the next sixty seconds have not happened yet.

**At settlement.** Anyone can call `settle()`. The hook reads the running total
again, subtracts the bookmark, and divides by elapsed time to get the average
price across the window. If the price kept drifting the way the trade was
positioned by more than 20 ticks, the escrow is donated to the liquidity
providers. Otherwise it goes back to the trader.

Whoever calls settle keeps 2% of the escrow. A trader settling their own receipt
receives both the refund and the bounty, so self-settling costs them nothing.
Escrow left unsettled for ten minutes defaults to the liquidity providers, which
is the safe direction to fail in.

No oracle. No off chain service. The pool's own price path is the entire signal.

See [docs/SPEC.md](docs/SPEC.md) for the exact rule and parameters.

## Evidence

Replayed against 26,209 real USDC/WETH swaps from mainnet.

| | |
|---|---|
| Flagged as informed | 3.20% of trades |
| Same threshold under a null model | 2.85% |
| Value captured by informed flow | $305,032 |
| Recovered by the escrow | 42.8% of that |
| LP revenue over the base fee alone | +32.7% |
| Expected cost to an uninformed trader | +0.71 bps |

Parameters were chosen on that last number rather than on how many trades get
flagged. Settings that look better on revenue charge ordinary traders three
times as much, which is the opposite of what the hook claims to do. See
`analysis/economics.py`.

## What is new here

Charging informed flow more than retail is a well known goal. Uniswap has an
open request for it (v4-periphery issue #40) and many teams have attempted it:

| Project | Signal | Decides |
|---|---|---|
| PegGuard | Trailing basis EMA vs Pyth | Before the swap |
| TRIDENT | Oracle gap | Before the swap |
| Yield-Subsidized Directional | Fee scaling by direction | Before the swap |
| DAMM | Revealed fee preference | Before the swap |
| Nezlobin Directional Fee | Prior block price direction | Before the swap |
| Arb Controller | Prior block price direction | Before the swap |
| **This** | **The swap's own realised drift** | **After the swap** |

Every prior design classifies a trade before it executes, which means predicting.
A fee set in advance has to be conservative: it overtaxes benign flow that
happens to arrive during volatility, and undertaxes patterns its signal was not
built for. Settling afterwards has no classification error on the charging side,
because it observes the outcome instead of forecasting it.

The literature has proposed linking fee levels to markout. Using each swap's own
realised drift to settle that swap's own fee is the part that has not been built.

### The measurement that makes it work

There are three places you could start measuring from, and the choice decides
whether the mechanism functions at all.

| Start from | What it actually measures |
|---|---|
| The price before the swap | Mostly how large the trade was |
| The price the trader paid | Drowned by their own impact reverting |
| **The price after the swap** | **Only what the market did next** |

We built the middle one first and it failed. Across 26,000 real swaps every
threshold flagged fewer trades than random chance, because a trader's own price
impact bouncing back pulls everyone toward looking benign. Starting from the post
swap price excludes the trade's own footprint entirely.

## Honest limits

- It is statistical. A trade carrying no information still trips the threshold
  about 2.9% of the time by chance, which is where the 0.71 bps expected cost
  comes from.
- An arbitrageur who corrects the price in one clean move is not caught. The
  price does not keep drifting afterwards, so there is nothing to measure. What
  this catches is the trader who leaves the pool still moving.
- Attempted manipulation reads benign, because manipulation is a price move that
  snaps back.
- The escrow recovers 42.8% of what informed flow captured. Charging the rate
  that recovers all of it would double what ordinary traders pay, so the gap is
  deliberate.
- Not audited. The demo pool uses mock tokens with an unguarded mint.

## Partner integrations

**None.** This hook deliberately uses no oracle and no off chain service. The
pool's own price path is the entire signal, so there is nothing to integrate
without giving up the property that makes it different: every comparable design
depends on Pyth, Chainlink, or an AVS, and this one depends on nothing.

## Deployment

Unichain Sepolia, chain id 1301.

| | |
|---|---|
| Hook | `0x7dEC15A39D42c9B5d41E0c351c0C9aDcbC8AC044` |
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| Pool id | `0x455a876e00e907027eb9e133134c826c500f7efce9c425c6f3fb49e241455dae` |
| Swap router | `0x586E54DBEBd2999ef49f73632630AA8A689C6A6C` |
| iUSD | `0x6BdACF5421d27aE8E88405d135e8A291F7B34B31` |
| iETH | `0x818EB378DcAE64a4012c5bF0fDCC24c96fcBE57a` |

The pool is a normal static fee tier at 5 bps. The hook declares only `afterSwap`
and `afterSwapReturnDelta`, so it never touches pricing and routers quote it
normally. Verified against the v4 Quoter on the live pool.

## Tests

26 tests, 96% line coverage on the hook.

The one worth knowing about is `test/Replay.t.sol`. It walks a real mainnet tick
series through the hook's accumulator on the same timeline it would see on chain,
and asserts the Solidity drift matches the offline Python reference for all 200
cases. So "the contract implements the mechanism we analysed" is something you
can check with one command.

```bash
npm test                  # forge test
npm run analyze           # pick parameters from the replay
npm run dev               # frontend
```

## Layout

```
contracts/   foundry project, the hook and its tests
app/         next.js frontend
analysis/    offline classifier, gate, and parameter choice
docs/        mechanism spec
```

## Running the demo

```bash
npm run seed        # four swaps, one engineered to flag informed
                    # wait 60 seconds
npm run settle      # batch settle everything ready
npm run snapshot    # record the result as an offline fallback
```

The seeding is deliberate. At a 20 tick threshold only about 3% of real flow is
informed, so waiting for one during a demo is a coin toss. A small trade followed
by a large one in the same direction leaves the price still moving the way the
first trade was positioned, which is exactly the condition the hook is built to
detect.

## Status

Work in progress, built for the Uniswap Hook Incubator. Not audited. Do not use
with real funds.
