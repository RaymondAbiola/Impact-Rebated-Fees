import { ImageResponse } from "next/og";

// 3:2, matching what the hook directory actually renders
export const size = { width: 1536, height: 1024 };
export const contentType = "image/png";
export const alt = "Impact Rebated Fees";

const stat = (colour: string, value: string, label: string) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
    <span style={{ color: colour, fontSize: 52 }}>{value}</span>
    <span style={{ color: "#8e9998", fontSize: 26 }}>{label}</span>
  </div>
);

export default function Thumb() {
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
          padding: 92,
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18, fontSize: 30, color: "#8e9998" }}>
          <div style={{ display: "flex", width: 26, height: 26, borderRadius: 13, border: "4px solid #f05b4a" }} />
          Impact Rebated Fees
        </div>

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ fontSize: 96, lineHeight: 1.05, letterSpacing: -2.5 }}>A security deposit</div>
          <div style={{ fontSize: 96, lineHeight: 1.05, letterSpacing: -2.5 }}>on every swap.</div>
          <div style={{ display: "flex", gap: 16, marginTop: 34 }}>
            <div style={{ display: "flex", background: "#142622", color: "#3fe39b", borderRadius: 999, padding: "12px 26px", fontSize: 28 }}>
              Benign · refunded
            </div>
            <div style={{ display: "flex", background: "#2a1a18", color: "#f05b4a", borderRadius: 999, padding: "12px 26px", fontSize: 28 }}>
              Informed · paid to LPs
            </div>
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 40 }}>
          <div style={{ display: "flex", height: 1, background: "#2e3637" }} />
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            {stat("#3fe39b", "+32.7%", "LP revenue")}
            {stat("#e8edec", "0.71 bps", "cost to an ordinary trader")}
            {stat("#f05b4a", "26,209", "real swaps replayed")}
            {stat("#e8edec", "Uniswap v4", "live on Unichain")}
          </div>
        </div>
      </div>
    ),
    size,
  );
}
