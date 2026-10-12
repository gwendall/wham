import { MenuSwitch } from "@/components/MenuSwitch";
import { PixelSprite } from "@/components/PixelSprite";
import { FACE } from "@/lib/sprites";

// Small pixel scenes for the three steps of "How it works".

// The app's icon: the sun, wide awake, on candy. 63 px of face, 12 px in.
export function OpenArt() {
  return (
    <div aria-hidden="true" className="rounded-[20px] bg-candy p-3 shadow-[0_8px_24px_-8px_rgba(255,3,180,0.5)]">
      <PixelSprite rows={FACE} cell={3} className="block text-ink" />
    </div>
  );
}

// Wham's menu bar item, switched on, at twice its size on a strip of menu bar.
export function SwitchArt() {
  return (
    <div aria-hidden="true" className="flex h-14 items-center rounded-2xl bg-fg/6 px-4 text-fg">
      <MenuSwitch on scale={2} />
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
