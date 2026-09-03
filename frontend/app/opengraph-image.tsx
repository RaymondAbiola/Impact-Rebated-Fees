import { ImageResponse } from "next/og";

export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Impact Rebated Fees";

const chip = (bg: string, fg: string, text: string) => (
  <div
    style={{
      display: "flex",
      background: bg,
      color: fg,
      borderRadius: 999,
      padding: "10px 22px",
      fontSize: 26,
    }}
  >
    {text}
  </div>
);

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
          padding: 68,
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 25, color: "#8e9998" }}>
          <div
            style={{
              display: "flex",
              width: 22,
              height: 22,
              borderRadius: 11,
              border: "3px solid #f05b4a",
            }}
          />
          Impact Rebated Fees
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{ fontSize: 76, lineHeight: 1.04, letterSpacing: -2 }}>A security deposit</div>
          <div style={{ fontSize: 76, lineHeight: 1.04, letterSpacing: -2 }}>on every swap.</div>
          <div style={{ marginTop: 18, display: "flex", gap: 14 }}>
            {chip("#142622", "#3fe39b", "Benign · refunded")}
            {chip("#2a1a18", "#f05b4a", "Informed · paid to LPs")}
          </div>
        </div>

        <div style={{ display: "flex", gap: 54, fontSize: 24, color: "#8e9998" }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <span style={{ color: "#3fe39b", fontSize: 38 }}>+32.7%</span>
            <span>LP revenue</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <span style={{ color: "#e8edec", fontSize: 38 }}>0.71 bps</span>
            <span>cost to an ordinary trader</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <span style={{ color: "#f05b4a", fontSize: 38 }}>26,209</span>
            <span>real swaps replayed</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4, marginLeft: "auto" }}>
            <span style={{ color: "#e8edec", fontSize: 38 }}>Uniswap v4</span>
            <span>live on Unichain</span>
          </div>
        </div>
      </div>
    ),
    size,
  );
}
