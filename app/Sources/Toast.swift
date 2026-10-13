import AppKit
import CoreText
import QuartzCore

// A pill that drops out of the menu bar under the switch and says, in plain
// words, what the Mac will do now. On: a candy gradient with a pixel sun. Off: a
// dark pill with a pixel moon. The title is in pixel letters (`TitleFont`) and
// comes in letter by letter; the line under it explains.
// Core Animation only, so it runs at the display's refresh rate.
@MainActor
final class Toast {
    struct Style {
        let title: String
        let caption: String
        let sprite: [String]
        let spin: CGFloat
        let ink: CGColor
        let captionInk: CGColor
        let spriteInk: CGColor
        let fill: [CGColor]
        let rim: CGColor?
        let glow: CGColor?

        // The same pill with another line under the title.
        func saying(_ caption: String) -> Style {
            Style(title: title, caption: caption, sprite: sprite, spin: spin, ink: ink, captionInk: captionInk,
                  spriteInk: spriteInk, fill: fill, rim: rim, glow: glow)
        }
    }

    static var on: Style { Style(
        title: Words.say("MAC STAYS AWAKE"), caption: Words.say("Even with the lid closed"), sprite: Pixels.sun, spin: -.pi / 4,
        ink: Pixels.ink, captionInk: Pixels.ink.copy(alpha: 0.72)!, spriteInk: Pixels.ink,
        fill: Pixels.candy, rim: nil, glow: Pixels.glow) }

    static var off: Style { Style(
        title: Words.say("MAC CAN SLEEP"), caption: Words.say("Back to normal sleep"), sprite: Pixels.moon, spin: .pi / 6,
        ink: .white, captionInk: CGColor(gray: 1, alpha: 0.6), spriteInk: Pixels.moonInk,
        fill: [CGColor(gray: 0.08, alpha: 1)], rim: CGColor(gray: 1, alpha: 0.16), glow: nil) }

    // Five minutes before a timed session ends, still on: the candy pill, with
    // the time it lets go.
    static var soon: Style { Style(
        title: Words.say("5 MINUTES LEFT"), caption: Words.say("Then back to normal sleep"), sprite: Pixels.sun, spin: -.pi / 4,
        ink: Pixels.ink, captionInk: Pixels.ink.copy(alpha: 0.72)!, spriteInk: Pixels.ink,
        fill: Pixels.candy, rim: nil, glow: Pixels.glow) }

    // The first launch, and opening Wham again: where it is and what it does.
    static var hello: Style { note(Words.say("HI, I'M WHAM"), Words.say("Click me to keep your Mac awake")) }

    // Anything else Wham has to say, about its updates: the hello pill's look.
    static func note(_ title: String, _ caption: String) -> Style {
        Style(title: title, caption: caption, sprite: Pixels.sun, spin: -.pi / 4, ink: .white, captionInk: CGColor(gray: 1, alpha: 0.6),
              spriteInk: Pixels.candy[1], fill: [CGColor(gray: 0.08, alpha: 1)], rim: CGColor(gray: 1, alpha: 0.16), glow: nil)
    }

