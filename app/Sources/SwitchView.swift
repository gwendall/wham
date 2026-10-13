import AppKit
import QuartzCore

// The menu bar item: one switch whose knob carries the glyph. On: candy track,
// white knob on the right with a pixel sun. Off: a soft track, the knob on the
// left in the menu bar's ink with a pixel moon cut out of it. Unknown: orange,
// knob in the middle. The knob rolls as it slides. In a timed session the candy
// drains toward the knob as the time runs out. Built from Core Animation
// layers, so it moves at the display's refresh rate even while the main thread
// waits on pmset or a password prompt.
//
// The menu's Appearance changes two things. Monochrome draws it all in the
// menu bar's ink, like the icons around it: on, the track is solid and the
// knob a hole in it, with its sun in ink. Compact keeps the knob alone, in a
// ring as wide as an icon: it turns where it is instead of sliding, and in a
// timed session the ring runs out like a timer's.
final class SwitchView: NSView {
    struct Look: Equatable {
        var monochrome = false
        var compact = false
    }

    // An odd knob for an odd glyph: the 11-point sun and moon sit exactly 3
    // points from the knob's edge, on whole pixels at any scale.
    static let height: CGFloat = 21
    static let inset: CGFloat = 2
    static let knobSize: CGFloat = height - 2 * inset
    static let glyphInset = (knobSize - CGFloat(Pixels.sun.count)) / 2

    private let track = CALayer() // the groove and the candy
    private let groove = CAShapeLayer()
    private let candy = CAGradientLayer()
    private let drained = CAShapeLayer() // the candy's mask: what is left of a timed session
    private let hole = CAShapeLayer() // the track's mask when monochrome: the menu bar shows through the knob
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
    private(set) var look = Look()

