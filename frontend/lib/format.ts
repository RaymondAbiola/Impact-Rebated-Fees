export function fmtUnits(v: bigint, decimals = 18, places = 6) {
  const neg = v < 0n;
  const a = neg ? -v : v;
  const base = 10n ** BigInt(decimals);
  const whole = a / base;
  const frac = (a % base).toString().padStart(decimals, "0").slice(0, places);
  return `${neg ? "-" : ""}${whole}${places > 0 ? `.${frac}` : ""}`;
}

export function parseUnits(s: string, decimals = 18): bigint {
  const t = s.trim();
  if (!t || !/^\d*\.?\d*$/.test(t)) return 0n;
  const [w = "0", f = ""] = t.split(".");
  return BigInt(w || "0") * 10n ** BigInt(decimals) + BigInt((f + "0".repeat(decimals)).slice(0, decimals) || "0");
}

export function short(a?: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "";
}
