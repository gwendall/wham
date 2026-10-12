"use client";

import { useLayoutEffect, useRef } from "react";
import { PixelSprite } from "@/components/PixelSprite";
import { COMING, lerp, prefersReducedMotion, springFrames } from "@/lib/spring";
import { MOON, SUN } from "@/lib/sprites";

// The app's toast (app/Sources/Toast.swift), for the web: a pill that drops
// in on a spring, its pixel sprite popping and turning, the title's letters
// falling into place 22 ms apart, the caption last. It holds 2.2 s, then
// leaves in 0.16 s, easing in. With reduced motion it simply appears and goes.
// 52 px tall: the sprite's 24 px cell sits 14 px from the top, the bottom and
// the round end, concentric with it, which puts the sprite itself 15 px in; the
// text ends 20 px from the other end.
export type ToastKind = "on" | "off";
export type ToastShow = { kind: ToastKind; id: number };

const STYLES = {
  on: { title: "MAC STAYS AWAKE", caption: "Even with the lid closed", sprite: SUN, spin: 45 },
  off: { title: "MAC CAN SLEEP", caption: "Back to normal sleep", sprite: MOON, spin: -30 },
} as const;

const HOLD = 2200;
const LEAVE = 160;

export function Toast({ show, announce = true }: { show: ToastShow | null; announce?: boolean }) {
  const stage = useRef<HTMLDivElement>(null);
  const sprite = useRef<HTMLSpanElement>(null);
  const title = useRef<HTMLSpanElement>(null);
  const caption = useRef<HTMLSpanElement>(null);
  const style = STYLES[show?.kind ?? "on"];

  useLayoutEffect(() => {
    const root = stage.current;
    if (!show || !root) return;
    root.getAnimations({ subtree: true }).forEach((a) => a.cancel());
    root.style.visibility = "visible";

    if (!prefersReducedMotion()) {
      const arrive = springFrames([COMING], ([x]) => ({ transform: `translateY(${lerp(-12, 0, x)}px) scale(${lerp(0.92, 1, x)})` }));
      root.animate(arrive.frames, { duration: arrive.duration });
      root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, easing: "ease-out" });

      const pop = springFrames(
        [
          { omega: 18, zeta: 0.42 },
          { omega: 16, zeta: 0.5 },
        ],
        ([scale, turn]) => ({ transform: `rotate(${lerp(STYLES[show.kind].spin, 0, turn)}deg) scale(${lerp(0.2, 1, scale)})` }),
      );
      sprite.current?.animate(pop.frames, { duration: pop.duration, delay: 60, fill: "backwards" });

      const letters = Array.from(title.current?.querySelectorAll<HTMLElement>("[data-letter]") ?? []);
      letters.forEach((letter, i) => {
        const delay = 70 + 22 * i;
        letter.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 100, delay, easing: "ease-out", fill: "backwards" });
        letter.animate([{ transform: "translateY(-6px)" }, { transform: "none" }], {
          duration: 140,
          delay,
          easing: "ease-out",
          fill: "backwards",
        });
      });
      caption.current?.animate(
        [
          { opacity: 0, transform: "translateY(-3px)" },
          { opacity: 1, transform: "none" },
        ],
        { duration: 240, delay: 70 + 22 * letters.length, easing: "ease-out", fill: "backwards" },
      );
    }

    const timer = window.setTimeout(() => {
      if (prefersReducedMotion()) {
        root.style.visibility = "hidden";
        return;
      }
      const leave = root.animate(
        [
          { opacity: 1, transform: "none" },
          { opacity: 0, transform: "translateY(-8px) scale(0.92)" },
        ],
        { duration: LEAVE, easing: "ease-in", fill: "forwards" },
      );
      leave.onfinish = () => {
        root.style.visibility = "hidden";
      };
    }, HOLD);
    return () => window.clearTimeout(timer);
  }, [show]);

  const on = show?.kind !== "off";
  return (
    <>
      {announce && (
        <span role="status" className="sr-only">
          {show ? `${style.title.toLowerCase()}. ${style.caption}.` : ""}
        </span>
      )}
      <div ref={stage} aria-hidden="true" className="origin-top" style={{ visibility: "hidden" }}>
        <div
          className={`flex h-13 items-center gap-3 whitespace-nowrap rounded-full pl-3.5 pr-5 ${
            on ? "bg-candy text-ink shadow-[0_0_24px_rgba(255,3,180,0.45)]" : "bg-pill text-white ring-[0.5px] ring-white/16"
          }`}
        >
          <span ref={sprite} className={`flex size-6 shrink-0 items-center justify-center ${on ? "text-ink" : "text-moon"}`}>
            <PixelSprite rows={style.sprite} cell={2} />
          </span>
          <span className="flex flex-col">
            <span ref={title} className="font-pixel text-pixel whitespace-pre">
              {style.title.split("").map((char, i) =>
                char === " " ? (
                  <span key={i}> </span>
                ) : (
                  <span key={i} data-letter className="inline-block">
                    {char}
                  </span>
                ),
              )}
            </span>
            <span ref={caption} className={`text-micro font-bold ${on ? "text-ink/72" : "text-white/60"}`}>
              {style.caption}
            </span>
          </span>
        </div>
      </div>
    </>
  );
}
