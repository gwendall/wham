// The jobs the hero's laptop runs, one per loop, in this order. A new use case
// is one more object here: the terminal, the HUD and the screen all read from it.
// Terminal lines are drawn in Silkscreen, 24 px on a 640 px screen: keep the
// command and the done line under about 30 characters.

export type Scenario = {
  id: string;
  // Typed after the prompt, once Wham is on.
  command: string;
  // The counter beside the progress bar: "tests 12/40", "42%", "7.4/20 GB".
  progress: { total: number; label?: string; unit?: string; decimals?: number; percent?: boolean };
  // The last line, once the job is done.
  done: string;
  // The HUD floating over the shut laptop, in English: each language's words
  // are in messages/<code>.json under hud.<id>.
  hud: Hud;
};

export type Hud = { title: string; caption: string; done: string };

const CODING = "Lid closed. Still coding.";

export const SCENARIOS: readonly Scenario[] = [
  {
    id: "claude",
    command: 'claude "fix the failing tests"',
    progress: { label: "tests", total: 40 },
    done: "done! 40/40 tests pass",
    hud: { title: "Claude Code", caption: CODING, done: "Tests pass!" },
  },
  {
    id: "export",
    command: "./export film.mov",
    progress: { total: 100, percent: true },
    done: "done! film.mov is ready",
    hud: { title: "Exporting", caption: "Lid closed. Still exporting.", done: "Ready!" },
  },
  {
    id: "codex",
    command: 'codex "add dark mode"',
    progress: { label: "files", total: 18 },
    done: "done! dark mode is in",
    hud: { title: "Codex", caption: CODING, done: "Done!" },
  },
  {
    id: "ollama",
    command: "ollama pull qwen3:32b",
    progress: { total: 20, unit: " GB", decimals: 1 },
    done: "done! 20 GB pulled",
    hud: { title: "Downloading", caption: "Lid closed. Still downloading.", done: "Pulled!" },
  },
  {
    id: "opencode",
    command: 'opencode run "migrate the API"',
    progress: { label: "routes", total: 24 },
    done: "done! 24 routes migrated",
    hud: { title: "OpenCode", caption: CODING, done: "Migrated!" },
  },
  {
    id: "blender",
    command: "blender -b scene.blend -a",
    progress: { label: "frames", total: 240 },
    done: "done! 240 frames rendered",
    hud: { title: "Rendering", caption: "Lid closed. Still rendering.", done: "Rendered!" },
  },
  {
    id: "grok",
    command: 'grok "write the docs"',
    progress: { label: "pages", total: 12 },
    done: "done! 12 pages written",
    hud: { title: "Grok", caption: CODING, done: "Done!" },
  },
  {
    id: "backup",
    command: "rsync -a ~/Photos nas:backup",
    progress: { label: "files", total: 2400 },
    done: "done! 2400 files backed up",
    hud: { title: "Backing up", caption: "Lid closed. Still backing up.", done: "Backed up!" },
  },
];

// The counter at progress p, from 0 to 1.
export function meter({ progress }: Scenario, p: number) {
  const { total, label, unit = "", decimals = 0, percent } = progress;
  const value = (Math.floor(p * total * 10 ** decimals) / 10 ** decimals).toFixed(decimals);
  if (percent) return `${value}%`;
  return `${label ? `${label} ` : ""}${value}/${total}${unit}`;
}
