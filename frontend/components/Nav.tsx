"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { clsx } from "./clsx";

const links = [
  { href: "/", label: "Evidence" },
  { href: "/swap", label: "Swap" },
  { href: "/queue", label: "Settlement" },
];

export function Nav() {
  const path = usePathname();
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  return (
    <header className="sticky top-0 z-20 border-b border-line-soft bg-bg/85 backdrop-blur">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
      <div className="flex h-14 items-center gap-4 sm:h-16 sm:gap-6">
        <Link href="/" className="shrink-0 text-sm tracking-tight">
          Impact<span className="text-accent">·</span>Rebated
        </Link>

        {/* on phones the tabs move to their own row below, see further down */}
        <nav className="hidden gap-1 sm:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={clsx(
                "rounded-full px-3 py-1.5 text-sm transition-colors",
                path === l.href ? "bg-elevated text-ink" : "text-ink-dim hover:text-ink",
              )}
            >
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex shrink-0 items-center gap-2 sm:gap-3">
          <span className="numeric hidden rounded-full border border-line px-3 py-1.5 text-xs text-ink-faint sm:inline">
            Unichain Sepolia
          </span>
          {isConnected ? (
            <button
              onClick={() => disconnect()}
              className="numeric rounded-full bg-elevated px-3 py-1.5 text-xs text-ink-dim hover:text-ink"
            >
              {address?.slice(0, 6)}…{address?.slice(-4)}
            </button>
          ) : (
            <button
              disabled={isPending}
              onClick={() => connect({ connector: connectors[0] })}
              className="rounded-full bg-accent px-4 py-1.5 text-sm text-ground transition-colors hover:bg-accent-hi disabled:opacity-60"
            >
              {isPending ? "Connecting" : "Connect"}
            </button>
          )}
        </div>
      </div>

      <nav className="flex gap-1 pb-2 sm:hidden">
        {links.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={clsx(
              "flex-1 rounded-full px-2 py-1.5 text-center text-sm transition-colors",
              path === l.href ? "bg-elevated text-ink" : "text-ink-dim",
            )}
          >
            {l.label}
          </Link>
        ))}
      </nav>
      </div>
    </header>
  );
}
