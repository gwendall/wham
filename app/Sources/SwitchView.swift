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
// timed session the ring runs out like a timer's. A change of look moves
// there at the display's refresh rate, colors, hole, track and the status
// item's width together.
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
    private let drained = CALayer() // the candy's mask: what is left of a timed session,
    private let bar = CAShapeLayer() // as a bar from the far end to the knob,
    private let ring = CAShapeLayer() // or, compact, as a ring that runs out
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

    // The look as drawn, from 0 to 1 toward monochrome and toward compact:
    // a change of look moves it there frame by frame, from where it is.
    struct Blend: Equatable {
        var mono: CGFloat = 0
        var compact: CGFloat = 0
    }
    private(set) var blend = Blend()
    private var blendFrom = Blend()
    private(set) var blendStart: CFTimeInterval = 0
    private var ticker: AnyObject? // a display link from macOS 14, a timer before
    private var deadline: Timer?
    static let lookDuration: CFTimeInterval = 0.45
    // Each frame of a change of look: the status item takes itemLength.
    var onFrame: (() -> Void)?

    // The track: 42 by 21, or a ring of 21 when compact.
    var trackSize: NSSize { NSSize(width: 42 - 21 * blend.compact, height: Self.height) }
    // The status item's width: the track and a little room around it, 50 or
    // 23 points.
    var itemLength: CGFloat { snap(trackSize.width + 8 - 6 * blend.compact) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        candy.startPoint = CGPoint(x: 0, y: 0.5)
        candy.endPoint = CGPoint(x: 1, y: 0.5)
        candy.masksToBounds = true
        candy.mask = drained
        drained.addSublayer(bar)
        drained.addSublayer(ring)
        bar.fillColor = CGColor(gray: 0, alpha: 1)
        ring.fillColor = nil
        ring.strokeColor = CGColor(gray: 0, alpha: 1)
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
        redraw()
    }

    private func redraw() {
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
        for sublayer in [track, groove, candy, drained, bar, ring, hole, knob, day, sun, night] { sublayer.contentsScale = scale }
        needsLayout = true
    }

    // From the menu's Appearance: animated, it moves there frame by frame,
    // and the status item takes each frame's itemLength.
    func setLook(_ newLook: Look, animated: Bool) {
        guard newLook != look else { return }
        look = newLook
        for layer in [knob, hole, bar, ring, groove, candy, day, night] { layer.removeAllAnimations() }
        blendFrom = blend
        blendStart = CACurrentMediaTime()
        if animated && hasShown && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            tick()
            startTicking()
        } else {
            stopTicking()
            advanceLook(to: .infinity)
        }
    }

    // Draws the change of look as it stands at `time` (CACurrentMediaTime);
    // true once it is there.
    @discardableResult
    func advanceLook(to time: CFTimeInterval) -> Bool {
        let target = Blend(mono: look.monochrome ? 1 : 0, compact: look.compact ? 1 : 0)
        let elapsed = time - blendStart
        let progress = elapsed >= Self.lookDuration ? 1 : Self.ease(max(0, elapsed))
        blend = Blend(mono: blendFrom.mono + (target.mono - blendFrom.mono) * progress,
                      compact: blendFrom.compact + (target.compact - blendFrom.compact) * progress)
        onFrame?()
        redraw()
        return progress >= 1
    }

    // The knob's spring without its bounce, brought to rest at lookDuration.
    private static func ease(_ time: CFTimeInterval) -> CGFloat {
        let omega = 2 * Double.pi / 0.42
        func settled(_ time: Double) -> Double { 1 - (1 + omega * time) * exp(-omega * time) }
        return CGFloat(min(1, settled(time) / settled(lookDuration)))
    }

    // Every frame the display shows, where it can say when (macOS 14 on), a
    // sixtieth of a second otherwise, and an end in any case: a display
    // asleep shows no frames.
    private func startTicking() {
        deadline?.invalidate()
        let end = Timer(timeInterval: Self.lookDuration + 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.ticker != nil else { return }
                self.advanceLook(to: .infinity)
                self.stopTicking()
            }
        }
        RunLoop.main.add(end, forMode: .common)
        deadline = end
        guard ticker == nil else { return }
        if #available(macOS 14, *), window != nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            ticker = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    @objc private func tick() {
        if advanceLook(to: CACurrentMediaTime()) { stopTicking() }
    }

    private func stopTicking() {
        if #available(macOS 14, *) { (ticker as? CADisplayLink)?.invalidate() }
        (ticker as? Timer)?.invalidate()
        ticker = nil
        deadline?.invalidate()
        deadline = nil
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
        let fromPath = bar.presentation()?.path ?? bar.path
        let fromEnd = ring.presentation()?.strokeEnd ?? ring.strokeEnd
        let fromGroove = groove.presentation()?.opacity ?? groove.opacity
        left = newLeft
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = drainedPath(), end = ringEnd(left)
        if animated && state == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            fade(bar, "path", from: fromPath, to: path, duration: 0.4)
            fade(ring, "strokeEnd", from: fromEnd, to: end, duration: 0.4)
            fade(groove, "opacity", from: fromGroove, to: grooveOpacity, duration: 0.4)
        }
        bar.path = path
        ring.strokeEnd = end
        showDrained()
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

    // The candy's masks: a bar, and for a compact ring a stroke as thick as
    // the ring's radius, from the top, clockwise, cut short by strokeEnd.
    private func shapeDrained() {
        let size = trackSize
        bar.frame = drained.bounds
        ring.frame = drained.bounds
        bar.path = drainedPath()
        let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = size.height / 4
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: -3 * .pi / 2, clockwise: true)
        ring.path = path
        ring.lineWidth = size.height / 2
        ring.strokeEnd = ringEnd(left)
        showDrained()
    }

    // The bar, or the ring in a timed session as compact, one fading into
    // the other as the look changes. Untimed, the bar is the whole track.
    private func showDrained() {
        let timed = left < 1
        bar.opacity = timed ? Float(1 - blend.compact) : 1
        ring.opacity = timed ? Float(blend.compact) : 0
    }

    // The track, less the knob's disk with the knob at x: the whole disk when
    // monochrome, a hole opening from its center on the way there.
    private func holePath(_ x: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: trackSize))
        let size = Self.knobSize * blend.mono
        path.addEllipse(in: CGRect(x: x - trackRect.minX - size / 2, y: trackRect.height / 2 - size / 2, width: size, height: size))
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

    // On its side of the track, or in the middle when compact or unknown.
    private func knobX(_ state: Bool?) -> CGFloat {
        let side: CGFloat
        switch state {
        case true?: side = trackRect.maxX - Self.inset - Self.knobSize / 2
        case false?: side = trackRect.minX + Self.inset + Self.knobSize / 2
        case nil: side = trackRect.midX
        }
        let x = side + (trackRect.midX - side) * blend.compact
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
        let on = state == true, mono = blend.mono
        // Unknown: orange, or the ink at half when monochrome.
        let ink = state != nil ? label : Self.mix(orange, label.copy(alpha: 0.5) ?? label, mono)
        groove.fillColor = ink.copy(alpha: 0.2)
        groove.opacity = grooveOpacity
        candy.colors = Pixels.candy.map { Self.mix($0, label, mono) }
        candy.opacity = on ? 1 : 0
        // The knob's face turns over quickly, halfway: on a dark menu bar its
        // disk and its sun trade light and dark, and a slow fade would lose
        // the sun on the way.
        let face = Self.smoothstep(0.3, 0.7, mono)
        day.backgroundColor = CGColor(gray: 1, alpha: 1 - face)
        day.shadowOpacity = Float(0.3 * (1 - face))
        sun.fillColor = Self.mix(Pixels.ink, label, face)
        night.fillColor = ink
        night.opacity = on ? 0 : 1
        day.opacity = on ? 1 : 0
        track.mask = mono > 0 ? hole : nil
        let x = knobX(state)
        knob.position = CGPoint(x: x, y: trackRect.midY)
        hole.path = holePath(x)
    }

    private static func smoothstep(_ from: CGFloat, _ to: CGFloat, _ value: CGFloat) -> CGFloat {
        let share = min(1, max(0, (value - from) / (to - from)))
        return share * share * (3 - 2 * share)
    }

    // A color part of the way to another, in extended sRGB.
    private static func mix(_ from: CGColor, _ to: CGColor, _ share: CGFloat) -> CGColor {
        if share <= 0 { return from }
        if share >= 1 { return to }
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let a = from.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let b = to.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              a.count == 4, b.count == 4 else { return share < 0.5 ? from : to }
        return CGColor(colorSpace: space, components: zip(a, b).map { $0 + ($1 - $0) * share }) ?? to
    }
}
