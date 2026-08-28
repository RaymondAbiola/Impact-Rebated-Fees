import { clsx } from "./clsx";

export function Card({ className, children }: { className?: string; children: React.ReactNode }) {
  return <div className={clsx("raised rounded-3xl", className)}>{children}</div>;
}

export function Well({ className, children }: { className?: string; children: React.ReactNode }) {
  return <div className={clsx("inset rounded-3xl", className)}>{children}</div>;
}

export function Label({ children }: { children: React.ReactNode }) {
  return (
    <p className="numeric text-[0.68rem] uppercase tracking-[0.2em] text-ink-faint">{children}</p>
  );
}

const toneClass = {
  benign: "bg-benign-soft text-benign",
  informed: "bg-informed-soft text-informed",
  pending: "bg-pending-soft text-pending",
  quiet: "border border-line text-ink-faint",
} as const;

export function Chip({
  tone = "quiet",
  children,
}: {
  tone?: keyof typeof toneClass;
  children: React.ReactNode;
}) {
  return (
    <span className={clsx("rounded-full px-3 py-1 text-sm", toneClass[tone])}>{children}</span>
  );
}