    private static let captionFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11.5) } ?? base
    }()

    static let height: CGFloat = 52
    static let margin: CGFloat = 26 // room for the glow and the springs' overshoot
    static let hold: TimeInterval = 2.2

    let host = NSView()
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var generation = 0

    // What the evals take a picture of.
    var window: NSWindow { panel }

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        host.wantsLayer = true
        panel.contentView = host
    }

    // `anchor` is the switch, in screen coordinates.
    func show(_ style: Style, under anchor: NSRect) {
        generation += 1
        let current = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.backingScaleFactor ?? panel.backingScaleFactor

        let title = TitleFont.letters(style.title)
        let titleLine = TitleFont.line(title)
        let titleWidth = CGFloat(CTLineGetTypographicBounds(titleLine, nil, nil, nil)).rounded(.up)
        let caption = Self.textImage(style.caption, font: Self.captionFont, color: style.captionInk, scale: scale, crisp: false)
        let icon = CGFloat(style.sprite.count) * TitleFont.pixel
        // The sprite sits in the pill's round end, as far from its left edge as from the top and bottom.
        let padLeft = (Self.height - icon) / 2, gap: CGFloat = 11, padRight: CGFloat = 20
        let height = Self.height
        let width = padLeft + icon + gap + max(titleWidth, caption?.size.width ?? 0) + padRight

        // Place the pill just under the switch, inside the screen.
        let size = NSSize(width: width + 2 * Self.margin, height: height + 2 * Self.margin)
        var origin = NSPoint(x: (anchor.midX - size.width / 2).rounded(), y: anchor.minY - 6 - height - Self.margin)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            origin.x = min(max(origin.x, screen.frame.minX - Self.margin + 8), screen.frame.maxX - size.width + Self.margin - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        host.frame = NSRect(origin: .zero, size: size)

        let root = host.layer!
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        // stage: everything, scaled from the pill's top edge so it drops from the menu bar.
        let stage = CALayer()
        stage.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        stage.anchorPoint = CGPoint(x: 0.5, y: 1)
        stage.position = CGPoint(x: size.width / 2, y: Self.margin + height)
        root.addSublayer(stage)

        let radius = height / 2
        if let glow = style.glow {
            let halo = CALayer()
            halo.frame = stage.bounds
            halo.shadowPath = CGPath(roundedRect: stage.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            halo.shadowColor = glow
            halo.shadowOpacity = 0.45
            halo.shadowRadius = 13
            halo.shadowOffset = .zero
            stage.addSublayer(halo)
        }
        let pill = CAGradientLayer()
        pill.frame = stage.bounds
        pill.cornerRadius = radius
        pill.masksToBounds = true
        if style.fill.count > 1 {
            pill.colors = style.fill
            pill.startPoint = CGPoint(x: 0, y: 0.5)
            pill.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            pill.backgroundColor = style.fill.first
        }
        if let rim = style.rim {
            pill.borderColor = rim
            pill.borderWidth = 0.5
        }
        stage.addSublayer(pill)

        let sprite = CALayer()
        sprite.bounds = CGRect(x: 0, y: 0, width: icon, height: icon)
        sprite.position = CGPoint(x: padLeft + icon / 2, y: height / 2)
        sprite.contents = Pixels.image(style.sprite, color: style.spriteInk)
        sprite.magnificationFilter = .nearest
        pill.addSublayer(sprite)

        // Title and caption, centered together. Every edge sits on a whole point,
        // so the pixel letters stay sharp.
        let textX = padLeft + icon + gap
        let titleCap = 5 * TitleFont.pixel // Silkscreen's capitals are 5 pixels tall
        let lineGap: CGFloat = 6
        let captionCap = Self.captionFont.capHeight.rounded()
        let block = titleCap + lineGap + captionCap
        let titleBaseline = ((height + block) / 2 - titleCap).rounded()
        let captionBaseline = titleBaseline - lineGap - captionCap

        var letters: [CALayer] = []
        for character in title where !character.text.allSatisfy(\.isWhitespace) {
            // Silkscreen at the screen's scale; another face on a grid of whole
            // points, enlarged without smoothing, so it is pixel letters too.
            let pointScale = character.silkscreen ? scale : 1
            guard let glyph = Self.textImage(character.text, font: character.font as NSFont, color: style.ink, scale: pointScale, crisp: true) else { continue }
            let offset = CTLineGetOffsetForStringIndex(titleLine, character.offset, nil)
            let letter = CALayer()
            letter.contents = glyph.image
            letter.contentsScale = pointScale
            letter.magnificationFilter = .nearest
            letter.frame = CGRect(x: textX + offset.rounded(), y: titleBaseline - glyph.descent, width: glyph.size.width, height: glyph.size.height)
            pill.addSublayer(letter)
            letters.append(letter)
        }
        let captionLayer = CALayer()
        if let caption {
            captionLayer.contents = caption.image
            captionLayer.contentsScale = scale
            captionLayer.frame = CGRect(x: textX, y: captionBaseline - caption.descent, width: caption.size.width, height: caption.size.height)
            pill.addSublayer(captionLayer)
        }

        panel.orderFrontRegardless()

        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reduceMotion {
            Self.basic(stage, "opacity", from: 0, to: 1, at: now, duration: 0.2)
        } else {
            // Coming in: a spring, ω 16, ζ 0.72.
            Self.spring(stage, "transform.scale", from: 0.92, to: 1, at: now, omega: 16, zeta: 0.72)
            Self.spring(stage, "transform.translation.y", from: 12, to: 0, at: now, omega: 16, zeta: 0.72)
            Self.basic(stage, "opacity", from: 0, to: 1, at: now, duration: 0.12)
            Self.spring(sprite, "transform.scale", from: 0.2, to: 1, at: now + 0.06, omega: 18, zeta: 0.42)
            Self.spring(sprite, "transform.rotation.z", from: style.spin, to: 0, at: now + 0.06, omega: 16, zeta: 0.5)
            // Each letter drops into place, one after the other.
            for (i, letter) in letters.enumerated() {
                let start = now + 0.07 + 0.022 * Double(i)
                Self.basic(letter, "opacity", from: 0, to: 1, at: start, duration: 0.1)
                Self.basic(letter, "transform.translation.y", from: 6, to: 0, at: start, duration: 0.14)
            }
            let after = now + 0.07 + 0.022 * Double(letters.count)
            Self.basic(captionLayer, "opacity", from: 0, to: 1, at: after, duration: 0.24)
            Self.basic(captionLayer, "transform.translation.y", from: 3, to: 0, at: after, duration: 0.24)
        }
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { [weak self] in
            guard let self, self.generation == current else { return }
            self.leave(stage, reduceMotion: reduceMotion)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    // Leaving: 0.16 s, easing in, back up toward the menu bar.
    private func leave(_ stage: CALayer, reduceMotion: Bool) {
        let now = CACurrentMediaTime()
        let timing = CAMediaTimingFunction(name: .easeIn)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !reduceMotion {
            Self.basic(stage, "transform.scale", from: 1, to: 0.92, at: now, duration: 0.16, timing: timing)
            Self.basic(stage, "transform.translation.y", from: 0, to: 8, at: now, duration: 0.16, timing: timing)
            // The model ends gone too, so nothing snaps back when the animations end.
            stage.transform = CATransform3DTranslate(CATransform3DMakeScale(0.92, 0.92, 1), 0, 8, 0)
        }
        Self.basic(stage, "opacity", from: 1, to: 0, at: now, duration: 0.16, timing: timing)
        stage.opacity = 0
        CATransaction.commit()
    }

    // A run of text drawn once at the screen's scale, with its baseline on a whole point.
    private static func textImage(_ text: String, font: NSFont, color: CGColor, scale: CGFloat, crisp: Bool)
        -> (image: CGImage, size: CGSize, descent: CGFloat)? {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)).rounded(.up) + 1
        let below = descent.rounded(.up), above = ascent.rounded(.up)
        let size = CGSize(width: width, height: above + below)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        if crisp {
            context.setShouldAntialias(false)
            context.setShouldSmoothFonts(false)
        }
        context.textPosition = CGPoint(x: 0, y: below)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        return (image, size, below)
    }

    private static func spring(_ layer: CALayer, _ keyPath: String, from: CGFloat, to: CGFloat, at time: CFTimeInterval, omega: CGFloat, zeta: CGFloat) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * zeta * omega
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        animation.beginTime = time
        animation.fillMode = .backwards
        layer.add(animation, forKey: keyPath)
    }

    // Animations hold their start value until they begin, then leave the model value showing.
    private static func basic(_ layer: CALayer, _ keyPath: String, from: CGFloat, to: CGFloat, at time: CFTimeInterval, duration: CFTimeInterval,
                              timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = time
        animation.fillMode = .backwards
        animation.timingFunction = timing
        layer.add(animation, forKey: keyPath)
    }
}

