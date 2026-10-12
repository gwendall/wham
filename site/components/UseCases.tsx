import { PixelSprite } from "@/components/PixelSprite";
import { SCENARIOS } from "@/lib/scenarios";
import type { Sprite } from "@/lib/sprites";

// "What it is for": what people leave running with the lid shut. The coding
// agents lead, on a wide candy card, then four small cards: two full rows from
// 640 px up. Every card has 24 px of padding and 24 px corners.

const TILES = ["bg-candy-pink", "bg-candy-yellow", "bg-candy-cyan", "bg-moon"];

const JOBS: { sprite: Sprite; title: string; text: string }[] = [
  {
    sprite: [
      "###########",
      "#.#.#.#.#.#",
      "###########",
      "#.........#",
      "#...#.....#",
      "#...##....#",
      "#...###...#",
      "#...##....#",
      "#...#.....#",
      "#.........#",
      "###########",
      "#.#.#.#.#.#",
      "###########",
    ],
    title: "Exports and renders",
    text: "Final Cut, Premiere, DaVinci Resolve or Blender, all the way to the last frame.",
  },
  {
    sprite: [
      "....###....",
      "....###....",
      "....###....",
      "....###....",
      ".#########.",
      "..#######..",
      "...#####...",
      "....###....",
      ".....#.....",
      "#.........#",
      "###########",
    ],
    title: "Big downloads",
    text: "Models, games, a fresh Xcode. Close the lid at 3%, open it at 100%.",
  },
  {
    sprite: [
      "....####.....",
      "...######.##.",
      "..##########.",
      ".#####.######",
      "#####...#####",
      "####.....####",
      "######.######",
      "######.######",
      ".###########.",
    ],
    title: "Backups and syncs",
    text: "Time Machine, a NAS, Backblaze, iCloud or Dropbox, all the way through.",
  },
  {
    sprite: [
      "..#######..",
      ".#.......#.",
      "#..#####..#",
      "..#.....#..",
      ".#..###..#.",
      "...#...#...",
      ".....#.....",
      "....###....",
      "....###....",
    ],
    title: "Servers and streaming",
    text: "Plex, AirPlay to the speakers, Screen Sharing or SSH: your Mac still answers.",
  },
];

export const PROMPT = [
  "###########",
  "###########",
  "#.........#",
  "#.#.......#",
  "#..#......#",
  "#...#.....#",
  "#..#......#",
  "#.#..####.#",
  "#.........#",
  "###########",
];

// The lead card's little transcript, straight from the hero's scenarios.
const TRANSCRIPT = ["claude", "codex"].map((id) => SCENARIOS.find((s) => s.id === id)!);

export function UseCases() {
  return (
    <ul className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <li className="relative overflow-hidden rounded-3xl bg-candy p-6 text-ink sm:col-span-2">
        <div className="absolute inset-0 bg-white/30" aria-hidden="true" />
        <div className="relative grid grid-cols-1 gap-6 md:grid-cols-[1fr_auto] md:items-center">
          <div className="min-w-0">
            <Tile sprite={PROMPT} className="bg-ink text-white" />
            <h3 className="mt-6 text-title font-black">AI coding agents</h3>
            <p className="mt-2 text-body text-ink/80">
              Hand Claude Code, Codex, OpenCode or Grok a long task, close the lid and go. They keep working until it is done.
            </p>
          </div>
          <pre
            aria-hidden="true"
            className="min-w-0 whitespace-pre-wrap break-words rounded-2xl bg-ink p-4 font-mono text-small text-white ring-1 ring-white/10 dark:bg-[#1c1222]"
          >
            {TRANSCRIPT.map((s, i) => (
              <span key={s.id}>
                {i > 0 && "\n"}
                <span className="select-none text-white/45">$ </span>
                {s.command}
                {"\n"}
                <span className="text-candy-yellow">{s.done}</span>
              </span>
            ))}
          </pre>
        </div>
      </li>
      {JOBS.map((job, i) => (
        <li key={job.title} className="flex gap-4 rounded-3xl bg-card p-6 ring-1 ring-line sm:flex-col sm:gap-6">
          <Tile sprite={job.sprite} className={`${TILES[i % TILES.length]} text-ink`} />
          <div className="min-w-0">
            <h3 className="text-title font-black">{job.title}</h3>
            <p className="mt-2 text-body text-muted">{job.text}</p>
          </div>
        </li>
      ))}
    </ul>
  );
}

export function Tile({ sprite, className }: { sprite: Sprite; className: string }) {
  return (
    <span className={`flex size-12 shrink-0 items-center justify-center rounded-xl ${className}`}>
      <PixelSprite rows={sprite} cell={2} />
    </span>
  );
}
