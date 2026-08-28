import { http, createConfig, createStorage, cookieStorage } from "wagmi";
import { unichainSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [unichainSepolia],
  connectors: [injected()],
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
  transports: {
    [unichainSepolia.id]: http("https://sepolia.unichain.org"),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
