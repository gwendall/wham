import type { Metadata, Viewport } from "next";
import { Nunito } from "next/font/google";
import localFont from "next/font/local";
import "./globals.css";

// Silkscreen by Jason Kottke (SIL Open Font License 1.1), the app's own copy
// (scripts/sync.mjs). Its capitals are 5 of 8 pixels tall, but its ascent and
// descent are uneven, which sets them a pixel low in any line box. These
// overrides make the box 1em with 3/16 em under the baseline: in a line height
// of 1, the capitals sit dead center, on whole pixels at every multiple of 8 px.
const silkscreen = localFont({
  src: "../generated/Silkscreen-Regular.ttf",
  weight: "400",
  variable: "--font-silkscreen",
  display: "swap",
  declarations: [
    { prop: "ascent-override", value: "81.25%" },
    { prop: "descent-override", value: "18.75%" },
    { prop: "line-gap-override", value: "0%" },
  ],
});

const nunito = Nunito({
  subsets: ["latin"],
  variable: "--font-nunito",
  display: "swap",
});

const title = "Wham - your Mac stays awake, lid closed";
const description =
  "Close the lid. Your Mac stays awake. A one-click menu bar switch that keeps your Mac awake, for real, even with the lid shut. Free and open source.";

export const metadata: Metadata = {
  metadataBase: new URL("https://wham.sh"),
  title,
  description,
  applicationName: "Wham",
  authors: [{ name: "Gwendall", url: "https://gwendall.com" }],
  creator: "Gwendall",
  keywords: ["Mac", "macOS", "keep awake", "lid closed", "clamshell", "menu bar", "pmset", "caffeinate", "Amphetamine alternative"],
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    url: "https://wham.sh",
    siteName: "Wham",
    title,
    description,
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fff7fb" },
    { media: "(prefers-color-scheme: dark)", color: "#0f0a14" },
  ],
  colorScheme: "light dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${silkscreen.variable} ${nunito.variable}`}>
      <body className="min-h-dvh overflow-x-clip">{children}</body>
    </html>
  );
}
