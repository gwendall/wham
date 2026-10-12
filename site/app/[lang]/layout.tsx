import type { Metadata, Viewport } from "next";
import { UiSounds } from "@/components/UiSounds";
import { fonts } from "@/lib/fonts";
import { isLocale, LANGUAGES, LOCALES, messages, pathFor } from "@/lib/i18n";
import "../globals.css";

export function generateStaticParams() {
  return LOCALES.map((lang) => ({ lang }));
}

export async function generateMetadata({ params }: LayoutProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params;
  // not-found.tsx titles itself.
  if (!isLocale(lang)) return {};
  const { meta } = await messages(lang);
  const languages = Object.fromEntries(LOCALES.map((code) => [LANGUAGES[code].tag, pathFor(code)]));
  return {
    metadataBase: new URL("https://wham.sh"),
    title: meta.title,
    description: meta.description,
    applicationName: "Wham",
    authors: [{ name: "Gwendall", url: "https://gwendall.com" }],
    creator: "Gwendall",
    keywords: meta.keywords.split(",").map((word) => word.trim()),
    alternates: { canonical: pathFor(lang), languages: { ...languages, "x-default": "/" } },
    openGraph: {
      type: "website",
      url: pathFor(lang),
      siteName: "Wham",
      locale: LANGUAGES[lang].og,
      alternateLocale: LOCALES.filter((code) => code !== lang).map((code) => LANGUAGES[code].og),
      title: meta.title,
      description: meta.description,
    },
    twitter: {
      card: "summary_large_image",
      title: meta.title,
      description: meta.description,
    },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fff7fb" },
    { media: "(prefers-color-scheme: dark)", color: "#0f0a14" },
  ],
  colorScheme: "light dark",
};

export default async function RootLayout({ children, params }: LayoutProps<"/[lang]">) {
  const { lang } = await params;
  // A language the site does not have: the page's notFound() shows
  // not-found.tsx, in English.
  return (
    <html lang={isLocale(lang) ? LANGUAGES[lang].tag : "en"} className={fonts}>
      <body className="min-h-dvh overflow-x-clip">
        {children}
        <UiSounds />
      </body>
    </html>
  );
}
