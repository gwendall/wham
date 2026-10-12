"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { MenuSwitch } from "@/components/MenuSwitch";
import { PixelSprite } from "@/components/PixelSprite";
import { Toast, type ToastShow } from "@/components/Toast";
import { chime } from "@/lib/chime";
import { musicState } from "@/lib/music";
import { FACE, MOON } from "@/lib/sprites";

// A working copy of Wham's menu bar item, at its real size in points: the
// switch with its glyph in the knob, the chime and the toast. As in the app,
// the switch is its own feedback: no highlight box on hover or press, only a
// focus ring for the keyboard. The little desktop behind it follows the
// brand: on is candy, off is night.

// Pixel stars on the night wallpaper: [x %, y %, size px].
const STARS = [
  [8, 30, 3],
  [17, 62, 2],
  [27, 22, 2],
  [36, 78, 3],
  [61, 26, 2],
  [72, 70, 2],
  [83, 40, 3],
  [91, 82, 2],
  [47, 88, 2],
  [12, 86, 2],
] as const;

export type DemoLabels = Record<"switch" | "hint" | "caption" | "finder" | "file" | "edit" | "view" | "go" | "window" | "day", string>;

export function MenuBarDemo({ labels }: { labels: DemoLabels }) {
  const [on, setOn] = useState(false);
  const [toast, setToast] = useState<ToastShow | null>(null);
  const [touched, setTouched] = useState(false);
  const [anchor, setAnchor] = useState<number | null>(null);
  const desk = useRef<HTMLDivElement>(null);
  const item = useRef<HTMLButtonElement>(null);
  const toastBox = useRef<HTMLDivElement>(null);

  // Where the switch sits, so the toast and the hint drop right under it.
  useLayoutEffect(() => {
    const box = desk.current;
    const button = item.current;
    if (!box || !button) return;
    const measure = () => {
      const d = box.getBoundingClientRect();
      const b = button.getBoundingClientRect();
      setAnchor(b.left + b.width / 2 - d.left);
    };
    measure();
    const sizes = new ResizeObserver(measure);
    sizes.observe(box);
    return () => sizes.disconnect();
  }, []);

  // Centered under the switch, kept inside the desktop.
  useLayoutEffect(() => {
    const box = toastBox.current;
    const d = desk.current;
    if (!box || !d || anchor === null) return;
    const width = box.offsetWidth;
    box.style.left = `${Math.min(Math.max(anchor - width / 2, 8), d.clientWidth - width - 8)}px`;
  }, [toast, anchor]);

  function flip() {
    const next = !on;
    setOn(next);
    setTouched(true);
    setToast((t) => ({ kind: next ? "on" : "off", id: (t?.id ?? 0) + 1 }));
    // The speaker in the header mutes the whole page, this too.
    if (musicState() !== "off") chime(next);
  }

  const label = on ? "text-ink" : "text-white";
  return (
    <figure className="m-0">
      <div
        ref={desk}
        className="relative h-75 overflow-hidden rounded-3xl bg-night shadow-[0_24px_64px_-28px_rgba(26,11,23,0.55)] ring-1 ring-line sm:h-85"
      >
        {/* Night wallpaper, then candy on top when the switch is on. */}
        <div aria-hidden="true" className="absolute inset-0 bg-[radial-gradient(120%_80%_at_50%_120%,#4a2257_0%,transparent_60%),linear-gradient(180deg,#120b19,#21112b)]">
          {STARS.map(([x, y, size], i) => (
            <span
              key={i}
              className="twinkle absolute bg-white"
              style={{ left: `${x}%`, top: `${y}%`, width: size, height: size, animationDelay: `${i * 0.37}s` }}
            />
          ))}
        </div>
        <div
          aria-hidden="true"
          className={`absolute inset-0 bg-candy transition-opacity duration-500 ${on ? "opacity-100" : "opacity-0"}`}
        >
          <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,255,255,0.45),rgba(255,255,255,0.15))]" />
        </div>

        {/* The menu bar. */}
        <div
          className={`relative z-10 flex h-10 items-center justify-between px-3 font-system text-small backdrop-blur-xl transition-colors duration-500 sm:px-4 ${
            on ? "bg-white/35" : "bg-black/30"
          } ${label}`}
        >
          <div aria-hidden="true" className="flex items-center gap-4 sm:gap-5">
            <span className="font-bold">{labels.finder}</span>
            <span className="hidden sm:inline">{labels.file}</span>
            <span className="hidden sm:inline">{labels.edit}</span>
            <span className="hidden md:inline">{labels.view}</span>
            <span className="hidden md:inline">{labels.go}</span>
            <span className="hidden lg:inline">{labels.window}</span>
          </div>
          <div className="flex items-center gap-2 sm:gap-3">
            <button
              ref={item}
              type="button"
              role="switch"
              aria-checked={on}
              data-sound="none"
              aria-label={labels.switch}
              onClick={flip}
              className={`relative flex h-8 cursor-pointer items-center rounded-full px-2 focus-visible:outline-2 ${
                on ? "focus-visible:outline-ink" : "focus-visible:outline-white"
              }`}
            >
              <MenuSwitch on={on} />
            </button>
            <WifiIcon />
            <BatteryIcon />
            <span aria-hidden="true" className="font-medium tabular-nums">
              <span className="hidden sm:inline">{labels.day} </span>9:41
            </span>
          </div>
        </div>

        {/* The art in the middle: a sleepy moon, or the sun wide awake. */}
        <div aria-hidden="true" className="absolute inset-x-0 bottom-0 top-10 flex items-center justify-center">
          <div className={`absolute transition-all duration-500 ${on ? "scale-50 opacity-0" : "scale-100 opacity-100"}`}>
            <div className="relative text-moon">
              <PixelSprite rows={MOON} cell={7} />
              <span className="zzz absolute -right-10 -top-4 font-pixel text-pixel-lg text-moon">Z</span>
              <span className="zzz zzz-2 absolute -right-16 -top-12 font-pixel text-pixel text-moon">Z</span>
            </div>
          </div>
          <div className={`absolute transition-all duration-500 ${on ? "scale-100 opacity-100" : "scale-50 opacity-0"}`}>
            <div className="bob text-ink">
              <PixelSprite rows={FACE} cell={5} />
            </div>
          </div>
        </div>

        {!touched && anchor !== null && (
          <div
            aria-hidden="true"
            className="pointer-events-none absolute top-12 z-20 -translate-x-1/2 text-white"
            style={{ left: anchor }}
          >
            {/* The bob animates `translate` too, so it lives a level down: on the
                same element it would undo the centering. */}
            <div className="hint flex flex-col items-center gap-2">
              <PixelSprite rows={ARROW} cell={2} />
              <span className="whitespace-nowrap font-pixel text-pixel">{labels.hint}</span>
            </div>
          </div>
        )}

        <div ref={toastBox} className="pointer-events-none absolute top-12 z-20">
          <Toast show={toast} />
        </div>
      </div>
      <figcaption className="mt-4 text-center text-small text-muted">
        {labels.caption}
      </figcaption>
    </figure>
  );
}

