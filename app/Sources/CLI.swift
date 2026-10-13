import AppKit
import Darwin
import Foundation

// `wham on`, `wham off`, `wham status`: the same switch, from a terminal. The
// `wham` command is a link to the app's own binary; the app sees the name it
// was called by and answers here instead of opening the menu bar item.
enum CLI {
    static let commands: Set<String> = ["on", "off", "toggle", "status", "run", "log", "version", "--version", "-v", "help", "--help", "-h"]

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
        Journal.source = "cli"
        Words.english = true
        switch args.first ?? "help" {
        case "on":
            guard args.count <= 2 else { return usage() }
            guard args.count == 2 else { return on(for: nil, why: "cli on") }
            guard let length = Session.duration(args[1]) else {
                fputs("wham: '\(args[1])' is not a duration: try 45m, 2h or 1h30m\n", stderr)
                return 64
            }
            return on(for: length, why: "cli on \(args[1])")
        case "off": return args.count == 1 ? off(why: "cli off") : usage()
        case "toggle":
            guard let current = Sleep.isDisabled else { return unreadable() }
            return current ? off(why: "cli toggle") : on(for: nil, why: "cli toggle")
        case "status":
            guard let current = Sleep.isDisabled else { return unreadable() }
            print(describe(current, until: current ? Session.offAt : nil))
            return 0
        case "run":
            return keepAwake(while: Array(args.dropFirst()))
        case "log":
            guard args.count <= 2, let count = args.count == 2 ? Int(args[1]) : 50, count > 0 else { return usage() }
            let lines = Journal.tail(count)
            if lines.isEmpty { fputs("wham: nothing in the journal yet (\(Journal.scrub(Journal.file.path)))\n", stderr) }
            for line in lines { print(line) }
            return 0
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

    private static func on(for length: TimeInterval?, why: String) -> Int32 {
        if let refusal = refusal() {
            fputs("wham: \(refusal)\n", stderr)
            return 1
        }
        guard flip(true, why: why) else { return 1 }
        let until = length.map { Date().addingTimeInterval($0) }
        share(until)
        openApp()
        print(describe(true, until: until))
        return 0
    }

    private static func off(why: String) -> Int32 {
        guard flip(false, why: why) else { return 1 }
        share(nil)
        print(describe(false))
        return 0
    }

    // Low battery or a hot Mac: the reason not to turn on, if there is one.
    private static func refusal() -> String? {
        let reading = Session.read(offAt: nil)
        guard let end = Session.end(reading) else { return nil }
        Journal.note("refused", ["reason": "\(end)", "battery": reading.battery, "limit": reading.batteryLimit,
                                 "draining": reading.draining ? true : nil])
        let text = Session.refusal(end, battery: reading.battery, pluggedIn: reading.draining)
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
    private static func flip(_ on: Bool, why: String) -> Bool {
        if Sleep.isDisabled == on || Sleep.set(on, why: why) { return true }
        let status = Sleep.run("/usr/bin/sudo", [Sleep.pmset, "-a", "disablesleep", on ? "1" : "0"], quiet: false)
        let confirmed = Sleep.confirm(on)
        Journal.note("flag", ["on": on, "why": why, "via": "password", "ok": confirmed, "sudo": status])
        guard confirmed else {
            fputs("wham: your Mac refused the setting, it is still \(on ? "off" : "on")\n", stderr)
            return false
        }
        return true
    }

    // `wham run make`: awake while the command runs, then as it was before.
    // If this process is killed first, its watchdog gives sleep back.
    private static func keepAwake(while command: [String]) -> Int32 {
        guard !command.isEmpty else { return usage() }
        // The program's name only: its arguments may say anything.
        let program = URL(fileURLWithPath: command[0]).lastPathComponent
        let started = Date()
        let watchdog = Watchdog()
        var turnedOn = false
        if Sleep.isDisabled != true {
            if let refusal = refusal() {
                fputs("wham: \(refusal), running it without keeping your Mac awake\n", stderr)
            } else {
                watchdog.arm()
                turnedOn = flip(true, why: "cli run")
                if turnedOn {
                    share(nil)
                    openApp()
                } else {
                    watchdog.standDown()
                }
            }
        }
        Journal.note("run", ["program": program, "awake": turnedOn || Sleep.isDisabled == true])
        let status = spawn(command)
        Journal.note("run-ended", ["program": program, "status": status, "took": "\(Int(Date().timeIntervalSince(started)))s"])
        if turnedOn {
            if Sleep.isDisabled == true && flip(false, why: "cli run ended") { share(nil) }
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
      wham log [50]      the last lines of Wham's journal, to see what happened
      wham version

    \(guards)

    The menu bar app does the same with one click. https://wham.sh
    """ }

    // When Wham lets the Mac sleep on its own, with the menu's Battery Limit.
    private static var guards: String {
        let limit = Session.batteryLimit
        guard limit != Session.never else {
            return """
            When your Mac gets critically hot, Wham lets it sleep. On battery, it stays
            awake until the battery runs out (Battery Limit: Never, in the menu).
            """
        }
        return """
        On battery at \(limit)% or less (Battery Limit, in the menu), or when your
        Mac gets critically hot, Wham lets it sleep.
        """
    }
}

// The command `wham run` waits on, for the signal handlers (which cannot capture).
private var runningChild: pid_t = 0
