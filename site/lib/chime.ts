// Wham's switch sound, the same as the app's (app/Sources/Chime.swift): a
// four-note arpeggio on a 25% pulse wave. E5 G#5 B5 E6, 55 ms apart, each note
// cut by the next, the last one ringing 160 ms. Up to switch on, down and
// softer to switch off.
import { audioContext } from "@/lib/audio";

const ROOT = 659.26; // E5
const STEPS = [0, 4, 7, 12];
const GAP = 0.055;
const RING = 0.16;
const ATTACK = 0.0015;
const RELEASE = 0.002;

const waves = new Map<number, PeriodicWave>();

// A band-limited 25% pulse: harmonics a_n = 2/(n pi) sin(n pi 0.25), up to 18 kHz.
export function pulse(audio: AudioContext, freq: number): PeriodicWave {
  const cached = waves.get(freq);
  if (cached) return cached;
  const count = Math.floor(18_000 / freq);
  const real = new Float32Array(count + 1);
  const imag = new Float32Array(count + 1);
  for (let n = 1; n <= count; n++) real[n] = (2 / (n * Math.PI)) * Math.sin(n * Math.PI * 0.25);
  // Normalized to a peak of 1, like the app's buffer before its final gain.
  const wave = audio.createPeriodicWave(real, imag);
  waves.set(freq, wave);
  return wave;
}

export function chime(on: boolean) {
  const audio = audioContext();
  if (!audio) return;
  const peak = on ? 0.25 : 0.19;
  const notes = (on ? STEPS : [...STEPS].reverse()).map((st) => ROOT * 2 ** (st / 12));
  const start = audio.currentTime + 0.01;
  notes.forEach((freq, index) => {
    const last = index === notes.length - 1;
    const at = start + index * GAP;
    const length = last ? RING : GAP;
    const decay = last ? 0.07 : 0.05;
    const osc = audio.createOscillator();
    osc.setPeriodicWave(pulse(audio, freq));
    osc.frequency.value = freq;
    const gain = audio.createGain();
    const g = gain.gain;
    // 1.5 ms attack, an exponential decay, a 2 ms release: no click at either end.
    g.setValueAtTime(0, at);
    g.linearRampToValueAtTime(peak * Math.exp(-ATTACK / decay), at + ATTACK);
    g.setTargetAtTime(0, at + ATTACK, decay);
    g.setValueAtTime(peak * Math.exp(-(length - RELEASE) / decay), at + length - RELEASE);
    g.linearRampToValueAtTime(0, at + length);
    osc.connect(gain).connect(audio.destination);
    osc.start(at);
    osc.stop(at + length + 0.005);
    osc.onended = () => gain.disconnect();
  });
}
