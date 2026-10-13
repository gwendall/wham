import AppKit
import QuartzCore

// The menu bar item: one switch whose knob carries the glyph. On: candy track,
// white knob on the right with a pixel sun. Off: a soft track, the knob on the
// left in the menu bar's ink with a pixel moon cut out of it. Unknown: orange,
// knob in the middle. The knob rolls as it slides. In a timed session the candy
// drains toward the knob as the time runs out. Built from Core Animation
// layers, so it moves at the display's refresh rate even while the main thread
// waits on pmset or a password prompt.
final class SwitchView: NSView {
    // An odd knob for an odd glyph: the 11-point sun and moon sit exactly 3
    // points from the knob's edge, on whole pixels at any scale.
    static let track = NSSize(width: 42, height: 21)
    static let inset: CGFloat = 2
    static let knobSize: CGFloat = track.height - 2 * inset
    static let glyphInset = (knobSize - CGFloat(Pixels.sun.count)) / 2

    private let groove = CAShapeLayer()
    private let candy = CAGradientLayer()
    private let drained = CAShapeLayer() // the candy's mask: what is left of a timed session
    private let knob = CALayer() // slides and rolls, carrying both faces
    private let day = CALayer()
    private let sun = CAShapeLayer()
    private let night = CAShapeLayer() // a disk with the moon cut out
    private var trackRect = NSRect.zero
    private var label = CGColor(gray: 0, alpha: 1)
    private var orange = CGColor(gray: 0, alpha: 1)

    private(set) var state: Bool?
    private(set) var hasShown = false
    // The share of a timed session still to run; 1 when untimed.
    private(set) var left: CGFloat = 1

    var contentWidth: CGFloat { Self.track.width }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        candy.colors = Pixels.candy
        candy.startPoint = CGPoint(x: 0, y: 0.5)
        candy.endPoint = CGPoint(x: 1, y: 0.5)
        candy.cornerRadius = Self.track.height / 2
        candy.masksToBounds = true
        drained.fillColor = CGColor(gray: 0, alpha: 1)
        drained.frame = CGRect(origin: .zero, size: Self.track)
        drained.path = drainedPath()
        candy.mask = drained

        let disk = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        let glyphOrigin = CGPoint(x: Self.glyphInset, y: Self.glyphInset)
        knob.bounds = disk
        day.frame = disk
        day.cornerRadius = Self.knobSize / 2
        day.backgroundColor = CGColor(gray: 1, alpha: 1)
        day.shadowColor = CGColor(gray: 0, alpha: 1)
        day.shadowOpacity = 0.3
        day.shadowRadius = 1
        day.shadowOffset = .zero // it rolls: an offset shadow would turn with it
        sun.path = Pixels.path(Pixels.sun, origin: glyphOrigin)
        sun.fillColor = Pixels.ink
        day.addSublayer(sun)
        night.frame = disk
        let cutout = CGMutablePath()
        cutout.addEllipse(in: disk)
        cutout.addPath(Pixels.path(Pixels.moon, origin: glyphOrigin))
        night.path = cutout
        night.fillRule = .evenOdd
        knob.addSublayer(day)
        knob.addSublayer(night)

        for sublayer in [groove, candy, knob] { layer?.addSublayer(sublayer) }
        resolveColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var onToggle: (() -> Void)?
    var onMenu: (() -> Void)?