// The toast's title face. Silkscreen, a pixel font, draws Latin letters with
// their accents; what it lacks (Japanese, Korean and Chinese, the odd Ÿ) comes
// from a system face for the app's language, drawn on a grid of whole points
// so it reads as pixel letters too. At 14 pt those faces stand about as tall as
// Silkscreen's capitals and keep their strokes apart on such a grid, where
// lighter cuts, and PingFang, run together.
enum TitleFont {
    static var url = Bundle.main.url(forResource: "Silkscreen-Regular", withExtension: "ttf")
    // Silkscreen draws on a grid of 8 pixels per em: at 16 pt one of its pixels is 2 pt.
    static let pixel: CGFloat = 2
    static let silkscreen: CTFont = {
        if let url, let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            return CTFontCreateWithFontDescriptor(first, 8 * pixel, nil)
        }
        return NSFont.monospacedSystemFont(ofSize: 14, weight: .bold) as CTFont
    }()
    static let size: CGFloat = 14
    static let faces = ["ja": "HiraginoSans-W6", "ko": "AppleSDGothicNeo-Bold", "zh-Hans": "STHeitiSC-Medium"]

    struct Letter {
        let text: String
        let font: CTFont
        let silkscreen: Bool
        let offset: Int // in UTF-16 units, as Core Text counts
    }

    static func letters(_ title: String, language: String = Words.language) -> [Letter] {
        var letters: [Letter] = [], offset = 0
        for character in title {
            let text = String(character)
            let silkscreen = character.isWhitespace || has(Self.silkscreen, text)
            letters.append(Letter(text: text, font: silkscreen ? Self.silkscreen : fallback(text, language: language),
                                  silkscreen: silkscreen, offset: offset))
            offset += text.utf16.count
        }
        return letters
    }

    // Silkscreen leaves two of its pixels between capitals: one is enough, as on wham.sh.
    static func line(_ letters: [Letter]) -> CTLine {
        let line = NSMutableAttributedString()
        for letter in letters {
            line.append(NSAttributedString(string: letter.text, attributes: [.font: letter.font, .kern: letter.silkscreen ? -pixel : 0]))
        }
        return CTLineCreateWithAttributedString(line)
    }

    // The language's face when it has the character, else the one macOS picks.
    static func fallback(_ text: String, language: String) -> CTFont {
        let named = faces[language].map { CTFontCreateWithName($0 as CFString, size, nil) }
        if let named, CTFontCopyPostScriptName(named) as String == faces[language], has(named, text) { return named }
        let base = named ?? NSFont.systemFont(ofSize: size, weight: .bold) as CTFont
        return CTFontCreateForString(base, text as CFString, CFRange(location: 0, length: text.utf16.count))
    }

    static func has(_ font: CTFont, _ text: String) -> Bool {
        let units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) && !glyphs.contains(0)
    }
}
