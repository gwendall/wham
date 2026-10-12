"use client";

import { useEffect, useRef, useState } from "react";

// A shell command with a copy button. The box is 56 px tall with 16 px corners;
// the button sits 8 px from its top, bottom and right edges, with 8 px corners,
// so the two curves stay concentric. "Copy" and "Copied" share one cell and
// cross-fade, so the button never changes width.
export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef(0);
  useEffect(() => () => window.clearTimeout(timer.current), []);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
    } catch {
      // Older browsers, or a page without clipboard access: select it instead.
      const range = document.createRange();
      const code = document.getElementById(`cmd-${slug(command)}`);
      if (!code) return;
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
      return;
    }
    setCopied(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <div className="flex h-14 min-w-0 items-center gap-2 rounded-2xl bg-ink pl-4 pr-2 text-white ring-1 ring-white/10 dark:bg-[#1c1222]">
      <span aria-hidden="true" className="select-none font-mono text-small text-candy-pink">
        $
      </span>
      <code
        id={`cmd-${slug(command)}`}
        className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap pr-3 font-mono text-small [mask-image:linear-gradient(90deg,#000_calc(100%-12px),transparent)] [scrollbar-width:none]"
      >
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        data-copied={copied}
        className="group relative isolate grid h-10 shrink-0 cursor-pointer place-items-center overflow-hidden rounded-lg bg-white/10 px-3 font-pixel text-pixel text-white transition-colors hover:bg-white/18 data-[copied=true]:text-ink"
      >
        <span aria-hidden="true" className="absolute inset-0 -z-10 bg-candy opacity-0 transition-opacity group-data-[copied=true]:opacity-100" />
        <span className="col-start-1 row-start-1 pixel-even transition-[opacity,translate] group-data-[copied=true]:-translate-y-2 group-data-[copied=true]:opacity-0">
          Copy
        </span>
        <span
          aria-hidden="true"
          className="col-start-1 row-start-1 pixel-even translate-y-2 opacity-0 transition-[opacity,translate] group-data-[copied=true]:translate-y-0 group-data-[copied=true]:opacity-100"
        >
          Copied
        </span>
      </button>
      <span role="status" className="sr-only">
        {copied ? "Copied to the clipboard" : ""}
      </span>
    </div>
  );
}

function slug(text: string) {
  return text.replace(/[^a-z0-9]+/gi, "-").toLowerCase();
}
