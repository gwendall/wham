import AppKit
import ServiceManagement

// The menu bar app. A click flips the switch; a right-click (or control-click)
// opens the menu.
@MainActor
final class Wham: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleView = SwitchView()
    private let toast = Toast()
    // Made on the first click: CoreAudio stays unloaded until there is something to play.
    private lazy var sounds = [true: NSSound(data: Chime.wav(Chime.samples(on: true))),
                               false: NSSound(data: Chime.wav(Chime.samples(on: false)))]
    private var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }
    private var busy = false
    private var sleepGivenBack = false
    private var updating = false
    // A newer version found and not installed (Update Automatically is off, or
    // it could not install): the menu offers it. The one being installed, and
    // whether someone asked from the menu, who then hears how it went.
    private var available: String?
    private var installing: String?
    private var asked = false
    // Check for Updates while the menu is open: a check asked for there says
    // how it went right there, rather than in a pill.
    private weak var updateRow: UpdateRow?
    // Read at launch: once a new copy is in place, the files say its version.
    private let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private var timer: Timer?
    private var updateTimer: Timer?
    private let watchdog = Watchdog()
    private var watch: Watch?
    // A timed session's end and start, and what ended the last session on its own.
    private var offAt: Date?
    private var onAt: Date?
    private var endTimer: Timer?
    private var warnTimer: Timer?
    private var ended: (why: String, at: Date)?
    private var lidWasClosed = false
    // Set when macOS says it is about to restart, shut down or log out.
    private var poweringOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.runsFromTemporaryCopy && offerToMove() { return }
        guard let button = item.button else { return }
        toggleView.setLook(look)
        item.length = toggleView.itemLength
        toggleView.frame = button.bounds
        toggleView.autoresizingMask = [.width, .height]
        button.addSubview(toggleView)
        toggleView.onToggle = { [weak self] in self?.toggle() }
        toggleView.onMenu = { [weak self] in self?.showMenu() }
        // VoiceOver and ⌘-clicks still go through the button.
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        offAt = Session.offAt
        onAt = Session.onAt
        lidWasClosed = Sleep.lidClosed
        let restarted = UserDefaults.standard.object(forKey: "resumeAtLogin")
        check()
        scheduleEnd()
        resumeAfterUpdate()
        resumeAfterRestart(restarted)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poweringOff = true }
        }
        // Catches anything else flipping the flag (`wham on` in a terminal, pmset,
        // a reboot). The tolerance lets macOS batch these wakeups with others.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 1
        watch = Watch { [weak self] in self?.check() }
        // `wham on 2h` in a terminal.
        DistributedNotificationCenter.default().addObserver(forName: Session.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.offAt = Session.offAt
                self.onAt = Session.onAt
                self.scheduleEnd()
                self.check()
            }
        }
        scheduleUpdates()
        pressForEvals()
        // A menu bar switch is only useful if it is there: open at login from the
        // first launch on (the menu can turn this off), and say hello once. The
        // first launch of a newer version says which one it is.
        if !Self.runsFromTemporaryCopy {
            let defaults = UserDefaults.standard
            let updated = Update.isUpdate(to: running, from: defaults.string(forKey: "lastVersion"), ranBefore: defaults.bool(forKey: "loginItemSet"))
            defaults.set(running, forKey: "lastVersion")
            if !defaults.bool(forKey: "loginItemSet") {
                defaults.set(true, forKey: "loginItemSet")
                try? LoginItem.set(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.hello() }
            } else if updated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.pop(Toast.note("UPDATED TO \(self.running)", "What's New is in the menu")) }
            }
        }
    }

    // Opening Wham again (Finder, Spotlight, `open -a Wham`) shows where it is.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hello()
        return false
    }

    private func hello() {
        guard let button = item.button, let window = button.window, window.occlusionState.contains(.visible),
              window.screen?.frame.contains(window.frame) == true else {
            return alert("Wham is running, but its switch has no room in the menu bar (too many icons, or the notch). "
                + "Hold ⌘ and drag a few other icons out of the menu bar to make room for it.")
        }
        pop(Toast.hello)
    }

    // Shows a pill under the switch. The evals read what it said.
    private func pop(_ style: Toast.Style) {
        guard let button = item.button, let window = button.window else { return }
        toast.show(style, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
        print("toast \(style.title): \(style.caption)")
        fflush(stdout)
    }

    // Opened from the disk image (or from Downloads, which macOS runs from a
    // hidden copy), Wham could not open at login. Offers to move it.
    private static var runsFromTemporaryCopy: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    private func offerToMove() -> Bool {
        let ask = NSAlert()
        ask.messageText = "Move Wham to Applications?"
        ask.informativeText = "Wham is running from the disk image. From Applications it can open at login and stay in your menu bar."
        ask.addButton(withTitle: "Move to Applications")
        ask.addButton(withTitle: "Not Now")
        activate()
        guard ask.runModal() == .alertFirstButtonReturn else { return false }
        let files = FileManager.default
        let folder = files.isWritableFile(atPath: "/Applications")
            ? URL(fileURLWithPath: "/Applications") : files.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let destination = folder.appendingPathComponent("Wham.app")
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
            try files.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            alert("Wham could not move itself: \(error.localizedDescription). Drag it into Applications instead.")
            return false
        }
        // This copy already passed Gatekeeper; without the flag it opens from Applications for real.
        Sleep.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    // A few times a day, and not right at login, while the network wakes up.
    private func scheduleUpdates() {
        guard !Self.runsFromTemporaryCopy else { return }
        let delay = UserDefaults.standard.double(forKey: "updateDelay")
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay > 0 ? delay : 60)) { self.checkForUpdate() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdate() }
        }
        updateTimer?.tolerance = 1800
    }

    // Asks GitHub for the latest version. A newer one is installed when Wham
    // updates automatically or someone asked from the menu, and otherwise
    // offered in the menu.
    private func checkForUpdate(asked: Bool = false) {
        if asked { self.asked = true }
        guard !updating else { return }
        updating = true
        let app = Bundle.main.bundleURL, running = running
        DispatchQueue.global(qos: .utility).async {
            let latest = Update.latest()
            let newer = latest.flatMap { Update.isNewer($0, than: running) ? $0 : nil }
            let replaceable = newer != nil && Update.canReplace(app)
            Self.onMain { self.found(latest, newer: newer, replaceable: replaceable) }
        }
    }

    // Back on the main thread, menu open or not: a menu opened from the main
    // queue holds that queue until it closes, while the run loop goes on.
    nonisolated private static func onMain(_ work: @escaping @MainActor () -> Void) {
        let loop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { MainActor.assumeIsolated { work() } }
        CFRunLoopWakeUp(loop)
    }

    // After a delay, menu open or not (see onMain).
    private static func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        RunLoop.main.add(Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated { work() } }, forMode: .common)
    }

    private func found(_ latest: String?, newer: String?, replaceable: Bool) {
        if latest != nil { available = newer }
        guard let newer else {
            return settle(latest == nil ? ("CAN'T CHECK", "GitHub did not answer, try again later", .said(Line.noAnswer))
                                        : ("UP TO DATE", "Wham \(running) is the latest", .done(Line.latest(running))))
        }
        guard asked || Update.isOn else { return settle(nil) }
        // Not in a folder its user may write to, or a build from source: the
        // download is on wham.sh.
        guard replaceable else { return settle(("CAN'T UPDATE ITSELF", "Get Wham \(newer) at wham.sh", nil), openSite: true) }
        installing = newer
        if let updateRow {
            updateRow.state = updateState
        } else if asked {
            pop(Toast.note("UPDATING", "To Wham \(newer), back in a moment"))
        }
        let app = Bundle.main.bundleURL
        DispatchQueue.global(qos: .utility).async {
            let installed = Update.install(newer, over: app)
            Self.onMain {
                installed ? self.reopen() : self.settle(("CAN'T UPDATE", "Wham \(newer) did not install, try again later", .said(Line.failed(newer))))
            }
        }
    }

    // The check is over: tells whoever asked from the menu how it went, in
    // its row if the menu is still open (and the row has words for it),
    // otherwise in a pill.
    private func settle(_ note: (title: String, caption: String, row: UpdateRow.State?)?, openSite: Bool = false) {
        updating = false
        installing = nil
        let told = asked
        asked = false
        guard told, let note else {
            updateRow?.state = updateState
            return
        }
        if let updateRow, let row = note.row {
            updateRow.state = row
            return
        }
        updateRow?.enclosingMenuItem?.menu?.cancelTracking()
        pop(Toast.note(note.title, note.caption))
        if openSite { self.openSite() }
    }

    // The new copy opens once this one is gone. Leaving without the quit
    // handler keeps the switch as it is: on stays on, through the update.
    private func reopen() {
        guard !busy else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.reopen() }
            return
        }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open \"$0\"",
                              Bundle.main.bundlePath]
        guard (try? relaunch.run()) != nil else { return }
        watchdog.standDown()
        exit(0)
    }

    // Quitting gives sleep back, whoever asks: the menu, a script, logging out.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !sleepGivenBack && Sleep.isDisabled == true && Sleep.set(false) {
            let defaults = UserDefaults.standard
            if poweringOff || Self.quitToPowerOff {
                // A restart, a shutdown or a logout: on again at the next login
                // with Stay On After Restart, until the session's end if timed.
                if Self.staysOnAfterRestart { defaults.set(offAt ?? true as Any, forKey: "resumeAtLogin") }
            } else {
                // Quit by someone else while on. `brew upgrade` quits the old copy and
                // opens the new one right away: that one turns back on.
                defaults.set(Date().addingTimeInterval(60), forKey: "resumeBefore")
            }
        }
        if Sleep.isDisabled != true { watchdog.standDown() }
        return .terminateNow
    }

    // The reason macOS gives with its quit event, when it quits the apps to
    // restart, shut down or log out.
    private static var quitToPowerOff: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let why = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown].map { OSType($0) }.contains(why)
    }

    // Stay On After Restart, off by default: a Mac restarted and then put in
    // a bag should sleep. The Mac had restarted, shut down or logged out with
    // Wham on; it turns back on, unless its timed session ended meanwhile.
    private static var staysOnAfterRestart: Bool {
        get { UserDefaults.standard.bool(forKey: "stayOnAfterRestart") }
        set { UserDefaults.standard.set(newValue, forKey: "stayOnAfterRestart") }
    }

    private func resumeAfterRestart(_ saved: Any?) {
        guard let saved else { return }
        UserDefaults.standard.removeObject(forKey: "resumeAtLogin")
        let until = saved as? Date
        guard Self.staysOnAfterRestart, until.map({ $0 > Date() }) ?? true, Sleep.isDisabled == false, !refuses() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard Sleep.set(true) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.setOffAt(until)
                    self.show(true)
                    self.announce(true, caption: until.map { "Back on after the restart, until \(Session.clock($0))" } ?? "Back on after the restart")
                    self.check()
                }
            }
        }
    }

    private func resumeAfterUpdate() {
        guard let deadline = UserDefaults.standard.object(forKey: "resumeBefore") as? Date else { return }
        UserDefaults.standard.removeObject(forKey: "resumeBefore")
        guard deadline > Date() && Sleep.isDisabled == false else { return }
        // `sudo -n` never prompts: without the rule this quietly does nothing.
        DispatchQueue.global(qos: .userInitiated).async {
            guard Sleep.set(true) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.show(true); self.announce(true); self.check() } }
        }
    }

    private func show(_ state: Bool?) {
        if state == true { drain() }
        toggleView.show(state, animated: true)
        let tip: String
        switch state {
        case true? where offAt != nil:
            tip = "Wham is on until \(Session.clock(offAt!)): your Mac stays awake, even with the lid closed. Click to turn off."
        case true?: tip = "Wham is on: your Mac stays awake, even with the lid closed. Click to turn off."
        case false?: tip = "Wham is off: your Mac sleeps as usual. Click to turn on."
        case nil: tip = "Wham can't read your Mac's sleep setting"
        }
        item.button?.setAccessibilityLabel(tip)
        item.button?.toolTip = tip
    }

    // On every change: the tick, the power source, the heat, the lid, the
    // `wham` command. Shows the kernel's state and, while on, ends the session
    // if its time, the battery or the heat says so.
    private func check() {
        guard !busy else { return }
        let state = Sleep.isDisabled
        if !toggleView.hasShown || state != toggleView.state { show(state) }
        let lidClosed = Sleep.lidClosed
        defer { lidWasClosed = lidClosed }
        guard state == true else {
            watchdog.standDown()
            if offAt != nil { setOffAt(nil) }
            return
        }
        watchdog.arm()
        let reading = Session.read(offAt: offAt)
        if let end = Session.end(reading) { return stop(end, battery: reading.battery) }
        drain()
        if lidClosed && !lidWasClosed { sleepScreenSoon() }
    }

    // The switch's candy, as much of it as the timed session has left.
    private func drain() {
        toggleView.drain(CGFloat(Session.remaining(from: onAt, to: offAt)), animated: true)
    }

    private func stop(_ end: Session.End, battery: Int?) {
        let why = Session.why(end, battery: battery)
        ended = (why, Date())
        setOffAt(nil)
        change(to: false, mayInstall: false, caption: why)
    }

    // Low battery or a hot Mac: says so instead of turning on.
    private func refuses() -> Bool {
        let reading = Session.read(offAt: nil)
        guard let end = Session.end(reading) else { return false }
        announce(false, caption: Session.refusal(end, battery: reading.battery))
        return true
    }

    // From now until `date`, or untimed (nil).
    private func setOffAt(_ date: Date?) {
        Session.setEnd(date)
        offAt = Session.offAt
        onAt = Session.onAt
        scheduleEnd()
    }

    // On time even while macOS naps the app; the tick is the backstop.
    private func scheduleEnd() {
        endTimer?.invalidate()
        warnTimer?.invalidate()
        endTimer = nil
        warnTimer = nil
        guard let offAt else { return }
        endTimer = at(offAt) { $0.check() }
        if let warnAt = Session.warnAt(from: onAt, to: offAt), warnAt > Date() {
            warnTimer = at(warnAt) { $0.warn() }
        }
    }

    private func at(_ date: Date, _ action: @escaping @MainActor (Wham) -> Void) -> Timer {
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // Five minutes before a timed session ends, a pill says so, without a
    // sound: time to pick another length, or No Time Limit. Not to a closed lid.
    private func warn() {
        guard let offAt, Sleep.isDisabled == true, !Sleep.lidClosed, offAt > Date() else { return }
        pop(Toast.soon.saying("Then back to normal sleep, at \(Session.clock(offAt))"))
    }

    // A few seconds after the lid closes, so a monitor plugged into a closed
    // MacBook has taken over first, if there is one.
    private func sleepScreenSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard Sleep.isDisabled == true, Sleep.lidClosed, Screen.builtInAloneAndLit else { return }
            DispatchQueue.global(qos: .utility).async { Screen.sleep() }
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    // Opened under the switch rather than through the button, which would
    // light up the menu bar's highlight around the switch while it is open. It
    // hangs from the menu bar's bottom edge, as a status menu does: any higher
    // and macOS tucks its first line behind a scroll arrow, which the switch's
    // own frame would do on a Mac with a notch, where the menu bar is taller.
    // The point given is the first line's top, 5 points inside the menu.
    private func showMenu(_ menu: NSMenu? = nil) {
        guard let button = item.button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let bar = min(window.frame.minY, window.screen?.visibleFrame.maxY ?? window.frame.minY)
        (menu ?? self.menu()).popUp(positioning: nil, at: NSPoint(x: frame.minX, y: bar - 6), in: nil)
    }

    private func menu() -> NSMenu {
        let on = Sleep.isDisabled == true
        let menu = NSMenu()
        let line: String
        if on, let offAt {
            line = "Mac stays awake until \(Session.clock(offAt)) (\(Session.timeLeft(offAt.timeIntervalSinceNow)) left)"
        } else if on {
            line = "Mac stays awake, even with the lid closed"
        } else if let ended {
            line = "\(ended.why), stopped at \(Session.clock(ended.at))"
        } else {
            line = "Mac sleeps as usual"
        }
        let status = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem(title: on ? "Turn Off" : "Turn On", action: #selector(toggle), keyEquivalent: ""))
        let timed = NSMenuItem(title: on ? "Stay Awake For" : "Turn On For", action: nil, keyEquivalent: "")
        timed.submenu = lengths(on: on)
        menu.addItem(timed)
        menu.addItem(.separator())
        let sound = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        sound.state = muted ? .off : .on
        menu.addItem(sound)
        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearance.submenu = appearances()
        menu.addItem(appearance)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(login)
        let restart = NSMenuItem(title: "Stay On After Restart", action: #selector(toggleRestart), keyEquivalent: "")
        restart.state = Self.staysOnAfterRestart ? .on : .off
        restart.toolTip = "If Wham is on when your Mac restarts, it turns back on when you log in."
        menu.addItem(restart)
        let updates = NSMenuItem(title: "Update Automatically", action: #selector(toggleUpdates), keyEquivalent: "")
        updates.state = Update.isOn ? .on : .off
        menu.addItem(updates)
        let limit = NSMenuItem(title: "Battery Limit", action: nil, keyEquivalent: "")
        limit.submenu = batteryLimits()
        menu.addItem(limit)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About Wham \(CLI.version)", action: #selector(openSite), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "What's New", action: #selector(openChangelog), keyEquivalent: ""))
        menu.addItem(updateItem())
        menu.addItem(NSMenuItem(title: "Made by Gwendall", action: #selector(openAuthor), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wham (lets your Mac sleep)", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items { entry.target = self }
        menu.delegate = self
        return menu
    }

    // Check for Updates, or the new version Wham found and did not install,
    // as a row that keeps the menu open when clicked. Its action is for the
    // keyboard: Return closes the menu, and a pill says how it went.
    private func updateItem() -> NSMenuItem {
        // As wide as its widest line, with any version found while the menu is open.
        let row = UpdateRow(updateState, width: UpdateRow.width(for: Line.all(running: running, found: available ?? "10.10.10")))
        row.onClick = { [weak self, weak row] in
            guard let self else { return }
            self.checkForUpdate(asked: true)
            row?.state = self.updateState
        }
        row.onChange = { print("row \($0)"); fflush(stdout) }
        let entry = NSMenuItem(title: row.title, action: #selector(checkNow), keyEquivalent: "")
        entry.view = row
        return entry
    }

    private var updateState: UpdateRow.State {
        if let installing { return .busy(Line.updating(to: installing)) }
        if updating { return .busy(Line.checking) }
        return .action(available.map { Line.update(to: $0) } ?? Line.check)
    }

    // What the update row says, each line written once.
    private enum Line {
        static let check = "Check for Updates"
        static let checking = "Checking for Updates…"
        static let noAnswer = "Can't check now, try later"
        static func update(to version: String) -> String { "Update to Wham \(version)" }
        static func updating(to version: String) -> String { "Updating to Wham \(version)…" }
        static func latest(_ version: String) -> String { "Wham \(version) is up to date" }
        static func failed(_ version: String) -> String { "Wham \(version) did not install" }
        static func all(running: String, found: String) -> [String] {
            [check, checking, noAnswer, update(to: found), updating(to: found), latest(running), failed(found)]
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateRow = menu.items.lazy.compactMap { $0.view as? UpdateRow }.first
    }

    func menuDidClose(_ menu: NSMenu) {
        updateRow = nil
    }

    // The row draws the menu's selection itself.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        updateRow?.highlighted = item?.view === updateRow
    }

    // 1, 2, 4 or 8 hours from now, each with the time it would end on the
    // right, in gray; and, in a timed session, a way back to no end at all.
    private func lengths(on: Bool) -> NSMenu {
        let lengths = NSMenu()
        let now = Date()
        let entries = [1, 2, 4, 8].map { hours in
            (hours, hours == 1 ? "1 Hour" : "\(hours) Hours", Session.clock(now.addingTimeInterval(TimeInterval(hours) * 3600), now: now))
        }
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let stop = (entries.map { width($0.1) }.max() ?? 0) + 24 + (entries.map { width($0.2) }.max() ?? 0)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: stop)]
        for (hours, title, end) in entries {
            let entry = NSMenuItem(title: title, action: #selector(stayAwake(_:)), keyEquivalent: "")
            let text = NSMutableAttributedString(string: "\(title)\t", attributes: [.font: font, .paragraphStyle: style])
            text.append(NSAttributedString(string: end, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor]))
            entry.attributedTitle = text
            entry.tag = hours
            entry.target = self
            lengths.addItem(entry)
        }
        if on && offAt != nil {
            lengths.addItem(.separator())
            let forever = NSMenuItem(title: "No Time Limit", action: #selector(noTimeLimit), keyEquivalent: "")
            forever.target = self
            lengths.addItem(forever)
        }
        return lengths
    }

    // Monochrome and Compact, each on its own.
    private func appearances() -> NSMenu {
        let looks = NSMenu()
        let monochrome = NSMenuItem(title: "Monochrome", action: #selector(toggleMonochrome), keyEquivalent: "")
        monochrome.state = look.monochrome ? .on : .off
        monochrome.toolTip = "In the menu bar's own color, like the icons around it."
        let compact = NSMenuItem(title: "Compact", action: #selector(toggleCompact), keyEquivalent: "")
        compact.state = look.compact ? .on : .off
        compact.toolTip = "As wide as an icon: the switch turns instead of sliding."
        for entry in [monochrome, compact] {
            entry.target = self
            looks.addItem(entry)
        }
        return looks
    }

    private var look: SwitchView.Look {
        get { SwitchView.Look(monochrome: UserDefaults.standard.bool(forKey: "monochrome"), compact: UserDefaults.standard.bool(forKey: "compact")) }
        set {
            UserDefaults.standard.set(newValue.monochrome, forKey: "monochrome")
            UserDefaults.standard.set(newValue.compact, forKey: "compact")
            toggleView.setLook(newValue)
            item.length = toggleView.itemLength
        }
    }

    @objc private func toggleMonochrome() { look.monochrome.toggle() }
    @objc private func toggleCompact() { look.compact.toggle() }
    @objc private func toggleRestart() { Self.staysOnAfterRestart.toggle() }

    // On battery, the charge at which Wham lets the Mac sleep.
    private func batteryLimits() -> NSMenu {
        let limits = NSMenu()
        let header = NSMenuItem(title: "Sleep on battery at", action: nil, keyEquivalent: "")
        header.isEnabled = false
        limits.addItem(header)
        for percent in Session.batteryLimits {
            let entry = NSMenuItem(title: "\(percent)%", action: #selector(setBatteryLimit(_:)), keyEquivalent: "")
            entry.tag = percent
            entry.state = percent == Session.batteryLimit ? .on : .off
            entry.target = self
            limits.addItem(entry)
        }
        return limits
    }

    // For the evals: once launched, presses menu items by title, one after the
    // other, as WHAM_PRESS lists them: "Turn On For/2 Hours,Turn Off". "Switch"
    // is a click on the switch, "Terminate" a quit from outside (an upgrade),
    // "Restart" the quit macOS sends before a restart, "Menu" opens the menu
    // for real and says whether it showed whole, "Click Updates" opens it and
    // clicks Check for Updates as a mouse would, "Status" prints the menu's
    // first line and its lengths, "Items" the menu's items, "Look" the
    // appearance and the status item's width, and "Pause" waits a step.
    private func pressForEvals() {
        guard let list = ProcessInfo.processInfo.environment["WHAM_PRESS"] else { return }
        var steps = list.split(separator: ",").map { $0.split(separator: "/").map(String.init) }
        func next() {
            guard !steps.isEmpty else { return }
            guard !busy else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { next() } }
            let path = steps.removeFirst()
            switch path {
            case ["Switch"]: toggle()
            case ["Terminate"]: NSApp.terminate(nil)
            case ["Restart"]:
                poweringOff = true
                NSApp.terminate(nil)
            case ["Look"]:
                print("look", look.monochrome ? "monochrome" : "color", look.compact ? "compact" : "wide", Int(item.length))
                fflush(stdout)
            case ["Pause"]: break
            case ["Items"]:
                print("items", self.menu().items.map { $0.isSeparatorItem ? "-" : $0.title }.joined(separator: " | "))
                fflush(stdout)
            case ["Status"]:
                let menu = self.menu()
                let lengths = menu.items.first { $0.submenu != nil }?.submenu?.items ?? []
                print("status", menu.items.first?.title ?? "")
                print("lengths", lengths.map { $0.isSeparatorItem ? "-" : $0.attributedTitle?.string ?? $0.title }.joined(separator: " | "))
                fflush(stdout)
            case ["Menu"]:
                let menu = self.menu()
                perform(#selector(lookAt(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            case ["Click Updates"]:
                let menu = self.menu()
                perform(#selector(clickUpdates(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            default:
                var entry: NSMenuItem?, menu: NSMenu? = self.menu()
                // A length's title also carries its end time, after a tab.
                for title in path {
                    entry = menu?.items.first { $0.title == title || $0.title.hasPrefix(title + "\t") }
                    menu = entry?.submenu
                }
                if let entry, let action = entry.action { NSApp.sendAction(action, to: entry.target, from: entry) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
    }

    // The open menu's window against the menu's own height, then closes it.
    @objc private func lookAt(_ menu: NSMenu) {
        let shown = NSApp.windows.first { $0.isVisible && $0.className.contains("Menu") }
        print("menu", shown.map { $0.frame.height >= menu.size.height ? "whole" : "cut, \(Int($0.frame.height)) of \(Int(menu.size.height)) points" } ?? "missing")
        fflush(stdout)
        menu.cancelTracking()
    }

    // Clicks Check for Updates in the open menu, follows its row until the
    // check is over, says whether the menu stayed open, then closes it. On the
    // way it says where the row's title starts against the row above's, in
    // the menu as drawn, and with WHAM_SHOTS saves the menu at each step there.
    // The menu goes by where the pointer really is: it moves onto the row for
    // the click, then back.
    @objc private func clickUpdates(_ menu: NSMenu) {
        guard let row = updateRow, let window = row.window else {
            print("row missing")
            fflush(stdout)
            return menu.cancelTracking()
        }
        let shots = ProcessInfo.processInfo.environment["WHAM_SHOTS"]
        func shoot(_ name: String) -> CGImage? {
            let image = Self.picture(of: window)
            if let shots, let image {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
            }
            return image
        }
        let frame = row.convert(row.bounds, to: nil)
        let measures = row.measures
        print("row title at x \(measures.x), \(measures.height) points tall; the menu's at x \(measures.menuX.map { "\($0)" } ?? "-"), \(measures.menuHeight.map { "\($0)" } ?? "-") tall")
        if let image = shoot("1-idle") {
            let above = frame.offsetBy(dx: 0, dy: frame.height)
            if Self.screenShows {
                let mine = Self.ink(in: image, of: window, at: frame), theirs = Self.ink(in: image, of: window, at: above)
                print("ink starts at x", theirs.map { "\($0.x)" } ?? "-", "above,", mine.map { "\($0.x)" } ?? "-", "in the row;",
                      "contrast", theirs.map { String(format: "%.3f", $0.contrast) } ?? "-", "above,", mine.map { String(format: "%.3f", $0.contrast) } ?? "-", "in the row")
            } else {
                print("ink not drawn: the screen is locked or asleep")
            }
        }
        fflush(stdout)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let home = CGEvent(source: nil)?.location
        let onScreen = window.convertPoint(toScreen: center)
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y))
        func post(_ type: NSEvent.EventType) {
            guard let event = NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                 pressure: type == .leftMouseDown ? 1 : 0) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        post(.mouseMoved)
        // A busy Mac takes a while to highlight the row: the click waits for it.
        var waited = 0.0
        @MainActor func hovered() {
            if !row.highlighted, waited < 5 {
                waited += 0.1
                return Self.after(0.1) { hovered() }
            }
            print("row highlighted", row.highlighted)
            _ = shoot("2-highlighted")
            post(.leftMouseDown)
            post(.leftMouseUp)
            waited = 0
            Self.after(0.4) {
                _ = shoot("3-busy")
                over()
            }
        }
        @MainActor func over() {
            if case .busy = row.state, waited < 15 {
                waited += 0.2
                return Self.after(0.2) { over() }
            }
            // The picture once the menu has drawn the answer.
            Self.after(0.3) {
                _ = shoot("4-told")
                print("menu", window.isVisible ? "still open" : "closed")
                fflush(stdout)
                menu.cancelTracking()
                if let home { CGWarpMouseCursorPosition(home) }
            }
        }
        Self.after(0.2) { hovered() }
    }

    // A window of this app as drawn, which needs no permission. Called by
    // name: the SDK no longer lets Swift call it, the system still answers.
    private static func picture(of window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        // Just this window, without its shadow, at the screen's resolution.
        return unsafeBitCast(symbol, to: Create.self)(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue()
    }

    // Nothing is drawn while the screen is locked or asleep.
    private static var screenShows: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return CGDisplayIsAsleep(CGMainDisplayID()) == 0 && session?["CGSSessionScreenIsLocked"] as? Bool != true
    }

    // Where the first column of text starts in a row of a picture of the
    // window, in points (the first pixel that differs from the row's
    // background, taken three quarters of the way across), and how far its
    // text gets from that background, from 0 to 1 (black on white).
    private static func ink(in image: CGImage, of window: NSWindow, at row: NSRect) -> (x: CGFloat, contrast: Double)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(image.width) / window.frame.width
        let top = Int((window.frame.height - row.maxY + 3) * scale), bottom = Int((window.frame.height - row.minY - 3) * scale)
        guard top >= 0, bottom < image.height, top < bottom else { return nil }
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let at = y * image.bytesPerRow + x * image.bitsPerPixel / 8
            return (Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2]))
        }
        let background = pixel(Int(row.width * 0.75 * scale), (top + bottom) / 2)
        var first: CGFloat?, contrast = 0
        for x in Int(8 * scale)..<Int(row.width * 0.75 * scale) {
            for y in top...bottom {
                let p = pixel(x, y)
                let distance = abs(p.0 - background.0) + abs(p.1 - background.1) + abs(p.2 - background.2)
                guard distance > 90 else { continue }
                if first == nil { first = CGFloat(x) / scale }
                contrast = max(contrast, distance)
            }
        }
        return first.map { ($0, Double(contrast) / 765) }
    }

    @objc private func toggleSound() { muted.toggle() }

    @objc private func toggleUpdates() {
        Update.isOn.toggle()
        if Update.isOn { checkForUpdate() }
    }

    @objc private func checkNow() { checkForUpdate(asked: true) }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isOn)
        } catch {
            alert("Wham could not change its login item: \(error.localizedDescription)")
        }
    }

    @objc private func openSite() { NSWorkspace.shared.open(URL(string: "https://wham.sh")!) }
    @objc private func openChangelog() { NSWorkspace.shared.open(URL(string: "https://wham.sh/changelog")!) }
    @objc private func openAuthor() { NSWorkspace.shared.open(URL(string: "https://gwendall.com")!) }

    // The pill under the switch says the new state in words, with its sound
    // (not from under a closed lid).
    private func announce(_ on: Bool, caption: String? = nil) {
        let style = on ? Toast.on : Toast.off
        pop(caption.map(style.saying) ?? style)
        guard !muted, !Sleep.lidClosed, let sound = sounds[on] ?? nil else { return }
        sound.stop()
        sound.play()
    }

    @objc private func toggle() {
        guard !busy else { return }
        guard let current = Sleep.isDisabled else {
            return alert("Wham can't read your Mac's sleep setting.")
        }
        if !current && refuses() { return }
        ended = nil
        setOffAt(nil)
        change(to: !current, mayInstall: true)
    }

    // "Turn On For" and "Stay Awake For": from now, for that many hours.
    @objc private func stayAwake(_ sender: NSMenuItem) {
        guard !busy, let current = Sleep.isDisabled else { return }
        if !current && refuses() { return }
        let until = Date().addingTimeInterval(TimeInterval(sender.tag) * 3600)
        ended = nil
        setOffAt(until)
        let caption = "Until \(Session.clock(until))"
        if current {
            show(true)
            announce(true, caption: caption)
        } else {
            change(to: true, mayInstall: true, caption: caption)
        }
    }

    // In a timed session: no end, the Mac stays awake until turned off.
    @objc private func noTimeLimit() {
        guard !busy, Sleep.isDisabled == true else { return }
        setOffAt(nil)
        show(true)
        announce(true, caption: "Until you turn it off")
    }

    // A new limit counts at once: on battery under it, the session ends.
    @objc private func setBatteryLimit(_ sender: NSMenuItem) {
        Session.batteryLimit = sender.tag
        check()
    }

    // The switch moves on the click, then pmset runs off the main thread. If the
    // Mac refuses, the switch slides back to the kernel's state.
    private func change(to target: Bool, mayInstall: Bool, caption: String? = nil) {
        show(target)
        announce(target, caption: caption)
        apply(target, mayInstall: mayInstall)
    }

    private func apply(_ target: Bool, mayInstall: Bool) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Sleep.set(target)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(target, ok: ok, mayInstall: mayInstall) }
            }
        }
    }

    private func finish(_ target: Bool, ok: Bool, mayInstall: Bool) {
        busy = false
        if ok { return check() }
        guard mayInstall && !Sleep.hasRule else {
            revert(from: target)
            return alert(target ? "Your Mac refused the setting: it can still go to sleep." : "Your Mac refused: sleep is still blocked.")
        }
        switch Sleep.installRule() {
        case .done: apply(target, mayInstall: false)
        case .cancelled: revert(from: target)
        case .failed(let message):
            revert(from: target)
            alert("Permission not installed: \(message)")
        }
    }

    private func revert(from target: Bool) {
        let actual = Sleep.isDisabled
        show(actual)
        if let actual, actual != target { announce(actual) }
    }

    @objc private func quit() {
        if Sleep.isDisabled == true && !Sleep.set(false) {
            return alert("Your Mac refused to allow sleep again, so Wham stays open.")
        }
        sleepGivenBack = true
        NSApp.terminate(nil)
    }

    private func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Wham"
        alert.informativeText = text
        activate()
        alert.runModal()
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}

// Open at login: SMAppService from macOS 13 on, a LaunchAgent before. When
// macOS holds the item for approval (System Settings > Login Items), turning
// it on opens that page.
enum LoginItem {
    private static let agent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/sh.wham.app.plist")

    static var isOn: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agent.path)
    }

    static func set(_ on: Bool) throws {
        if #available(macOS 13, *) {
            if !on { return try SMAppService.mainApp.unregister() }
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } else if on {
            let plist: [String: Any] = ["Label": "sh.wham.app", "ProgramArguments": ["/usr/bin/open", "-b", "sh.wham.app"], "RunAtLoad": true]
            try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent)
        } else {
            try FileManager.default.removeItem(at: agent)
        }
    }
}
