"use client";

import { ErrorScreen, useErrorLocale } from "@/components/ErrorScreen";
import { UiSounds } from "@/components/UiSounds";
import { fonts } from "@/lib/fonts";
import { LANGUAGES } from "@/lib/locales";
import "./globals.css";

// When the root layout itself fails, and for the static 500 page: this one
// brings its own document, styles and fonts.
export default function GlobalError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  const locale = useErrorLocale();
  return (
    <html lang={LANGUAGES[locale].tag} className={fonts}>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body className="overflow-x-clip">
        <ErrorScreen kind="failed" retry={retry} digest={error.digest} />
        <UiSounds />
      </body>
    </html>
  );
}
