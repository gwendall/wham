import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { FACE, SUN, SUN_LIT, spriteLayers, type Sprite } from "@/lib/sprites";

// The share card, 1200 x 630: candy, the pixel WHAM, the headline, the sun.
// Silkscreen comes from the app's own copy (generated/ by scripts/sync.mjs).
export const ogSize = { width: 1200, height: 630 };
export const ogAlt = "Wham: close the lid, your Mac stays awake.";

const INK = "#1a0b17";
// Silkscreen puts a font pixel (1/8 em) of space on both sides of a capital, two
// between letters. As on the page, every size takes one off, so its letters sit
// one font pixel apart: 3 px at 24, 4 at 32, 5 at 40, 20 at 160.
const track = (size: number) => -size / 8;
const silkscreen = await readFile(join(process.cwd(), "generated", "Silkscreen-Regular.ttf"));

function Pixels({ rows, cell, color }: { rows: Sprite; cell: number; color: string }) {
  return (
    <svg width={rows[0].length * cell} height={rows.length * cell} viewBox={`0 0 ${rows[0].length} ${rows.length}`}>
      {spriteLayers(rows, color).map(({ color: key, fill, d }) => (
        <path key={key} d={d} fill={fill} shapeRendering="crispEdges" />
      ))}
    </svg>
  );
}

export function ogImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          position: "relative",
          backgroundImage: "linear-gradient(90deg, #ff7ad9, #ffd36e, #6fd3ff)",
          fontFamily: "Silkscreen",
          color: INK,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            backgroundImage: "linear-gradient(180deg, rgba(255,255,255,0.32), rgba(255,255,255,0))",
          }}
        />
        <div style={{ display: "flex", flexDirection: "column", justifyContent: "space-between", padding: "64px 72px", width: "100%" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 24, letterSpacing: track(24), opacity: 0.75 }}>
            <Pixels rows={SUN_LIT} cell={2} color={INK} />
            MENU BAR APP FOR MACOS
          </div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div style={{ display: "flex", flexDirection: "column" }}>
              <div style={{ display: "flex", fontSize: 160, lineHeight: 1, letterSpacing: track(160) }}>WHAM</div>
              <div style={{ display: "flex", flexDirection: "column", fontSize: 40, lineHeight: 1.4, letterSpacing: track(40), marginTop: 28 }}>
                <span>CLOSE THE LID.</span>
                <span>YOUR MAC STAYS AWAKE.</span>
              </div>
            </div>
            <Pixels rows={FACE} cell={12} color={INK} />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 14,
                padding: "0 30px 0 24px",
                height: 64,
                borderRadius: 32,
                background: "#141414",
                color: "#ffffff",
                fontSize: 32,
                letterSpacing: track(32),
              }}
            >
              <Pixels rows={SUN} cell={3} color="#ff7ad9" />
              WHAM.SH
            </div>
            <span style={{ fontSize: 24, letterSpacing: track(24), opacity: 0.75 }}>FREE AND OPEN SOURCE</span>
          </div>
        </div>
      </div>
    ),
    {
      ...ogSize,
      fonts: [{ name: "Silkscreen", data: silkscreen, style: "normal", weight: 400 }],
    },
  );
}
