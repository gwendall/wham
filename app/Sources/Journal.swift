import Darwin
import Foundation
import os

// What Wham did and what it saw, one line per event, to tell afterwards what
// happened: ~/Library/Logs/Wham/Wham.log, which `wham log` prints and Console
// opens. Each line also goes to the Mac's own log (subsystem sh.wham.app),
// next to what macOS says about sleep and the network at that moment.
//
// It stays on the Mac and is never sent anywhere. Nothing in it names the
// user, the Mac, a network or an address: no network name, no IP or hardware
// address, no user or host name (sudo's own words have them taken out), and
// of a `wham run` command only the program's name. Small: two files of
// 256 KB at most, the older one dropped. Written from a background queue, a
// line at a time, only when something happens.
enum Journal {
    static let limit = 256 * 1024

    // WHAM_LOG_DIR moves it, for the tests and the evals.
    static let folder: URL = {
        if let dir = ProcessInfo.processInfo.environment["WHAM_LOG_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Wham")
    }()
    static var file: URL { folder.appendingPathComponent("Wham.log") }
    static var older: URL { folder.appendingPathComponent("Wham.1.log") }

    // Who writes: the menu bar app or the `wham` command.
    static var source = "app"

    private static let queue = DispatchQueue(label: "sh.wham.journal", qos: .utility)
    private static let system = OSLog(subsystem: "sh.wham.app", category: "journal")

    // "flag on=yes why=switch took=84ms": the event, then what it is about.
    // A nil value is left out.
    static func note(_ event: String, _ fields: KeyValuePairs<String, Any?> = [:]) {
        note(event, fields.map { ($0.key, $0.value) })
    }

    static func note(_ event: String, _ fields: [(String, Any?)]) {
        let text = Self.text(event, fields)
        let stamped = "\(stamp(Date())) \(source)[\(getpid())] \(text)"
        os_log("%{public}@", log: system, type: .default, text)
        queue.async { append(stamped) }
    }

    // Waits for the lines still on their way: before the command exits, or
    // the app leaves without its run loop.
    static func flush() { queue.sync {} }

    static func text(_ event: String, _ fields: [(String, Any?)]) -> String {
        var words = [event]
        for (key, value) in fields {
            guard let value, let shown = show(value) else { continue }
            words.append("\(key)=\(quote(shown))")
        }
        return words.joined(separator: " ")
    }

    // "2026-10-13 20:31:05.123 +0200", in the Mac's time zone.
    static func stamp(_ date: Date) -> String {
        var seconds = time_t(date.timeIntervalSince1970.rounded(.down)), parts = tm()
        localtime_r(&seconds, &parts)
        var buffer = [CChar](repeating: 0, count: 64)
        strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M:%S", &parts)
        let milliseconds = Int(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * 1000)
        var zone = [CChar](repeating: 0, count: 16)
        strftime(&zone, zone.count, "%z", &parts)
        return String(cString: buffer) + String(format: ".%03d ", milliseconds) + String(cString: zone)
    }

    private static func show(_ value: Any) -> String? {
        switch value {
        case let flag as Bool: return flag ? "yes" : "no"
        case let date as Date: return stamp(date)
        case let number as Double: return String(format: "%g", number)
        case let text as String: return text.isEmpty ? nil : scrub(text)
        default: return "\(value)"
        }
    }

    // A value with a space, a quote or an equal sign, in quotes, on one line.
    static func quote(_ value: String) -> String {
        let flat = value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        guard flat.contains(where: { $0 == " " || $0 == "\"" || $0 == "=" || $0 == "\\" }) else { return flat }
        return "\"" + flat.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // The home folder as ~, the user's and the Mac's names taken out, as
    // whole words (a short name stays inside longer ones).
    static func scrub(_ text: String) -> String {
        var text = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for (name, stand) in names {
            text = name.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: stand)
        }
        return text
    }

    private static let names: [(NSRegularExpression, String)] = [(NSFullUserName(), "<user>"), (NSUserName(), "<user>"), (hostName, "<mac>")]
        .filter { $0.0.count >= 3 }
        .compactMap { name, stand in
            (try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b", options: .caseInsensitive)).map { ($0, stand) }
        }

    // gethostname, not ProcessInfo's, which may ask the network.
    private static let hostName: String = {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        let name = String(cString: buffer)
        return String(name.split(separator: ".").first ?? "")
    }()

    // Before something else writes there: the watchdog's shell.
    static func prepare() { queue.sync { makeFolder() } }

    // Only its user may open it.
    private static func makeFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // One write per line, appended: the app and the command can both write.
    // Past the limit, the file becomes the older one, which drops the one before.
    private static func append(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        var info = stat()
        if stat(file.path, &info) == 0, Int(info.st_size) + bytes.count > limit {
            rename(file.path, older.path)
        }
        func open() -> Int32 { Darwin.open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600) }
        var fd = open()
        // The first line, or the folder was deleted meanwhile.
        if fd < 0 && errno == ENOENT {
            makeFolder()
            fd = open()
        }
        guard fd >= 0 else { return }
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    // The last `count` lines, across both files.
    static func tail(_ count: Int) -> [String] {
        flush()
        let text = [older, file].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init))
    }

    // What the watchdog's shell appends once it gave sleep back for this
    // process, gone, with the exit status of its command (in $status). The
    // shell's date has no milliseconds.
    static var watchdogLine: String {
        "printf '%s watchdog[%s] fired for=\(getpid()) status=%s\\n' \"$(date '+%Y-%m-%d %H:%M:%S %z')\" \"$$\" \"$status\" >> \(shellQuote(file.path))"
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // A file in the journal's folder while the app runs: still there at the
    // next launch, the app ended without quitting (a crash, a force quit, the
    // Mac losing power). It holds when that run started.
    static var marker: URL { folder.appendingPathComponent("running") }

    static func markRunning() -> Date? {
        flush()
        let previous = try? String(contentsOf: marker, encoding: .utf8)
        prepare()
        try? "\(Date().timeIntervalSince1970)\n".write(to: marker, atomically: true, encoding: .utf8)
        return previous.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.map { Date(timeIntervalSince1970: $0) }
    }

    static func markStopped() {
        try? FileManager.default.removeItem(at: marker)
    }

    // Wham's newest crash report since `date`, by name only: macOS writes
    // them to ~/Library/Logs/DiagnosticReports.
    static func crashReport(since date: Date) -> String? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("Wham") }
            .compactMap { url -> (String, Date)? in
                guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      modified > date else { return nil }
                return (url.lastPathComponent, modified)
            }
            .max { $0.1 < $1.1 }?.0
    }
}

// A few facts about the Mac, for the journal's launch line.
enum Machine {
    static var model: String { sysctl("hw.model") ?? "?" }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        var translated: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1 ? "x86_64-rosetta" : "x86_64"
        #endif
    }

    static var macOS: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var booted: Date? {
        var time = timeval(), size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
