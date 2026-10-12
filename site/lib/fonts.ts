import { Nunito } from "next/font/google";
import localFont from "next/font/local";

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

// Latin and its extension cover every European language here; Japanese,
// Korean and Chinese fall back to the system's own sans.
const nunito = Nunito({
  subsets: ["latin", "latin-ext"],
  variable: "--font-nunito",
  display: "swap",
});

export const fonts = `${silkscreen.variable} ${nunito.variable}`;
