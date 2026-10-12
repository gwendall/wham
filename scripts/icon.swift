// Draws Wham's app icon: a candy squircle with the pixel sun, wide awake.
//
//   swift scripts/icon.swift <out-dir>
//
// Writes <out-dir>/AppIcon.icns and <out-dir>/icon-1024.png. Small sizes use
// the 11 x 11 menu bar sun; from 64 px up the sun gets its face.
import AppKit

let face = [
    "........#........",
    "........#........",
    "..#...........#..",
    "...#.........#...",
    "......#####......",
    ".....#######.....",
    "....#########....",
    "....##.###.##....",
    "##..##.###.##..##",
    "....#########....",
    "....###.#.###....",
    ".....###.###.....",
    "......#####......",
    "...#.........#...",
    "..#...........#..",
    "........#........",
    "........#........",
]

let small = [
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

let ink = CGColor(srgbRed: 0x1a / 255, green: 0x0b / 255, blue: 0x17 / 255, alpha: 1)
let candy = [
    CGColor(srgbRed: 1, green: 0x7a / 255, blue: 0xd9 / 255, alpha: 1),
    CGColor(srgbRed: 1, green: 0xd3 / 255, blue: 0x6e / 255, alpha: 1),
    CGColor(srgbRed: 0x6f / 255, green: 0xd3 / 255, blue: 1, alpha: 1),
]

func render(_ size: Int) -> CGImage {
    let s = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // The macOS icon grid: an 824-point squircle on a 1024 canvas, with a soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(candy[0])
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: candy as CFArray, locations: [0, 0.5, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // A light from above.
    let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(light, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    context.restoreGState()

    // The sun, on whole pixels.
    let sprite = size >= 64 ? face : small
    let cells = sprite.count
    let cell = max(1, ((body.width * 0.66) / CGFloat(cells)).rounded(.down))
    let side = cell * CGFloat(cells)
    let origin = CGPoint(x: ((s - side) / 2).rounded(), y: ((s - side) / 2).rounded())
    context.setFillColor(ink)
    for (y, row) in sprite.enumerated() {
        for (x, char) in row.enumerated() where char == "#" {
            context.fill(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(cells - 1 - y) * cell, width: cell, height: cell))
        }
    }
    return context.makeImage()!
}

func png(_ image: CGImage, _ url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(render(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(render(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(render(1024), out.appendingPathComponent("icon-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
