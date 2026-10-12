# wham.sh

The website for [Wham](https://github.com/gwendall/wham): Next.js (App Router), Tailwind v4 and a little three.js.

```sh
pnpm install
pnpm dev      # http://localhost:3000
pnpm build    # production build
pnpm lint
```

## One source of truth

`install.sh`, `uninstall.sh` and the Silkscreen font live at the root of the repo. `scripts/sync.mjs` runs before
`dev` and `build`, copies them into `generated/` (gitignored), and fails the build if one is missing. Edit the root
files, never the copies.

## Routes

| Request                              | Response                                         |
| ------------------------------------ | ------------------------------------------------ |
| `GET /` from a browser               | the page                                         |
| `GET /` from curl, wget, HTTPie, xh  | `install.sh` as `text/plain`, so `curl -fsSL wham.sh \| sh` works |
| `/install`, `/install.sh`            | `install.sh`                                     |
| `/uninstall`, `/uninstall.sh`        | `uninstall.sh`                                   |
| `/download`                          | 302 to the latest `Wham.dmg` on GitHub Releases  |

The user agent check is a rewrite in `next.config.ts`, so it runs in the router, before any function. It only matches
command line clients: link unfurlers (Slack, iMessage, X) still get the page and its share card.

## Deploying on Vercel

- Root directory: `site`.
- Turn on "Include files outside the root directory in the Build Step", since `scripts/sync.mjs` reads `../install.sh`,
  `../uninstall.sh` and `../app/Resources/Silkscreen-Regular.ttf`.
- No environment variables.
- Add both `wham.sh` and `www.wham.sh`; the canonical URL is `https://wham.sh`.
