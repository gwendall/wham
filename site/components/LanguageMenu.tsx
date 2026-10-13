"use client";

import { useEffect, useId, useRef, useState } from "react";
import { PixelSprite } from "@/components/PixelSprite";
import { LANG_COOKIE, LANGUAGES, LOCALES, pathFor, type Locale } from "@/lib/locales";
import { SUN } from "@/lib/sprites";

const GLOBE = [
  "...#####...",
  ".##..#..##.",
  ".#..#.#..#.",
  "#...#.#...#",
  "###########",
  "#..#...#..#",
  "###########",
  "#...#.#...#",
  ".#..#.#..#.",
  ".##..#..##.",
  "...#####...",
];

// A year: wham.sh opens in this language from then on (next.config.ts).
function remember(code: Locale) {
  document.cookie = `${LANG_COOKIE}=${code}; path=/; max-age=31536000; samesite=lax`;
}

// The header's language switch: a pixel globe and the current code, opening a
// list of the languages, each named in itself, leading to the same page in it
// (`page`, "" for the home page). Picking one remembers it in a cookie, so
// wham.sh opens in it next time.
export function LanguageMenu({ current, page = "", label }: { current: Locale; page?: string; label: string }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const list = useId();

  useEffect(() => {
    if (!open) return;
    function onPointer(event: PointerEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKey(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      setOpen(false);
      button.current?.focus();
    }
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div ref={root} className="relative">
      <button
        ref={button}
        type="button"
        aria-label={label}
        aria-expanded={open}
        aria-controls={list}
        title={label}
        onClick={() => setOpen((o) => !o)}
        className="flex h-10 min-w-10 cursor-pointer items-center justify-center gap-2 rounded-full px-2.5 transition-colors hover:bg-fg/6 aria-expanded:bg-fg/6"
      >
        <PixelSprite rows={GLOBE} cell={2} />
        <span aria-hidden="true" className="hidden font-pixel text-pixel pixel-even sm:inline">
          {current.toUpperCase()}
        </span>
      </button>
      <ul
        id={list}
        hidden={!open}
        className="absolute right-0 top-12 z-50 w-48 rounded-2xl bg-card p-1.5 shadow-[0_24px_64px_-28px_rgba(26,11,23,0.55)] ring-1 ring-line"
      >
        {LOCALES.map((code) => (
          <li key={code}>
            <a
              href={pathFor(code, page)}
              hrefLang={LANGUAGES[code].tag}
              lang={LANGUAGES[code].tag}
              aria-current={code === current ? "page" : undefined}
              data-sound="select"
              onClick={() => remember(code)}
              className="flex h-10 items-center justify-between gap-3 rounded-xl px-3 text-body font-bold transition-colors hover:bg-fg/6 aria-[current=page]:text-fg"
            >
              {LANGUAGES[code].name}
              {code === current && <PixelSprite rows={SUN} cell={1} className="text-candy-pink" />}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}