const ARROW = ["...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###.."];

function WifiIcon() {
  return (
    <svg aria-hidden="true" width="17" height="13" viewBox="0 0 17 13" fill="currentColor">
      <path d="M8.5 2.6c2.4 0 4.6.9 6.3 2.5l1.3-1.3A10.7 10.7 0 0 0 8.5.8C5.6.8 2.9 1.9.9 3.8l1.3 1.3A9 9 0 0 1 8.5 2.6Z" />
      <path d="M8.5 6.2c1.4 0 2.7.5 3.7 1.4l1.3-1.3a7.2 7.2 0 0 0-10 0l1.3 1.3c1-.9 2.3-1.4 3.7-1.4Z" />
      <path d="M8.5 9.6c.5 0 .9.2 1.2.4L8.5 12.3 7.3 10c.3-.2.7-.4 1.2-.4Z" />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <svg aria-hidden="true" width="26" height="13" viewBox="0 0 26 13" fill="none">
      <rect x="0.75" y="0.75" width="21.5" height="11.5" rx="3.25" stroke="currentColor" strokeOpacity="0.5" strokeWidth="1.5" />
      <rect x="2.5" y="2.5" width="14" height="8" rx="1.75" fill="currentColor" />
      <path d="M24 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" fill="currentColor" fillOpacity="0.5" />
    </svg>
  );
}
