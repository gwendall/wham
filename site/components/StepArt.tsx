import { PixelSprite } from "@/components/PixelSprite";
import { MOON, SUN } from "@/lib/sprites";

// Small pixel scenes for the three steps of "How it works".

export function SwitchArt() {
  return (
    <div aria-hidden="true" className="flex items-center gap-[8px] rounded-[10px] bg-white/45 px-3 py-2 text-ink dark:bg-white/10 dark:text-white">
      <PixelSprite rows={SUN} cell={2} />
      <span className="relative block h-[24px] w-[42px] rounded-full bg-candy">
        <span className="absolute right-[4px] top-[4px] h-[16px] w-[16px] rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.3)]" />
      </span>
    </div>
  );
}

// A laptop seen from the side, its lid closing on a loop. The hinge glows once it is shut.
export function LidArt() {
  return (
    <div aria-hidden="true" className="relative h-[80px] w-[84px]">
      <span className="step-glow absolute bottom-[2px] left-[-8px] h-[20px] w-[20px] rounded-full bg-candy-pink blur-[7px]" />
      <span className="absolute bottom-[4px] left-[6px] h-[8px] w-[74px] bg-current" />
      <span className="absolute bottom-0 left-[12px] h-[4px] w-[10px] bg-current opacity-40" />
      <span className="absolute bottom-0 right-[10px] h-[4px] w-[10px] bg-current opacity-40" />
      <span className="step-lid absolute bottom-[12px] left-[6px] h-[6px] w-[70px] bg-current" />
    </div>
  );
}

export function RunArt() {
  return (
    <div aria-hidden="true" className="flex w-[150px] flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="font-pixel text-[16px] leading-none">Running</span>
        <span className="text-moon opacity-60">
          <PixelSprite rows={MOON} cell={1} />
        </span>
      </div>
      <div className="h-[14px] w-full overflow-hidden rounded-[3px] bg-current/12 p-[2px]">
        <div className="step-bar pixel-bar-fill h-full w-[70%]" style={{ ["--bar-width" as string]: "146px" }} />
      </div>
    </div>
  );
}
