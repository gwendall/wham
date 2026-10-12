// Draws the background of Wham's disk image: a pixel arrow from the app to
// the Applications folder, and two lines saying what to do.
//
//   swift scripts/dmg-background.swift <font.ttf> <out-dir>
//
// Writes <out-dir>/background.png (660 x 400) and background@2x.png. The icons
// sit at (170, 200) and (490, 200), see scripts/dmg.py.
import AppKit
import CoreText

let width = 660, height = 400
// Finder writes the icon names in black in light mode and in white in dark
// mode, over the picture: berry to blue keeps both readable (about 4.5:1).
let berry = CGColor(srgbRed: 0xc2 / 255, green: 0x40 / 255, blue: 0x9f / 255, alpha: 1)
let blue = CGColor(srgbRed: 0x4a / 255, green: 0x7f / 255, blue: 0xd6 / 255, alpha: 1)
let candy = [
    CGColor(srgbRed: 1, green: 0x7a / 255, blue: 0xd9 / 255, alpha: 1),
    CGColor(srgbRed: 1, green: 0xd3 / 255, blue: 0x6e / 255, alpha: 1),
    CGColor(srgbRed: 0x6f / 255, green: 0xd3 / 255, blue: 1, alpha: 1),
]

let arrow = [
    ".........#....",
    ".........##...",
    ".........###..",
    "#############.",
    "##############",
    "#############.",
    ".........###..",
    ".........##...",
    ".........#....",
]
let sparkle = [
    "..#..",
    "..#..",
    "##.##",
    "..#..",
    "..#..",
]

let args = CommandLine.arguments
guard args.count > 2 else { print("usage: dmg-background.swift <font.ttf> <out-dir>"); exit(64) }
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: args[1]) as CFURL) as! [CTFontDescriptor]
let out = URL(fileURLWithPath: args[2])

// The color at t (0 to 1) along a run of colors.
func blend(_ colors: [CGColor], _ t: CGFloat) -> CGColor {
    guard colors.count > 1 else { return colors[0] }
    let position = t * CGFloat(colors.count - 1)
    let i = min(colors.count - 2, Int(position)), f = position - CGFloat(i)
    let a = colors[i].components!, b = colors[i + 1].components!
    return CGColor(srgbRed: a[0] + (b[0] - a[0]) * f, green: a[1] + (b[1] - a[1]) * f, blue: a[2] + (b[2] - a[2]) * f, alpha: 1)
}

func draw(scale: Int) -> CGImage {
    let s = CGFloat(scale)
    let context = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: s, y: s)
    // Points from the top left, like Finder's.
    func y(_ top: CGFloat) -> CGFloat { CGFloat(height) - top }

    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [berry, blue] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: y(0)), end: CGPoint(x: CGFloat(width), y: y(CGFloat(height))), options: [])

    // Sprites on whole pixels, in candy colors from left to right.
    func sprite(_ rows: [String], cell: CGFloat, center: CGPoint, colors: [CGColor]) {
        let w = CGFloat(rows[0].count) * cell, h = CGFloat(rows.count) * cell
        let origin = CGPoint(x: (center.x - w / 2).rounded(), y: (center.y - h / 2).rounded())
        for (row, line) in rows.enumerated() {
            for (column, char) in line.enumerated() where char == "#" {
                context.setFillColor(blend(colors, CGFloat(column) / CGFloat(max(1, line.count - 1))))
                context.fill(CGRect(x: origin.x + CGFloat(column) * cell, y: y(origin.y + CGFloat(row + 1) * cell), width: cell, height: cell))
            }
        }
    }
    sprite(arrow, cell: 5, center: CGPoint(x: 330, y: 196), colors: candy)
    for (point, color) in [(CGPoint(x: 64, y: 72), candy[0]), (CGPoint(x: 600, y: 96), candy[2]),
                           (CGPoint(x: 92, y: 330), candy[1]), (CGPoint(x: 586, y: 318), candy[0])] {
        sprite(sparkle, cell: 3, center: point, colors: [color])
    }

    // Text, centered. The pixel font is drawn without smoothing so its pixels stay square.
    func text(_ string: String, font: CTFont, color: CGColor, top: CGFloat, crisp: Bool) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.saveGState()
        context.setShouldAntialias(!crisp)
        context.textPosition = CGPoint(x: ((CGFloat(width) - bounds.width) / 2).rounded(), y: y(top).rounded())
        CTLineDraw(line, context)
        context.restoreGState()
    }
    let pixel = CTFontCreateWithFontDescriptor(descriptors[0], 16, nil)
    let rounded = NSFont.systemFont(ofSize: 13, weight: .semibold).fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: 13) } ?? .systemFont(ofSize: 13, weight: .semibold)
    text("DRAG WHAM INTO APPLICATIONS", font: pixel, color: .white, top: 64, crisp: true)
    text("Then click its switch in your menu bar.", font: rounded as CTFont, color: CGColor(gray: 1, alpha: 0.85), top: 334, crisp: false)
    return context.makeImage()!
}

for scale in [1, 2] {
    let rep = NSBitmapImageRep(cgImage: draw(scale: scale))
    rep.size = NSSize(width: width, height: height)
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
