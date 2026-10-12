// Wham's pixel art, cell for cell the same as the app's (app/Sources/Pixels.swift
// and scripts/icon.swift). One string per row: "#" is ink (or the color the
// sprite is drawn in), "o" butter, "p" pink, "." empty.
export type Sprite = readonly string[];

export const INK = "#1a0b17";
export const PALETTE: Record<string, string> = { o: "#fff1b8", p: "#ff8fc8" };

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

// The same sun with a butter center inside its ink ring, where it is drawn big
// enough to show two colors.
export const SUN_LIT: Sprite = [
  ".....#.....",
  ".#...#...#.",
  "..#.....#..",
  "....###....",
  "...#ooo#...",
  "##.#ooo#.##",
  "...#ooo#...",
  "....###....",
  "..#.....#..",
  ".#...#...#.",
  ".....#.....",
];

// Its ink fills the whole 11 x 11 box, so centering the box centers the moon.
export const MOON: Sprite = [
  "....##.....",
  "..###......",
  ".###.......",
  ".###.......",
  "####.......",
  "####.......",
  "####......#",
  ".#####...##",
  ".#########.",
  "..#######..",
  "....###....",
];

// The app icon's sun, wide awake: an ink ring, a butter face, pink cheeks.
export const FACE: Sprite = [
  "..........#..........",
  "..........#..........",
  "...#......#......#...",
  "....#...........#....",
  "........#####........",
  "......##ooooo##......",
  ".....#ooooooooo#.....",
  ".....#ooooooooo#.....",
  "....#ooo#ooo#ooo#....",
  "....#ooo#ooo#ooo#....",
  "###.#ooooooooooo#.###",
  "....#opo#ooo#opo#....",
  "....#oooo###oooo#....",
  ".....#ooo#p#ooo#.....",
  ".....#ooooooooo#.....",
  "......##ooooo##......",
  "........#####........",
  "....#...........#....",
  "...#......#......#...",
  "..........#..........",
  "..........#..........",
];

// The same sun, dizzy, for the error page: crossed eyes, a little "o".
export const DIZZY: Sprite = [
  "..........#..........",
  "..........#..........",
  "...#......#......#...",
  "....#...........#....",
  "........#####........",
  "......##ooooo##......",
  ".....#ooooooooo#.....",
  ".....#ooooooooo#.....",
  "....#oo#o#o#o#oo#....",
  "....#ooo#ooo#ooo#....",
  "###.#oo#o#o#o#oo#.###",
  "....#opooooooopo#....",
  "....#ooooo#ooooo#....",
  ".....#ooo#o#ooo#.....",
  ".....#oooo#oooo#.....",
  "......##ooooo##......",
  "........#####........",
  "....#...........#....",
  "...#......#......#...",
  "..........#..........",
  "..........#..........",
];

export const HEART: Sprite = [
  ".##.##.",
  "#######",
  "#######",
  ".#####.",
  "..###..",
  "...#...",
];

// One SVG path for the pixels of one color, one unit square per pixel.
export function spritePath(rows: Sprite, color = "#"): string {
  let d = "";
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] !== color) continue;
      // Merge runs of the same color into one rectangle.
      let end = x;
      while (row[end + 1] === color) end++;
      d += `M${x} ${y}h${end - x + 1}v1h-${end - x + 1}z`;
      x = end;
    }
  });
  return d;
}

// One path per color, ink first: `ink` fills the "#" pixels, the palette the rest.
export function spriteLayers(rows: Sprite, ink: string = INK) {
  const colors = [...new Set(rows.join("").replace(/\./g, ""))].sort((a, b) => (a === "#" ? -1 : b === "#" ? 1 : 0));
  return colors.map((color) => ({ color, fill: color === "#" ? ink : (PALETTE[color] ?? ink), d: spritePath(rows, color) }));
}
