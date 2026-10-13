import AppKit

// A menu row that keeps the menu open: a click on it is the row's, not the
// menu's, so an option changes and the menu stays, showing the new state.
// Only a click outside closes it.
//
// A menu item with a view draws itself, so this one copies the menu's own
// rows: its title where the menu puts the other titles (read from them once
// the menu shows, a measured guess on systems that draw menus otherwise), the
// menu's check mark in the menu's check column, a gray detail on the right,
// and the system's selection under the mouse, with the row's text inside it
// as macOS does.
@MainActor
class MenuRow: NSView {
    struct Content: Equatable {
        var title: String
        var detail: String?  // gray, on the right: when a length would end
        var checked = false
        var enabled = true
        var accessory = Accessory.none
    }

    enum Accessory { case none, spinner, done }

    var content: Content { didSet { if content != oldValue { restyle() } } }
    // Read again by reload(), while the menu is open.
    var source: (() -> Content)?
    var highlighted = false { didSet { if highlighted != oldValue { restyle() } } }
    var onClick: (() -> Void)?

    func reload() {
        if let source { content = source() }
    }

    // Wide enough for every title the row can hold, with its detail or its
    // spinner: the menu does not grow while open.
    static func width(for titles: [String], details: [String] = [], accessory: Bool = false) -> CGFloat {
        let widest = titles.map(textWidth).max() ?? 0
        if accessory { return ceil(guessedTitleX + 2 + widest + gap + side + trailing) }
        let detail = details.map(textWidth).max().map { detailGap + $0 } ?? 0
        return ceil(guessedTitleX + 2 + widest + detail + textTrailing)
    }

