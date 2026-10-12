import { ErrorScreen } from "@/components/ErrorScreen";
import { UiSounds } from "@/components/UiSounds";
import { fonts } from "@/lib/fonts";
import "./globals.css";

// A URL outside every route. app/[lang]/[...missing] takes nearly all of them
// first, so this is the last net, in English.
export default function GlobalNotFound() {
  return (
    <html lang="en" className={fonts}>
      <body className="overflow-x-clip">
        <ErrorScreen kind="notFound" />
        <UiSounds />
      </body>
    </html>
  );
}
