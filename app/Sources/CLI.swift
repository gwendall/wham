import AppKit
import Darwin
import Foundation

// `wham on`, `wham off`, `wham status`: the same switch, from a terminal. The
// `wham` command is a link to the app's own binary; the app sees the name it
// was called by and answers here instead of opening the menu bar item.
enum CLI {
    static let commands: Set<String> = ["on", "off", "toggle", "status", "run", "version", "--version", "-v", "help", "--help", "-h"]

    // Called through the `wham` link, Bundle.main is the link's folder: the
    // version comes from the bundle the binary really sits in.
    static var version: String {
        (app ?? .main).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static var app: Bundle? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return Bundle(url: URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    static func run(_ args: [String]) -> Int32 {
        switch args.first ?? "help" {
        case "on":
            guard args.count <= 2 else { return usage() }
            guard args.count == 2 else { return on(for: nil) }
            guard let length = Session.duration(args[1]) else {
                fputs("wham: '\(args[1])' is not a duration: try 45m, 2h or 1h30m\n", stderr)
                return 64
            }
            return on(for: length)
        case "off": return args.count == 1 ? off() : usage()
        case "toggle":
            guard let current = Sleep.isDisabled else { return unreadable() }
            return current ? off() : on(for: nil)
        case "status":
            guard let current = Sleep.isDisabled else { return unreadable() }
            print(describe(current, until: current ? Session.offAt : nil))
            return 0
        case "run":
            return keepAwake(while: Array(args.dropFirst()))
        case "version", "--version", "-v":
            print("wham \(version)")
            return 0
        case "help", "--help", "-h":
            print(help)
            return 0
        default:
            fputs("wham: unknown command '\(args[0])'\n\n\(help)\n", stderr)
            return 64
        }
    }

    static func describe(_ on: Bool, until: Date? = nil) -> String {
        guard on else { return "off: your Mac sleeps as usual" }
        return "on\(until.map { " until \(Session.clock($0))" } ?? ""): your Mac stays awake, even with the lid closed"
    }

    private static func on(for length: TimeInterval?) -> Int32 {
        if let refusal = refusal() {
            fputs("wham: \(refusal)\n", stderr)
            return 1
        }
        guard flip(true) else { return 1 }
        let until = length.map { Date().addingTimeInterval($0) }
        share(until)
        openApp()
        print(describe(true, until: until))
        return 0
    }

    private static func off() -> Int32 {
        guard flip(false) else { return 1 }
        share(nil)
        print(describe(false))
        return 0
    }

    // Low battery or a hot Mac: the reason not to turn on, if there is one.
    private static func refusal() -> String? {
        let reading = Session.read(offAt: nil)
        guard let end = Session.end(reading) else { return nil }
        let text = Session.refusal(end, battery: reading.battery)
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    // The menu bar app is what watches the battery and the heat, and ends a
    // timed session: opens it, out of sight, if it is not running.
    private static func openApp() {
        guard let app, app.bundleIdentifier == "sh.wham.app", !NSRunningApplication.runningApplications(withBundleIdentifier: "sh.wham.app")
            .contains(where: { $0.processIdentifier != getpid() }) else { return }
        Sleep.run("/usr/bin/open", ["-g", app.bundlePath])
    }

    // Tells the menu bar app when the session ends, and that the switch moved:
    // it shows it at once rather than on its next look.
    private static func share(_ until: Date?) {
        if Session.offAt != until { Session.setEnd(until) }
        DistributedNotificationCenter.default().postNotificationName(Session.changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    // Without the app's sudoers rule, falls back to a plain `sudo`, which asks
    // for the password in the terminal.
    private static func flip(_ on: Bool) -> Bool {
        if Sleep.isDisabled == on || Sleep.set(on) { return true }
        Sleep.run("/usr/bin/sudo", [Sleep.pmset, "-a", "disablesleep", on ? "1" : "0"], quiet: false)
        guard Sleep.confirm(on) else {
            fputs("wham: your Mac refused the setting, it is still \(on ? "off" : "on")\n", stderr)
            return false
        }
        return true
    }

    // `wham run make`: awake while the command runs, then as it was before.
    // If this process is killed first, its watchdog gives sleep back.
    private static func keepAwake(while command: [String]) -> Int32 {
        guard !command.isEmpty else { return usage() }
        let watchdog = Watchdog()
        var turnedOn = false
        if Sleep.isDisabled != true {
            if let refusal = refusal() {
                fputs("wham: \(refusal), running it without keeping your Mac awake\n", stderr)
            } else {
                watchdog.arm()
                turnedOn = flip(true)
                if turnedOn {
                    share(nil)
                    openApp()
                } else {
                    watchdog.standDown()
                }
            }
        }
        let status = spawn(command)
        if turnedOn {
            if Sleep.isDisabled == true && flip(false) { share(nil) }
            watchdog.standDown()
        }
        return status
    }

    // Runs the command in the foreground, as if typed, and returns its exit
    // status. A Ctrl-C reaches it from the terminal while this process waits it
    // out; a hangup or a kill sent here is passed on to it.
    private static func spawn(_ command: [String]) -> Int32 {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults)
        sigemptyset(&mask)
        for number in [SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE] { sigaddset(&defaults, number) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        signal(SIGINT, SIG_IGN)
        signal(SIGQUIT, SIG_IGN)
        let argv = command.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let error = posix_spawnp(&pid, command[0], nil, &attributes, argv, environ)
        guard error == 0 else {
            fputs("wham: \(command[0]): \(String(cString: strerror(error)))\n", stderr)
            return error == ENOENT ? 127 : 126
        }
        runningChild = pid
        signal(SIGTERM) { kill(runningChild, $0) }
        signal(SIGHUP) { kill(runningChild, $0) }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let signalNumber = status & 0x7f
        return signalNumber == 0 ? (status >> 8) & 0xff : 128 + signalNumber
    }

    private static func usage() -> Int32 {
        fputs("\(help)\n", stderr)
        return 64
    }

    private static func unreadable() -> Int32 {
        fputs("wham: can't read your Mac's sleep setting\n", stderr)
        return 1
    }

    static var help: String { """
    wham - keeps your Mac awake, even with the lid closed

    usage:
      wham on            your Mac stays awake, lid closed too
      wham on 2h         for two hours (45m, 1h30m, 1d...), then it sleeps as usual
      wham off           your Mac sleeps as usual
      wham run <cmd>     stays awake while the command runs, then as it was
      wham toggle        flip it
      wham status        say which one it is
      wham version

    On battery at \(Session.batteryLimit)% or less (Battery Limit, in the menu), or when your
    Mac gets critically hot, Wham lets it sleep.

    The menu bar app does the same with one click. https://wham.sh
    """ }
}

// The command `wham run` waits on, for the signal handlers (which cannot capture).
private var runningChild: pid_t = 0
