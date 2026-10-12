import AppKit
import QuartzCore

// The menu bar item: a pixel glyph (a sun when the Mac stays awake, a moon when
// it may sleep) followed by a switch. On: candy track, white knob on the right.
// Off: outlined track, knob on the left. Unknown: orange outline, knob in the
// middle. Built from Core Animation layers, so the knob glides at the display's
// refresh rate even while the main thread waits on pmset or a password prompt.
final class SwitchView: NSView {
    static let track = NSSize(width: 28, height: 16)
    static let glyph: CGFloat = 11 // one point per sprite pixel
    static let gap: CGFloat = 5
    static let inset: CGFloat = 2.5
    static let knobSize: CGFloat = track.height - 2 * inset

    private let sun = CALayer()
    private let moon = CALayer()
    private let outline = CAShapeLayer()
    private let candy = CAGradientLayer()
    private let candyMask = CAShapeLayer()
    private let knob = CALayer()
    private var trackRect = NSRect.zero
    private var label = CGColor(gray: 0, alpha: 1)
    private var orange = CGColor(gray: 0, alpha: 1)

    private(set) var state: Bool?
    private(set) var hasShown = false

    var contentWidth: CGFloat { Self.glyph + Self.gap + Self.track.width }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for (layer, sprite) in [(sun, Pixels.sun), (moon, Pixels.moon)] {
            let mask = CALayer()
            mask.contents = Pixels.image(sprite, color: CGColor(gray: 0, alpha: 1))
            mask.magnificationFilter = .nearest
            layer.mask = mask
            layer.bounds = CGRect(x: 0, y: 0, width: Self.glyph, height: Self.glyph)
            mask.frame = layer.bounds
        }
        candy.colors = Pixels.candy
        candy.startPoint = CGPoint(x: 0, y: 0.5)
        candy.endPoint = CGPoint(x: 1, y: 0.5)
        candy.mask = candyMask
        outline.lineWidth = 1.5
        outline.fillColor = nil
        knob.cornerRadius = Self.knobSize / 2
        knob.bounds = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        knob.shadowColor = CGColor(gray: 0, alpha: 1)
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        knob.shadowRadius = 1
        for sublayer in [sun, moon, outline, candy, knob] { layer?.addSublayer(sublayer) }
        resolveColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Clicks belong to the status bar button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = ((bounds.width - contentWidth) / 2).rounded()
        let glyphCenter = CGPoint(x: x + Self.glyph / 2, y: bounds.midY.rounded() + 0.5)
        sun.position = glyphCenter
        moon.position = glyphCenter
        trackRect = NSRect(x: x + Self.glyph + Self.gap, y: (bounds.midY - Self.track.height / 2).rounded(),
                           width: Self.track.width, height: Self.track.height)
        let radius = Self.track.height / 2
        candy.frame = trackRect
        candyMask.path = CGPath(roundedRect: CGRect(origin: .zero, size: trackRect.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        let stroked = trackRect.insetBy(dx: 0.75, dy: 0.75)
        outline.path = CGPath(roundedRect: stroked, cornerWidth: stroked.height / 2, cornerHeight: stroked.height / 2, transform: nil)
        knob.position = CGPoint(x: knobX(state), y: trackRect.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [sun, moon, outline, candy, candyMask, knob] { sublayer.contentsScale = scale }
    }

    // The menu bar flips between light and dark with the wallpaper.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    func show(_ newState: Bool?, animated: Bool) {
        let animate = animated && hasShown && state != nil && newState != nil && state != newState
        // Start from what is on screen, so a change mid-flight never jumps.
        let current = knob.presentation() ?? knob
        let fromX = current.position.x
        let fromKnobColor = current.backgroundColor
        let fromCandy = candy.presentation()?.opacity ?? candy.opacity
        let fromOutline = outline.presentation()?.opacity ?? outline.opacity

        state = newState
        hasShown = true
        let on = newState == true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let move = spring("position.x", duration: 0.34, bounce: 0.18)
            move.fromValue = fromX
            move.toValue = knobX(newState)
            knob.add(move, forKey: "move")

            // The knob stretches as it leaves, like a drop of liquid.
            let stretch = CAKeyframeAnimation(keyPath: "bounds.size.width")
            stretch.values = [Self.knobSize, Self.knobSize + 4, Self.knobSize]
            stretch.keyTimes = [0, 0.35, 1]
            stretch.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            stretch.duration = 0.32
            knob.add(stretch, forKey: "stretch")

            fade(candy, "opacity", from: fromCandy, to: on ? 1 : 0)
            fade(outline, "opacity", from: fromOutline, to: on ? 0 : 1)
            fade(knob, "backgroundColor", from: fromKnobColor, to: knobColor(newState), duration: 0.16)

            // The glyph that arrives pops in turning; the one that leaves shrinks away.
            let (arriving, leaving) = on ? (sun, moon) : (moon, sun)
            let pop = spring("transform.scale", duration: 0.4, bounce: 0.4)
            pop.fromValue = 0.2
            pop.toValue = 1
            arriving.add(pop, forKey: "pop")
            let turn = spring("transform.rotation.z", duration: 0.45, bounce: 0.3)
            turn.fromValue = on ? -CGFloat.pi / 2 : CGFloat.pi / 3
            turn.toValue = 0
            arriving.add(turn, forKey: "turn")
            fade(arriving, "opacity", from: 0, to: 1, duration: 0.12)
            fade(leaving, "opacity", from: leaving.presentation()?.opacity ?? 1, to: 0, duration: 0.12)
            fade(leaving, "transform.scale", from: 1, to: 0.3, duration: 0.14)
        }
        applyModel()
        CATransaction.commit()
    }

    // The spring of CASpringAnimation(perceptualDuration:bounce:), which needs
    // macOS 14, from its stiffness and damping.
    private func spring(_ keyPath: String, duration: CGFloat, bounce: CGFloat) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.stiffness = pow(2 * .pi / duration, 2)
        animation.damping = 4 * .pi * (1 - bounce) / duration
        animation.duration = animation.settlingDuration
        return animation
    }

    private func fade(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any?, duration: CFTimeInterval = 0.24) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: keyPath)
    }

    private func knobX(_ state: Bool?) -> CGFloat {
        switch state {
        case true?: trackRect.maxX - Self.inset - Self.knobSize / 2
        case false?: trackRect.minX + Self.inset + Self.knobSize / 2
        case nil: trackRect.midX
        }
    }

    private func knobColor(_ state: Bool?) -> CGColor {
        switch state {
        case true?: CGColor(gray: 1, alpha: 1)
        case false?: label
        case nil: orange
        }
    }

    private func resolveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label = NSColor.labelColor.cgColor
            orange = NSColor.systemOrange.cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyModel()
        CATransaction.commit()
    }

    private func applyModel() {
        let on = state == true
        sun.backgroundColor = label
        moon.backgroundColor = label
        sun.opacity = on ? 1 : 0
        moon.opacity = on ? 0 : (state == nil ? 0.5 : 1)
        candy.opacity = on ? 1 : 0
        outline.strokeColor = state == nil ? orange : label
        outline.opacity = on ? 0 : 1
        knob.backgroundColor = knobColor(state)
        knob.shadowOpacity = on ? 0.3 : 0
        knob.position = CGPoint(x: knobX(state), y: trackRect.midY)
    }
}
