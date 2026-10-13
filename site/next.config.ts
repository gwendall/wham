import type { NextConfig } from "next";

// Command-line clients get the installer at the bare domain, so
// `curl -fsSL wham.sh | sh` works. Matched on the user agent only: link
// unfurlers (Slack, iMessage, X) also send `Accept: */*`, and they must get the
// page and its preview, not a shell script.
const CLI_AGENT = "(?:(?:curl|[Ww]get|HTTPie|xh|aria2)/.*|fetch libfetch/.*)";

// English is the page at /, every other language under its code (lib/locales.ts).
// A first visit to / goes to the browser's first language, when the site has
// it; after that, to the one picked in the header (the wham-lang cookie). The
// same goes for every other page: /changelog is /fr/changelog in French.
const PAGES = ["/changelog"];
const OTHER = "fr|es|de|it|pt|ja|ko|zh";
// The first language of Accept-Language: "fr-FR,fr;q=0.9,en;q=0.8" is French.
// Chinese only in its Simplified forms: zh-TW and zh-HK readers get English.
const FIRST = "(?<lang>fr|es|de|it|pt|ja|ko)(?:-[^,;]*)?(?:[,;].*)?";
const FIRST_ZH = "zh(?:-(?:CN|SG|Hans)[^,;]*)?(?:[,;].*)?";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  experimental: {
    // The root layout is app/[lang]/layout.tsx: a URL no language matches gets
    // app/global-not-found.tsx.
    globalNotFound: true,
    // Vercel restores .next/cache before each build, and Turbopack's build cache
    // then served the previous globals.css through the Tailwind loader: new
    // pages, old stylesheet (12/10/2026). The site builds in seconds without it.
    turbopackFileSystemCacheForBuild: false,
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async rewrites() {
    return {
      beforeFiles: [
        { source: "/", has: [{ type: "header", key: "user-agent", value: CLI_AGENT }], destination: "/install" },
        { source: "/", destination: "/en" },
        ...PAGES.map((page) => ({ source: page, destination: `/en${page}` })),
        { source: "/install.sh", destination: "/install" },
        { source: "/uninstall.sh", destination: "/uninstall" },
      ],
      afterFiles: [],
      fallback: [],
    };
  },
  async redirects() {
    const cli = { type: "header", key: "user-agent", value: CLI_AGENT } as const;
    const chosen = { type: "cookie", key: "wham-lang" } as const;
    const languages = (page: string) => [
      { source: `/en${page}`, destination: page || "/", permanent: true },
      { source: page || "/", has: [{ ...chosen, value: `(?<lang>${OTHER})` }], missing: [cli], destination: `/:lang${page}`, permanent: false },
      { source: page || "/", has: [{ type: "header", key: "accept-language", value: FIRST } as const], missing: [chosen, cli], destination: `/:lang${page}`, permanent: false },
      { source: page || "/", has: [{ type: "header", key: "accept-language", value: FIRST_ZH } as const], missing: [chosen, cli], destination: `/zh${page}`, permanent: false },
    ];
    return [
      ...["", ...PAGES].flatMap(languages),
      {
        source: "/download",
        destination: "https://github.com/gwendall/wham/releases/latest/download/Wham.dmg",
        statusCode: 302,
      },
    ];
  },
};

export default nextConfig;
