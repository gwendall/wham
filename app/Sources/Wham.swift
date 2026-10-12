import AppKit
import ServiceManagement

// The menu bar app. A click flips the switch; a right-click (or control-click)
// opens the menu.
@MainActor
final class Wham: NSObject, NSApplicationDelegate {
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
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.runsFromTemporaryCopy && offerToMove() { return }
        guard let button = item.button else { return }
        item.length = toggleView.contentWidth + 8
        toggleView.frame = button.bounds
        toggleView.autoresizingMask = [.width, .height]
        button.addSubview(toggleView)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
        resumeAfterUpdate()
        // Catches anything else flipping the flag (`wham on` in a terminal, pmset,
        // a reboot). The tolerance lets macOS batch these wakeups with others.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 1
        // A menu bar switch is only useful if it is there: open at login from the
        // first launch on (the menu can turn this off), and say hello once.
        if !UserDefaults.standard.bool(forKey: "loginItemSet") && !Self.runsFromTemporaryCopy {
            UserDefaults.standard.set(true, forKey: "loginItemSet")
            try? LoginItem.set(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.hello() }
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
                + "Hold ⌘ and drag other icons away to make room, or use `wham on` and `wham off` in Terminal.")
        }
        toast.show(Toast.hello, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
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

    // Quitting gives sleep back, whoever asks: the menu, a script, logging out.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !sleepGivenBack && Sleep.isDisabled == true && Sleep.set(false) {
            // Quit by someone else while on. `brew upgrade` quits the old copy and
            // opens the new one right away: that one turns back on.
            UserDefaults.standard.set(Date().addingTimeInterval(60), forKey: "resumeBefore")
        }
        return .terminateNow
    }

    private func resumeAfterUpdate() {
        guard let deadline = UserDefaults.standard.object(forKey: "resumeBefore") as? Date else { return }
        UserDefaults.standard.removeObject(forKey: "resumeBefore")
        guard deadline > Date() && Sleep.isDisabled == false else { return }
        // `sudo -n` never prompts: without the rule this quietly does nothing.
        DispatchQueue.global(qos: .userInitiated).async {
            guard Sleep.set(true) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.show(true); self.announce(true) } }
        }
    }

    private func show(_ state: Bool?) {
        toggleView.show(state, animated: true)
        let tip: String
        switch state {
        case true?: tip = "Wham is on: your Mac stays awake, even with the lid closed. Click to turn off."
        case false?: tip = "Wham is off: your Mac sleeps as usual. Click to turn on."
        case nil: tip = "Wham can't read your Mac's sleep setting"
        }
        item.button?.setAccessibilityLabel(tip)
        item.button?.toolTip = tip
    }

    private func refresh() {
        guard !busy else { return }
        let state = Sleep.isDisabled
        if !toggleView.hasShown || state != toggleView.state { show(state) }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let on = Sleep.isDisabled == true
        let menu = NSMenu()
        let status = NSMenuItem(title: on ? "Mac stays awake, even with the lid closed" : "Mac sleeps as usual", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem(title: on ? "Turn Off" : "Turn On", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(.separator())
        let sound = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        sound.state = muted ? .off : .on
        menu.addItem(sound)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About Wham \(CLI.version)", action: #selector(openSite), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Made by Gwendall", action: #selector(openAuthor), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wham (lets your Mac sleep)", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items { entry.target = self }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleSound() { muted.toggle() }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isOn)
        } catch {
            alert("Wham could not change its login item: \(error.localizedDescription)")
        }
    }

    @objc private func openSite() { NSWorkspace.shared.open(URL(string: "https://wham.sh")!) }
    @objc private func openAuthor() { NSWorkspace.shared.open(URL(string: "https://gwendall.com")!) }

    // The pill under the switch says the new state in words, with its sound.
    private func announce(_ on: Bool) {
        guard let button = item.button, let window = button.window else { return }
        toast.show(on ? Toast.on : Toast.off, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
        guard !muted, let sound = sounds[on] ?? nil else { return }
        sound.stop()
        sound.play()
    }

    @objc private func toggle() {
        guard !busy else { return }
        guard let current = Sleep.isDisabled else {
            return alert("Wham can't read your Mac's sleep setting.")
        }
        change(to: !current, mayInstall: true)
    }

    // The switch moves on the click, then pmset runs off the main thread. If the
    // Mac refuses, the switch slides back to the kernel's state.
    private func change(to target: Bool, mayInstall: Bool) {
        show(target)
        announce(target)
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
        if ok { return }
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
