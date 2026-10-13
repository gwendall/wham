import type { ReactNode } from "react";
import { LanguageMenu } from "@/components/LanguageMenu";
import { MusicToggle } from "@/components/MusicToggle";
import { PixelSprite } from "@/components/PixelSprite";
import { pathFor, type Locale, type Messages } from "@/lib/i18n";
import { rich } from "@/lib/rich";
import { HEART, SUN, SUN_LIT } from "@/lib/sprites";

// What every page of the site shares: its header, its footer, and the way it
// sets links and code in a sentence.

export const GITHUB = "https://github.com/gwendall/wham";

type Props = { m: Messages; lang: Locale };

// `page` is where the header sits, "" for the home page or "/changelog": its
// links lead to the home page's sections, and the language switch to this page
// in another language.
export function Header({ m, lang, page = "" }: Props & { page?: string }) {
  const home = page ? pathFor(lang) : "";
  return (
    <header className="page flex h-20 items-center justify-between gap-4">
      <a href={home || "#main"} className="flex items-center gap-3 rounded-lg" aria-label={m.nav.home}>
        <PixelSprite rows={SUN_LIT} cell={2} />
        <span className="flex items-baseline">
          <span className="font-pixel text-pixel-lg">Wham</span>
          <span className="text-title font-extrabold text-muted">.sh</span>
        </span>
      </a>
      <nav aria-label={m.nav.main} className="flex items-center gap-1 text-body font-bold">
        <NavLink href={`${home}#how`} className="hidden md:flex">
          {m.nav.how}
        </NavLink>
        <NavLink href={`${home}#compare`} className="hidden lg:flex">
          {m.nav.compare}
        </NavLink>
        <NavLink href={`${home}#faq`} className="hidden md:flex">
          {m.nav.faq}
        </NavLink>
        {/* On a phone the hero's own button is right below. */}
        <a href="/download" data-sound="download" className="press hidden h-10 items-center whitespace-nowrap rounded-full bg-candy px-4 text-ink sm:flex">
          {m.nav.download}
        </a>
        <LanguageMenu current={lang} page={page} label={m.nav.language} />
        <MusicToggle labels={m.sound} />
        <a
          href={GITHUB}
          className="hidden size-10 items-center justify-center rounded-full transition-colors hover:bg-fg/6 sm:flex"
          aria-label={m.nav.github}
        >
          <GitHubIcon />
        </a>
      </nav>
    </header>
  );
}

export function Footer({ m, lang }: Props) {
  return (
    <footer className="page pb-8">
      <div className="relative overflow-hidden rounded-4xl bg-night px-8 py-16 text-center text-white dark:ring-1 dark:ring-white/10">
        <div
          aria-hidden="true"
          className="absolute inset-x-0 -bottom-24 mx-auto h-48 w-[80%] rounded-full bg-[radial-gradient(closest-side,rgba(255,3,180,0.35),transparent)]"
        />
        <div className="relative flex flex-col items-center">
          <PixelSprite rows={SUN_LIT} cell={4} className="text-candy-yellow" />
          <p className="mt-6 text-title font-black">
            <span className="block">{m.footer.title}</span> <span className="block text-white/60">{m.footer.subtitle}</span>
          </p>
          <a
            href="https://gwendall.com"
            className="group mt-12 flex flex-col items-center gap-3 rounded-2xl p-3"
            aria-label={m.footer.madeLabel}
          >
            <span className="flex items-center gap-3 font-pixel text-pixel text-white/60 pixel-even">
              {rich(m.footer.madeWith, {
                heart: () => (
                  <PixelSprite rows={HEART} cell={3} className="text-candy-pink transition-transform duration-300 group-hover:scale-125" />
                ),
              })}
            </span>
            <span className="font-pixel text-pixel-lg text-white pixel-even transition-colors group-hover:text-candy-yellow">Gwendall</span>
            <span className="h-1 w-full bg-candy opacity-80 transition-opacity group-hover:opacity-100" />
          </a>
        </div>
      </div>
      <div className="mt-6 flex flex-col items-center justify-between gap-3 text-small text-muted sm:flex-row">
        <p className="flex items-center gap-2">
          <PixelSprite rows={SUN} cell={1} />
          <span>{rich(m.footer.license, { mit: (text) => <A href={`${GITHUB}/blob/main/LICENSE`}>{text}</A> })}</span>
        </p>
        <nav aria-label={m.nav.footer} className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 font-bold">
          <a href={pathFor(lang, "/changelog")} className="transition-colors hover:text-fg">
            {m.nav.changelog}
          </a>
          <a href={GITHUB} className="transition-colors hover:text-fg">
            GitHub
          </a>
          <a href="/install" className="transition-colors hover:text-fg">
            install.sh
          </a>
          <a href="/uninstall" className="transition-colors hover:text-fg">
            uninstall.sh
          </a>
        </nav>
      </div>
    </footer>
  );
}

// The first stop of the keyboard: straight to the page's own content.
export function SkipLink({ m }: { m: Messages }) {
  return (
    <a
      href="#main"
      className="sr-only z-50 rounded-full bg-ink px-4 py-2 text-body font-bold text-white focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
    >
      {m.nav.skip}
    </a>
  );
}

function NavLink({ href, className = "", children }: { href: string; className?: string; children: ReactNode }) {
  return (
    <a href={href} className={`h-10 items-center rounded-full px-4 transition-colors hover:bg-fg/6 ${className}`}>
      {children}
    </a>
  );
}

export function Code({ children }: { children: ReactNode }) {
  return <code className="rounded-sm bg-fg/7 px-1 font-mono text-[0.875em] text-fg">{children}</code>;
}

export function A({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      className="font-bold text-fg underline decoration-candy-pink decoration-2 underline-offset-4 transition-colors hover:decoration-candy-cyan"
    >
      {children}
    </a>
  );
}

function GitHubIcon() {
  return (
    <svg aria-hidden="true" width="20" height="20" viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
}
