// The site's theme, an original tune, and the small tracker that turns it into
// a chipvoice Performance: several parts, each with its own instruments, that
// chipvoice's planner lays out on a console's voices (scripts/music.mjs plays
// it). Nothing here is chipvoice: it is plain data in, plain data out.
//
// A song is { bpm, order, sections, channels, instruments }:
//   order     the sections in play order; the whole order loops.
//   channels  { name: { role, inst, volume, gate, priority, kit } }, `role` the
//             voice chipvoice gives it first (lead, chord, bass, perc).
//   sections  { name: { bars, [channel]: line | copy } }; a channel without one
//             rests in that section.
//
// A melodic line is tokens: `E5:4` a note four sixteenths long (the length
// carries over to the next token), `r` a rest, `-` a tie, `G3+C4+E4` a chord,
// `E5'` a short note, `@flute` an instrument, `%70` a level for what follows,
// `|` a bar line (checked). A drum line is a letter per sixteenth from the
// channel's kit, `.` for silence. A copy, { copy: 'lead', delay, volume, third },
// plays another channel's notes of the section `delay` sixteenths later, or a
// diatonic third under them with `third`.

const TPB = 192;
const STEP = TPB / 4;
const BAR = 16;
/** The release left between two notes of a line, so a key-off never lands on the next key-on. */
const GAP_SECONDS = 0.008;
const NAMES = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const SCALE = [0, 2, 4, 5, 7, 9, 11]; // C major, the theme's key
const ROLE_PRIORITY = { lead: 10, bass: 9, perc: 8, chord: 5 };

