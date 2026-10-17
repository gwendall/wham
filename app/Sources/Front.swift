import AppKit

// Brings a window of Wham's to the front, every time it is asked for, even
// when it is already open behind another app's windows: above the app in use
// (since macOS 14, asking to become the active app is a request macOS may turn
// down, and a menu bar app's window then opened behind), out of the Dock, onto
// the current Space; then again once the menu that asked has closed, so the
// window gets the keyboard too.
@MainActor
enum Front {
    static func bring(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.collectionBehavior.insert(.moveToActiveSpace)
        activate()
        // Above every app's windows for a moment, whether or not macOS lets
        // the app become active, then back among them, still in front.
        let level = window.level
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            activate()
            window.level = level
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    // An alert about to run modal: above everything too.
    static func bring(_ alert: NSAlert) {
        activate()
        DispatchQueue.main.async {
            alert.window.orderFrontRegardless()
            alert.window.makeKey()
        }
    }

    static func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}
