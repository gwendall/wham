import AppKit
import Metal
import QuartzCore

// Draws the menu bar switch in each of its looks, on a light and a dark menu
// bar: off, on, and on with half of a timed session left. With --film, each
// look turning on instead, a frame every 40 ms. Built and run by
// scripts/sheet.sh. Off screen, with CARenderer, which keeps the masks that
// CALayer.render(in:) drops.
let film = CommandLine.arguments.contains("--film")
let out = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "build/sheet.png"
let scale: CGFloat = 4
let cell = NSSize(width: 64, height: 30)
let looks: [(String, SwitchView.Look)] = [
    ("Color", .init()),
    ("Monochrome", .init(monochrome: true)),
    ("Compact", .init(compact: true)),
    ("Compact, monochrome", .init(monochrome: true, compact: true)),
]
let bars: [(NSAppearance.Name, CGColor)] = [(.aqua, CGColor(gray: 0.93, alpha: 1)), (.darkAqua, CGColor(gray: 0.16, alpha: 1))]
let states: [(String, Bool?, CGFloat)] = [("Off", false, 1), ("On", true, 1), ("Half left", true, 0.5)]
let frames = 12
let columns = film ? frames : states.count
let label: CGFloat = 150

@main
enum Sheet {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let rows = looks.count * bars.count
        let size = CGSize(width: label + CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        root.backgroundColor = CGColor(gray: 1, alpha: 1)
        var views: [SwitchView] = []

        for (lookIndex, (name, look)) in looks.enumerated() {
            for (barIndex, (appearance, background)) in bars.enumerated() {
                let row = lookIndex * bars.count + barIndex
                let y = size.height - CGFloat(row + 1) * cell.height
                let caption = CATextLayer()
                caption.string = barIndex == 0 ? name : ""
                caption.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                caption.fontSize = 11 * scale
                caption.foregroundColor = CGColor(gray: 0.2, alpha: 1)
                caption.contentsScale = 1
                caption.frame = CGRect(x: 8 * scale, y: (y + 4) * scale, width: (label - 8) * scale, height: 18 * scale)
                root.addSublayer(caption)
                for column in 0..<columns {
                    let state = film ? (true as Bool?, CGFloat(1)) : (states[column].1, states[column].2)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: cell), styleMask: .borderless, backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: appearance)
                    let view = SwitchView()
                    view.setLook(look)
                    view.frame = NSRect(origin: .zero, size: cell)
                    window.contentView = view
                    view.layoutSubtreeIfNeeded()
                    if film {
                        view.show(false, animated: false)
                    } else {
                        if state.0 == true { view.drain(state.1, animated: false) }
                        view.show(state.0, animated: false)
                    }
                    views.append(view)
                    let holder = CALayer()
                    holder.frame = CGRect(x: (label + CGFloat(column) * cell.width) * scale, y: y * scale,
                                          width: cell.width * scale, height: cell.height * scale)
                    holder.backgroundColor = background
                    // The item's own width, as the menu bar gives it.
                    let item = CALayer()
                    item.frame = CGRect(x: (cell.width - view.itemLength) / 2 * scale, y: 0, width: view.itemLength * scale, height: 1.5 * scale)
                    item.backgroundColor = CGColor(srgbRed: 1, green: 0.2, blue: 0.6, alpha: 0.5)
                    holder.addSublayer(item)
                    let layer = CALayer()
                    layer.bounds = CGRect(origin: .zero, size: cell)
                    for sublayer in view.layer?.sublayers ?? [] { layer.addSublayer(sublayer) }
                    layer.anchorPoint = .zero
                    layer.position = .zero
                    layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
                    holder.addSublayer(layer)
                    root.addSublayer(holder)
                }
            }
        }
        CATransaction.flush()

        let width = Int(root.frame.width), height = Int(root.frame.height)
        let device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        let texture = device.makeTexture(descriptor: descriptor)!
        let queue = device.makeCommandQueue()!
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        CATransaction.flush()
        renderer.bounds = root.frame

        func render(at time: CFTimeInterval) -> [UInt8] {
            renderer.beginFrame(atTime: time, timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            let buffer = queue.makeCommandBuffer()!
            let blit = buffer.makeBlitCommandEncoder()!
            blit.synchronize(resource: texture)
            blit.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return bytes
        }

        var bytes: [UInt8]
        if film {
            // Every view turns on at once; column n is the sheet at n × 40 ms.
            for view in views { view.show(true, animated: true) }
            CATransaction.flush()
            let start = CACurrentMediaTime()
            bytes = [UInt8](repeating: 255, count: width * height * 4)
            let cellWidth = Int(cell.width * scale), left = Int(label * scale)
            for frame in 0..<frames {
                let shot = render(at: start + Double(frame) * 0.04)
                for y in 0..<height {
                    let from = (y * width + left + frame * cellWidth) * 4
                    bytes.replaceSubrange(from..<from + cellWidth * 4, with: shot[from..<from + cellWidth * 4])
                }
                if frame == 0 {
                    for y in 0..<height {
                        let from = y * width * 4
                        bytes.replaceSubrange(from..<from + left * 4, with: shot[from..<from + left * 4])
                    }
                }
            }
        } else {
            bytes = render(at: CACurrentMediaTime() + 5)
        }
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        // The texture's rows run from the top; the layers' y from the bottom.
        let flipped = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        flipped.translateBy(x: 0, y: CGFloat(height))
        flipped.scaleBy(x: 1, y: -1)
        flipped.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rep = NSBitmapImageRep(cgImage: flipped.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        withExtendedLifetime(views) {}
}
}