export function midi(name) {
  const m = /^([A-G])([#b]?)(\d)$/.exec(name);
  if (!m) throw new Error(`bad note ${name}`);
  return 12 * (Number(m[3]) + 1) + NAMES[m[1]] + (m[2] === "#" ? 1 : m[2] === "b" ? -1 : 0);
}

/** A pitch moved `steps` degrees along the scale (a note off the scale moves by the nearest one's interval). */
function diatonic(pitch, steps) {
  const pc = ((pitch % 12) + 12) % 12;
  const near = SCALE.reduce((best, s) => (Math.abs(s - pc) < Math.abs(best - pc) ? s : best), 0);
  const base = pitch - (pc - near);
  const deg = SCALE.indexOf(near) + steps;
  const octave = Math.floor(deg / 7);
  const target = base - near + SCALE[((deg % 7) + 7) % 7] + 12 * octave;
  return target + (pc - near);
}

const TOKEN = /^((?:[A-G][#b]?\d)(?:\+[A-G][#b]?\d)*|r|-)(?::(\d+))?(')?$/;

function parseLine(line, { inst, instruments, where }) {
  const notes = [];
  let pos = 0, len = 4, cur = { inst, vol: 1 };
  for (const tok of line.trim().split(/\s+/)) {
    if (tok === "|") {
      if (pos % BAR) throw new Error(`${where}: bar line at step ${pos}`);
      continue;
    }
    if (tok[0] === "@") {
      if (!instruments[tok.slice(1)]) throw new Error(`${where}: no instrument ${tok}`);
      cur = { ...cur, inst: tok.slice(1) };
      continue;
    }
    if (tok[0] === "%") {
      cur = { ...cur, vol: Number(tok.slice(1)) / 100 };
      continue;
    }
    const m = TOKEN.exec(tok);
    if (!m) throw new Error(`${where}: bad token ${tok}`);
    if (m[2]) len = Number(m[2]);
    if (m[1] === "-") {
      if (!notes.length) throw new Error(`${where}: a tie with nothing before it`);
      notes[notes.length - 1].len += len;
    } else if (m[1] !== "r") {
      notes.push({ at: pos, len, pitches: m[1].split("+").map(midi), short: !!m[3], ...cur });
    }
    pos += len;
  }
  return { notes, steps: pos };
}

function parseDrums(line, kit, where) {
  const s = line.replace(/[\s|]/g, "");
  const hits = [];
  for (let i = 0; i < s.length; i++) {
    if (s[i] === ".") continue;
    if (!kit[s[i]]) throw new Error(`${where}: no drum ${s[i]}`);
    hits.push({ at: i, letter: s[i] });
  }
  return { hits, steps: s.length };
}

/**
 * The song as a chipvoice Performance for `chip`: `pre` bars of the order's
 * end, then the order, then `tail` bars of its start, so the loop's two ends
 * carry the same tails (the echo, a release). Returns the performance and,
 * in seconds, where the order starts in it and how long it lasts.
 */
export function compile(song, chip, { pre = 2, tail = 1, releaseSeconds = 2 } = {}) {
  const tps = (TPB * song.bpm) / 60;
  const starts = [];
  let total = 0;
  for (const name of song.order) {
    if (!song.sections[name]) throw new Error(`no section ${name}`);
    starts.push(total);
    total += song.sections[name].bars * BAR * STEP;
  }

  // every channel's notes over one time round the order, in ticks
  const byChannel = {};
  const copies = [];
  for (const [cname, ch] of Object.entries(song.channels)) {
    byChannel[cname] = [];
    song.order.forEach((sname, i) => {
      const section = song.sections[sname];
      const line = section[cname];
      const where = `${sname}/${cname}`;
      if (line == null) return;
      if (typeof line === "object") return copies.push({ cname, from: starts[i], to: starts[i] + section.bars * BAR * STEP, ...line });
      const { notes, hits, steps } = ch.role === "perc" ? parseDrums(line, ch.kit, where) : parseLine(line, { inst: ch.inst, instruments: song.instruments, where });
      if (steps !== section.bars * BAR) throw new Error(`${where}: ${steps} steps for ${section.bars * BAR}`);
      for (const n of notes ?? hits) byChannel[cname].push({ ...n, tick: starts[i] + n.at * STEP, len: (n.len ?? 1) * STEP });
    });
  }
  for (const c of copies) {
    const ch = song.channels[c.cname];
    const shift = (song.channels[c.copy].transpose ?? 0) - (ch.transpose ?? 0);
    for (const n of byChannel[c.copy]) {
      const tick = n.tick + (c.delay ?? 0) * STEP;
      if (n.tick < c.from || n.tick >= c.to || tick >= c.to) continue;
      const pitches = n.pitches.map((p) => (c.third ? diatonic(p, -2) : p) + shift);
      byChannel[c.cname].push({ ...n, tick, pitches, inst: c.inst ?? ch.inst, vol: (n.vol ?? 1) * (c.volume ?? 1) });
    }
    byChannel[c.cname].sort((a, b) => a.tick - b.tick);
  }

  // the pre-roll and the tail, cut from the order's own notes
  const barTicks = BAR * STEP;
  const preTicks = Math.min(pre * barTicks, total);
  const tailTicks = Math.min(tail * barTicks, total);
  const timeline = {};
  for (const [cname, list] of Object.entries(byChannel)) {
    const out = [];
    for (const n of list) {
      const len = Math.min(n.len, total - n.tick);
      out.push({ ...n, tick: n.tick + preTicks, len });
      if (n.tick >= total - preTicks) out.push({ ...n, tick: n.tick - (total - preTicks), len });
      if (n.tick < tailTicks) out.push({ ...n, tick: n.tick + preTicks + total, len: Math.min(n.len, tailTicks - n.tick) });
    }
    timeline[cname] = out.sort((a, b) => a.tick - b.tick);
  }
  const endTick = preTicks + total + tailTicks + Math.round(releaseSeconds * tps);
  const gap = Math.max(1, Math.round(GAP_SECONDS * tps));

  let id = 0;
  const parts = [];
  for (const [cname, ch] of Object.entries(song.channels)) {
    const programs = {};
    const programOf = (name) => (programs[name] ??= Object.keys(programs).length + 1);
    const notes = [];
    const list = timeline[cname];
    list.forEach((n, i) => {
      if (ch.role === "perc") {
        const d = ch.kit[n.letter];
        const next = list.slice(i + 1).find((m) => m.tick > n.tick);
        const end = Math.min(n.tick + Math.max(STEP, Math.round(d.seconds * tps)), next ? next.tick : Infinity, endTick);
        notes.push({ id: `${cname}${id++}`, tick: n.tick, endTick: Math.max(n.tick + 1, end - 1), pitch: 60, drum: d.drum, velocity: velocity(ch.volume, d.volume ?? 1), program: programOf(d.inst) });
        return;
      }
      const held = Math.max(gap + 1, Math.round(n.len * (n.short ? 0.5 : ch.gate ?? 1)));
      const end = Math.min(n.tick + held - gap, endTick);
      for (const pitch of n.pitches) {
        notes.push({ id: `${cname}${id++}`, tick: n.tick, endTick: end, pitch: pitch + (ch.transpose ?? 0), velocity: velocity(ch.volume, n.vol), program: programOf(n.inst) });
      }
    });
    const instruments = {};
    for (const [name, p] of Object.entries(programs)) {
      if (!song.instruments[name]) throw new Error(`${cname}: no instrument ${name}`);
      instruments[`${chip}:${p}`] = song.instruments[name];
    }
    if (notes.length) parts.push({ id: cname, name: cname, role: ch.role, priority: ch.priority ?? ROLE_PRIORITY[ch.role], notes, instruments });
  }
  return {
    performance: {
      version: 1, title: song.title, ticksPerBeat: TPB, endTick, parts, notices: [],
      tempos: [{ tick: 0, microsecondsPerBeat: Math.round(60e6 / song.bpm) }],
    },
    start: preTicks / tps,
    seconds: total / tps,
  };
}

function velocity(channel = 0.85, note = 1) {
  return Math.max(1, Math.min(127, Math.round(127 * channel * note)));
}

// ─── The instruments ──────────────────────────────────────────────────────────
// chipvoice instruments: a volume per 60 Hz frame (0 to 15, the last held with
// `sustain`), a pulse's duty (0 to 3: 12.5, 25, 50, 75 %), a SNES sample by name.

const fade = (from, to, frames) => Array.from({ length: frames }, (_, i) => Math.round(from + ((to - from) * i) / Math.max(1, frames - 1)));

export const SNES = {
  mallet: { sample: "mallet", volume: [15], sustain: true },
  flute: { sample: "flute", volume: [14], sustain: true, vibrato: { depth: 0.18, rate: 11, delay: 14 } },
  brass: { sample: "brass", volume: [15], sustain: true, vibrato: { depth: 0.12, rate: 11, delay: 18 } },
  harp: { sample: "harp", volume: [15], sustain: true },
  pluck: { sample: "harp", volume: [14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0] },
  stab: { sample: "brass", volume: [13, 12, 11, 9, 7, 5, 3, 1, 0] },
  bell: { sample: "mallet", volume: fade(14, 0, 40) },
  strings: { sample: "strings", volume: [12], sustain: true },
  organ: { sample: "sine64", volume: [12], sustain: true },
  slap: { sample: "picked-bass", volume: [15], sustain: true },
  synthbass: { sample: "synth-bass", volume: [15], sustain: true },
  kick: { sample: "kick", volume: [15] },
  snare: { sample: "snare", volume: [14] },
  hat: { sample: "hat", volume: [15, 12, 8] },
  ohat: { sample: "ohat", volume: [13] },
  crash: { sample: "ohat", volume: fade(12, 0, 50) },
  shaker: { sample: "hat", volume: [12, 7, 3, 0] },
};
export const SNES_KIT = {
  k: { inst: "kick", drum: 36, seconds: 0.25 },
  s: { inst: "snare", drum: 38, seconds: 0.2 },
  x: { inst: "snare", drum: 38, seconds: 0.1, volume: 0.45 },
  h: { inst: "hat", drum: 42, seconds: 0.06 },
  t: { inst: "shaker", drum: 70, seconds: 0.05 },
  o: { inst: "ohat", drum: 46, seconds: 0.25 },
  c: { inst: "crash", drum: 49, seconds: 0.9 },
};

// ─── The theme ────────────────────────────────────────────────────────────────
// Bright sixties-by-way-of-the-eighties pop in C: a verse on the doo-wop
// changes, a chorus that climbs, all of it written for this site.

const CHORDS = {
  C: { root: "C3", fifth: "G2", keys: "G3+C4+E4" },
  Am: { root: "A2", fifth: "E3", keys: "A3+C4+E4" },
  F: { root: "F2", fifth: "C3", keys: "A3+C4+F4" },
  G: { root: "G2", fifth: "D3", keys: "G3+B3+D4" },
  Em: { root: "E2", fifth: "B2", keys: "G3+B3+E4" },
  Dm: { root: "D3", fifth: "A2", keys: "A3+D4+F4" },
};
const up = (note) => note.replace(/\d/, (o) => String(Number(o) + 1));

/** One bar of a figure per chord, joined with bar lines. */
const bars = (chords, figure) => chords.map((name, i) => figure(CHORDS[name], i)).join(" | ");

// The bass bounces in octaves, and walks up into the next verse.
const octaves = (c) => `${c.root}:2 ${up(c.root)}:2 `.repeat(4).trim();
const walkUp = "G2:4 A2:4 B2:4 D3:4";
// The keys: plucks on the beat in the verse, stabs on every eighth in the chorus.
const onbeats = (c) => `${c.keys}:2 r:2 `.repeat(4).trim();
const eighths = (c) => `${c.keys}:2 `.repeat(8).trim();

const VERSE = ["C", "Am", "F", "G", "C", "Am", "F", "G"];
const CHORUS = ["F", "G", "Em", "Am", "Dm", "G", "C", "G"];

const LEAD = {
  A: [
    "E5:3 E5:3 G5:2 r:2 E5:2 D5:2 C5:2",
    "E5:3 E5:3 A5:2 r:2 G5:2 E5:2 C5:2",
    "F5:3 F5:3 A5:2 r:2 C6:2 A5:2 F5:2",
    "G5:4 r:2 B4:2 D5:2 F5:2 E5:2 D5:2",
    "E5:3 E5:3 G5:2 r:2 E5:2 D5:2 C5:2",
    "E5:3 E5:3 A5:2 r:2 G5:2 E5:2 C5:2",
    "A5:3 A5:3 C6:2 r:2 A5:2 G5:2 F5:2",
    "G5:4 F5:2 E5:2 D5:8",
  ],
  A2: [
    "E5:3 E5:3 G5:2 r:2 E5:2 D5:2 C5:2",
    "E5:3 E5:3 A5:2 r:2 G5:2 E5:2 C5:2",
    "F5:3 F5:3 A5:2 r:2 C6:2 A5:2 F5:2",
    "G5:4 r:2 B4:2 D5:2 F5:2 E5:2 D5:2",
    "G5:3 G5:3 C6:2 r:2 B5:2 A5:2 G5:2",
    "A5:3 A5:3 E6:2 r:2 D6:2 C6:2 A5:2",
    "F5:3 A5:3 C6:2 r:2 D6:2 C6:2 A5:2",
    "B5:4 A5:2 G5:2 D5:8",
  ],
  B: [
    "C6:2 C6:2 r:2 A5:2 C6:3 D6:3 C6:2",
    "B5:2 B5:2 r:2 G5:2 B5:3 D6:3 B5:2",
    "G5:2 G5:2 r:2 E5:2 G5:3 B5:3 G5:2",
    "A5:3 C6:3 E6:4 D6:2 C6:2 B5:2",
    "A5:2 A5:2 r:2 F5:2 A5:3 C6:3 A5:2",
    "B5:2 B5:2 r:2 G5:2 B5:3 D6:3 B5:2",
    "C6:6 G5:2 E5:2 G5:2 C6:4",
    "D6:4 B5:2 G5:2 r:2 G5:2 A5:2 B5:2",
  ],
};
LEAD.B2 = [...LEAD.B.slice(0, 6), "C6:3 C6:3 E6:2 r:2 D6:2 C6:2 G5:2", "D6:2 C6:2 B5:2 A5:2 G5:2 F5:2 E5:2 D5:2"];

// The second voice in the verse: a slow line under the tune, on the chord
// tones it leaves out, that climbs into the chorus.
const COUNTER = [
  "G4:12 A4:4",
  "C5:8 B4:4 A4:4",
  "A4:12 G4:4",
  "B4:8 G4:8",
  "G4:12 A4:4",
  "C5:8 E5:4 C5:4",
  "C5:12 A4:4",
  "D5:8 B4:8",
];

// Kick and snare on one voice (a backbeat with a skip in it), the hats on another.
const DRUMS = {
  verse: "k...s.k.k...s...",
  chorus: "k...s.k.k.k.s.k.",
  fill: "k...s...k.s.ssss",
};
const HATS = {
  verse: "h.t.h.t.h.t.h.th",
  chorus: "h.o.h.o.h.o.h.o.",
  crash: "c.o.h.o.h.o.h.o.",
  fill: "h.t.h.t.........",
};
const eight = (line, last) => [...Array(7).fill(line), last].join(" | ");

/**
 * The theme, its timbres picked by name: `lead` plays the tune (`octave` -1 an
 * octave down), `answer` holds a counter-line under it in the verse and sings a
 * third under it in the chorus, `keys` and `stabs` play the chords, `bass` the
 * bass. `mix` sets channels' volumes (0 to 1) by name.
 */
export function theme({ lead = "mallet", octave = 0, answer = "flute", keys = "pluck", stabs = "stab", bass = "synthbass", bpm = 156, mix = {} } = {}) {
  const verse = (name) => ({
    bars: 8,
    lead: LEAD[name].join(" | "),
    answer: COUNTER.join(" | "),
    bass: bars(VERSE, octaves),
    keys: bars(VERSE, onbeats),
    drums: eight(DRUMS.verse, DRUMS.fill),
    hats: eight(HATS.verse, HATS.fill),
  });
  const chorus = (name) => ({
    bars: 8,
    lead: LEAD[name].join(" | "),
    answer: { copy: "lead", third: true, volume: 0.8 },
    bass: `${bars(CHORUS.slice(0, 7), octaves)} | ${walkUp}`,
    keys: `@${stabs} ${bars(CHORUS, eighths)}`,
    drums: eight(DRUMS.chorus, DRUMS.fill),
    hats: [HATS.crash, ...Array(6).fill(HATS.chorus), HATS.fill].join(" | "),
  });
  const song = {
    title: "Wham theme",
    bpm,
    instruments: SNES,
    order: ["A", "B", "A2", "B2"],
    channels: {
      lead: { role: "lead", inst: lead, transpose: 12 * octave, volume: 0.85, gate: 0.92 },
      answer: { role: "chord", inst: answer, volume: 0.7, gate: 0.9, priority: 6 },
      bass: { role: "bass", inst: bass, volume: 0.8, gate: 0.6 },
      keys: { role: "chord", inst: keys, volume: 0.45, gate: 0.7 },
      drums: { role: "perc", kit: SNES_KIT, volume: 0.85 },
      hats: { role: "perc", kit: SNES_KIT, volume: 0.7, priority: 7 },
    },
    sections: { A: verse("A"), B: chorus("B"), A2: verse("A2"), B2: chorus("B2") },
  };
  for (const [name, volume] of Object.entries(mix)) song.channels[name].volume = volume;
  return song;
}
