import CoreGraphics

// Wham's pixel art and colors, shared by the menu bar item, the toast and the
// app icon. Sprites are drawn one cell per pixel and scaled up without smoothing.
enum Pixels {
    static let sun = [
        ".....#.....",
        ".#...#...#.",
        "..#.....#..",
        "....###....",
        "...#####...",
        "##.#####.##",
        "...#####...",
        "....###....",
        "..#.....#..",
        ".#...#...#.",
        ".....#.....",
    ]

    // Like the sun, the moon's ink fills its whole box, so centering the box
    // centers the moon.
    static let moon = [
        "....##.....",
        "..###......",
        ".###.......",
        ".###.......",
        "####.......",
        "####.......",
        "####......#",
        ".#####...##",
        ".#########.",
        "..#######..",
        "....###....",
    ]

    static let ink = CGColor(srgbRed: 0x1a / 255, green: 0x0b / 255, blue: 0x17 / 255, alpha: 1)
    static let candy = [
        CGColor(srgbRed: 1, green: 0x7a / 255, blue: 0xd9 / 255, alpha: 1),
        CGColor(srgbRed: 1, green: 0xd3 / 255, blue: 0x6e / 255, alpha: 1),
        CGColor(srgbRed: 0x6f / 255, green: 0xd3 / 255, blue: 1, alpha: 1),
    ]
    static let glow = CGColor(srgbRed: 1, green: 3 / 255, blue: 180 / 255, alpha: 1)
    static let moonInk = CGColor(srgbRed: 0.75, green: 0.71, blue: 1, alpha: 1)

    // The sprite's cells as squares of `cell` points, from `origin` (bottom left).
    static func path(_ rows: [String], origin: CGPoint, cell: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() where char == "#" {
                path.addRect(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(rows.count - 1 - y) * cell, width: cell, height: cell))
            }
        }
        return path
    }

    // The sprite at one pixel per cell, in one color.
    static func image(_ rows: [String], color: CGColor) -> CGImage? {
        let height = rows.count, width = rows.map(\.count).max() ?? 0
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(color)
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "#" {
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }
}
