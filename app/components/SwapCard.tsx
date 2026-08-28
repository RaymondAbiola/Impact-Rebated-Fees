"use client";

import { useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { addresses, erc20Abi, poolKey } from "@/lib/generated";
import { QUOTER, quoterAbi } from "@/lib/quoter";
import { ESCROW_FEE_BPS, SETTLEMENT_WINDOW_SECONDS } from "@/lib/hooks";
import { fmtUnits, parseUnits } from "@/lib/format";
import { Label, Well } from "./ui";

const POOL_FEE_BPS = poolKey.fee / 100;

export function SwapCard() {
  const { address, isConnected } = useAccount();
  const [zeroForOne, setZeroForOne] = useState(true);
  const [amount, setAmount] = useState("1");

  const tokenIn = zeroForOne ? addresses.currency0 : addresses.currency1;
  const tokenOut = zeroForOne ? addresses.currency1 : addresses.currency0;
  const symIn = zeroForOne ? "iUSD" : "iETH";
  const symOut = zeroForOne ? "iETH" : "iUSD";

  const parsed = parseUnits(amount);

  const { data: balances } = useReadContracts({
    query: { enabled: Boolean(address), refetchInterval: 8_000 },
    contracts: [
      { address: tokenIn, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
      { address: tokenOut, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
    ],
  });

  const { data: quote, isFetching: quoting } = useReadContract({
    address: QUOTER,
    abi: quoterAbi,
    functionName: "quoteExactInputSingle",
    args: [{ poolKey, zeroForOne, exactAmount: parsed, hookData: "0x" }],
    query: { enabled: parsed > 0n, refetchInterval: 12_000 },
  });

  const out = quote?.[0] ?? 0n;
  // the hook takes its cut from the output, so the escrow is a slice of what
  // would otherwise have landed in the trader's wallet
  const escrow = (out * ESCROW_FEE_BPS) / (10_000n - ESCROW_FEE_BPS);

  return (
    <div className="raised rounded-3xl p-6">
      <div className="flex items-center justify-between">
        <Label>You pay</Label>
        <button
          onClick={() => setZeroForOne((v) => !v)}
          className="numeric rounded-full border border-line px-3 py-1 text-xs text-ink-dim transition-colors hover:text-ink"
        >
          flip
        </button>
      </div>

      <Well className="mt-3 flex items-baseline gap-3 p-4">
        <input
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          inputMode="decimal"
          className="numeric w-full bg-transparent text-3xl outline-none placeholder:text-ink-faint"
          placeholder="0"
        />
        <span className="numeric shrink-0 text-sm text-ink-dim">{symIn}</span>
      </Well>
      <p className="numeric mt-2 text-xs text-ink-faint">
        balance {balances?.[0]?.result !== undefined ? fmtUnits(balances[0].result as bigint, 18, 4) : "—"} {symIn}
      </p>

      <div className="mt-5">
        <Label>You receive</Label>
        <Well className="mt-3 flex items-baseline gap-3 p-4">
          <span className="numeric w-full text-3xl text-ink-dim">
            {quoting && parsed > 0n ? "…" : fmtUnits(out, 18, 6)}
          </span>
          <span className="numeric shrink-0 text-sm text-ink-dim">{symOut}</span>
        </Well>
      </div>

      <dl className="mt-6 space-y-2 border-t border-line-soft pt-4 text-sm">
        <div className="flex justify-between">
          <dt className="text-ink-dim">Pool fee</dt>
          <dd className="numeric">{POOL_FEE_BPS.toFixed(2)} bps</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-ink-dim">Held in escrow</dt>
          <dd className="numeric text-pending">
            {Number(ESCROW_FEE_BPS)} bps · {fmtUnits(escrow, 18, 6)} {symOut}
          </dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-ink-dim">Refundable in</dt>
          <dd className="numeric">{SETTLEMENT_WINDOW_SECONDS}s</dd>
        </div>
      </dl>

      <p className="mt-4 text-xs leading-relaxed text-ink-faint">
        The escrow comes back unless the price keeps drifting your way. Settle it
        yourself and you keep the keeper bounty too, so it costs you nothing.
      </p>

      <button
        disabled
        className="mt-5 w-full rounded-2xl bg-elevated py-3 text-sm text-ink-faint"
      >
        {isConnected ? "Execution lands in the next commit" : "Connect a wallet"}
      </button>
    </div>
  );
}
