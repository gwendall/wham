// The app's Core Animation springs, sampled into Web Animations keyframes.
// A spring is (omega, zeta): stiffness omega^2, damping 2 zeta omega, mass 1.
export type Spring = { omega: number; zeta: number };

// Punkmaker's COMING spring, the brand's arrival.
export const COMING: Spring = { omega: 16, zeta: 0.72 };

// SwiftUI-style (perceptual duration, bounce) to (omega, zeta).
export function perceptual(duration: number, bounce: number): Spring {
  return { omega: (2 * Math.PI) / duration, zeta: 1 - bounce };
}

// Progress from 0 to 1 (with overshoot) after t seconds.
export function springAt({ omega, zeta }: Spring, t: number): number {
  const wd = omega * Math.sqrt(1 - zeta * zeta);
  return 1 - Math.exp(-zeta * omega * t) * (Math.cos(wd * t) + ((zeta * omega) / wd) * Math.sin(wd * t));
}

// Seconds until the spring stays within 0.1% of its target.
export function settle({ omega, zeta }: Spring): number {
  return Math.log(1000) / (zeta * omega);
}

// Keyframes for one or more springs played together. `frame` gets each
// spring's progress at the same instant and returns that keyframe.
export function springFrames(springs: Spring[], frame: (progress: number[]) => Keyframe) {
  const duration = Math.max(...springs.map(settle));
  const steps = Math.ceil(duration * 60);
  const frames: Keyframe[] = [];
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * duration;
    frames.push(frame(springs.map((s) => (i === steps ? 1 : springAt(s, t)))));
  }
  return { frames, duration: duration * 1000 };
}

export function lerp(from: number, to: number, x: number) {
  return from + (to - from) * x;
}

export function prefersReducedMotion() {
  return typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
