import Foundation
import IOKit

// The only state is the kernel's: IOPMrootDomain's "SleepDisabled", the flag
// `pmset disablesleep` sets. Unlike power assertions (what Caffeine-style apps
// hold), it also blocks the sleep triggered by closing the lid. Nothing caches
// it: every click and every tick re-reads it, so the switch cannot drift from
// what the Mac will actually do.
enum Sleep {
    static let sudoersFile = "/private/etc/sudoers.d/wham"
    static let pmset = "/usr/bin/pmset"

    // nil when the kernel does not answer.
    static var isDisabled: Bool? { root("SleepDisabled") }

    // The lid sensor. The evals stand in for the lid with a file named in
    // WHAM_FAKE_LID, read each time: "closed", "closed monitor" (a monitor
    // drives the closed Mac), anything else for open.
    static var lidClosed: Bool { fakeLid.map { $0.contains("closed") } ?? root("AppleClamshellState") ?? false }

    // Closed, and the kernel's word that a closed lid puts the Mac to sleep:
    // not when a monitor drives it.
    static var lidSleeps: Bool {
        lidClosed && (fakeLid.map { !$0.contains("monitor") } ?? root("AppleClamshellCausesSleep") ?? false)
    }

    private static var fakeLid: String? {
        ProcessInfo.processInfo.environment["WHAM_FAKE_LID"].map { (try? String(contentsOfFile: $0, encoding: .utf8)) ?? "" }
    }

    // The kernel weighs the lid when it moves or the power source changes,
    // never when the flag clears: a Mac given sleep back under a closed lid
    // stays awake, draining and heating as if Wham were still on, until
    // something else happens. This does what closing the lid would have done.
    // Not under the evals' stand-in lid: the journal line is the proof.
    static func sleepNow() {
        guard fakeLid == nil else { return }
        run(pmset, ["sleepnow"])
    }

    // The same for the watchdog's shell, once it gave sleep back: the lid
    // closed, closing it sleeps, and the flag off, all three or nothing.
    static let sleepUnderLidShell = "[ \"$(/usr/sbin/ioreg -rd1 -c IOPMrootDomain | /usr/bin/grep -cE "
        + "'\"(AppleClamshellState|AppleClamshellCausesSleep)\" = Yes|\"SleepDisabled\" = No')\" = 3 ] && \(pmset) sleepnow"

