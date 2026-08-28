"use client";

import { useCallback, useState } from "react";
import { encodeAbiParameters, maxUint256 } from "viem";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { addresses, erc20Abi, poolKey, swapRouterAbi } from "./generated";

// the pool can move all the way to either end, we are not price-limiting here
const MIN_SQRT_PRICE_PLUS_ONE = 4295128740n;
const MAX_SQRT_PRICE_MINUS_ONE = 1461446703485210103287273052203988822378723970341n;

export type SwapStage = "idle" | "approving" | "swapping" | "done" | "error";

/**
 * Without a beneficiary in hookData the hook only sees the router, and every
 * refund is sent to a contract that cannot forward it. This is the one thing
 * the app must not get wrong.
 */
export function beneficiaryData(account: `0x${string}`) {
  return encodeAbiParameters([{ type: "address" }], [account]);
}

export function useSwap() {
  const { address } = useAccount();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [stage, setStage] = useState<SwapStage>("idle");
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const [error, setError] = useState<string | undefined>();

  const swap = useCallback(
    async (zeroForOne: boolean, amountIn: bigint) => {
      if (!address || !client || amountIn <= 0n) return;
      setError(undefined);
      setHash(undefined);

      const tokenIn = zeroForOne ? addresses.currency0 : addresses.currency1;

      try {
        const allowance = await client.readContract({
          address: tokenIn,
          abi: erc20Abi,
          functionName: "allowance",
          args: [address, addresses.swapRouter],
        });

        if ((allowance as bigint) < amountIn) {
          setStage("approving");
          const approveHash = await writeContractAsync({
            address: tokenIn,
            abi: erc20Abi,
            functionName: "approve",
            args: [addresses.swapRouter, maxUint256],
          });
          await client.waitForTransactionReceipt({ hash: approveHash });
        }

        setStage("swapping");
        const swapHash = await writeContractAsync({
          address: addresses.swapRouter,
          abi: swapRouterAbi,
          functionName: "swap",
          args: [
            poolKey,
            {
              zeroForOne,
              amountSpecified: -amountIn, // negative is exact input
              sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_PLUS_ONE : MAX_SQRT_PRICE_MINUS_ONE,
            },
            { takeClaims: false, settleUsingBurn: false },
            beneficiaryData(address),
          ],
        });
        setHash(swapHash);
        await client.waitForTransactionReceipt({ hash: swapHash });
        setStage("done");
      } catch (e) {
        setError(e instanceof Error ? e.message.split("\n")[0] : "transaction failed");
        setStage("error");
      }
    },
    [address, client, writeContractAsync],
  );

  const mint = useCallback(async () => {
    if (!address || !client) return;
    setError(undefined);
    try {
      setStage("approving");
      for (const token of [addresses.currency0, addresses.currency1]) {
        const h = await writeContractAsync({
          address: token,
          abi: erc20Abi,
          functionName: "mint",
          args: [address, 1000n * 10n ** 18n],
        });
        await client.waitForTransactionReceipt({ hash: h });
      }
      setStage("idle");
    } catch (e) {
      setError(e instanceof Error ? e.message.split("\n")[0] : "mint failed");
      setStage("error");
    }
  }, [address, client, writeContractAsync]);

  return { swap, mint, stage, hash, error, reset: () => setStage("idle") };
}

export const EXPLORER = "https://sepolia.uniscan.xyz";
