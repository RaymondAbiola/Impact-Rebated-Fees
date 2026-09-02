import type { Metadata } from "next";
import { Instrument_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";
import { Nav } from "@/components/Nav";

const instrument = Instrument_Sans({
  variable: "--font-instrument",
  subsets: ["latin"],
  display: "swap",
});

const plexMono = IBM_Plex_Mono({
  variable: "--font-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
  display: "swap",
});

const description =
  "A Uniswap v4 hook that charges every swap a deposit, then gives it back sixty seconds later unless the pool was still mispriced after the trade.";

export const metadata: Metadata = {
  metadataBase: new URL("https://impact-rebated-fees.vercel.app"),
  title: {
    default: "Impact Rebated Fees",
    template: "%s · Impact Rebated Fees",
  },
  description,
  openGraph: {
    title: "Impact Rebated Fees",
    description,
    url: "/",
    siteName: "Impact Rebated Fees",
    type: "website",
  },
  twitter: { card: "summary_large_image", title: "Impact Rebated Fees", description },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${instrument.variable} ${plexMono.variable}`}>
      <body className="min-h-dvh bg-bg text-ink font-sans antialiased">
        <Providers>
          <Nav />
          {children}
        </Providers>
      </body>
    </html>
  );
}
