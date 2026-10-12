"use client";

import { useLayoutEffect, useRef, useState } from "react";
import { PixelSprite } from "@/components/PixelSprite";
import { Toast, type ToastShow } from "@/components/Toast";
import { chime } from "@/lib/chime";
import { lerp, perceptual, prefersReducedMotion, springFrames } from "@/lib/spring";
import { FACE, MOON, SUN } from "@/lib/sprites";

// A working copy of Wham's menu bar item (app/Sources/SwitchView.swift), at
// one and a half times its size: the pixel glyph, the switch, the chime and
// the toast. The little desktop behind it follows the brand: on is candy, off
// is night.
const TRACK_W = 42;
const TRACK_H = 24;
const INSET = 4;
const KNOB = TRACK_H - 2 * INSET;
const TRAVEL = TRACK_W - 2 * INSET - KNOB;

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

export function MenuBarDemo() {
  const [on, setOn] = useState(false);
  const [toast, setToast] = useState<ToastShow | null>(null);
  const [touched, setTouched] = useState(false);
  const [anchor, setAnchor] = useState<number | null>(null);
  const desk = useRef<HTMLDivElement>(null);
  const item = useRef<HTMLButtonElement>(null);
  const toastBox = useRef<HTMLDivElement>(null);
  const knob = useRef<HTMLSpanElement>(null);
  const sun = useRef<HTMLSpanElement>(null);
  const moon = useRef<HTMLSpanElement>(null);

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
    chime(next);
    if (prefersReducedMotion()) return;

    const k = knob.current;
    if (k) {
      const [from, to] = next ? [0, TRAVEL] : [TRAVEL, 0];
      const move = springFrames([perceptual(0.34, 0.18)], ([x]) => ({ transform: `translateX(${lerp(from, to, x)}px)` }));
      k.animate(move.frames, { duration: move.duration });
      // The knob stretches as it leaves, like a drop of liquid.
      k.animate(
        [
          { width: `${KNOB}px`, left: `${INSET}px` },
          { width: `${KNOB + 4}px`, left: `${INSET - (next ? 0 : 4)}px`, offset: 0.35, easing: "ease-in-out" },
          { width: `${KNOB}px`, left: `${INSET}px` },
        ],
        { duration: 320, easing: "ease-out" },
      );
    }
    // The glyph that arrives pops in turning; the one that leaves shrinks away.
    const [arriving, leaving] = next ? [sun.current, moon.current] : [moon.current, sun.current];
    const pop = springFrames([perceptual(0.4, 0.4), perceptual(0.45, 0.3)], ([scale, turn]) => ({
      transform: `rotate(${lerp(next ? 90 : -60, 0, turn)}deg) scale(${lerp(0.2, 1, scale)})`,
    }));
    arriving?.animate(pop.frames, { duration: pop.duration });
    arriving?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120 });
    leaving?.animate(
      [
        { opacity: 1, transform: "scale(1)" },
        { opacity: 0, transform: "scale(0.3)" },
      ],
      { duration: 140, easing: "ease-in-out" },
    );
  }

  const label = on ? "text-ink" : "text-white";
  return (
    <figure className="m-0">
      <div
        ref={desk}
        className="relative h-[300px] overflow-hidden rounded-[22px] bg-night shadow-[0_24px_60px_-28px_rgba(26,11,23,0.55)] ring-1 ring-line sm:h-[340px]"
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
          className={`relative z-10 flex h-10 items-center justify-between px-3 font-system text-[14px] backdrop-blur-xl transition-colors duration-500 sm:px-4 ${
            on ? "bg-white/35" : "bg-black/30"
          } ${label}`}
        >
          <div aria-hidden="true" className="flex items-center gap-4 sm:gap-5">
            <span className="font-bold">Finder</span>
            <span className="hidden sm:inline">File</span>
            <span className="hidden sm:inline">Edit</span>
            <span className="hidden md:inline">View</span>
            <span className="hidden md:inline">Go</span>
            <span className="hidden lg:inline">Window</span>
          </div>
          <div className="flex items-center gap-2 sm:gap-3">
            <button
              ref={item}
              type="button"
              role="switch"
              aria-checked={on}
              aria-label="Keep this Mac awake, even with the lid closed"
              onClick={flip}
              className={`relative flex h-[32px] cursor-pointer items-center gap-[8px] rounded-[8px] px-[8px] transition-colors hover:bg-white/20 focus-visible:outline-2 focus-visible:outline-offset-2 ${
                on ? "focus-visible:outline-ink" : "focus-visible:outline-white"
              }`}
            >
              <span className="relative block h-[22px] w-[22px]">
                <span ref={sun} className={`absolute inset-0 ${on ? "opacity-100" : "opacity-0"}`}>
                  <PixelSprite rows={SUN} cell={2} />
                </span>
                <span ref={moon} className={`absolute inset-0 ${on ? "opacity-0" : "opacity-100"}`}>
                  <PixelSprite rows={MOON} cell={2} />
                </span>
              </span>
              <span className="relative block" style={{ width: TRACK_W, height: TRACK_H }}>
                <span
                  className={`absolute inset-0 rounded-full border-2 border-current transition-opacity duration-200 ${on ? "opacity-0" : "opacity-100"}`}
                />
                <span className={`absolute inset-0 rounded-full bg-candy transition-opacity duration-200 ${on ? "opacity-100" : "opacity-0"}`} />
                <span
                  ref={knob}
                  className={`absolute rounded-full transition-colors duration-150 ${on ? "bg-white shadow-[0_1px_2px_rgba(0,0,0,0.3)]" : "bg-current"}`}
                  style={{ left: INSET, top: INSET, width: KNOB, height: KNOB, transform: `translateX(${on ? TRAVEL : 0}px)` }}
                />
              </span>
            </button>
            <WifiIcon />
            <BatteryIcon />
            <span aria-hidden="true" className="font-medium tabular-nums">
              <span className="hidden sm:inline">Mon </span>9:41
            </span>
          </div>
        </div>

        {/* The art in the middle: a sleepy moon, or the sun wide awake. */}
        <div aria-hidden="true" className="absolute inset-x-0 bottom-0 top-10 flex items-center justify-center">
          <div className={`absolute transition-all duration-500 ${on ? "scale-50 opacity-0" : "scale-100 opacity-100"}`}>
            <div className="relative text-moon">
              <PixelSprite rows={MOON} cell={7} />
              <span className="zzz absolute -right-9 -top-3 font-pixel text-[24px] text-moon">Z</span>
              <span className="zzz zzz-2 absolute -right-16 -top-10 font-pixel text-[16px] text-moon">Z</span>
            </div>
          </div>
          <div className={`absolute transition-all duration-500 ${on ? "scale-100 opacity-100" : "scale-50 opacity-0"}`}>
            <div className="bob text-ink">
              <PixelSprite rows={FACE} cell={6} />
            </div>
          </div>
        </div>

        {!touched && anchor !== null && (
          <div
            aria-hidden="true"
            className="hint pointer-events-none absolute top-[46px] z-20 flex -translate-x-1/2 flex-col items-center gap-1 text-white"
            style={{ left: anchor }}
          >
            <PixelSprite rows={ARROW} cell={2} />
            <span className="font-pixel text-[16px] leading-none">Click me</span>
          </div>
        )}

        <div ref={toastBox} className="pointer-events-none absolute top-[46px] z-20">
          <Toast show={toast} />
        </div>
      </div>
      <figcaption className="mt-3 text-center text-[14px] text-muted">
        Sound on: that is the real chime, an 8-bit arpeggio played by your browser.
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
