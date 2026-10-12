"use client";

import { useEffect } from "react";
import { musicState } from "@/lib/music";
import { sfx, type Sfx } from "@/lib/sfx";

const INTERACTIVE = 'a[href], button, [role="button"], summary, select, input, label';

// Every link and button on the page answers with a little sound: a link pings,
// a row that opens goes up and one that closes comes down, a copy sparkles,
// Download plays the app's own chime. `data-sound` on an element picks another
// one, or "none" for an element with a sound of its own (the demo switch). One
// listener for the whole page, on the capture phase, so it reads a row's state
// before the click changes it.
export function UiSounds() {
  useEffect(() => {
    function onClick(event: MouseEvent) {
      if (!(event.target instanceof Element)) return;
      const element = event.target.closest(INTERACTIVE);
      if (!element || element.matches(":disabled, [aria-disabled='true']")) return;
      const kind = element.closest("[data-sound]")?.getAttribute("data-sound");
      if (kind === "none") return;
      // The speaker: a sound as it turns on, and one as it goes quiet.
      if (element.closest("[data-music-toggle]")) return sfx(musicState() === "playing" ? "close" : "open");
      if (musicState() === "off") return;
      const expanded = element.getAttribute("aria-expanded");
      sfx(
        (kind as Sfx | null | undefined) ??
          (expanded === "true" ? "close" : expanded === "false" ? "open" : element.tagName === "A" ? "link" : "tap"),
      );
    }
    document.addEventListener("click", onClick, { capture: true });
    return () => document.removeEventListener("click", onClick, { capture: true });
  }, []);
  return null;
}
