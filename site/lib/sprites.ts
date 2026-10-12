// Wham's pixel art, cell for cell the same as the app's (app/Sources/Pixels.swift
// and scripts/icon.swift). One string per row, "#" for a lit pixel.
export type Sprite = readonly string[];

export const SUN: Sprite = [
  ".....#.....",
  ".#...#...#.",
  "..#.....#..",
  "....###....",
  "...#####...",
  "##.#####.##",
  "...#####...",
  "....###....",
  "..#.....#..",
  ".#...#...#.",
  ".....#.....",
];

export const MOON: Sprite = [
  "....##.....",
  "..###......",
  ".###.......",
  ".###.......",
  "####.......",
  "####.......",
  "####.......",
  ".#####.....",
  ".#########.",
  "..#######..",
  "....###....",
];

// The app icon's sun, wide awake.
export const FACE: Sprite = [
  "........#........",
  "........#........",
  "..#...........#..",
  "...#.........#...",
  "......#####......",
  ".....#######.....",
  "....#########....",
  "....##.###.##....",
  "##..##.###.##..##",
  "....#########....",
  "....###.#.###....",
  ".....###.###.....",
  "......#####......",
  "...#.........#...",
  "..#...........#..",
  "........#........",
  "........#........",
];

export const HEART: Sprite = [
  ".##.##.",
  "#######",
  "#######",
  ".#####.",
  "..###..",
  "...#...",
];

// One SVG path for a sprite, one unit square per lit pixel.
export function spritePath(rows: Sprite): string {
  let d = "";
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] !== "#") continue;
      // Merge runs of lit pixels into one rectangle.
      let end = x;
      while (row[end + 1] === "#") end++;
      d += `M${x} ${y}h${end - x + 1}v1h-${end - x + 1}z`;
      x = end;
    }
  });
  return d;
}
