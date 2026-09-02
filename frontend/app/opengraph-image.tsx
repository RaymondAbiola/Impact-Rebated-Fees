import { ImageResponse } from "next/og";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Impact Rebated Fees";

export default function OG() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#161b1b",
          color: "#e8edec",
          padding: 72,
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 26, color: "#8e9998" }}>
          <div style={{ width: 18, height: 18, borderRadius: 9, background: "#f05b4a" }} />
          Impact Rebated Fees
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ fontSize: 78, lineHeight: 1.05, letterSpacing: -2 }}>
            A security deposit
          </div>
          <div style={{ fontSize: 78, lineHeight: 1.05, letterSpacing: -2 }}>on every swap.</div>
        </div>

        <div style={{ display: "flex", gap: 56, fontSize: 26, color: "#8e9998" }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <span style={{ color: "#3fe39b", fontSize: 40 }}>+32.7%</span>
            <span>LP revenue</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <span style={{ color: "#e8edec", fontSize: 40 }}>0.71 bps</span>
            <span>cost to an ordinary trader</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <span style={{ color: "#f05b4a", fontSize: 40 }}>26,209</span>
            <span>real swaps replayed</span>
          </div>
        </div>
      </div>
    ),
    size,
  );
}
