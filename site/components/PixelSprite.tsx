import { spritePath, type Sprite } from "@/lib/sprites";

// A sprite drawn on whole pixels: `cell` CSS pixels per sprite pixel.
export function PixelSprite({
  rows,
  cell = 2,
  className,
  title,
}: {
  rows: Sprite;
  cell?: number;
  className?: string;
  title?: string;
}) {
  const width = rows[0].length;
  const height = rows.length;
  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      width={width * cell}
      height={height * cell}
      shapeRendering="crispEdges"
      className={className}
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
    >
      <path d={spritePath(rows)} fill="currentColor" />
    </svg>
  );
}
