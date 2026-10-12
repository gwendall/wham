"use client";

import dynamic from "next/dynamic";
import { useCallback, useState } from "react";
import { Toast, type ToastShow } from "@/components/Toast";
import type { Hud } from "@/lib/scenarios";

// three.js loads after the page, and only in the browser.
const MacScene = dynamic(() => import("@/components/MacScene"), { ssr: false });

export function HeroStage({ label, huds }: { label: string; huds: Record<string, Hud> }) {
  const [toast, setToast] = useState<ToastShow | null>(null);
  const onToast = useCallback(() => setToast((t) => ({ kind: "on", id: (t?.id ?? 0) + 1 })), []);
  return (
    <div
      role="img"
      aria-label={label}
      className="relative mx-auto aspect-[6/5] w-full max-w-[560px]"
    >
      <MacScene onToast={onToast} huds={huds} />
      <div className="pointer-events-none absolute left-1/2 top-[3%] -translate-x-1/2">
        <Toast show={toast} announce={false} />
      </div>
    </div>
  );
}
