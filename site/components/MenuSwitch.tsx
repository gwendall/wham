"use client";

import { useId, useLayoutEffect, useRef } from "react";
import { INK, MOON, SUN, spritePath } from "@/lib/sprites";
import { perceptual, prefersReducedMotion, settle, springAt } from "@/lib/spring";

// Wham's menu bar item: one switch, the glyph inside its knob. In points, the
// track is 42 x 21 and fully round, the knob 17 and 2 in, so the 11 point glyph
// sits 3 points from the knob's edge on every side.
//   On: candy track, white knob on the right, the ink sun in it.
//   Off: the track in the label color at 20%, the knob on the left in the label
//   color, the moon cut out of it down to the bar behind.
// Flipping, the knob slides on a slight spring and rolls: it turns by its
// travel over its radius, clockwise going right, while the glyphs crossfade in
// the first 0.16 s. `scale` draws it at a whole multiple. At rest every edge
// of the glyph is on a whole point, and the browser already puts an svg on
// whole device pixels (moving it again by the layout's fraction blurs it).
const W = 42;
const H = 21;
const INSET = 2;
const KNOB = 17;
const R = KNOB / 2;
const GLYPH_AT = (KNOB - 11) / 2;
const OFF_X = INSET;
const ON_X = W - INSET - KNOB;
const SLIDE = perceptual(0.34, 0.18);
const FADE = 0.16;

const SUN_PATH = spritePath(SUN);
const MOON_PATH = spritePath(MOON);

// Degrees the knob has turned after rolling `distance` points.
const roll = (distance: number) => (distance / R) * (180 / Math.PI);

type Pose = { x: number; lit: number; sun: number; moon: number };

export function MenuSwitch({ on, scale = 1, className = "" }: { on: boolean; scale?: number; className?: string }) {
  const id = useId().replace(/[^\w-]/g, "");
  const knobRef = useRef<SVGGElement>(null);
  const sunRef = useRef<SVGGElement>(null);
  const moonRef = useRef<SVGGElement>(null);
  const fillRef = useRef<SVGCircleElement>(null);
  const whiteRef = useRef<SVGCircleElement>(null);
  const candyRef = useRef<SVGRectElement>(null);
  const dimRef = useRef<SVGRectElement>(null);
  const pose = useRef<Pose>({ x: on ? ON_X : OFF_X, lit: on ? 1 : 0, sun: 0, moon: 0 });
  const shown = useRef(on);

  // Before the browser paints: the new state's markup is in, the pose starts from the old one.
  useLayoutEffect(() => {
    if (shown.current === on) return;
    shown.current = on;
    const from = { ...pose.current };
    const to = on ? ON_X : OFF_X;
    const target = on ? 1 : 0;
    const paint = (p: Pose) => {
      pose.current = p;
      const knob = `translate(${p.x} 0)`;
      knobRef.current?.setAttribute("transform", knob);
      sunRef.current?.setAttribute("transform", `rotate(${p.sun} ${R} ${INSET + R})`);
      moonRef.current?.setAttribute("transform", `${knob} rotate(${p.moon} ${R} ${INSET + R})`);
      for (const [el, value] of [
        [sunRef, p.lit],
        [whiteRef, p.lit],
        [candyRef, p.lit],
        [moonRef, 1 - p.lit],
        [fillRef, 1 - p.lit],
        [dimRef, 1 - p.lit],
      ] as const) {
        el.current?.setAttribute("opacity", `${value}`);
      }
    };
    if (prefersReducedMotion()) {
      paint({ x: to, lit: target, sun: 0, moon: 0 });
      return;
    }
    const duration = settle(SLIDE);
    const start = performance.now();
    let frame = 0;
    paint(from);
    const tick = (now: number) => {
      const t = Math.max(0, now - start) / 1000;
      const done = t >= duration;
      const x = from.x + (to - from.x) * springAt(SLIDE, t);
      const f = Math.min(t / FADE, 1);
      const lit = from.lit + (target - from.lit) * f * f * (3 - 2 * f);
      // The glyph that arrives ends upright; the one that leaves starts where it was.
      const arriving = roll(x - to);
      const leaving = roll(x - from.x);
      if (done) paint({ x: to, lit: target, sun: 0, moon: 0 });
      else paint({ x, lit, sun: on ? arriving : from.sun + leaving, moon: on ? from.moon + leaving : arriving });
      if (!done) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [on]);

  const p: Pose = { x: on ? ON_X : OFF_X, lit: on ? 1 : 0, sun: 0, moon: 0 };
  const knob = `translate(${p.x} 0)`;
  return (
    <svg
      aria-hidden="true"
      width={W * scale}
      height={H * scale}
      viewBox={`0 0 ${W} ${H}`}
      overflow="visible"
      className={`block shrink-0 ${className}`}
    >
      <defs>
        <linearGradient id={`${id}-candy`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#ff7ad9" />
          <stop offset="0.5" stopColor="#ffd36e" />
          <stop offset="1" stopColor="#6fd3ff" />
        </linearGradient>
        <filter id={`${id}-shadow`} x="-50%" y="-50%" width="200%" height="200%">
          <feDropShadow dx="0" dy="0.5" stdDeviation="0.6" floodColor="#000" floodOpacity="0.3" />
        </filter>
        {/* The moon is a hole: through the knob and the track, down to the bar. */}
        <mask id={`${id}-hole`} maskUnits="userSpaceOnUse" x={-4} y={-4} width={W + 8} height={H + 8}>
          <rect x={-4} y={-4} width={W + 8} height={H + 8} fill="#fff" />
          <g ref={moonRef} transform={`${knob} rotate(${p.moon} ${R} ${INSET + R})`} opacity={1 - p.lit}>
            <path d={MOON_PATH} transform={`translate(${GLYPH_AT} ${INSET + GLYPH_AT})`} fill="#000" shapeRendering="crispEdges" />
          </g>
        </mask>
      </defs>
      <g mask={`url(#${id}-hole)`}>
        <rect ref={dimRef} width={W} height={H} rx={H / 2} fill="currentColor" fillOpacity={0.2} opacity={1 - p.lit} />
        <rect ref={candyRef} width={W} height={H} rx={H / 2} fill={`url(#${id}-candy)`} opacity={p.lit} />
        <g ref={knobRef} transform={knob}>
          <circle ref={fillRef} cx={R} cy={INSET + R} r={R} fill="currentColor" opacity={1 - p.lit} />
          <circle ref={whiteRef} cx={R} cy={INSET + R} r={R} fill="#fff" filter={`url(#${id}-shadow)`} opacity={p.lit} />
          <g ref={sunRef} transform={`rotate(${p.sun} ${R} ${INSET + R})`} opacity={p.lit}>
            <path d={SUN_PATH} transform={`translate(${GLYPH_AT} ${INSET + GLYPH_AT})`} fill={INK} shapeRendering="crispEdges" />
          </g>
        </g>
      </g>
    </svg>
  );
}
