import type { NextConfig } from "next";

// Command-line clients get the installer at the bare domain, so
// `curl -fsSL wham.sh | sh` works. Matched on the user agent only: link
// unfurlers (Slack, iMessage, X) also send `Accept: */*`, and they must get the
// page and its preview, not a shell script.
const CLI_AGENT = "(?:(?:curl|[Ww]get|HTTPie|xh|aria2)/.*|fetch libfetch/.*)";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
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
        { source: "/install.sh", destination: "/install" },
        { source: "/uninstall.sh", destination: "/uninstall" },
      ],
      afterFiles: [],
      fallback: [],
    };
  },
  async redirects() {
    return [
      {
        source: "/download",
        destination: "https://github.com/gwendall/wham/releases/latest/download/Wham.dmg",
        statusCode: 302,
      },
    ];
  },
};

export default nextConfig;
