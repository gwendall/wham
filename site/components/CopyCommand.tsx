"use client";

import { useEffect, useRef, useState } from "react";

// A shell command with a copy button. `primary` is the big candy one.
export function CopyCommand({ command, primary = false }: { command: string; primary?: boolean }) {
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
    <div
      className={`group flex min-w-0 items-center gap-2 rounded-[16px] bg-ink pl-4 pr-2 text-white dark:bg-[#1c1222] ${
        primary
          ? "candy-ring h-[60px] shadow-[0_10px_40px_-12px_rgba(255,3,180,0.55)] sm:h-[64px] sm:pl-5"
          : "h-[52px] ring-1 ring-white/10"
      }`}
    >
      <span aria-hidden="true" className="select-none font-mono text-candy-pink">
        $
      </span>
      <code
        id={`cmd-${slug(command)}`}
        className={`min-w-0 flex-1 overflow-x-auto whitespace-nowrap pr-3 font-mono [mask-image:linear-gradient(90deg,#000_calc(100%-12px),transparent)] [scrollbar-width:none] ${
          primary ? "text-[14px] min-[400px]:text-[15px] sm:text-[18px]" : "text-[14px] sm:text-[15px]"
        }`}
      >
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        className={`flex h-[40px] shrink-0 cursor-pointer items-center justify-center rounded-[11px] px-2.5 font-pixel sm:px-3 text-[16px] leading-none transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-candy-yellow ${
          copied ? "bg-candy text-ink" : "bg-white/10 text-white hover:bg-white/20"
        } ${primary ? "min-w-[68px] sm:min-w-[84px]" : "min-w-[68px] sm:min-w-[76px]"}`}
      >
        {copied ? "Copied" : "Copy"}
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
