"use client";

import { useState } from "react";
import { Label } from "./ui";

export type Cell = {
  window_seconds: number;
  theta_bps: number;
  lp_uplift_pct: number;
  uninformed_overcharge_bps: number;
};

const W = 720;
const H = 300;
const PAD = { l: 46, r: 16, t: 16, b: 40 };
const LIMIT = 1.0; // the constraint we held: under a bp on uninformed flow

export function TradeoffChart({ grid, chosen }: { grid: Cell[]; chosen: Cell }) {
  const [hover, setHover] = useState<Cell | null>(null);

  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;
  const maxX = Math.max(...grid.map((c) => c.uninformed_overcharge_bps)) * 1.05;
  const maxY = Math.max(...grid.map((c) => c.lp_uplift_pct)) * 1.05;

  const sx = (v: number) => PAD.l + (v / maxX) * plotW;
  const sy = (v: number) => PAD.t + plotH - (v / maxY) * plotH;

  const active = hover ?? chosen;

  return (
    <figure className="raised rounded-3xl p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <Label>Every setting we tested</Label>
        <span className="numeric text-xs text-ink-faint">{grid.length} combinations</span>
      </div>

      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="mt-5 w-full"
        role="img"
        aria-label="LP revenue against what an uninformed trader pays, for each window and threshold combination."
      >
        {[0.25, 0.5, 0.75, 1].map((f) => (
          <line key={f} x1={PAD.l} x2={W - PAD.r} y1={sy(maxY * f)} y2={sy(maxY * f)} stroke="var(--color-chart-grid)" strokeWidth="1" />
        ))}

        {/* everything right of this line overcharges ordinary traders */}
        <rect x={sx(LIMIT)} y={PAD.t} width={W - PAD.r - sx(LIMIT)} height={plotH} fill="var(--color-chart-informed)" opacity="0.06" />
        <line x1={sx(LIMIT)} x2={sx(LIMIT)} y1={PAD.t} y2={PAD.t + plotH} stroke="var(--color-ink-faint)" strokeWidth="1" strokeDasharray="3 3" />
        <text x={sx(LIMIT) + 6} y={PAD.t + 12} fill="var(--color-ink-dim)" fontSize="11" fontFamily="var(--font-mono)">
          1 bp limit
        </text>

        {grid.map((c, i) => {
          const isChosen = c.window_seconds === chosen.window_seconds && c.theta_bps === chosen.theta_bps;
          const over = c.uninformed_overcharge_bps > LIMIT;
          return (
            <circle
              key={i}
              cx={sx(c.uninformed_overcharge_bps)}
              cy={sy(c.lp_uplift_pct)}
              r={isChosen ? 7 : 4.5}
              fill={isChosen ? "var(--color-chart-benign)" : "var(--color-ink-faint)"}
              opacity={over && !isChosen ? 0.35 : 1}
              stroke={isChosen ? "var(--color-surface)" : "none"}
              strokeWidth="2"
              onMouseEnter={() => setHover(c)}
              onMouseLeave={() => setHover(null)}
            />
          );
        })}

        <text x={PAD.l} y={H - 10} fill="var(--color-ink-faint)" fontSize="11" fontFamily="var(--font-mono)">
          0
        </text>
        <text x={W / 2 - 60} y={H - 10} fill="var(--color-ink-dim)" fontSize="11">
          what an uninformed trader pays, bps
        </text>
        <text x={8} y={PAD.t + 8} fill="var(--color-ink-dim)" fontSize="11" transform={`rotate(-90 14 ${PAD.t + 8})`}>
          LP revenue
        </text>
      </svg>

      <figcaption className="mt-3 text-sm text-ink-dim">
        <span className="numeric text-ink">
          {active.window_seconds}s · θ {active.theta_bps} bps
        </span>{" "}
        · LP revenue{" "}
        <span className="numeric text-ink">+{active.lp_uplift_pct.toFixed(1)}%</span> · uninformed pays{" "}
        <span className="numeric text-ink">+{active.uninformed_overcharge_bps.toFixed(2)} bps</span>
        {hover === null && <span className="text-ink-faint"> — the setting we shipped</span>}
      </figcaption>
    </figure>
  );
}
