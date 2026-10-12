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
    static var isDisabled: Bool? {
        let root = IOServiceGetMatchingService(0, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? Bool
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
    // the main thread.
    static func set(_ on: Bool) -> Bool {
        guard run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]) == 0 else { return false }
        return confirm(on)
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
            return .failed("this Mac's sudo settings skip /private/etc/sudoers.d (common on managed Macs). Use `wham on` in Terminal instead.")
        }
        return .failed(message)
    }

    static var installScript: String {
        let prompt = "Wham needs your permission, just once, to keep your Mac from sleeping."
        return "do shell script \"\(installShell())\" with administrator privileges with prompt \"\(prompt)\""
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