    static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }

    // macOS 26 rows are taller, with rounder selections.
    private static let modern: Bool = {
        if #available(macOS 26, *) { return true } else { return false }
    }()
    static var height: CGFloat { modern ? 24 : 22 }
    private static let guessedTitleX: CGFloat = modern ? 22 : 21
    // The spinner, or the gray check of a version up to date, and what is
    // around it; a title's or a detail's distance from the right edge, as
    // the menu's own; a detail's least distance from its title.
    private static let side: CGFloat = 16
    private static let gap: CGFloat = 6
    private static let trailing: CGFloat = 14
    private static let textTrailing: CGFloat = 18
    private static let detailGap: CGFloat = 24
    // The menu's check mark: the system's checkmark at the menu's size,
    // just left of the titles.
    private static let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13, weight: .bold, scale: .small))

    // Where the menu puts its titles in a row, and the appearance it draws
    // them in, as read from its own rows the last time: a submenu made only
    // of these rows has none of its own to read.
    private static var measured: (x: CGFloat, y: CGFloat, height: CGFloat, appearance: NSAppearance)?

    private let selection = NSVisualEffectView()
    // What the row shows, moved into the selection while it is there.
    private let ink = NSView()
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let check = NSImageView()
    private let spinner = NSProgressIndicator()
    private let done = NSImageView()
    private var remeasuring = false

    init(_ content: Content, width: CGFloat) {
        self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        selection.material = .selection
        selection.isEmphasized = true
        selection.state = .active
        selection.blendingMode = .behindWindow
        selection.wantsLayer = true
        selection.layer?.cornerRadius = Self.modern ? 7 : 4
        for field in [label, detail] {
            field.font = .menuFont(ofSize: 0)
            field.lineBreakMode = .byTruncatingTail
        }
        detail.alignment = .right
        check.image = Self.checkmark
        check.imageScaling = .scaleNone
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        done.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        done.contentTintColor = .tertiaryLabelColor
        for view in [label, detail, check, spinner, done] as [NSView] { ink.addSubview(view) }
        addSubview(selection)
        addSubview(ink)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        restyle()
    }

    required init?(coder: NSCoder) { nil }

    var title: String { content.title }

    private func restyle() {
        label.stringValue = content.title
        detail.stringValue = content.detail ?? ""
        detail.isHidden = content.detail == nil
        selection.isHidden = !(highlighted && content.enabled)
        // On the selection, the text goes inside it, as the menu's own rows do.
        let host: NSView = selection.isHidden ? self : selection
        if ink.superview !== host { host.addSubview(ink) }
        // The menu's own colors: its gray is the one of its disabled lines.
        let color: NSColor = !content.enabled ? .tertiaryLabelColor : selection.isHidden ? .labelColor : .selectedMenuItemTextColor
        label.textColor = color
        check.contentTintColor = color
        detail.textColor = selection.isHidden ? .secondaryLabelColor : .selectedMenuItemTextColor
        check.isHidden = !content.checked
        if content.accessory == .spinner { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        done.isHidden = content.accessory != .done
        // Its menu item says the same: what the keyboard types to, and the
        // state VoiceOver reads.
        enclosingMenuItem?.title = content.title
        enclosingMenuItem?.state = content.checked ? .on : .off
        setAccessibilityLabel(content.detail.map { "\(content.title), \($0)" } ?? content.title)
        setAccessibilityEnabled(content.enabled)
        needsLayout = true
    }

    // One of the menu's own titles, where the menu draws them with views
    // (macOS 14 on, at least): its frame in the window, its row's, and the
    // appearance it is drawn in. Rows like this one are not the menu's own.
    private func menuTitle() -> (frame: NSRect, row: NSRect, appearance: NSAppearance)? {
        func find(_ view: NSView) -> NSTextField? {
            if view is MenuRow { return nil }
            if let field = view as? NSTextField { return field }
            for sub in view.subviews { if let field = find(sub) { return field } }
            return nil
        }
        guard let root = window?.contentView, let field = find(root), let holder = field.superview else { return nil }
        return (holder.convert(field.frame, to: nil), holder.convert(holder.bounds, to: nil), field.effectiveAppearance)
    }

    var underPointer: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    // For the evals: where this title starts in the window, and its row's
    // height, against the menu's own (nil where the menu draws without views).
    var measures: (x: CGFloat, height: CGFloat, menuX: CGFloat?, menuHeight: CGFloat?) {
        let native = menuTitle()
        return (label.convert(label.bounds, to: nil).minX, bounds.height, native?.frame.minX, native?.row.height)
    }

    override func layout() {
        super.layout()
        selection.frame = bounds.insetBy(dx: 5, dy: 0)
        ink.frame = ink.superview === selection ? bounds.offsetBy(dx: -selection.frame.minX, dy: -selection.frame.minY) : bounds
        // Drawn as the menu's own titles: before macOS 26 the menu hands views
        // like this one a vibrant appearance, in which labelColor is lighter.
        // A menu that opens again lays this row out before its own: their
        // titles have no frame yet. The last measure then, and once more on
        // the next pass, when they have one.
        if let native = menuTitle() {
            if native.frame.height > 0 {
                Self.measured = (convert(native.frame, from: nil).minX, native.frame.minY - native.row.minY, native.frame.height, native.appearance)
            } else if !remeasuring {
                remeasuring = true
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.remeasuring = false
                        self?.needsLayout = true
                    }
                }
            }
        }
        let measured = Self.measured
        if let look = measured?.appearance ?? window?.effectiveAppearance, appearance?.name != look.name { appearance = look }
        // The menu's own title, moved into this row: same x, same place in its row.
        let x = measured?.x ?? Self.guessedTitleX
        let height = measured?.height ?? label.fittingSize.height
        let y = measured?.y ?? (bounds.height - height) / 2
        var right = bounds.maxX - Self.textTrailing + 2
        if content.accessory != .none {
            let side = Self.side
            let box = NSRect(x: bounds.maxX - Self.trailing - side, y: (bounds.height - side) / 2, width: side, height: side)
            spinner.frame = box
            done.frame = box
            right = box.minX - Self.gap
        }
        if content.detail != nil {
            let width = ceil(detail.fittingSize.width)
            detail.frame = NSRect(x: right - width, y: y, width: width, height: height)
            right = detail.frame.minX - Self.detailGap + 4
        }
        label.frame = NSRect(x: x, y: y, width: max(0, right - x), height: height)
        if let size = Self.checkmark?.size {
            check.frame = NSRect(x: x - size.width, y: floor((bounds.height - size.height) / 2), width: size.width, height: size.height)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restyle()
    }

    // The menu stays open: the click is the row's, not the menu's.
    override func mouseUp(with event: NSEvent) {
        if content.enabled { onClick?() }
    }

    override func rightMouseUp(with event: NSEvent) {
        if content.enabled { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard content.enabled else { return false }
        onClick?()
        return true
    }
}
