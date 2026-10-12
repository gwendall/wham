// The site's background music, played on a Super Nintendo by chipvoice:
//
//   pnpm music                        the theme (scripts/song.mjs)
//   pnpm music path/to/song.mid       a MIDI file instead, the whole file looped
//   pnpm music --out <dir>            a WAV and an MP3 to listen to, nothing else
//
// Writes public/music.mp3, one time round the loop with MARGIN seconds of the
// music on either side, and lib/music-loop.ts, where the loop sits in it. The
// player loops on [start, end]: an MP3 decoder may add a few milliseconds of
// silence up front, and the margin keeps the loop on music whatever it adds.
// Needs ffmpeg with lame. Run it by hand and commit what it writes.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { importMidi, planPerformance, renderPerformance, snesChip, toWav } from "chipvoice";
import { compile, theme } from "./song.mjs";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const MARGIN = 0.1;
// The S-DSP's own rate: nothing it plays reaches above 16 kHz.
const SAMPLE_RATE = 32000;
// The timbres and levels the listening tests picked; the levels put each part
// at its loudness against the lead (BS.1770, each part alone).
const THEME = {
  lead: "mallet",
  answer: "flute",
  mix: { lead: 0.62, answer: 0.18, bass: 0.43, keys: 0.25, drums: 0.75, hats: 1 },
};

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  if (i < 0) return undefined;
  const [, value] = args.splice(i, 2);
  return value;
};
const out = flag("--out");
const midi = args[0];

const mono = ({ left, right }) => {
  const m = new Float32Array(left.length);
  for (let i = 0; i < m.length; i++) m[i] = right ? (left[i] + right[i]) / 2 : left[i];
  return m;
};
const render = (performance) =>
  mono(renderPerformance(planPerformance(performance, snesChip, { mix: false, allowLoss: true, space: "room" }), snesChip, { sampleRate: SAMPLE_RATE }));

// One time round the loop, with MARGIN seconds before and after it.
function music() {
  const margin = Math.round(MARGIN * SAMPLE_RATE);
  if (midi) {
    // A MIDI file loops whole: its last bars wrap round into the margin before it.
    const once = render(importMidi(new Uint8Array(readFileSync(midi)), { title: basename(midi) }));
    const samples = new Float32Array(once.length + margin * 2);
    samples.set(once.subarray(once.length - margin), 0);
    samples.set(once, margin);
    samples.set(once.subarray(0, margin), margin + once.length);
    return { samples, loop: once.length / SAMPLE_RATE };
  }
  // The theme is rendered with bars of its end before it and of its start after
  // it, so both margins hold the music (and its echo) the loop will play.
  const { performance, start, seconds } = compile(theme(THEME), "snes");
  const all = render(performance);
  const from = Math.round(start * SAMPLE_RATE) - margin;
  const length = Math.round(seconds * SAMPLE_RATE) + 2 * margin;
  return { samples: all.slice(from, from + length), loop: seconds };
}

const { samples, loop } = music();
let peak = 0;
for (const s of samples) peak = Math.max(peak, Math.abs(s));
for (let i = 0; i < samples.length; i++) samples[i] *= 0.9 / peak;

const work = out ?? join(tmpdir(), `wham-music-${process.pid}`);
mkdirSync(work, { recursive: true });
const wav = join(work, "music.wav");
writeFileSync(wav, toWav({ sampleRate: SAMPLE_RATE, left: samples, right: null, seconds: samples.length / SAMPLE_RATE, peak: 0.9 }));
const mp3 = out ? join(out, "music.mp3") : join(site, "public", "music.mp3");
mkdirSync(dirname(mp3), { recursive: true });
execFileSync("ffmpeg", ["-v", "error", "-y", "-i", wav, "-ac", "1", "-c:a", "libmp3lame", "-b:a", "80k", mp3]);
if (!out) {
  rmSync(work, { recursive: true, force: true });
  writeFileSync(
    join(site, "lib", "music-loop.ts"),
    [
      "// Written by scripts/music.mjs with public/music.mp3. Do not edit.",
      `export const MUSIC_LOOP = { start: ${MARGIN}, end: ${+(MARGIN + loop).toFixed(6)} };`,
      "",
    ].join("\n"),
  );
}
console.log(`${midi ? basename(midi) : "theme"}: ${loop.toFixed(2)} s loop -> ${mp3}`);
