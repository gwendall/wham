// One AudioContext for the whole page, made on first use: the chime and the
// music share it, so a browser that wants a gesture before any sound unlocks
// both at once.
let context: AudioContext | null = null;

export function audioContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  try {
    context ??= new AudioContext();
  } catch {
    return null;
  }
  if (context.state === "suspended" && document.visibilityState === "visible") void context.resume();
  return context;
}