    // The track: 42 by 21, or a ring of 21 when compact.
    var trackSize: NSSize { NSSize(width: look.compact ? Self.height : 42, height: Self.height) }
    // The status item's width: the track and a little room around it.
    var itemLength: CGFloat { trackSize.width + (look.compact ? 2 : 8) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        candy.startPoint = CGPoint(x: 0, y: 0.5)
        candy.endPoint = CGPoint(x: 1, y: 0.5)
        candy.masksToBounds = true
        candy.mask = drained
        hole.fillRule = .evenOdd
        hole.fillColor = CGColor(gray: 0, alpha: 1)
        track.addSublayer(groove)
        track.addSublayer(candy)

        let disk = CGRect(x: 0, y: 0, width: Self.knobSize, height: Self.knobSize)
        let glyphOrigin = CGPoint(x: Self.glyphInset, y: Self.glyphInset)
        knob.bounds = disk
        day.frame = disk
        day.cornerRadius = Self.knobSize / 2
        day.shadowColor = CGColor(gray: 0, alpha: 1)
        day.shadowRadius = 1
        day.shadowOffset = .zero // it rolls: an offset shadow would turn with it
        sun.path = Pixels.path(Pixels.sun, origin: glyphOrigin)
        day.addSublayer(sun)
        night.frame = disk
        let cutout = CGMutablePath()
        cutout.addEllipse(in: disk)
        cutout.addPath(Pixels.path(Pixels.moon, origin: glyphOrigin))
        night.path = cutout
        night.fillRule = .evenOdd
        knob.addSublayer(day)
        knob.addSublayer(night)

        for sublayer in [track, knob] { layer?.addSublayer(sublayer) }
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
        let size = trackSize, radius = size.height / 2
        trackRect = NSRect(x: snap((bounds.width - size.width) / 2), y: snap((bounds.height - size.height) / 2),
                           width: size.width, height: size.height)
        track.frame = trackRect
        groove.path = CGPath(roundedRect: track.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        candy.frame = track.bounds
        candy.cornerRadius = radius
        drained.frame = candy.bounds
        hole.frame = track.bounds
        shapeDrained()
        applyModel()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [track, groove, candy, drained, hole, knob, day, sun, night] { sublayer.contentsScale = scale }
        needsLayout = true
    }

    // From the menu's Appearance; the status item takes the new itemLength.
    func setLook(_ newLook: Look) {
        guard newLook != look else { return }
        look = newLook
        for layer in [knob, hole, drained, groove, candy, day, night] { layer.removeAllAnimations() }
        needsLayout = true
        resolveColors()
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
            if toX != fromX {
                let move = spring("position.x", duration: 0.42, bounce: 0.2)
                move.fromValue = fromX
                move.toValue = toX
                knob.add(move, forKey: "move")
                // A monochrome track's hole goes along, on the same spring.
                let follow = spring("path", duration: 0.42, bounce: 0.2)
                follow.fromValue = holePath(fromX)
                follow.toValue = holePath(toX)
                hole.add(follow, forKey: "move")
            }
            // It rolls without slipping: one radian per radius travelled, clockwise
            // going right, and lands upright. A compact knob turns where it is,
            // half a turn, the same way: clockwise to turn on.
            let turn = look.compact ? (on ? CGFloat.pi : -CGFloat.pi) : (toX - fromX) / (Self.knobSize / 2)
            let roll = spring("transform.rotation.z", duration: 0.42, bounce: 0.2)
            roll.fromValue = fromTurn + turn
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
    // the start, a ring around the knob at the end. A compact ring runs out
    // from the top, counterclockwise. Moves in quarter points, so the tick that
    // calls this redraws only when there is something to see.
    func drain(_ newLeft: CGFloat, animated: Bool) {
        let newLeft = min(1, max(0, newLeft))
        guard step(newLeft) != step(left) else { return }
        let fromPath = drained.presentation()?.path ?? drained.path
        let fromEnd = drained.presentation()?.strokeEnd ?? drained.strokeEnd
        let fromGroove = groove.presentation()?.opacity ?? groove.opacity
        left = newLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = drainedPath(), end = ringEnd(left)
        if animated && state == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if look.compact {
                fade(drained, "strokeEnd", from: fromEnd, to: end, duration: 0.4)
            } else {
                fade(drained, "path", from: fromPath, to: path, duration: 0.4)
            }
            fade(groove, "opacity", from: fromGroove, to: grooveOpacity, duration: 0.4)
        }
        if look.compact { drained.strokeEnd = end } else { drained.path = path }
        groove.opacity = grooveOpacity
        CATransaction.commit()
    }

    private func step(_ left: CGFloat) -> CGFloat { look.compact ? ringEnd(left) : drainedWidth(left) }

    private func drainedWidth(_ left: CGFloat) -> CGFloat {
        let size = trackSize
        return ((size.height + (size.width - size.height) * left) * 4).rounded() / 4
    }

    private func drainedPath() -> CGPath {
        let size = trackSize, width = drainedWidth(left), radius = size.height / 2
        return CGPath(roundedRect: CGRect(x: size.width - width, y: 0, width: width, height: size.height),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // The share of a compact ring left, in quarter points of its edge.
    private func ringEnd(_ left: CGFloat) -> CGFloat {
        let edge = .pi * trackSize.height
        return (left * edge * 4).rounded() / 4 / edge
    }

    // The candy's mask: a bar, or for a compact ring a stroke as thick as the
    // ring's radius, from the top, clockwise, cut short by strokeEnd.
    private func shapeDrained() {
        let size = trackSize
        if look.compact {
            let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = size.height / 4
            let ring = CGMutablePath()
            ring.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
            ring.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: -3 * .pi / 2, clockwise: true)
            drained.path = ring
            drained.fillColor = nil
            drained.strokeColor = CGColor(gray: 0, alpha: 1)
            drained.lineWidth = size.height / 2
            drained.strokeEnd = ringEnd(left)
        } else {
            drained.path = drainedPath()
            drained.fillColor = CGColor(gray: 0, alpha: 1)
            drained.strokeColor = nil
            drained.strokeEnd = 1
        }
    }

    // The track, less the knob's disk with the knob at x.
    private func holePath(_ x: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: trackSize))
        path.addEllipse(in: CGRect(x: x - trackRect.minX - Self.knobSize / 2, y: Self.inset, width: Self.knobSize, height: Self.knobSize))
        return path
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
        case _ where look.compact: x = trackRect.midX
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
        let on = state == true, mono = look.monochrome
        // Unknown: orange, or the ink at half when monochrome.
        let ink = state != nil ? label : mono ? label.copy(alpha: 0.5) ?? label : orange
        groove.fillColor = ink.copy(alpha: 0.2)
        groove.opacity = grooveOpacity
        candy.colors = mono ? [label, label] : Pixels.candy
        candy.opacity = on ? 1 : 0
        day.backgroundColor = mono ? nil : CGColor(gray: 1, alpha: 1)
        day.shadowOpacity = mono ? 0 : 0.3
        sun.fillColor = mono ? label : Pixels.ink
        night.fillColor = ink
        night.opacity = on ? 0 : 1
        day.opacity = on ? 1 : 0
        track.mask = mono ? hole : nil
        let x = knobX(state)
        knob.position = CGPoint(x: x, y: trackRect.midY)
        hole.path = holePath(x)
    }
}
