import type { MetadataRoute } from "next";
import { LANGUAGES, LOCALES, pathFor } from "@/lib/locales";

const url = (path: string) => new URL(path, "https://wham.sh").href;

// One page per language, each naming the others.
export default function sitemap(): MetadataRoute.Sitemap {
  const languages = Object.fromEntries(LOCALES.map((code) => [LANGUAGES[code].tag, url(pathFor(code))]));
  return LOCALES.map((code) => ({
    url: url(pathFor(code)),
    changeFrequency: "monthly",
    priority: code === "en" ? 1 : 0.8,
    alternates: { languages },
  }));
}
