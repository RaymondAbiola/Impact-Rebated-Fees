// Records the live queue to data/snapshot.json so the demo still has something
// truthful to render if the rpc is unreachable when it matters.
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createPublicClient, http, parseAbiItem } from "viem";
import { unichainSepolia } from "viem/chains";

const here = dirname(fileURLToPath(import.meta.url));
const gen = readFileSync(resolve(here, "../lib/generated.ts"), "utf8");
const hook = gen.match(/hook: "(0x[0-9a-fA-F]+)"/)[1];
const deployedAt = BigInt(gen.match(/deployedAtBlock = (\d+)n/)[1]);

const client = createPublicClient({
  chain: unichainSepolia,
  transport: http("https://sepolia.unichain.org"),
});

const settledEvent = parseAbiItem(
  "event ReceiptSettled(uint256 indexed receiptId, address indexed beneficiary, bool informed, int256 driftTicks, address currency, uint256 payout, uint256 bounty, bool expired)",
);

const abi = JSON.parse(
  readFileSync(resolve(here, "../../contracts/out/ImpactRebatedFees.sol/ImpactRebatedFees.json"), "utf8"),
).abi;

const head = await client.getBlockNumber();
const count = await client.readContract({ address: hook, abi, functionName: "nextReceiptId" });

const settlements = [];
let to = head;
while (to >= deployedAt) {
  const from = to - 9999n > deployedAt ? to - 9999n : deployedAt;
  const logs = await client.getLogs({ address: hook, event: settledEvent, fromBlock: from, toBlock: to });
  settlements.push(...logs.map((l) => ({
    id: Number(l.args.receiptId),
    informed: Boolean(l.args.informed),
    drift: l.args.driftTicks.toString(),
    currency: l.args.currency,
    payout: l.args.payout.toString(),
    bounty: l.args.bounty.toString(),
    expired: Boolean(l.args.expired),
  })));
  if (from === deployedAt) break;
  to = from - 1n;
}

const n = Number(count);
const ids = Array.from({ length: Math.min(n, 25) }, (_, i) => n - 1 - i).filter((i) => i >= 0);
const receipts = [];
for (const id of ids) {
  const r = await client.readContract({ address: hook, abi, functionName: "receipts", args: [BigInt(id)] });
  const [drift, ready] = await client.readContract({ address: hook, abi, functionName: "driftOf", args: [BigInt(id)] });
  receipts.push({
    id,
    beneficiary: r[1],
    swapTimestamp: Number(r[2]),
    zeroForOne: r[3],
    settled: r[4],
    escrowAmount: r[7].toString(),
    escrowCurrency: r[8],
    drift: drift.toString(),
    ready,
  });
}

const block = await client.getBlock({ blockNumber: head });
writeFileSync(
  resolve(here, "../data/snapshot.json"),
  JSON.stringify({ capturedAt: Number(block.timestamp), count: n, receipts, settlements }, null, 2),
);
console.log(`snapshot: ${receipts.length} receipts, ${settlements.length} settlements`);
