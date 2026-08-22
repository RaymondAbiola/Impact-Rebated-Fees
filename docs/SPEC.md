# Mechanism spec

Single source of truth for the classification rule and its parameters. The
offline classifier in `analysis/` and the hook in `contracts/` must agree with
this document and with each other.

## Fee split

A swap of size `x` pays `BASE_FEE + ESCROW_FEE` in total.

| Portion | Goes to | When | How |
|---|---|---|---|
| `BASE_FEE` | LPs | Immediately | Dynamic LP fee override returned from `beforeSwap` |
| `ESCROW_FEE` | Held by hook | At swap | Hook fee taken via `afterSwapReturnDelta`, minted as ERC-6909 claims |

These are two different mechanisms and it matters. A dynamic fee override goes
entirely to LPs through core accounting and the hook cannot recover any of it,
so the escrowed portion has to be taken separately as a hook fee.

At settlement the escrow either gets `donate()`d to the LPs or burned and sent
back to the trader.

## Execution price

The reference point for a swap is the **volume-weighted price the trade actually
got**, derived from the swap's `BalanceDelta`:

```
P_exec = |amount1| / |amount0|
```

Not the pre-swap price and not the post-swap price. Both are wrong:

- **Pre-swap price** would flag every large trade as informed, because every
  swap moves the price by its own size.
- **Post-swap price** would classify arbitrage as benign. An arbitrageur moves
  the pool to the true price and it stays there, so measuring from where they
  left it gives roughly zero markout. Measuring from what they *paid* captures
  the gap they collected.

## Classification

Let `P_after` be the pool's reference price at the end of the settlement window
and `d` the trade direction.

```
zeroForOne  (sold token0):  informed if  P_after < P_exec * (1 - THETA)
!zeroForOne (bought token0): informed if  P_after > P_exec * (1 + THETA)
```

In words: the trader is informed if the price kept moving the way their trade
was positioned for, by more than the threshold.

- informed  -> escrow donated to LPs
- otherwise -> escrow refunded to trader

`P_after` is a time-weighted average across the settlement window rather than a
spot reading, so a single-block price push cannot move it.

### Implementation note

Compare as a ratio using full-precision `mulDiv` rather than converting to log
space. Ticks are tempting because one tick is roughly one basis point, but the
execution VWAP does not land on a tick boundary and the conversion costs more
than it saves.

## Parameters

Placeholders until the sweep in `analysis/` locks them. Once chosen they live in
`contracts/src/Params.sol` and are mirrored into the analysis config.

| Name | Placeholder | Meaning |
|---|---|---|
| `BASE_FEE` | 5 bps | Paid to LPs at swap time, never refundable |
| `ESCROW_FEE` | 25 bps | Held, then refunded or donated |
| `K` | 20 blocks | Settlement window |
| `THETA` | 10 bps | Markout threshold for calling a trade informed |
| `MIN_SWAP` | TBD | Below this, skip escrow entirely and charge base fee only |
| `MAX_REFUND` | `ESCROW_FEE` | Per-swap refund cap |
| `EXPIRY` | 10x `K` | After this, unsettled escrow defaults to LPs |
| `BOUNTY` | TBD | Share of escrow paid to whoever calls `settle` |

`K` and `THETA` are the two real dials. `K` too short and noise dominates; too
long and capital sits idle and the signal blurs. `THETA` trades false positives
against false negatives directly.

## Invariants

The test suite has to hold these:

- `sum(escrow held) >= sum(unsettled liabilities)` at all times
- a receipt settles at most once
- every receipt has a settlement path, including after expiry
- refund never exceeds what was escrowed for that swap
- the hook never touches `BASE_FEE` once it has gone to LPs

## Known gaps

- **Beneficiary.** Swaps arrive through routers, so `msg.sender` is not the
  trader. The intended recipient is passed through `hookData`, with a fallback
  to `msg.sender` when absent.
- **Settlement gas.** Paid by a bounty from the escrow, with batch settlement to
  amortise it.
- **Manipulation.** Farming refunds means moving the pool's average price across
  the whole window, which costs more than the capped refund. Test 34 has to
  demonstrate this, not just assert it.
- **Classification error.** This is statistical, not exact. The measured error
  rate gets published rather than hidden.
