import Darwin
import Foundation

// `wham on`, `wham off`, `wham status`: the same switch, from a terminal. The
// `wham` command is a link to the app's own binary; the app sees the name it
// was called by and answers here instead of opening the menu bar item.
enum CLI {
    static let commands: Set<String> = ["on", "off", "toggle", "status", "version", "--version", "-v", "help", "--help", "-h"]

    // Called through the `wham` link, Bundle.main is the link's folder: the
    // version comes from the bundle the binary really sits in.
    static var version: String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let bundle = proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0
            ? Bundle(url: URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            : nil
        return (bundle ?? .main).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static func run(_ args: [String]) -> Int32 {
        switch args.first ?? "help" {
        case "on": return set(true)
        case "off": return set(false)
        case "toggle":
            guard let current = Sleep.isDisabled else { return unreadable() }
            return set(!current)
        case "status":
            guard let current = Sleep.isDisabled else { return unreadable() }
            print(describe(current))
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

    static func describe(_ on: Bool) -> String {
        on ? "on: your Mac stays awake, even with the lid closed" : "off: your Mac sleeps as usual"
    }

    // Without the app's sudoers rule, falls back to a plain `sudo`, which asks
    // for the password in the terminal.
    private static func set(_ on: Bool) -> Int32 {
        if Sleep.isDisabled == on {
            print(describe(on))
            return 0
        }
        if !Sleep.set(on) {
            Sleep.run("/usr/bin/sudo", [Sleep.pmset, "-a", "disablesleep", on ? "1" : "0"], quiet: false)
            guard Sleep.confirm(on) else {
                fputs("wham: your Mac refused the setting, it is still \(on ? "off" : "on")\n", stderr)
                return 1
            }
        }
        print(describe(on))
        return 0
    }

    private static func unreadable() -> Int32 {
        fputs("wham: can't read your Mac's sleep setting\n", stderr)
        return 1
    }

    static let help = """
    wham - keeps your Mac awake, even with the lid closed

    usage:
      wham on        your Mac stays awake, lid closed too
      wham off       your Mac sleeps as usual
      wham toggle    flip it
      wham status    say which one it is
      wham version

    The menu bar app does the same with one click. https://wham.sh
    """
}
