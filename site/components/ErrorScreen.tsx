"use client";

import { useParams } from "next/navigation";
import { PixelSprite } from "@/components/PixelSprite";
import { ERRORS } from "@/generated/errors";
import { fill, isLocale, pathFor, type Locale } from "@/lib/locales";
import { rich } from "@/lib/rich";
import { DIZZY, MOON, SUN_LIT } from "@/lib/sprites";

const ISSUES = "https://github.com/gwendall/wham/issues";

// The language of the URL that failed, or English when it has none.
export function useErrorLocale(): Locale {
  const lang = useParams<{ lang?: string }>()?.lang;
  return typeof lang === "string" && isLocale(lang) ? lang : "en";
}

type Props = { kind: "notFound" } | { kind: "failed"; retry: () => void; digest?: string };

// Every error page of the site, in the hero's clothes: the pixel eyebrow, a
// candy wordmark, the headline and its highlighter. A missing page is asleep,
// a moon snoring on the right; a broken one is the sun, dizzy and shaken.
export function ErrorScreen(props: Props) {
  const locale = useErrorLocale();
  const home = pathFor(locale);
  const failed = props.kind === "failed";
  const words = failed ? ERRORS[locale].failed : ERRORS[locale].notFound;
  const wordmark = failed ? ERRORS[locale].failed.wordmark : "404";
  const primary = "press candy-glow flex h-14 items-center rounded-full bg-candy px-6 text-lead font-black text-ink";
  const secondary = "flex h-14 items-center rounded-full px-6 text-lead font-black ring-1 ring-line transition-colors hover:bg-fg/6";

  return (
    <div className="flex min-h-dvh flex-col">
      <title>{`${words.eyebrow} · Wham`}</title>
      <header className="page flex h-20 items-center">
        <a href={home} className="flex items-center gap-3 rounded-lg">
          <PixelSprite rows={SUN_LIT} cell={2} />
          <span className="flex items-baseline">
            <span className="font-pixel text-pixel-lg">Wham</span>
            <span className="text-title font-extrabold text-muted">.sh</span>
          </span>
        </a>
      </header>
      <main id="main" className="page grid flex-1 grid-cols-1 content-center items-center gap-12 pb-(--section-y) lg:grid-cols-[1.3fr_1fr]">
        <div className="flex min-w-0 flex-col items-start">
          <p className="flex items-center gap-2 font-pixel text-pixel text-muted">
            <PixelSprite rows={failed ? DIZZY : MOON} cell={1} className="text-candy-pink" />
            {words.eyebrow}
          </p>
          <p aria-hidden="true" className="wordmark mt-6 font-pixel text-wordmark">
            <span className="wordmark-shadow">{wordmark}</span>
            <span className="wordmark-face">{wordmark}</span>
          </p>
          <h1 className="mt-8 text-display font-black">
            <span className="block">{words.title}</span> <span className="candy-mark">{words.mark}</span>
          </h1>
          <p className="mt-6 max-w-[32rem] text-lead text-muted">
            {rich(words.text, {
              github: (text) => (
                <a href={ISSUES} className="font-bold text-fg underline decoration-candy-pink decoration-2 underline-offset-4">
                  {text}
                </a>
              ),
            })}
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            {failed && (
              <button type="button" onClick={props.retry} className={`${primary} cursor-pointer`}>
                {ERRORS[locale].failed.retry}
              </button>
            )}
            <a href={home} className={failed ? secondary : primary}>
              {words.home}
            </a>
          </div>
          {failed && props.digest && (
            <p className="mt-6 font-mono text-small text-muted">{fill(ERRORS[locale].failed.code, { digest: props.digest })}</p>
          )}
        </div>
        <div aria-hidden="true" className="hidden justify-center lg:flex">
          {failed ? (
            <PixelSprite rows={DIZZY} cell={12} className="shaken" />
          ) : (
            <span className="relative">
              <PixelSprite rows={MOON} cell={20} className="text-moon" />
              <span className="snore absolute -right-6 -top-4 font-pixel text-pixel-lg text-candy-pink">
                <span>z</span>
                <span>z</span>
                <span>z</span>
              </span>
            </span>
          )}
        </div>
      </main>
    </div>
  );
}