    // The switch takes its own clicks. A click left to the status bar button
    // underneath would light up the menu bar's pressed highlight around it, a box
    // much wider than it is tall; the knob is the only feedback. VoiceOver still
    // presses the button.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // A ⌘-drag moves menu bar items around: that one stays the button's.
        if event.modifierFlags.contains(.command) { return super.mouseDown(with: event) }
        if event.modifierFlags.contains(.control) { onMenu?() }
    }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { return super.mouseUp(with: event) }
        // Let go elsewhere and nothing happens, like any button.
        guard !event.modifierFlags.contains(.control), bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onToggle?()
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackRect = NSRect(x: snap((bounds.width - Self.track.width) / 2), y: snap((bounds.height - Self.track.height) / 2),
                           width: Self.track.width, height: Self.track.height)
        let radius = Self.track.height / 2
        groove.path = CGPath(roundedRect: trackRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        candy.frame = trackRect
        drained.frame = candy.bounds
        drained.path = drainedPath()
        knob.position = CGPoint(x: knobX(state), y: trackRect.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [groove, candy, drained, knob, day, sun, night] { sublayer.contentsScale = scale }
        needsLayout = true
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
        let fromTurn = current.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        let fromDay = day.presentation()?.opacity ?? day.opacity
        let fromNight = night.presentation()?.opacity ?? night.opacity
        let fromCandy = candy.presentation()?.opacity ?? candy.opacity
        let fromGroove = groove.presentation()?.opacity ?? groove.opacity

        state = newState
        hasShown = true
        let on = newState == true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let toX = knobX(newState)
            let move = spring("position.x", duration: 0.42, bounce: 0.2)
            move.fromValue = fromX
            move.toValue = toX
            knob.add(move, forKey: "move")
            // It rolls without slipping: one radian per radius travelled, clockwise
            // going right, and lands upright.
            let roll = spring("transform.rotation.z", duration: 0.42, bounce: 0.2)
            roll.fromValue = fromTurn + (toX - fromX) / (Self.knobSize / 2)
            roll.toValue = 0
            knob.add(roll, forKey: "roll")
            // The sun and the moon trade places in the first turn.
            fade(day, "opacity", from: fromDay, to: on ? 1 : 0, duration: 0.16)
            fade(night, "opacity", from: fromNight, to: on ? 0 : 1, duration: 0.16)
            fade(candy, "opacity", from: fromCandy, to: on ? 1 : 0)
            fade(groove, "opacity", from: fromGroove, to: grooveOpacity)
        }
        applyModel()
        CATransaction.commit()
    }

    // A timed session's candy drains from the far end toward the knob: whole at
    // the start, a ring around the knob at the end. Moves in quarter points, so
    // the tick that calls this redraws only when there is something to see.
    func drain(_ newLeft: CGFloat, animated: Bool) {
        let newLeft = min(1, max(0, newLeft))
        guard drainedWidth(newLeft) != drainedWidth(left) else { return }
        let from = drained.presentation()?.path ?? drained.path
        let fromGroove = groove.presentation()?.opacity ?? groove.opacity
        left = newLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = drainedPath()
        if animated && state == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            fade(drained, "path", from: from, to: path, duration: 0.4)
            fade(groove, "opacity", from: fromGroove, to: grooveOpacity, duration: 0.4)
        }
        drained.path = path
        groove.opacity = grooveOpacity
        CATransaction.commit()
    }

    private func drainedWidth(_ left: CGFloat) -> CGFloat {
        let size = Self.track
        return ((size.height + (size.width - size.height) * left) * 4).rounded() / 4
    }

    private func drainedPath() -> CGPath {
        let size = Self.track, width = drainedWidth(left), radius = size.height / 2
        return CGPath(roundedRect: CGRect(x: size.width - width, y: 0, width: width, height: size.height),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // The soft track shows where the candy has drained, and when off.
    private var grooveOpacity: Float { state == true && left >= 1 ? 0 : 1 }

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
        let x: CGFloat
        switch state {
        case true?: x = trackRect.maxX - Self.inset - Self.knobSize / 2
        case false?: x = trackRect.minX + Self.inset + Self.knobSize / 2
        case nil: x = trackRect.midX
        }
        return snap(x - Self.knobSize / 2) + Self.knobSize / 2
    }

    // On whole device pixels, so the knob and its glyph stay sharp and centered.
    private func snap(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
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
        let ink = state == nil ? orange : label
        groove.fillColor = ink.copy(alpha: 0.2)
        groove.opacity = grooveOpacity
        candy.opacity = on ? 1 : 0
        night.fillColor = ink
        night.opacity = on ? 0 : 1
        day.opacity = on ? 1 : 0
        knob.position = CGPoint(x: knobX(state), y: trackRect.midY)
    }
}
