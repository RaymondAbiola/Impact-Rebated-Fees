"use client";

import { useCallback, useState } from "react";
import { usePublicClient, useWriteContract } from "wagmi";
import { hook } from "./contracts";

export function useSettle() {
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const [busy, setBusy] = useState<number | "batch" | null>(null);
  const [error, setError] = useState<string | undefined>();

  const run = useCallback(
    async (key: number | "batch", send: () => Promise<`0x${string}`>) => {
      setError(undefined);
      setBusy(key);
      try {
        const h = await send();
        await client?.waitForTransactionReceipt({ hash: h });
      } catch (e) {
        setError(e instanceof Error ? e.message.split("\n")[0] : "settle failed");
      } finally {
        setBusy(null);
      }
    },
    [client],
  );

  const settleOne = useCallback(
    (id: number) =>
      run(id, () => writeContractAsync({ ...hook, functionName: "settle", args: [BigInt(id)] })),
    [run, writeContractAsync],
  );

  const settleMany = useCallback(
    (ids: number[]) =>
      run("batch", () =>
        writeContractAsync({
          ...hook,
          functionName: "settleBatch",
          args: [ids.map((i) => BigInt(i))],
        }),
      ),
    [run, writeContractAsync],
  );

  return { settleOne, settleMany, busy, error };
}
