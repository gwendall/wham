"use client";

import { useLayoutEffect, useRef } from "react";
import { PixelSprite } from "@/components/PixelSprite";
import { COMING, lerp, prefersReducedMotion, springFrames } from "@/lib/spring";
import { MOON, SUN } from "@/lib/sprites";

// The app's toast (app/Sources/Toast.swift), for the web: a pill that drops
// in on a spring, its pixel sprite popping and turning, the title's letters
// falling into place 22 ms apart, the caption last. It holds 2.2 s, then
// leaves in 0.16 s, easing in.
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

    if (prefersReducedMotion()) {
      root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200 });
    } else {
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
      const reduce = prefersReducedMotion();
      const leave = root.animate(
        [
          { opacity: 1, transform: "none" },
          { opacity: 0, transform: reduce ? "none" : "translateY(-8px) scale(0.92)" },
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
          className={`flex h-[46px] items-center gap-[11px] whitespace-nowrap rounded-[23px] pl-[15px] pr-[20px] ${
            on ? "bg-candy text-ink shadow-[0_0_26px_rgba(255,3,180,0.45)]" : "bg-pill text-white ring-[0.5px] ring-white/16"
          }`}
        >
          <span ref={sprite} className={`flex shrink-0 ${on ? "text-ink" : "text-moon"}`}>
            <PixelSprite rows={style.sprite} cell={2} />
          </span>
          <span className="flex flex-col gap-[7px]">
            <span ref={title} className="font-pixel text-[16px] leading-[10px] whitespace-pre">
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
            <span ref={caption} className={`text-[12px] font-bold leading-[12px] ${on ? "text-ink/72" : "text-white/60"}`}>
              {style.caption}
            </span>
          </span>
        </div>
      </div>
    </>
  );
}
