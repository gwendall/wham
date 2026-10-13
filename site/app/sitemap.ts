import type { MetadataRoute } from "next";
import { LANGUAGES, LOCALES, pathFor } from "@/lib/locales";

const url = (path: string) => new URL(path, "https://wham.sh").href;

// Each page in each language, naming the others.
const PAGES = [
  { page: "", changeFrequency: "monthly", priority: 1 },
  { page: "/changelog", changeFrequency: "weekly", priority: 0.6 },
] as const;

export default function sitemap(): MetadataRoute.Sitemap {
  return PAGES.flatMap(({ page, changeFrequency, priority }) => {
    const languages = Object.fromEntries(LOCALES.map((code) => [LANGUAGES[code].tag, url(pathFor(code, page))]));
    return LOCALES.map((code) => ({
      url: url(pathFor(code, page)),
      changeFrequency,
      priority: code === "en" ? priority : Math.round(priority * 8) / 10,
      alternates: { languages },
    }));
  });
}
