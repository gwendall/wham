import AppKit
import ServiceManagement

// The menu bar app. A click flips the switch; a right-click (or control-click)
// opens the menu.
@MainActor
final class Wham: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleView = SwitchView()
    private let toast = Toast()
    // Each made the first time it plays: CoreAudio stays unloaded until there
    // is something to play. The one playing, which the next one cuts, and the
    // last one asked for, which the evals read.
    private var sounds: [Chime.Sound: NSSound] = [:]
    private var playing: NSSound?
    private var heard: Chime.Sound?
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
    // The menu while it is open: a click on one of its options changes it
    // and the menu stays, showing the new state, so it is kept in step with
    // Wham until it closes. What waits for it to close (a password prompt,
    // an alert), and a refusal it says in its first line meanwhile, since
    // the pills hide behind an open menu.
    private weak var openMenu: NSMenu?
    private var afterMenu: [@MainActor () -> Void] = []
    private var said: String?
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
    // For the evals' "Film": each frame of a change of look, when it was
    // drawn, the status item's width and how monochrome the switch was.
    private var film: [(time: CFTimeInterval, length: CGFloat, mono: CGFloat)]?
    // The menus open now, submenus too, as their delegate hears it: a
    // submenu's window just closed can still say it is visible.
    private var shownMenus: Set<ObjectIdentifier> = []
    // When Wham last brought the open menu in step, and when a submenu last
    // closed: the click eval's trail says whether one follows the other.
    private var refreshedAt = Date.distantPast, submenuClosedAt = Date.distantPast
    private var filmed = ""
    private var lidWasClosed = false
    // Set when macOS says it is about to restart, shut down or log out.
    private var poweringOff = false
    // For the journal: the flag as last seen, the power and the heat as
    // last read, and the network while on.
    private var seenFlag: Bool??
    private var sensed: Sensed?
    private let connectivity = Connectivity()
    private var sampleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched()
        if Self.runsFromTemporaryCopy && offerToMove() { return }
        guard let button = item.button else { return }
        toggleView.setLook(look, animated: false)
        item.length = toggleView.itemLength
        // A change of look moves the status item's width with it, frame by frame.
        toggleView.onFrame = { [weak self] in self?.lookMoved() }
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
            Journal.note("system", ["event": "power-off"])
        }
        // The Mac's sleep and its screens', for the journal: a Mac that sleeps
        // while Wham is on is what the journal is there to catch.
        let system: [(NSNotification.Name, String)] = [(NSWorkspace.willSleepNotification, "sleep"), (NSWorkspace.didWakeNotification, "wake"),
                                                       (NSWorkspace.screensDidSleepNotification, "screens-sleep"), (NSWorkspace.screensDidWakeNotification, "screens-wake")]
        for (name, event) in system {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Journal.note("system", ["event": event, "flag": Self.flagWord(Sleep.isDisabled), "lid": Sleep.lidClosed ? "closed" : "open"])
            }
        }
        // Catches anything else flipping the flag (`wham on` in a terminal, pmset,
        // a reboot). The tolerance lets macOS batch these wakeups with others.
        // In the menu's mode too: an open menu follows the time left.
        let tick = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
                self?.refreshMenu()
            }
        }
        tick.tolerance = 1
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        watch = Watch { [weak self] in
            self?.sense()
            self?.check()
        }
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
                let set = try? LoginItem.set(true)
                Journal.note("setting", ["open-at-login": set != nil, "approval": set == false ? "asked" : nil, "first-launch": true])
                if set == false { LoginItem.askForApproval() }
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

    // The journal's first lines: this run, the Mac, the settings, and how the
    // run before ended when it did not quit.
    private func launched() {
        let previous = Journal.markRunning()
        let reading = Session.read(offAt: nil)
        sensed = Sensed(reading)
        let flag = Sleep.isDisabled
        seenFlag = .some(flag)
        let defaults = UserDefaults.standard
        let resume: String? = defaults.object(forKey: "resumeAtLogin") != nil ? "after restart"
            : defaults.object(forKey: "resumeBefore") != nil ? "after quit from outside" : nil
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        Journal.note("launch", ["version": running, "build": build, "macos": Machine.macOS, "arch": Machine.arch, "model": Machine.model,
                                "path": Bundle.main.bundlePath, "booted": Machine.booted, "flag": Self.flagWord(flag), "rule": Sleep.hasRule,
                                "lid": Sleep.lidClosed ? "closed" : "open", "displays": Screen.count,
                                "power": reading.onBattery ? "battery" : "ac", "battery": reading.battery, "heat": Self.heatWord,
                                "session-end": Session.offAt, "resume": resume])
        Journal.note("settings", ["sound": !muted, "monochrome": look.monochrome, "compact": look.compact, "open-at-login": LoginItem.isOn,
                                  "stay-on-after-restart": Self.staysOnAfterRestart, "update-automatically": Update.isOn,
                                  "battery-limit": Self.limitWord])
        if let previous {
            Journal.note("previous-run", ["ended": "without quitting", "started": previous, "crash-report": Journal.crashReport(since: previous)])
        }
    }

    // The words the journal uses.
    nonisolated private static func flagWord(_ state: Bool?) -> String { state.map { $0 ? "on" : "off" } ?? "unreadable" }

    private static var limitWord: String {
        Session.batteryLimit == Session.never ? "never" : "\(Session.batteryLimit)%"
    }

    private static var heatWord: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // The power source, the battery by steps of 5% while on it, the heat: a
    // line in the journal when one of them changes, as macOS says (Watch).
    private func sense() {
        let reading = Session.read(offAt: nil)
        let now = Sensed(reading)
        let before = sensed
        sensed = now
        guard let before, now != before else { return }
        if now.onBattery != before.onBattery {
            Journal.note("power", ["source": now.onBattery ? "battery" : "ac", "battery": reading.battery])
        } else if now.onBattery && now.step != before.step {
            Journal.note("battery", ["level": reading.battery, "limit": Self.limitWord, "flag": Self.flagWord(Sleep.isDisabled)])
        }
        if now.thermal != before.thermal || now.pressure != before.pressure || now.critical != before.critical {
            Journal.note("heat", ["state": Self.heatWord, "pressure": Heat.level, "critical": reading.critical])
        }
    }

    // The lid, with the screens connected, and with Wham on, the Wi-Fi as
    // it is then.
    private func lidMoved(_ closed: Bool, on: Bool) {
        Journal.note("lid", ["closed": closed, "displays": Screen.count, "flag": Self.flagWord(Sleep.isDisabled)])
        if on { connectivity.sample(closed ? "lid-closed" : "lid-opened") }
    }

    // Every ten minutes while the Mac stays awake under its closed lid.
    private func sampleWhileClosed(_ on: Bool) {
        sampleTimer?.invalidate()
        sampleTimer = nil
        guard on else { return }
        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectivity.sample("lid-closed") }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func hello() {
        guard let button = item.button, let window = button.window, window.occlusionState.contains(.visible),
              window.screen?.frame.contains(window.frame) == true else {
            return alert("Wham is running, but its switch has no room in the menu bar (too many icons, or the notch). "
                + "Hold ⌘ and drag a few other icons out of the menu bar to make room for it.")
        }
        pop(Toast.hello)
    }

    // Shows a pill under the switch, unless the menu is open: the menu hides
    // it, and shows what changed itself. The evals read what it said.
    private func pop(_ style: Toast.Style) {
        guard let button = item.button, let window = button.window else { return }
        if openMenu == nil { toast.show(style, under: window.convertToScreen(button.convert(button.bounds, to: nil))) }
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
        guard ask.runModal() == .alertFirstButtonReturn else {
            Journal.note("move", ["answer": "not now"])
            return false
        }
        let files = FileManager.default
        let folder = files.isWritableFile(atPath: "/Applications")
            ? URL(fileURLWithPath: "/Applications") : files.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let destination = folder.appendingPathComponent("Wham.app")
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
            try files.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            Journal.note("move", ["to": folder.path, "ok": false, "error": error.localizedDescription])
            alert("Wham could not move itself: \(error.localizedDescription). Drag it into Applications instead.")
            return false
        }
        Journal.note("move", ["to": folder.path, "ok": true])
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
            let (latest, failure) = Update.latest()
            let newer = latest.flatMap { Update.isNewer($0, than: running) ? $0 : nil }
            let replaceable = newer != nil && Update.canReplace(app)
            Self.onMain {
                Journal.note("update-check", ["asked": self.asked, "latest": latest, "failure": failure, "newer": newer != nil,
                                              "replaceable": newer == nil ? nil : replaceable, "automatic": Update.isOn])
                self.found(latest, newer: newer, replaceable: replaceable)
            }
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
            return settle(latest == nil ? ("CAN'T CHECK", "GitHub did not answer, try again later", .said(Line.noAnswer), .refused)
                                        : ("UP TO DATE", "Wham \(running) is the latest", .done(Line.latest(running)), .check(true)))
        }
        guard asked || Update.isOn else { return settle(nil) }
        // Not in a folder its user may write to, or a build from source: the
        // download is on wham.sh.
        guard replaceable else { return settle(("CAN'T UPDATE ITSELF", "Get Wham \(newer) at wham.sh", nil, .select), openSite: true) }
        installing = newer
        if let updateRow {
            updateRow.state = updateState
        } else if asked {
            pop(Toast.note("UPDATING", "To Wham \(newer), back in a moment"))
        }
        let app = Bundle.main.bundleURL
        DispatchQueue.global(qos: .utility).async {
            let failure = Update.install(newer, over: app)
            Journal.note("update-install", ["version": newer, "ok": failure == nil, "failure": failure])
            Self.onMain {
                failure == nil ? self.reopen() : self.settle(("CAN'T UPDATE", "Wham \(newer) did not install, try again later", .said(Line.failed(newer)), .refused))
            }
        }
    }

    // The check is over: tells whoever asked from the menu how it went, in
    // its row if the menu is still open (and the row has words for it),
    // otherwise in a pill, with its sound (the row has its own).
    private func settle(_ note: (title: String, caption: String, row: UpdateRow.State?, sound: Chime.Sound)?, openSite: Bool = false) {
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
        closeMenu {
            self.pop(Toast.note(note.title, note.caption))
            self.play(note.sound)
            if openSite { NSWorkspace.shared.open(Self.site) }
        }
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
        guard (try? relaunch.run()) != nil else { return Journal.note("relaunch", ["ok": false]) }
        watchdog.standDown()
        Journal.note("relaunch", ["for": "update", "flag": Self.flagWord(Sleep.isDisabled)])
        Journal.markStopped()
        Journal.flush()
        exit(0)
    }

    // Quitting gives sleep back, whoever asks: the menu, a script, logging out.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let powerOff = poweringOff || Self.quitToPowerOff
        let by = sleepGivenBack ? "menu" : powerOff ? "restart, shutdown or logout" : "outside"
        if !sleepGivenBack && Sleep.isDisabled == true && Sleep.set(false, why: "quit by \(by)") {
            let defaults = UserDefaults.standard
            if powerOff {
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
        let defaults = UserDefaults.standard
        Journal.note("quit", ["by": by, "flag": Self.flagWord(Sleep.isDisabled),
                              "resume": defaults.object(forKey: "resumeAtLogin") != nil ? "at login" : defaults.object(forKey: "resumeBefore") != nil ? "within a minute" : nil])
        Journal.markStopped()
        Journal.flush()
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
        func skip(_ why: String) { Journal.note("resume", ["after": "restart", "skipped": why]) }
        guard Self.staysOnAfterRestart else { return skip("Stay On After Restart is off") }
        guard until.map({ $0 > Date() }) ?? true else { return skip("its session ended meanwhile") }
        guard Sleep.isDisabled == false else { return skip("flag \(Self.flagWord(Sleep.isDisabled))") }
        guard !refuses() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard Sleep.set(true, why: "resume after restart") else { return }
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
        func skip(_ why: String) { Journal.note("resume", ["after": "quit from outside", "skipped": why]) }
        guard deadline > Date() else { return skip("opened more than a minute later") }
        guard Sleep.isDisabled == false else { return skip("flag \(Self.flagWord(Sleep.isDisabled))") }
        // `sudo -n` never prompts: without the rule this quietly does nothing.
        DispatchQueue.global(qos: .userInitiated).async {
            guard Sleep.set(true, why: "resume after quit from outside") else { return }
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
        refreshMenu()
    }

    // On every change: the tick, the power source, the heat, the lid, the
    // `wham` command. Shows the kernel's state and, while on, ends the session
    // if its time, the battery or the heat says so.
    private func check() {
        guard !busy else { return }
        let state = Sleep.isDisabled
        if !toggleView.hasShown || state != toggleView.state { show(state) }
        // A change this app did not write: `wham` in a terminal, pmset, a
        // watchdog, a restart.
        if seenFlag != .some(state) {
            if !(state.map { Sleep.wroteLately($0) } ?? false) { Journal.note("flag-changed", ["to": Self.flagWord(state), "by": "outside"]) }
            seenFlag = .some(state)
        }
        let lidClosed = Sleep.lidClosed
        defer { lidWasClosed = lidClosed }
        if lidClosed != lidWasClosed { lidMoved(lidClosed, on: state == true) }
        if (state == true && lidClosed) != (sampleTimer != nil) { sampleWhileClosed(state == true && lidClosed) }
        guard state == true else {
            watchdog.standDown()
            connectivity.stop()
            if offAt != nil { setOffAt(nil) }
            return
        }
        watchdog.arm()
        connectivity.start()
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
        let caption = Session.why(end, battery: battery)
        Journal.note("session-ended", ["reason": "\(end)", "battery": battery, "limit": Self.limitWord, "heat": Self.heatWord])
        ended = (caption, Date())
        setOffAt(nil)
        change(to: false, mayInstall: false, caption: caption, why: "session ended: \(end)")
    }

    // Low battery or a hot Mac: says so instead of turning on.
    private func refuses() -> Bool {
        let reading = Session.read(offAt: nil)
        guard let end = Session.end(reading) else { return false }
        Journal.note("refused", ["reason": "\(end)", "battery": reading.battery, "limit": Self.limitWord, "heat": Self.heatWord])
        let refusal = Session.refusal(end, battery: reading.battery)
        if openMenu != nil { said = refusal }
        announce(false, caption: refusal, sound: .refused)
        refreshMenu()
        return true
    }

    // From now until `date`, or untimed (nil).
    private func setOffAt(_ date: Date?) {
        if date != offAt { Journal.note("session", ["end": date.map(Journal.stamp) ?? "none"]) }
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
        Journal.note("warning", ["end": offAt])
        pop(Toast.soon.saying("Then back to normal sleep, at \(Session.clock(offAt))"))
    }

    // A few seconds after the lid closes, so a monitor plugged into a closed
    // MacBook has taken over first, if there is one.
    private func sleepScreenSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard Sleep.isDisabled == true, Sleep.lidClosed else { return }
            guard Screen.builtInAloneAndLit else { return Journal.note("screen", ["action": "left alone", "displays": Screen.count]) }
            Journal.note("screen", ["action": "put to sleep", "why": "lid closed"])
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

    // What the switch shows: on from the click, while pmset runs.
    private var isOn: Bool { toggleView.state == true }

    // The menu's first line: what the Mac does now, or what Wham just refused.
    private var statusLine: String {
        if let said { return said }
        if isOn { return Self.awake(until: offAt) }
        if let ended { return "\(ended.why), stopped at \(Session.clock(ended.at))" }
        return "Mac sleeps as usual"
    }

    private static func awake(until end: Date?, now: Date = Date()) -> String {
        guard let end else { return "Mac stays awake, even with the lid closed" }
        return "Mac stays awake until \(Session.clock(end, now: now)) (\(Session.timeLeft(end.timeIntervalSince(now))) left)"
    }

    // Every option is a row that keeps the menu open when clicked, and the
    // menu follows what changed while it is open. The links and Quit close it.
    private func menu() -> NSMenu {
        let menu = NSMenu()
        // The first line, gray. Its blank state image keeps the menu's check
        // column when no option is checked: the titles stay put when one gets
        // checked or unchecked while the menu is open.
        let status = LiveItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.offStateImage = Self.blankState
        status.refresh = { [unowned self] in $0.title = statusLine }
        menu.addItem(status)
        menu.addItem(row(["Turn On", "Turn Off"]) { [unowned self] in .init(title: isOn ? "Turn Off" : "Turn On") } click: { [unowned self] in flip("menu") })
        let timed = LiveItem(title: "", action: nil, keyEquivalent: "")
        timed.refresh = { [unowned self] in $0.title = isOn ? "Stay Awake For" : "Turn On For" }
        timed.submenu = lengths()
        menu.addItem(timed)
        menu.addItem(.separator())
        menu.addItem(row(["Sound"]) { [unowned self] in .init(title: "Sound", checked: !muted) } click: { [unowned self] in
            // Turned on, it says so; turned off, it is quiet already.
            muted.toggle()
            Journal.note("setting", ["sound": !muted])
            if !muted { play(.check(true)) }
        })
        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearance.submenu = appearances()
        menu.addItem(appearance)
        menu.addItem(row(["Open at Login"]) { .init(title: "Open at Login", checked: LoginItem.isOn) } click: { [unowned self] in toggleLogin() })
        menu.addItem(row(["Stay On After Restart"], tip: "If Wham is on when your Mac restarts, it turns back on when you log in.") {
            .init(title: "Stay On After Restart", checked: Self.staysOnAfterRestart)
        } click: { [unowned self] in
            Self.staysOnAfterRestart.toggle()
            Journal.note("setting", ["stay-on-after-restart": Self.staysOnAfterRestart])
            play(.check(Self.staysOnAfterRestart))
        })
        menu.addItem(row(["Update Automatically"]) { .init(title: "Update Automatically", checked: Update.isOn) } click: { [unowned self] in toggleUpdates() })
        let limit = NSMenuItem(title: "Battery Limit", action: nil, keyEquivalent: "")
        limit.submenu = batteryLimits()
        menu.addItem(limit)
        menu.addItem(.separator())
        let links = [NSMenuItem(title: "About Wham \(CLI.version)", action: #selector(openSite), keyEquivalent: ""),
                     NSMenuItem(title: "What's New", action: #selector(openChangelog), keyEquivalent: "")]
        for entry in links { menu.addItem(entry) }
        menu.addItem(updateItem())
        let author = NSMenuItem(title: "Made by Gwendall", action: #selector(openAuthor), keyEquivalent: "")
        menu.addItem(author)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Wham (lets your Mac sleep)", action: #selector(quit), keyEquivalent: "q")
        menu.addItem(quit)
        for entry in links + [author, quit] { entry.target = self }
        // As wide as any first line a click in it can bring: the menu does
        // not grow while open.
        let now = Date()
        let lines = ["Mac sleeps as usual", Self.awake(until: nil)]
            + [1, 2, 4, 8].map { Self.awake(until: now.addingTimeInterval(TimeInterval($0) * 3600), now: now.addingTimeInterval(60)) }
            + [Session.End.battery, .heat].map { Session.refusal($0, battery: 100) }
        menu.minimumWidth = MenuRow.width(for: lines)
        adopt(menu)
        refresh(menu)
        return menu
    }

    // A blank image as wide as the menu's check mark.
    private static let blankState = NSImage(size: NSSize(width: 13, height: 11))

    // An option as a row that keeps the menu open when clicked, as wide as
    // any of its `titles` with any of its `details`, read again from
    // `content` after each change while the menu is open. Its action is for
    // the keyboard: Return does the same, and closes the menu.
    private func row(_ titles: [String], details: [String] = [], tip: String? = nil,
                     _ content: @escaping @MainActor () -> MenuRow.Content, click: @escaping @MainActor () -> Void) -> LiveItem {
        let row = MenuRow(content(), width: MenuRow.width(for: titles, details: details))
        row.source = content
        row.onClick = { [weak self] in
            click()
            self?.refreshMenu()
        }
        row.toolTip = tip
        let entry = LiveItem(title: row.title, action: #selector(press(_:)), keyEquivalent: "")
        entry.target = self
        entry.view = row
        entry.state = row.content.checked ? .on : .off
        entry.toolTip = tip
        return entry
    }

    @objc private func press(_ sender: NSMenuItem) {
        (sender.view as? MenuRow)?.onClick?()
    }

    // Check for Updates, or the new version Wham found and did not install,
    // as a row that keeps the menu open when clicked.
    private func updateItem() -> NSMenuItem {
        // As wide as its widest line, with any version found while the menu is open.
        let row = UpdateRow(updateState, width: MenuRow.width(for: Line.all(running: running, found: available ?? "10.10.10"), accessory: true))
        row.onClick = { [weak self, weak row] in
            guard let self else { return }
            self.play(.select)
            self.checkForUpdate(asked: true)
            row?.state = self.updateState
        }
        // Its sound comes as it says how the check went, a second at least
        // after it started.
        row.onChange = { [weak self] state in
            print("row \(state)")
            fflush(stdout)
            if case .done = state { self?.play(.check(true)) }
            if case .said = state { self?.play(.refused) }
        }
        let entry = NSMenuItem(title: row.title, action: #selector(press(_:)), keyEquivalent: "")
        entry.target = self
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

    // The menu and its submenus tell Wham when they open, close and move
    // their selection.
    private func adopt(_ menu: NSMenu) {
        menu.delegate = self
        for entry in menu.items { if let submenu = entry.submenu { adopt(submenu) } }
    }

    func menuWillOpen(_ menu: NSMenu) {
        shownMenus.insert(ObjectIdentifier(menu))
        guard menu.supermenu == nil else { return }
        openMenu = menu
        updateRow = menu.items.lazy.compactMap { $0.view as? UpdateRow }.first
    }

    func menuDidClose(_ menu: NSMenu) {
        shownMenus.remove(ObjectIdentifier(menu))
        if menu.supermenu != nil { submenuClosedAt = Date() }
        // A submenu's rows lose their selection with it.
        for entry in menu.items { (entry.view as? MenuRow)?.highlighted = false }
        guard menu.supermenu == nil else { return }
        openMenu = nil
        updateRow = nil
        said = nil
        let waiting = afterMenu
        afterMenu = []
        if !waiting.isEmpty { Self.after(0.1) { for work in waiting { work() } } }
    }

    // The rows draw the menu's selection themselves. A click on one leaves
    // the menu without a selection until the pointer moves again: the row
    // still under the pointer keeps its own.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for entry in menu.items {
            guard let row = entry.view as? MenuRow else { continue }
            row.highlighted = item.map { $0 === entry } ?? row.underPointer
        }
    }

    // Closes the menu, then does `work` once it is gone (at once if no menu
    // is open): a password prompt, an alert or another app over an open menu
    // would leave it hanging there.
    private func closeMenu(then work: @escaping @MainActor () -> Void = {}) {
        guard let openMenu else { return work() }
        afterMenu.append(work)
        openMenu.cancelTracking()
    }

    // Brings the open menu in step with Wham: its titles, its checks, the
    // time left.
    private func refreshMenu() {
        guard let openMenu else { return }
        refreshedAt = Date()
        refresh(openMenu)
    }

    private func refresh(_ menu: NSMenu) {
        for entry in menu.items {
            if let live = entry as? LiveItem { live.refresh?(live) }
            (entry.view as? MenuRow)?.reload()
            if let submenu = entry.submenu { refresh(submenu) }
        }
    }

    // 1, 2, 4 or 8 hours from now, each with the time it would end on the
    // right, in gray; and No Time Limit, checked while the Mac stays awake
    // with no end. Always there: a row shown or hidden while the menu is
    // open would resize it under the pointer.
    private func lengths() -> NSMenu {
        let lengths = NSMenu()
        let hours = [1, 2, 4, 8]
        func title(_ count: Int) -> String { count == 1 ? "1 Hour" : "\(count) Hours" }
        func end(_ count: Int, from now: Date = Date()) -> String {
            Session.clock(now.addingTimeInterval(TimeInterval(count) * 3600), now: now)
        }
        // The ends move on while the menu is open, to another day maybe: as
        // wide as an end with its weekday too (a Wednesday at 12:58).
        let now = Date()
        var wednesday = DateComponents(year: 2025, month: 1, day: 1, hour: 12, minute: 58)
        wednesday.calendar = Calendar.current
        let widest = wednesday.date.map { [Session.clock($0, now: $0.addingTimeInterval(-86400))] } ?? []
        let titles = hours.map(title) + ["No Time Limit"], details = hours.map { end($0, from: now) } + widest
        for count in hours {
            lengths.addItem(row(titles, details: details) { .init(title: title(count), detail: end(count)) } click: { [unowned self] in stayAwake(for: count) })
        }
        lengths.addItem(.separator())
        lengths.addItem(row(titles, details: details) { [unowned self] in .init(title: "No Time Limit", checked: isOn && offAt == nil) } click: { [unowned self] in noTimeLimit() })
        return lengths
    }

    // Monochrome and Compact, each on its own.
    private func appearances() -> NSMenu {
        let looks = NSMenu()
        let titles = ["Monochrome", "Compact"]
        looks.addItem(row(titles, tip: "In the menu bar's own color, like the icons around it.") { [unowned self] in
            .init(title: "Monochrome", checked: look.monochrome)
        } click: { [unowned self] in
            look.monochrome.toggle()
            Journal.note("setting", ["monochrome": look.monochrome])
            play(.check(look.monochrome))
        })
        looks.addItem(row(titles, tip: "As wide as an icon: the switch turns instead of sliding.") { [unowned self] in
            .init(title: "Compact", checked: look.compact)
        } click: { [unowned self] in
            look.compact.toggle()
            Journal.note("setting", ["compact": look.compact])
            play(.check(look.compact))
        })
        return looks
    }

    private var look: SwitchView.Look {
        get { SwitchView.Look(monochrome: UserDefaults.standard.bool(forKey: "monochrome"), compact: UserDefaults.standard.bool(forKey: "compact")) }
        set {
            UserDefaults.standard.set(newValue.monochrome, forKey: "monochrome")
            UserDefaults.standard.set(newValue.compact, forKey: "compact")
            toggleView.setLook(newValue, animated: true)
        }
    }

    private func lookMoved() {
        item.length = toggleView.itemLength
        film?.append((CACurrentMediaTime(), item.length, toggleView.blend.mono))
    }

    // On battery, the charge at which Wham lets the Mac sleep.
    private func batteryLimits() -> NSMenu {
        let limits = NSMenu()
        let header = NSMenuItem(title: "Sleep on battery at", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.offStateImage = Self.blankState
        limits.addItem(header)
        let titles = Session.batteryLimits.map { "\($0)%" } + ["Never"]
        for percent in Session.batteryLimits {
            limits.addItem(row(titles) { .init(title: "\(percent)%", checked: percent == Session.batteryLimit) } click: { [unowned self] in setBatteryLimit(percent) })
        }
        limits.addItem(.separator())
        limits.addItem(row(titles, tip: "On battery, your Mac stays awake until the battery runs out. Save your work first.") {
            .init(title: "Never", checked: Session.batteryLimit == Session.never)
        } click: { [unowned self] in setBatteryLimit(Session.never) })
        return limits
    }

    // For the evals: once launched, presses menu items by title, one after the
    // other, as WHAM_PRESS lists them: "Turn On For/2 Hours,Turn Off". "Switch"
    // is a click on the switch, "Terminate" a quit from outside (an upgrade),
    // "Restart" the quit macOS sends before a restart, "Menu" opens the menu
    // for real and says whether it showed whole, "Click Updates" opens it and
    // clicks Check for Updates as a mouse would, "Click Rows" the options
    // WHAM_CLICKS lists, "Rows" draws the menu's own rows next to rows of
    // Wham's, "Status" prints the menu's first line and its lengths, "Items"
    // the menu's items, "Look" the appearance and the status item's width,
    // "Film/Compact" or "Film/Monochrome" changes the look and prints its
    // frames, and "Pause" waits a step.
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
                print("look", lookLine)
                fflush(stdout)
            case ["Pause"]: break
            case ["Film", "Compact"], ["Film", "Monochrome"]:
                // The film before, if a busy Mac has not printed it yet.
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(printFilm), object: nil)
                if film != nil { printFilm() }
                print("motion: Reduce Motion \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "on" : "off")\(SwitchView.movesAnyway ? ", moving anyway" : "")")
                film = []
                filmed = path[1]
                if path[1] == "Compact" { look.compact.toggle() } else { look.monochrome.toggle() }
                perform(#selector(printFilm), with: nil, afterDelay: 0.9, inModes: [.common])
            case ["Items"]:
                print("items", Self.describe(self.menu()))
                fflush(stdout)
            case ["Status"]:
                let menu = self.menu()
                print("status", menu.items.first?.title ?? "")
                print("lengths", Self.describe(menu.items.first { $0.submenu != nil }?.submenu ?? NSMenu()))
                fflush(stdout)
            case ["Menu"]:
                let menu = self.menu()
                perform(#selector(lookAt(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            case ["Click Updates"]:
                let menu = self.menu()
                perform(#selector(clickUpdates(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            case ["Click Rows"]:
                let menu = self.menu()
                perform(#selector(clickRows(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            case ["Rows"]:
                let menu = rowPairs()
                perform(#selector(comparePairs(_:)), with: menu, afterDelay: 0.5, inModes: [.common])
                showMenu(menu)
            default:
                var entry: NSMenuItem?, menu: NSMenu? = self.menu()
                for title in path {
                    entry = menu?.items.first { $0.title == title && !$0.isHidden }
                    menu = entry?.submenu
                }
                if let entry, let action = entry.action { NSApp.sendAction(action, to: entry.target, from: entry) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
    }

    // "film Compact: 28 frames in 450 ms, longest gap 17 ms, 50.0 49.5 … 23.0":
    // the frames of the change of look, with the status item's width each
    // time, or how monochrome the switch was.
    @objc private func printFilm() {
        let option = filmed
        let frames = film ?? []
        film = nil
        // A screen that is off has no frames to give: the change ends at once.
        guard Self.screenShows else {
            print("film \(option): not drawn: the screen is locked or asleep")
            fflush(stdout)
            return
        }
        let gaps = zip(frames.dropFirst(), frames).map { $0.time - $1.time }
        let values = frames.map { option == "Compact" ? String(format: "%.1f", $0.length) : String(format: "%.2f", $0.mono) }
        print("film \(option): \(frames.count) frames in \(Int(((frames.last?.time ?? 0) - (frames.first?.time ?? 0)) * 1000)) ms,",
              "longest gap \(Int((gaps.max() ?? 0) * 1000)) ms,", values.joined(separator: " "))
        fflush(stdout)
    }

    // "monochrome compact 23": the switch's look and the status item's width.
    private var lookLine: String {
        "\(look.monochrome ? "monochrome" : "color") \(look.compact ? "compact" : "wide") \(Int(item.length))"
    }

    // A menu's items as shown, a row's detail after a tab.
    private static func describe(_ menu: NSMenu) -> String {
        menu.items.filter { !$0.isHidden }.map { entry in
            if entry.isSeparatorItem { return "-" }
            guard let row = entry.view as? MenuRow else { return entry.title }
            let title = row.content.checked ? "\(row.title) checked" : row.title
            return row.content.detail.map { "\(title)\t\($0)" } ?? title
        }.joined(separator: " | ")
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
        func shoot(_ name: String) -> CGImage? { Self.shoot(window, name) }
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
        let home = CGEvent(source: nil)?.location
        Self.pointer(onto: frame, of: window)
        // A busy Mac takes a while to highlight the row: the click waits for it.
        Self.waitFor(5, { row.highlighted }) {
            print("row highlighted", row.highlighted)
            _ = shoot("2-highlighted")
            Self.click(frame, of: window)
            Self.after(0.4) {
                _ = shoot("3-busy")
                Self.waitFor(15, { !row.state.busy }) {
                    // The picture once the menu has drawn the answer.
                    Self.after(0.3) {
                        _ = shoot("4-told")
                        print("menu", window.isVisible ? "still open" : "closed")
                        fflush(stdout)
                        menu.cancelTracking()
                        if let home { CGWarpMouseCursorPosition(home) }
                    }
                }
            }
        }
    }

    // Clicks options of the open menu as a mouse would, one after the other,
    // as WHAM_CLICKS lists them ("Appearance/Monochrome,Turn On"): the pointer
    // rests on a submenu's title until the submenu opens, then clicks the row
    // in it. After each click, whether the menu is still open, what the row
    // says now, the switch's look and the menu's first line; with
    // WHAM_SHOTS, a picture of the menu. Then a click outside it, which closes
    // it, and the pointer goes back.
    @objc private func clickRows(_ menu: NSMenu) {
        var paths = (ProcessInfo.processInfo.environment["WHAM_CLICKS"] ?? "").split(separator: ",").map { $0.split(separator: "/").map(String.init) }
        let home = CGEvent(source: nil)?.location
        guard let root = Self.window(of: menu) else {
            print("menu missing")
            fflush(stdout)
            return menu.cancelTracking()
        }
        _ = Self.shoot(root, "click-0")
        var clicks = 0
        @MainActor func next() {
            guard !paths.isEmpty else {
                print("menu", root.isVisible && openMenu != nil ? "still open" : "closed")
                fflush(stdout)
                guard openMenu != nil else {
                    if let home { CGWarpMouseCursorPosition(home) }
                    return
                }
                // Left of the menu, halfway down.
                let outside = NSRect(x: -60, y: root.frame.height / 2, width: 1, height: 1)
                Self.pointer(onto: outside, of: root)
                Self.click(outside, of: root)
                Self.waitFor(2, { self.openMenu == nil }) {
                    print("outside: menu", self.openMenu == nil ? "closed" : "still open")
                    fflush(stdout)
                    menu.cancelTracking()
                    if let home { CGWarpMouseCursorPosition(home) }
                }
                return
            }
            let path = paths.removeFirst()
            var titles = path[...], current = menu, retried = false
            // Where the pointer, the menus and the selection were at each
            // move, said with a failure: what a menu that would not follow saw.
            var trail: [String] = []
            @MainActor func mark(_ label: String) {
                let at = NSEvent.mouseLocation
                let sub = current === menu ? nil : Self.window(of: current)
                trail.append("\(label): pointer \(Int(at.x)),\(Int(at.y)), \(self.shownMenus.count) shown, menu selects \(menu.highlightedItem?.title ?? "none")"
                    + (sub.map { ", submenu \($0.isVisible ? "visible" : "hidden") at \(Self.box($0.frame)) selects \(current.highlightedItem?.title ?? "none")" } ?? ""))
            }
            // A submenu that closed by itself: how long after Wham last
            // refreshed the open menu.
            @MainActor func closing() -> String {
                String(format: "a submenu closed %.2f s after a refresh", self.submenuClosedAt.timeIntervalSince(self.refreshedAt))
            }
            @MainActor func fail(_ why: String) {
                if let window = Self.window(of: current) { _ = Self.shoot(window, "click-\(clicks + 1)-failed") }
                print("click \(path.joined(separator: "/")): \(why)")
                next()
            }
            @MainActor func step() {
                // A pointer the menu did not follow (macOS 14 now and then):
                // the whole path once more from the top, said on its own line.
                // Its submenus closed first, the pointer on the first line, which
                // opens none: a submenu left open does not open again.
                @MainActor func again(_ why: String) -> Bool {
                    guard !retried else { return false }
                    retried = true
                    print("retry \(path.joined(separator: "/")): \(why) [\(trail.joined(separator: "; "))]")
                    fflush(stdout)
                    trail = []
                    titles = path[...]
                    current = menu
                    guard let first = Self.frame(of: menu.items.first?.title ?? "", in: root) else { step(); return true }
                    Self.pointer(onto: first, of: root)
                    Self.waitFor(3, { self.shownMenus.count <= 1 }, poke: Self.nudge(first, of: root)) { step() }
                    return true
                }
                let title = titles.removeFirst()
                guard let entry = current.items.first(where: { $0.title == title && !$0.isHidden }) else { return fail("no \(title)") }
                if let row = entry.view as? MenuRow, titles.isEmpty, let window = row.window {
                    let frame = row.convert(row.bounds, to: nil)
                    Self.pointer(onto: frame, of: window)
                    mark("onto \(title) at \(Self.box(window.convertToScreen(frame)))")
                    // Only a row the menu itself has selected: a click on any
                    // other would be the menu's.
                    // A submenu that closes meanwhile ends the wait.
                    let selected = { current.highlightedItem === entry && row.highlighted }
                    let start = Date()
                    var closed = false
                    let ready = { () -> Bool in
                        if !closed && !self.shownMenus.contains(ObjectIdentifier(current)) {
                            closed = true
                            mark(String(format: "closed after %.1f s, ", Date().timeIntervalSince(start)) + closing())
                        }
                        return selected() || closed
                    }
                    Self.waitFor(5, ready, poke: Self.nudge(frame, of: window)) {
                        guard current.highlightedItem === entry else {
                            // What the menu showed instead, to tell a pointer it
                            // missed from a submenu that was not there.
                            let seen = "\(title) did not highlight (\(self.shownMenus.count) menus shown, \(self.shownMenus.contains(ObjectIdentifier(current)) ? "this one" : "not this one"), selected \(current.highlightedItem?.title ?? "none"), its window \(window.isVisible ? "visible" : "hidden") \(window.windowNumber == root.windowNumber ? "the menu's own" : "its own"))"
                            if !again(seen) { fail("\(seen) [\(trail.joined(separator: "; "))]") }
                            return
                        }
                        self.heard = nil
                        Self.click(frame, of: window)
                        // Once a change of look has settled.
                        Self.after(0.8) {
                            clicks += 1
                            _ = Self.shoot(window, "click-\(clicks)")
                            let open = root.isVisible && self.openMenu != nil
                            print("click \(path.joined(separator: "/")): menu \(open ? "open" : "closed"), \(row.title)\(row.content.checked ? " checked" : ""), look \(self.lookLine), sound \(self.heard?.name ?? "none"), status \(menu.items.first?.title ?? "")")
                            fflush(stdout)
                            next()
                        }
                    }
                } else if let submenu = entry.submenu, let window = Self.window(of: current), let frame = Self.frame(of: title, in: window) {
                    mark("to \(title) at \(Self.box(window.convertToScreen(frame)))")
                    Self.pointer(onto: frame, of: window)
                    let shown = { self.shownMenus.contains(ObjectIdentifier(submenu)) && Self.window(of: submenu)?.isVisible == true }
                    Self.waitFor(5, shown, poke: Self.nudge(frame, of: window)) {
                        guard shown() else {
                            if !again("\(title) did not open") { fail("\(title) did not open") }
                            return
                        }
                        current = submenu
                        mark("\(title) open")
                        guard let inside = Self.window(of: submenu) else { return step() }
                        // As a hand goes, not in one jump: once the submenu
                        // stands still, along its title to the side it opened
                        // on, then just inside it, level with the title. macOS
                        // 14 still closes it now and then right after a
                        // synthetic move, the pointer inside; the retry above
                        // covers that, and the trail says when it happened.
                        Self.after(0.3) {
                            mark("\(title) still open")
                            let left = inside.frame.midX < window.frame.midX
                            let edge = NSRect(x: left ? frame.minX + 16 : frame.maxX - 16, y: frame.minY, width: 1, height: frame.height)
                            Self.pointer(onto: edge, of: window)
                            Self.after(0.15) {
                                // Level with the title, unless the submenu had to
                                // move up or down to fit the screen.
                                let level = window.convertToScreen(edge), box = inside.frame
                                let y = min(max(level.minY, box.minY + 4), box.maxY - level.height - 4)
                                let door = inside.convertFromScreen(NSRect(x: left ? box.maxX - 16 : box.minX + 16, y: y, width: 1, height: level.height))
                                Self.pointer(onto: door, of: inside)
                                Self.after(0.15) {
                                    mark("inside \(title)")
                                    guard shown() else {
                                        let seen = "\(title) closed on the way in, \(closing())"
                                        if !again(seen) { fail("\(seen) [\(trail.joined(separator: "; "))]") }
                                        return
                                    }
                                    step()
                                }
                            }
                        }
                    }
                } else {
                    // A row whose submenu closed after the pointer went in.
                    let seen = "\(title) not shown" + (current === menu ? "" : ", \(closing())")
                    if current === menu || !again(seen) { fail("\(seen) [\(trail.joined(separator: "; "))]") }
                }
            }
            step()
        }
        next()
    }

    // The menu's own rows over rows of Wham's that say the same: plain,
    // checked and gray, for "Rows".
    private func rowPairs() -> NSMenu {
        let menu = NSMenu()
        for content in [MenuRow.Content(title: "Plain"), .init(title: "Checked", checked: true), .init(title: "Gray", enabled: false)] {
            let native = NSMenuItem(title: content.title, action: content.enabled ? #selector(press(_:)) : nil, keyEquivalent: "")
            native.target = self
            native.state = content.checked ? .on : .off
            menu.addItem(native)
            menu.addItem(row([content.title]) { content } click: {})
        }
        adopt(menu)
        return menu
    }

    // Each of the menu's own rows against Wham's under it, in a picture of
    // the menu: the share of their pixels that differ, and where their ink
    // starts.
    @objc private func comparePairs(_ menu: NSMenu) {
        defer {
            fflush(stdout)
            menu.cancelTracking()
        }
        guard let window = Self.window(of: menu), let image = Self.shoot(window, "rows") else { return print("pairs missing") }
        guard Self.screenShows else { return print("pairs not drawn: the screen is locked or asleep") }
        for entry in menu.items {
            guard let row = entry.view as? MenuRow else { continue }
            let mine = row.convert(row.bounds, to: nil), theirs = mine.offsetBy(dx: 0, dy: mine.height)
            let differ = Self.differ(in: image, of: window, between: theirs, and: mine)
            let a = Self.ink(in: image, of: window, at: theirs), b = Self.ink(in: image, of: window, at: mine)
            print("pair \(row.title): \(differ.map { String(format: "%.4f", $0) } ?? "-") differ, ink at x \(a.map { "\($0.x)" } ?? "-") in the menu's, \(b.map { "\($0.x)" } ?? "-") in Wham's")
        }
    }

    // "x,y wxh", in points on the screen.
    private static func box(_ frame: NSRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }

    // The window a menu shows in, found through one of its rows.
    private static func window(of menu: NSMenu) -> NSWindow? {
        menu.items.lazy.compactMap { $0.view?.window }.first
    }

    // The row of one of the menu's own titles, in its window.
    private static func frame(of title: String, in window: NSWindow) -> NSRect? {
        func find(_ view: NSView) -> NSTextField? {
            if view is MenuRow { return nil }
            if let field = view as? NSTextField, field.stringValue == title { return field }
            for sub in view.subviews { if let field = find(sub) { return field } }
            return nil
        }
        guard let root = window.contentView, let holder = find(root)?.superview else { return nil }
        return holder.convert(holder.bounds, to: nil)
    }

    // The pointer onto the middle of `frame` in `window`, for real: the menu
    // goes by where it really is.
    private static func pointer(onto frame: NSRect, of window: NSWindow) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let onScreen = window.convertPoint(toScreen: center)
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y))
        post(.mouseMoved, at: center, in: window)
    }

    private static func click(_ frame: NSRect, of window: NSWindow) {
        post(.leftMouseDown, at: NSPoint(x: frame.midX, y: frame.midY), in: window)
        post(.leftMouseUp, at: NSPoint(x: frame.midX, y: frame.midY), in: window)
    }

    private static func post(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                             pressure: type == .leftMouseDown ? 1 : 0) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    // The pointer a point to one side of the middle of `frame`, then to the
    // other: a menu that missed one move (macOS 14 leaving a submenu for
    // another) sees the next.
    private static func nudge(_ frame: NSRect, of window: NSWindow) -> @MainActor () -> Void {
        var side: CGFloat = 1
        return {
            side = -side
            pointer(onto: frame.offsetBy(dx: side, dy: 0), of: window)
        }
    }

    // Goes on once `ready`, or after `seconds` anyway, menu open or not,
    // with `poke` between tries.
    private static func waitFor(_ seconds: Double, _ ready: @escaping @MainActor () -> Bool, poke: (@MainActor () -> Void)? = nil,
                                then work: @escaping @MainActor () -> Void) {
        if ready() || seconds <= 0 { return work() }
        after(0.1) {
            poke?()
            waitFor(seconds - 0.1, ready, poke: poke, then: work)
        }
    }

    // A picture of `window`, saved as `name` in WHAM_SHOTS when set.
    private static func shoot(_ window: NSWindow, _ name: String) -> CGImage? {
        let image = picture(of: window)
        if let shots = ProcessInfo.processInfo.environment["WHAM_SHOTS"], let image {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
        }
        return image
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

    // The share of the pixels of two rows of a picture of the window that
    // differ by more than a trace, where ink() reads them: clear of the
    // window's rounded edges.
    private static func differ(in image: CGImage, of window: NSWindow, between a: NSRect, and b: NSRect) -> Double? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(image.width) / window.frame.width
        let height = Int(a.height * scale), left = Int(8 * scale), width = Int(a.width * 0.75 * scale) - left
        let topA = Int((window.frame.height - a.maxY) * scale), topB = Int((window.frame.height - b.maxY) * scale)
        guard topA >= 0, topB >= 0, max(topA, topB) + height <= image.height, width > 0, height > 0 else { return nil }
        var differing = 0
        for y in 0..<height {
            for x in left..<left + width {
                let at = x * image.bitsPerPixel / 8
                let p = (topA + y) * image.bytesPerRow + at, q = (topB + y) * image.bytesPerRow + at
                let distance = (0..<3).reduce(0) { $0 + abs(Int(bytes[p + $1]) - Int(bytes[q + $1])) }
                if distance > 30 { differing += 1 }
            }
        }
        return Double(differing) / Double(width * height)
    }

    private func toggleUpdates() {
        Update.isOn.toggle()
        Journal.note("setting", ["update-automatically": Update.isOn])
        play(.check(Update.isOn))
        if Update.isOn { checkForUpdate() }
    }

    // Held by macOS for approval, the login item is given in System Settings,
    // which opens once the menu is gone.
    private func toggleLogin() {
        do {
            let on = !LoginItem.isOn
            let set = try LoginItem.set(on)
            Journal.note("setting", ["open-at-login": on, "approval": set ? nil : "asked"])
            play(.check(on))
            if !set { closeMenu { LoginItem.askForApproval() } }
        } catch {
            alert("Wham could not change its login item: \(error.localizedDescription)")
        }
    }

    private static let site = URL(string: "https://wham.sh")!
    @objc private func openSite() { visit(Self.site) }
    @objc private func openChangelog() { visit(URL(string: "https://wham.sh/changelog")!) }
    @objc private func openAuthor() { visit(URL(string: "https://gwendall.com")!) }

    // The menu's links, in the browser.
    private func visit(_ page: URL) {
        play(.select)
        NSWorkspace.shared.open(page)
    }

    // The pill under the switch says the new state in words, with its sound:
    // the switch's chime, unless something else was asked.
    private func announce(_ on: Bool, caption: String? = nil, sound: Chime.Sound? = nil) {
        let style = on ? Toast.on : Toast.off
        pop(caption.map(style.saying) ?? style)
        play(sound ?? (on ? .on : .off))
    }

    // One sound at a time, each cutting the one before, as the chime's notes
    // do. Not from under a closed lid, where it would play inside a bag.
    private func play(_ sound: Chime.Sound) {
        heard = sound
        guard !muted, !Sleep.lidClosed else { return }
        if sounds[sound] == nil { sounds[sound] = NSSound(data: Chime.wav(Chime.samples(sound))) }
        playing?.stop()
        playing = sounds[sound]
        playing?.play()
    }

    @objc private func toggle() { flip("switch") }

    // The switch or the menu's Turn On and Turn Off, which the journal tells apart.
    private func flip(_ why: String) {
        guard !busy else { return }
        guard let current = Sleep.isDisabled else {
            return alert("Wham can't read your Mac's sleep setting.")
        }
        if !current && refuses() { return }
        ended = nil
        setOffAt(nil)
        change(to: !current, mayInstall: true, why: why)
    }

    // "Turn On For" and "Stay Awake For": from now, for that many hours.
    private func stayAwake(for hours: Int) {
        guard !busy, let current = Sleep.isDisabled else { return }
        if !current && refuses() { return }
        let until = Date().addingTimeInterval(TimeInterval(hours) * 3600)
        ended = nil
        setOffAt(until)
        let caption = "Until \(Session.clock(until))"
        if current {
            show(true)
            announce(true, caption: caption, sound: .select)
        } else {
            change(to: true, mayInstall: true, caption: caption, why: "menu \(hours)h")
        }
    }

    // No end: the Mac stays awake until turned off. Off, it turns on.
    private func noTimeLimit() {
        guard !busy, let current = Sleep.isDisabled else { return }
        let caption = "Until you turn it off"
        if current {
            // Already so: the click still says it.
            guard offAt != nil else { return play(.select) }
            setOffAt(nil)
            show(true)
            announce(true, caption: caption, sound: .select)
        } else {
            if refuses() { return }
            ended = nil
            setOffAt(nil)
            change(to: true, mayInstall: true, caption: caption, why: "menu no time limit")
        }
    }

    // A new limit counts at once: on battery under it, the session ends,
    // and its chime cuts the limit's sound.
    private func setBatteryLimit(_ percent: Int) {
        Session.batteryLimit = percent
        Journal.note("setting", ["battery-limit": Self.limitWord])
        play(.select)
        check()
    }

    // The switch moves on the click, then pmset runs off the main thread. If the
    // Mac refuses, the switch slides back to the kernel's state.
    // `why` is what the journal says asked for it.
    private func change(to target: Bool, mayInstall: Bool, caption: String? = nil, why: String) {
        said = nil
        show(target)
        announce(target, caption: caption)
        apply(target, mayInstall: mayInstall, why: why)
    }

    private func apply(_ target: Bool, mayInstall: Bool, why: String) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Sleep.set(target, why: why)
            Self.onMain { self.finish(target, ok: ok, mayInstall: mayInstall, why: why) }
        }
    }

    private func finish(_ target: Bool, ok: Bool, mayInstall: Bool, why: String) {
        // The password prompt comes once the menu is gone.
        if !ok && mayInstall && !Sleep.hasRule && openMenu != nil {
            return closeMenu { self.finish(target, ok: ok, mayInstall: mayInstall, why: why) }
        }
        busy = false
        if ok { return check() }
        guard mayInstall && !Sleep.hasRule else {
            revert(from: target)
            return alert(target ? "Your Mac refused the setting: it can still go to sleep." : "Your Mac refused: sleep is still blocked.")
        }
        Journal.note("rule", ["install": "asking"])
        switch Sleep.installRule() {
        case .done:
            Journal.note("rule", ["install": "done"])
            apply(target, mayInstall: false, why: why)
        case .cancelled:
            Journal.note("rule", ["install": "cancelled"])
            revert(from: target)
        case .failed(let message):
            Journal.note("rule", ["install": "failed", "error": message])
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
        let wasOn = Sleep.isDisabled == true
        if wasOn && !Sleep.set(false, why: "quit from the menu") {
            return alert("Your Mac refused to allow sleep again, so Wham stays open.")
        }
        sleepGivenBack = true
        // Sleep given back, it says so first, to the end.
        if wasOn { play(.off) }
        Self.after(wasOn && !muted ? playing?.duration ?? 0 : 0) { NSApp.terminate(nil) }
    }

    private func alert(_ text: String) {
        guard openMenu == nil else { return closeMenu { self.alert(text) } }
        Journal.note("alert", ["text": text])
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

// Open at login: SMAppService from macOS 13 on, a LaunchAgent before. macOS
// may hold the item for approval (System Settings > Login Items): turning it
// on then says so, and askForApproval() opens that page.
enum LoginItem {
    private static let agent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/sh.wham.app.plist")

    static var isOn: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agent.path)
    }

    // False when macOS holds the item for approval.
    @discardableResult
    static func set(_ on: Bool) throws -> Bool {
        if #available(macOS 13, *) {
            if !on {
                try SMAppService.mainApp.unregister()
                return true
            }
            try SMAppService.mainApp.register()
            return SMAppService.mainApp.status != .requiresApproval
        } else if on {
            let plist: [String: Any] = ["Label": "sh.wham.app", "ProgramArguments": ["/usr/bin/open", "-b", "sh.wham.app"], "RunAtLoad": true]
            try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent)
        } else {
            try FileManager.default.removeItem(at: agent)
        }
        return true
    }

    static func askForApproval() {
        if #available(macOS 13, *) { SMAppService.openSystemSettingsLoginItems() }
    }
}

// A menu item read again while its menu is open.
final class LiveItem: NSMenuItem {
    var refresh: (@MainActor (LiveItem) -> Void)?
}

// The power and the heat as last read, for the journal to say when they change.
private struct Sensed: Equatable {
    var onBattery: Bool
    var step: Int?
    var thermal: Int
    var pressure: UInt64?
    var critical: Bool

    init(_ reading: Session.Reading) {
        onBattery = reading.onBattery
        step = reading.battery.map { $0 / 5 }
        thermal = ProcessInfo.processInfo.thermalState.rawValue
        pressure = Heat.level
        critical = reading.critical
    }
}
