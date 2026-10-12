"use client";

import { useSyncExternalStore } from "react";
import { PixelSprite } from "@/components/PixelSprite";
import { musicState, serverMusicState, subscribeMusic, toggleMusic } from "@/lib/music";

const SPEAKER = [
  "....#......",
  "...##...#..",
  "..###....#.",
  "#####.#...#",
  "#####..#..#",
  "#####..#..#",
  "#####..#..#",
  "#####.#...#",
  "..###....#.",
  "...##...#..",
  "....#......",
];

const MUTED = [
  "....#......",
  "...##......",
  "..###......",
  "#####.#...#",
  "#####..#.#.",
  "#####...#..",
  "#####..#.#.",
  "#####.#...#",
  "..###......",
  "...##......",
  "....#......",
];

// The header's sound switch: a pixel speaker, with its waves while the music
// plays, crossed out otherwise.
export function MusicToggle() {
  const state = useSyncExternalStore(subscribeMusic, musicState, serverMusicState);
  const on = state === "playing";
  return (
    <button
      type="button"
      data-music-toggle
      onClick={toggleMusic}
      aria-label="Music"
      aria-pressed={on}
      title={on ? "Music on" : "Music off"}
      className="flex size-10 items-center justify-center rounded-full transition-colors hover:bg-fg/6"
    >
      <PixelSprite rows={on ? SPEAKER : MUTED} cell={2} className={on ? "text-fg" : "text-muted"} />
    </button>
  );
}
