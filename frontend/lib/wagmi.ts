import { http, createConfig, createStorage, cookieStorage } from "wagmi";
import { unichainSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [unichainSepolia],
  connectors: [injected()],
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
  // one block a second on unichain, so poll at that cadence and the
  // settlement countdowns move without any client-side clock
  pollingInterval: 1_000,
  transports: {
    [unichainSepolia.id]: http("https://sepolia.unichain.org"),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
