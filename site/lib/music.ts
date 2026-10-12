// The site's background music: public/music.mp3, an original SNES tune made by
// scripts/music.mjs, looped between MUSIC_LOOP's two marks (the file runs a
// little past both, so the decoder's padding never lands inside the loop).
// Browsers let no page make a sound before the visitor's first click or key,
// so the music waits for that gesture ("armed") unless the visitor switched it
// off on an earlier visit. The toggle shows what you hear: on only while it plays.
import { audioContext } from "@/lib/audio";
import { MUSIC_LOOP } from "@/lib/music-loop";

export type MusicState = "off" | "armed" | "playing";

const SRC = "/music.mp3";
const KEY = "wham:music";
const GAIN = 0.3;
const FADE_IN = 1.5;
const FADE_OUT = 0.4;
// Gestures that let a page start sound (pointerdown only for a mouse; a touch
// counts when it ends, and not when it scrolled).
const GESTURES = ["pointerdown", "pointerup", "touchend", "keydown"] as const;

let state: MusicState = "armed";
let started = false;
let bytes: Promise<ArrayBuffer> | null = null;
let buffer: Promise<AudioBuffer> | null = null;
let playing: { source: AudioBufferSourceNode; gain: GainNode } | null = null;
const listeners = new Set<() => void>();

function set(next: MusicState) {
  state = next;
  listeners.forEach((listener) => listener());
}

function save(value: "on" | "off") {
  try {
    localStorage.setItem(KEY, value);
  } catch {}
}

function fetchBytes() {
  bytes ??= fetch(SRC).then((res) => {
    if (!res.ok) throw new Error(`${SRC}: ${res.status}`);
    return res.arrayBuffer();
  });
  return bytes;
}

function decode(audio: AudioContext) {
  buffer ??= fetchBytes().then((data) => audio.decodeAudioData(data));
  buffer.catch(() => {
    bytes = buffer = null;
  });
  return buffer;
}

async function play() {
  const audio = audioContext();
  if (!audio || playing) return;
  const data = await decode(audio).catch(() => null);
  if (!data) return;
  // Without a gesture yet, this waits for the next one.
  await audio.resume();
  if (state !== "armed" || playing) return;
  const source = audio.createBufferSource();
  source.buffer = data;
  source.loop = true;
  source.loopStart = MUSIC_LOOP.start;
  source.loopEnd = MUSIC_LOOP.end;
  const gain = audio.createGain();
  gain.gain.setValueAtTime(0, audio.currentTime);
  gain.gain.linearRampToValueAtTime(GAIN, audio.currentTime + FADE_IN);
  source.connect(gain).connect(audio.destination);
  source.start(0, MUSIC_LOOP.start);
  playing = { source, gain };
  set("playing");
}

function stop() {
  const audio = audioContext();
  if (audio && playing) {
    const { source, gain } = playing;
    const now = audio.currentTime;
    gain.gain.cancelScheduledValues(now);
    gain.gain.setValueAtTime(gain.gain.value, now);
    gain.gain.linearRampToValueAtTime(0, now + FADE_OUT);
    source.stop(now + FADE_OUT + 0.02);
    source.onended = () => gain.disconnect();
  }
  playing = null;
}

function onGesture(event: Event) {
  if (state !== "armed") return;
  // The toggle's own click decides for itself.
  if (event.target instanceof Element && event.target.closest("[data-music-toggle]")) return;
  if (event instanceof KeyboardEvent && (event.key === "Escape" || event.metaKey || event.ctrlKey || event.altKey)) return;
  if (event instanceof PointerEvent && event.type === "pointerdown" && event.pointerType !== "mouse") return;
  void play();
}

// A hidden tab goes quiet, and picks up where it was when it comes back.
function onVisibility() {
  const audio = playing?.source.context as AudioContext | undefined;
  if (!audio) return;
  if (document.visibilityState === "hidden") void audio.suspend();
  else if (state === "playing") void audio.resume();
}

function start() {
  if (started || typeof window === "undefined") return;
  started = true;
  let saved: string | null = null;
  try {
    saved = localStorage.getItem(KEY);
  } catch {}
  if (saved === "off") set("off");
  for (const type of GESTURES) window.addEventListener(type, onGesture, { capture: true, passive: true });
  document.addEventListener("visibilitychange", onVisibility);
  // Fetch the file while the page is idle, so the first click plays at once.
  if (state === "armed") {
    const idle = window.requestIdleCallback ?? ((run: () => void) => setTimeout(run, 1500));
    idle(() => void fetchBytes().catch(() => (bytes = null)));
  }
}

export function toggleMusic() {
  if (state === "playing") {
    stop();
    save("off");
    set("off");
  } else {
    save("on");
    set("armed");
    void play();
  }
}

export function subscribeMusic(listener: () => void) {
  start();
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export const musicState = () => state;
export const serverMusicState = (): MusicState => "armed";
