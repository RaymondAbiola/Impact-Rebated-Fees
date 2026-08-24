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

Locked by `analysis/economics.py`. These live in
`contracts/src/Params.sol` and are mirrored in `analysis/config.py`.

| Name | Value | Meaning |
|---|---|---|
| `BASE_FEE` | match the pool's existing tier | Paid to LPs at swap time, never refundable |
| `ESCROW_FEE` | 25 bps | Held, then refunded or donated |
| `K` | 60 seconds | Settlement window; convert to chain blocks at deployment |
| `THETA` | 20 bps | Post-swap drift threshold for calling a trade informed |
| `MIN_SWAP` | per currency, owner set | Below this, no escrow and no receipt |
| `EXPIRY` | 10x `K` | After this, unsettled escrow defaults to LPs |
| `BOUNTY` | 200 bps of escrow | Paid to whoever calls settle |

`BASE_FEE` is not a free parameter. Set it to whatever the pool already charges
and the escrow becomes a pure surcharge on informed flow: no ordinary trader
pays more than they do today, and the LP gain comes entirely from arbitrage.
Setting it below the current tier means cutting the fee on the ~97% of volume
that is benign, which loses LPs money at constant volume no matter how good the
classifier is.

`MAX_REFUND` from earlier drafts is gone. The refund is always exactly what was
escrowed for that swap, so it is capped by construction and a separate
parameter would be dead code.

`K` and `THETA` were chosen by `analysis/economics.py`, on economics rather
than hit rate. The number that decides it is what a trade carrying no
information expects to pay on top of the base fee: it still trips the threshold
at the null rate, and pays the escrow when it does.

| Window | Theta | Flags | Uninformed pays | LP revenue |
|---|---|---|---|---|
| 120s | 10 bps | 13.8% | +2.95 bps | +94% |
| **60s** | **20 bps** | **3.2%** | **+0.71 bps** | **+32.7%** |
| 60s | 40 bps | 1.0% | +0.26 bps | +18.7% |

120s/10bps looks better on revenue and is not defensible: on a 5 bps base fee it
makes an ordinary trader 59% worse off, which is the opposite of what the hook
claims to do. 60s/20bps keeps that cost under a basis point while still moving a
third of base-fee revenue to LPs.

The escrow recovers about 43% of what informed flow captured at this setting.
Charging the full 58 bps that would recover 100% also doubles what benign
traders pay, so the gap is deliberate.

## Invariants

The test suite has to hold these:

- `sum(escrow held) >= sum(unsettled liabilities)` at all times
- a receipt settles at most once
- every receipt has a settlement path, including after expiry
- refund never exceeds what was escrowed for that swap
- the hook never touches `BASE_FEE` once it has gone to LPs

## Known gaps

## Analysis gate

The first sweep compared execution-relative markout with a shuffled null and
showed a negative lift. That comparison is mechanically biased: execution
price includes the swap fee and own price impact, while the null does not. The
gate therefore decomposes markout into execution drag and post-swap drift, and
compares drift with the null. On the captured 26,209-swap fixture, the locked
120-second/10-bps cell has 13.79% real right-tail observations versus 12.00% in
the null (+1.79 percentage points). The complete distributions are in
`analysis/out/gate.json`; this is evidence of a weak but positive direction
signal, not a claim of exact informed-trader labeling.

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
