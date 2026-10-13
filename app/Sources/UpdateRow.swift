import AppKit

// Check for Updates, as a row that keeps the menu open: a click checks right
// there, the row says "Checking for Updates…" with a spinner, then how it went.
//
// A menu item with a view draws itself, so this one copies the menu's own
// rows: its title where the menu puts the other titles (read from them once
// the menu shows, a measured guess on systems that draw menus otherwise), the
// system's selection under the mouse, with the title inside it as macOS does.
@MainActor
final class UpdateRow: NSView {
    enum State: Equatable, CustomStringConvertible {
        case action(String)  // clickable: Check for Updates, Update to Wham 2.0
        case busy(String)    // Checking for Updates…, Updating to Wham 2.0…
        case done(String)    // the latest already: gray, with a check
        case said(String)    // anything else that happened: gray

        var title: String {
            switch self {
            case .action(let title), .busy(let title), .done(let title), .said(let title): return title
            }
        }

        var busy: Bool { if case .busy = self { return true } else { return false } }

        // What the evals read: "busy: Checking for Updates…".
        var description: String {
            switch self {
            case .action: return "action: \(title)"
            case .busy: return "busy: \(title)"
            case .done: return "done: \(title)"
            case .said: return "said: \(title)"
            }
        }
    }

    // What the row says. Busy, it stays so a second at least: a check that
    // answers at once would only flicker.
    var state: State {
        get { shown }
        set {
            later?.invalidate()
            later = nil
            let wait = 1 - Date().timeIntervalSince(busySince)
            if shown.busy, !newValue.busy, wait > 0 {
                let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.state = newValue } }
                RunLoop.main.add(timer, forMode: .common)
                later = timer
                return
            }
            if newValue.busy, !shown.busy { busySince = Date() }
            shown = newValue
        }
    }
    private var shown: State { didSet { restyle(); onChange?(shown) } }
    private var busySince = Date.distantPast
    private var later: Timer?
    var highlighted = false { didSet { restyle() } }
    var onClick: (() -> Void)?
    var onChange: ((State) -> Void)?

    // Every title the row can hold fits: the menu does not grow while open.
    static func width(for titles: [String]) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(guessedTitleX + 2 + widest + gap + accessory + trailing)
    }

    // macOS 26 rows are taller, with rounder selections.
    private static let modern: Bool = {
        if #available(macOS 26, *) { return true } else { return false }
    }()
    static var height: CGFloat { modern ? 24 : 22 }
    private static let guessedTitleX: CGFloat = modern ? 22 : 21
    private static let accessory: CGFloat = 16
    private static let gap: CGFloat = 6
    private static let trailing: CGFloat = 14

    private let selection = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let check = NSImageView()

    init(_ state: State, width: CGFloat) {
        shown = state
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        selection.material = .selection
        selection.isEmphasized = true
        selection.state = .active
        selection.blendingMode = .behindWindow
        selection.wantsLayer = true
        selection.layer?.cornerRadius = Self.modern ? 7 : 4
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.contentTintColor = .disabledControlTextColor
        for view in [selection, label, spinner, check] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        restyle()
    }

    required init?(coder: NSCoder) { nil }

    var title: String { state.title }

    private var clickable: Bool { if case .action = state { return true } else { return false } }

    private func restyle() {
        label.stringValue = title
        selection.isHidden = !(highlighted && clickable)
        // On the selection, the title goes inside it, as the menu's own rows do.
        let host: NSView = selection.isHidden ? self : selection
        if label.superview !== host { host.addSubview(label); needsLayout = true }
        label.textColor = !clickable ? .disabledControlTextColor : highlighted ? .selectedMenuItemTextColor : .labelColor
        if case .busy = state { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        check.isHidden = state != .done(title)
        setAccessibilityLabel(title)
        setAccessibilityEnabled(clickable)
    }

    // One of the menu's own titles, where the menu draws them with views
    // (macOS 26 on): its frame in the window, and its row's.
    private func menuTitle() -> (frame: NSRect, row: NSRect)? {
        guard let root = window?.contentView else { return nil }
        var found: NSTextField?
        func walk(_ view: NSView) {
            if found == nil, let field = view as? NSTextField, !field.isDescendant(of: self) { found = field }
            if found == nil { view.subviews.forEach(walk) }
        }
        walk(root)
        guard let field = found, let holder = field.superview else { return nil }
        return (holder.convert(field.frame, to: nil), holder.convert(holder.bounds, to: nil))
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
        let side = Self.accessory
        let accessory = NSRect(x: bounds.maxX - Self.trailing - side, y: (bounds.height - side) / 2, width: side, height: side)
        spinner.frame = accessory
        check.frame = accessory
        // The menu's own title, moved into this row: same x, same place in its row.
        let frame: NSRect
        if let native = menuTitle() {
            let x = convert(native.frame, from: nil).minX
            frame = NSRect(x: x, y: native.frame.minY - native.row.minY, width: accessory.minX - Self.gap - x, height: native.frame.height)
        } else {
            let height = label.fittingSize.height
            frame = NSRect(x: Self.guessedTitleX, y: (bounds.height - height) / 2, width: accessory.minX - Self.gap - Self.guessedTitleX, height: height)
        }
        label.frame = label.superview === selection ? frame.offsetBy(dx: -selection.frame.minX, dy: -selection.frame.minY) : frame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    // The menu stays open: the click is the row's, not the menu's.
    override func mouseUp(with event: NSEvent) {
        if clickable { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard clickable else { return false }
        onClick?()
        return true
    }
}
