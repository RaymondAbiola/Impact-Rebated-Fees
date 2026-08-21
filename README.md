# Impact Rebated Fees

A Uniswap v4 hook that charges every swap a high fee up front, holds most of it
in escrow, then settles it a short time later based on whether the trade actually
moved the pool against its liquidity providers.

Arbitrageurs forfeit the escrowed portion to LPs. Everyone else gets it back.

```
contracts/   foundry project, the hook and its tests
app/         next.js frontend
analysis/    offline classifier and historical replay
scripts/     demo seeding
```

Work in progress.
