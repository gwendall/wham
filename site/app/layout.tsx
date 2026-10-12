import type { Metadata, Viewport } from "next";
import { Nunito, Silkscreen } from "next/font/google";
import "./globals.css";

// Silkscreen by Jason Kottke (SIL Open Font License 1.1), the pixel face of the app.
const silkscreen = Silkscreen({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-silkscreen",
  display: "swap",
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