    // For a Wham on its way out, which cannot wait itself: a shell that
    // outlives it waits, then does the same. Long enough for `brew upgrade`,
    // whose new copy turns back on: the flag is on again, the Mac stays up.
    static func sleepUnderLidAfterExit(in seconds: Int = 30) {
        guard fakeLid == nil else { return }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "trap '' INT QUIT HUP; sleep \(seconds); \(sleepUnderLidShell)"]
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        try? shell.run()
    }

    // Looked up once: the tick reads it every two seconds.
    private static let rootDomain = IOServiceGetMatchingService(0, IOServiceMatching("IOPMrootDomain"))

    private static func root(_ key: String) -> Bool? {
        guard rootDomain != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    // Lets one user run exactly the two pmset commands Wham needs as root,
    // without a password. By user ID: names can hold spaces, dots, @ or a
    // domain, which sudoers would read as syntax.
    static func rule(uid: uid_t = getuid()) -> String {
        "#\(uid) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    }

    static var hasRule: Bool { FileManager.default.fileExists(atPath: sudoersFile) }

    // `sudo -n` never prompts, so this fails until the rule is installed. It
    // trusts the kernel, not the exit code. Blocks for up to 2 s: call it off
    // the main thread. The journal says why, and how it went.
    static func set(_ on: Bool, why: String) -> Bool {
        let started = Date()
        let (status, error) = runReading("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"])
        let ok = status == 0 && confirm(on)
        if ok { wrote(on) }
        Journal.note("flag", ["on": on, "why": why, "ok": ok, "took": "\(Int(Date().timeIntervalSince(started) * 1000))ms",
                              "sudo": ok ? nil : status, "error": ok ? nil : error,
                              "kernel": ok || status != 0 ? nil : isDisabled.map { $0 ? "on" : "off" } ?? "unreadable"])
        return ok
    }

    // What this process last wrote to the flag, and when: a change it did
    // not make is someone else's, which the journal says.
    private static let lock = NSLock()
    private static var lastWrite: (on: Bool, at: Date)?

    static func wrote(_ on: Bool) {
        lock.lock()
        lastWrite = (on, Date())
        lock.unlock()
    }

    static func wroteLately(_ on: Bool, within seconds: TimeInterval = 10) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastWrite else { return false }
        return lastWrite.on == on && Date().timeIntervalSince(lastWrite.at) < seconds
    }

    // Waits for the kernel to report the new value.
    static func confirm(_ on: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while isDisabled != on && Date() < deadline { usleep(50_000) }
        return isDisabled == on
    }

    enum Install { case done, cancelled, failed(String) }
    static let noIncludeDir = "wham-no-includedir"

    // One time, through macOS's own administrator prompt.
    static func installRule() -> Install {
        var error: NSDictionary?
        NSAppleScript(source: installScript)?.executeAndReturnError(&error)
        guard let error else { return .done }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
        if message.contains(noIncludeDir) {
            // sudoers skips sudoers.d: a Mac set up by an organization, where a
            // `wham on` from an administrator still works, asking each time.
            return .failed("this Mac is set up by an organization in a way that does not let apps turn sleep off (common on work Macs).")
        }
        return .failed(message)
    }

    // What macOS shows above the password field: why Wham asks, and what it
    // can then do.
    static var prompt: String {
        Words.say("Keeping your Mac awake with the lid closed takes a system setting that only an administrator can change. "
            + "Wham asks once; after that, it can turn that one setting on and off, and nothing else.")
    }

    static var installScript: String {
        "do shell script \"\(installShell())\" with administrator privileges with prompt \"\(prompt)\""
    }

    // What runs as root. The rule is checked by visudo before it goes live, and
    // written under a name with a dot first, since sudo skips such files. Some
    // managed Macs strip the line that makes sudo read sudoers.d: then the rule
    // would do nothing, so it says so instead. The paths are for the tests.
    static func installShell(sudoers: String = "/etc/sudoers", file: String = sudoersFile) -> String {
        let tmp = file + ".tmp"
        let folder = (file as NSString).deletingLastPathComponent
        return "grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers[.]d/?[[:space:]]*$' \(sudoers) || { echo \(noIncludeDir) >&2; exit 1; }; "
            + "mkdir -p \(folder) && echo '\(rule())' > \(tmp) && /usr/sbin/visudo -cf \(tmp) >/dev/null "
            + "&& chown root:wheel \(tmp) && chmod 0440 \(tmp) && mv \(tmp) \(file) || { rm -f \(tmp); exit 1; }"
    }

    // Its exit status and the first line it wrote to stderr.
    static func runReading(_ path: String, _ args: [String]) -> (status: Int32, error: String?) {
        let process = Process(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init)
        return (process.terminationStatus, line)
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], quiet: Bool = true) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

// If whoever turned sleep off goes away without giving it back (a crash, a
// force quit, a closed terminal), the Mac must not stay awake with nothing left
// to show it. While on, Wham keeps a tiny shell waiting on a pipe that only Wham
// writes to. However Wham ends, the kernel closes that pipe, and the shell gives
// sleep back. Wham tells it to stand down when it turns off, or leaves on purpose.
final class Watchdog {
    private var input: FileHandle?
    var isArmed: Bool { input != nil }

    // `command` and `then` are for the tests. Once the command ran, the shell
    // says so in the journal, then puts a Mac under a closed lid to sleep.
    func arm(command: String = "/usr/bin/sudo -n \(Sleep.pmset) -a disablesleep 0", then: String = Sleep.sleepUnderLidShell) {
        guard input == nil else { return }
        Journal.prepare()
        let pipe = Pipe(), shell = Process()
        // The writing end stays in this process alone: a child holding it,
        // the shell included, would keep the pipe open.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A Ctrl-C or a hangup meant for a terminal does not reach it.
        shell.arguments = ["-c", "trap '' INT QUIT HUP; read -r word; [ \"$word\" = stand-down ] && exit 0; \(command); status=$?; \(Journal.watchdogLine); \(then)"]
        shell.standardInput = pipe
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return Journal.note("watchdog", ["armed": false]) }
        input = pipe.fileHandleForWriting
        Journal.note("watchdog", ["armed": true, "shell": shell.processIdentifier])
    }

    func standDown() {
        guard let input else { return }
        Journal.note("watchdog", ["armed": false])
        // Throws rather than signals if the shell is already gone.
        try? input.write(contentsOf: Data("stand-down\n".utf8))
        try? input.close()
        self.input = nil
    }
}
