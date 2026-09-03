import { ImageResponse } from "next/og";

// linkedin cover ratio, 4:1. laid out horizontally rather than squashed.
export const size = { width: 1584, height: 396 };
export const contentType = "image/png";
export const alt = "Impact Rebated Fees";

const stat = (colour: string, value: string, label: string) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
    <span style={{ color: colour, fontSize: 34 }}>{value}</span>
    <span style={{ color: "#8e9998", fontSize: 19 }}>{label}</span>
  </div>
);

export default function Cover() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          background: "#161b1b",
          color: "#e8edec",
          padding: "0 72px",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 13, fontSize: 21, color: "#8e9998" }}>
            <div style={{ display: "flex", width: 18, height: 18, borderRadius: 9, border: "3px solid #f05b4a" }} />
            Impact Rebated Fees
          </div>
          <div style={{ fontSize: 54, lineHeight: 1.06, letterSpacing: -1.5 }}>A security deposit</div>
          <div style={{ fontSize: 54, lineHeight: 1.06, letterSpacing: -1.5, marginTop: -14 }}>on every swap.</div>
          <div style={{ display: "flex", gap: 11, marginTop: 8 }}>
            <div style={{ display: "flex", background: "#142622", color: "#3fe39b", borderRadius: 999, padding: "7px 16px", fontSize: 19 }}>
              Benign · refunded
            </div>
            <div style={{ display: "flex", background: "#2a1a18", color: "#f05b4a", borderRadius: 999, padding: "7px 16px", fontSize: 19 }}>
              Informed · paid to LPs
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: 46 }}>
          {stat("#3fe39b", "+32.7%", "LP revenue")}
          {stat("#e8edec", "0.71 bps", "cost to an ordinary trader")}
          {stat("#f05b4a", "26,209", "real swaps replayed")}
          {stat("#e8edec", "Uniswap v4", "live on Unichain")}
        </div>
      </div>
    ),
    size,
  );
}
