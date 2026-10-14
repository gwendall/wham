import AppKit

// Check for Updates, as a row of its own: a click checks right there, the row
// says "Checking for Updates…" with a spinner, then how it went.
@MainActor
final class UpdateRow: MenuRow {
    enum State: Equatable, CustomStringConvertible {
        case action(String)  // clickable: Check for Updates
        case offer(String)   // clickable, with the dot the switch shows: Update to Wham 2.0
        case busy(String)    // Checking for Updates…, Updating to Wham 2.0…
        case done(String)    // the latest already: gray, with a check
        case said(String)    // anything else that happened: gray

        var title: String {
            switch self {
            case .action(let title), .offer(let title), .busy(let title), .done(let title), .said(let title): return title
            }
        }

        var busy: Bool { if case .busy = self { return true } else { return false } }

        // What the evals read: "busy: Checking for Updates…".
        var description: String {
            switch self {
            case .action: return "action: \(title)"
            case .offer: return "offer: \(title)"
            case .busy: return "busy: \(title)"
            case .done: return "done: \(title)"
            case .said: return "said: \(title)"
            }
        }

        var content: Content {
            switch self {
            case .action: return Content(title: title)
            case .offer: return Content(title: title, accessory: .dot)
            case .busy: return Content(title: title, enabled: false, accessory: .spinner)
            case .done: return Content(title: title, enabled: false, accessory: .done)
            case .said: return Content(title: title, enabled: false)
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
    private var shown: State {
        didSet {
            content = shown.content
            onChange?(shown)
        }
    }
    private var busySince = Date.distantPast
    private var later: Timer?
    var onChange: ((State) -> Void)?

    init(_ state: State, width: CGFloat) {
        shown = state
        super.init(state.content, width: width)
    }

    required init?(coder: NSCoder) { nil }
}
