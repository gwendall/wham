import { ImageResponse } from "next/og";
import { FACE, spriteLayers } from "@/lib/sprites";

// The app icon for home screens: candy, and the sun wide awake.
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  const cell = 6;
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          backgroundImage: "linear-gradient(135deg, #ff7ad9, #ffd36e, #6fd3ff)",
        }}
      >
        <svg width={21 * cell} height={21 * cell} viewBox="0 0 21 21">
          {spriteLayers(FACE).map(({ color, fill, d }) => (
            <path key={color} d={d} fill={fill} shapeRendering="crispEdges" />
          ))}
        </svg>
      </div>
    ),
    size,
  );
}
