// The page's little sounds, on the chime's 25% pulse wave and in its key (E
// major), so a click on the page sounds like the app. Each one is a few notes
// of 30 to 50 ms, quieter than the chime. The header's speaker mutes them with
// the music.
import { audioContext } from "@/lib/audio";
import { chime, pulse } from "@/lib/chime";

export type Sfx = "tap" | "link" | "open" | "close" | "copy" | "select" | "download";

const E5 = 659.26;
const note = (semitones: number) => E5 * 2 ** (semitones / 12);

// [semitones above E5 for each note, the gap between notes, the last note's ring, peak]
const SOUNDS: Record<Exclude<Sfx, "download">, { notes: number[]; gap: number; ring: number; peak: number }> = {
  tap: { notes: [7], gap: 0.04, ring: 0.05, peak: 0.07 },
  link: { notes: [12, 19], gap: 0.035, ring: 0.06, peak: 0.06 },
  open: { notes: [0, 7], gap: 0.045, ring: 0.07, peak: 0.07 },
  close: { notes: [7, 0], gap: 0.045, ring: 0.06, peak: 0.055 },
  copy: { notes: [12, 16, 19, 24], gap: 0.03, ring: 0.09, peak: 0.06 },
  select: { notes: [4, 12], gap: 0.04, ring: 0.08, peak: 0.07 },
};

let last = -Infinity;

export function sfx(kind: Sfx) {
  const audio = audioContext();
  if (!audio) return;
  // Two in a row (a click that also opens something) would only blur.
  if (audio.currentTime - last < 0.03) return;
  last = audio.currentTime;
  if (kind === "download") return chime(true);
  const { notes, gap, ring, peak } = SOUNDS[kind];
  const start = audio.currentTime + 0.005;
  notes.forEach((step, index) => {
    const freq = note(step);
    const final = index === notes.length - 1;
    const at = start + index * gap;
    const length = final ? ring : gap;
    const decay = final ? ring / 2.5 : gap;
    const osc = audio.createOscillator();
    osc.setPeriodicWave(pulse(audio, freq));
    osc.frequency.value = freq;
    const gain = audio.createGain();
    const g = gain.gain;
    // The chime's envelope: 1.5 ms up, an exponential fall, 2 ms down to zero.
    g.setValueAtTime(0, at);
    g.linearRampToValueAtTime(peak, at + 0.0015);
    g.setTargetAtTime(0, at + 0.0015, decay);
    g.setValueAtTime(peak * Math.exp(-(length - 0.002) / decay), at + length - 0.002);
    g.linearRampToValueAtTime(0, at + length);
    osc.connect(gain).connect(audio.destination);
    osc.start(at);
    osc.stop(at + length + 0.005);
    osc.onended = () => gain.disconnect();
  });
}
