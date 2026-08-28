"use client";

import { useState } from "react";
import { Label } from "./ui";

type Props = { edges: number[]; counts: number[]; theta: number };

const W = 720;
const H = 260;
const PAD = { l: 8, r: 8, t: 16, b: 34 };

function binLabel(edges: number[], i: number) {
  if (i === 0) return `< ${edges[0]}`;
  if (i === edges.length) return `≥ ${edges[edges.length - 1]}`;
  return `${edges[i - 1]} to ${edges[i]}`;
}

export function DriftHistogram({ edges, counts, theta }: Props) {
  const [hover, setHover] = useState<number | null>(null);

  const total = counts.reduce((a, b) => a + b, 0);
  const max = Math.max(...counts);
  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;
  const bw = plotW / counts.length;

  // a bin is informed when its lower edge is at or above theta
  const isInformed = (i: number) => i > 0 && edges[i - 1] >= theta;
  const thetaIndex = edges.findIndex((e) => e === theta) + 1;
  const thetaX = PAD.l + thetaIndex * bw;

  const informedCount = counts.reduce((a, c, i) => a + (isInformed(i) ? c : 0), 0);

  return (
    <figure className="raised rounded-3xl p-6">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <Label>Where the drift lands</Label>
        <div className="flex items-center gap-4 text-xs">
          <span className="flex items-center gap-2 text-ink-dim">
            <span className="inline-block h-2.5 w-2.5 rounded-sm bg-chart-benign" />
            refunded
          </span>
          <span className="flex items-center gap-2 text-ink-dim">
            <span className="inline-block h-2.5 w-2.5 rounded-sm bg-chart-informed" />
            paid to LPs
          </span>
        </div>
      </div>

      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="mt-5 w-full"
        role="img"
        aria-label={`Distribution of post-swap drift across ${total.toLocaleString()} swaps. ${informedCount.toLocaleString()} exceed the ${theta} bps threshold.`}
      >
        {[0.25, 0.5, 0.75, 1].map((f) => (
          <line
            key={f}
            x1={PAD.l}
            x2={W - PAD.r}
            y1={PAD.t + plotH * (1 - f)}
            y2={PAD.t + plotH * (1 - f)}
            stroke="var(--color-chart-grid)"
            strokeWidth="1"
          />
        ))}

        {counts.map((c, i) => {
          const h = (c / max) * plotH;
          const x = PAD.l + i * bw;
          const y = PAD.t + plotH - h;
          return (
            <rect
              key={i}
              x={x + 1}
              y={y}
              width={Math.max(1, bw - 2)}
              height={Math.max(1, h)}
              rx="3"
              fill={isInformed(i) ? "var(--color-chart-informed)" : "var(--color-chart-benign)"}
              opacity={hover === null || hover === i ? 1 : 0.45}
              onMouseEnter={() => setHover(i)}
              onMouseLeave={() => setHover(null)}
            />
          );
        })}

        <line
          x1={thetaX}
          x2={thetaX}
          y1={PAD.t - 6}
          y2={PAD.t + plotH}
          stroke="var(--color-ink-faint)"
          strokeWidth="1"
          strokeDasharray="3 3"
        />
        <text
          x={thetaX + 6}
          y={PAD.t + 2}
          fill="var(--color-ink-dim)"
          fontSize="11"
          fontFamily="var(--font-mono)"
        >
          θ {theta} bps
        </text>

        <text x={PAD.l} y={H - 10} fill="var(--color-ink-faint)" fontSize="11" fontFamily="var(--font-mono)">
          −100
        </text>
        <text x={W / 2 - 6} y={H - 10} fill="var(--color-ink-faint)" fontSize="11" fontFamily="var(--font-mono)">
          0
        </text>
        <text x={W - PAD.r - 24} y={H - 10} fill="var(--color-ink-faint)" fontSize="11" fontFamily="var(--font-mono)">
          +100
        </text>
      </svg>

      <figcaption className="mt-3 text-sm text-ink-dim">
        {hover === null ? (
          <>
            <span className="numeric text-ink">{informedCount.toLocaleString()}</span> of{" "}
            <span className="numeric text-ink">{total.toLocaleString()}</span> swaps drifted past the
            threshold. Everything to the left of the dashed line is refunded.
          </>
        ) : (
          <>
            <span className="numeric text-ink">{binLabel(edges, hover)} bps</span> ·{" "}
            <span className="numeric text-ink">{counts[hover].toLocaleString()}</span> swaps ·{" "}
            {isInformed(hover) ? "paid to LPs" : "refunded"}
          </>
        )}
      </figcaption>
    </figure>
  );
}
