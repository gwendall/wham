import Foundation
import Security

// Wham's checks, without Xcode's test runner: compiled with the app's pure
// sources by scripts/test.sh, they exit non-zero on the first failure.

// Run again by the watchdog checks below: arms one, starts a long child that
// must not keep the watchdog's pipe open, then dies the hard way.
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--arm-and-die" {
    let watchdog = Watchdog()
    watchdog.arm(command: "/usr/bin/touch '\(CommandLine.arguments[2])'")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["5"]
    child.standardOutput = FileHandle.nullDevice
    try? child.run()
    print(child.processIdentifier)
    fflush(stdout)
    withExtendedLifetime(watchdog) { _ = kill(getpid(), SIGKILL) }
}

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("ok   \(message)")
    } else {
        print("FAIL \(message) (tests/main.swift:\(line))")
        failures += 1
    }
}

// The pitch of a stretch of the chime, from its autocorrelation.
func pitch(_ samples: [Float], from start: Double, length: Double) -> Double {
    let a = Int(start * Chime.rate), n = Int(length * Chime.rate)
    let window = Array(samples[a..<min(a + n, samples.count)])
    var best = (lag: 0, score: -Float.infinity)
    for lag in 20...80 {
        var score: Float = 0
        for i in 0..<(window.count - lag) { score += window[i] * window[i + lag] }
        if score > best.score { best = (lag, score) }
    }
    return Chime.rate / Double(best.lag)
}

// Chime: four notes that climb to switch on and fall to switch off.
for on in [true, false] {
    let samples = Chime.samples(on: on)
    let pitches = (0..<4).map { pitch(samples, from: Double($0) * Chime.gap + 0.008, length: 0.034) }
    let expected = (on ? Chime.steps : Chime.steps.reversed()).map { Chime.root * pow(2, Double($0) / 12) }
    let close = zip(pitches, expected).allSatisfy { abs($0 - $1) / $1 < 0.03 }
    check(close, "\(on ? "on" : "off") chime plays \(expected.map { Int($0) }) Hz (heard \(pitches.map { Int($0) }))")
    let peak = samples.map(abs).max() ?? 0
    check(abs(peak - (on ? 0.25 : 0.19)) < 0.001, "\(on ? "on" : "off") chime peaks at \(on ? 0.25 : 0.19)")
    check(abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.001, "\(on ? "on" : "off") chime starts and ends in silence")
}
let wav = Chime.wav([0, 0.5, -0.5])
check(wav.count == 44 + 6 && String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF", "WAV header and size")

// The sudoers rule allows exactly the two pmset commands.
check(Sleep.rule(uid: 501) == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1",
      "sudoers rule text, by user ID")
let ruleFile = FileManager.default.temporaryDirectory.appendingPathComponent("wham-rule-test")
try Sleep.rule().appending("\n").write(to: ruleFile, atomically: true, encoding: .utf8)
check(Sleep.run("/usr/sbin/visudo", ["-cf", ruleFile.path]) == 0, "visudo accepts the rule")
try? FileManager.default.removeItem(at: ruleFile)
check(Sleep.sudoersFile == "/private/etc/sudoers.d/wham" && !URL(fileURLWithPath: Sleep.sudoersFile).lastPathComponent.contains("."),
      "sudoers file name has no dot (sudo would skip it)")

// The install script: valid AppleScript, and its shell does the right thing
// with stand-in paths. As root only where sudo needs no password (CI).
var compileError: NSDictionary?
check(NSAppleScript(source: Sleep.installScript)?.compileAndReturnError(&compileError) == true, "install AppleScript compiles")
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("wham-install-\(getpid())")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
func shell(_ script: String, root: Bool = false) -> (status: Int32, output: String) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: root ? "/usr/bin/sudo" : "/bin/sh")
    process.arguments = root ? ["-n", "/bin/sh", "-c", script] : ["-c", script]
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
let managed = scratch.appendingPathComponent("sudoers-managed").path
let stock = scratch.appendingPathComponent("sudoers-stock").path
try "root ALL=(ALL) ALL\n".write(toFile: managed, atomically: true, encoding: .utf8)
try "root ALL=(ALL) ALL\n#includedir /private/etc/sudoers.d\n".write(toFile: stock, atomically: true, encoding: .utf8)
let target = scratch.appendingPathComponent("sudoers.d/wham").path
let refused = shell(Sleep.installShell(sudoers: managed, file: target))
check(refused.status != 0 && refused.output.contains(Sleep.noIncludeDir) && !FileManager.default.fileExists(atPath: target),
      "a sudoers without includedir is refused, nothing written")
let unprivileged = shell(Sleep.installShell(sudoers: stock, file: target))
check(unprivileged.status != 0 && !FileManager.default.fileExists(atPath: target) && !FileManager.default.fileExists(atPath: target + ".tmp"),
      "without root the install fails cleanly, no file left behind")
if shell("true", root: true).status == 0 {
    let installed = shell(Sleep.installShell(sudoers: stock, file: target), root: true)
    let attributes = try? FileManager.default.attributesOfItem(atPath: target)
    // 0440 root:wheel is unreadable to an admin user (wheel is root alone): read it as root.
    let content = shell("cat '\(target)'", root: true).output
    check(installed.status == 0 && (attributes?[.posixPermissions] as? Int) == 0o440 && (attributes?[.ownerAccountName] as? String) == "root"
          && content == Sleep.rule() + "\n",
          "as root the rule lands, 0440 root, exactly the rule\(installed.status == 0 ? "" : " (\(installed.output))")")
    _ = shell("rm -rf '\(scratch.path)'", root: true)
} else {
    print("skip installing as root (sudo asks for a password here)")
}
try? FileManager.default.removeItem(at: scratch)

// The kernel answers. CI machines are virtual and may not have the flag.
let kernelAnswers = Sleep.isDisabled != nil
let onCI = ProcessInfo.processInfo.environment["CI"] != nil
if kernelAnswers || !onCI {
    check(kernelAnswers, "IOPMrootDomain reports SleepDisabled")
} else {
    print("skip IOPMrootDomain has no SleepDisabled on this CI machine")
}

// Sprites are square, one cell per pixel.
for (name, sprite) in [("sun", Pixels.sun), ("moon", Pixels.moon)] {
    check(sprite.count == 11 && sprite.allSatisfy { $0.count == 11 }, "\(name) sprite is 11 x 11")
    check(Pixels.image(sprite, color: Pixels.ink)?.width == 11, "\(name) sprite renders")
    let cells = sprite.enumerated().flatMap { y, row in row.enumerated().filter { $0.element == "#" }.map { (x: $0.offset, y: y) } }
    check(cells.map(\.x).min() == 0 && cells.map(\.x).max() == 10 && cells.map(\.y).min() == 0 && cells.map(\.y).max() == 10,
          "\(name)'s ink fills its box, so centering the box centers the \(name)")
}

// Updates: the latest version from GitHub's redirect, compared number by number,
// and only Wham signed by its developer goes in.
check(Update.version(fromTag: "https://github.com/gwendall/wham/releases/tag/v1.2.0") == "1.2.0", "version from the release redirect")
check(Update.version(fromTag: "https://github.com/gwendall/wham/releases") == nil && Update.version(fromTag: "") == nil, "no tag, no version")
check(Update.version(fromTag: "https://github.com/gwendall/wham/releases/tag/v1.2.0-beta") == nil, "a pre-release is not offered")
check(Update.isNewer("1.10.0", than: "1.9.9") && Update.isNewer("2", than: "1.9.9") && Update.isNewer("1.0.1", than: "1.0"),
      "newer, number by number")
check(!Update.isNewer("1.0", than: "1.0.0") && !Update.isNewer("1.0.0", than: "1.0.1") && !Update.isNewer("1.0.1", than: "dev"),
      "same, older, or against a build from source: no update")
var requirement: SecRequirement?
check(SecRequirementCreateWithString(Update.requirement as CFString, [], &requirement) == errSecSuccess, "the signature requirement compiles")
check(!Update.isGenuine(URL(fileURLWithPath: CommandLine.arguments[0])) && !Update.isGenuine(URL(fileURLWithPath: "/System/Applications/Calculator.app")),
      "an app not signed by Wham's developer is refused")

// Sessions end on their own: the heat first, then a low battery (on battery
// only), then the time.
let now = Date()
check(Session.end(.init(now: now)) == nil && Session.end(.init(now: now, offAt: now.addingTimeInterval(1))) == nil,
      "nothing ends a session early")
check(Session.end(.init(now: now, offAt: now)) == .time, "a timed session ends on time")
check(Session.end(.init(now: now, onBattery: true, battery: 11)) == nil && Session.end(.init(now: now, onBattery: true, battery: 10)) == .battery,
      "on battery, 10% ends it")
check(Session.end(.init(now: now, onBattery: false, battery: 3)) == nil && Session.end(.init(now: now, onBattery: true, battery: nil)) == nil,
      "plugged in, or without a battery, the charge does not matter")
check(Session.end(.init(now: now, offAt: now, onBattery: true, battery: 3, critical: true)) == .heat, "the heat comes first")
check(Session.why(.battery, battery: 9) == "Battery at 9%" && Session.refusal(.heat, battery: nil).contains("too hot"), "it says why")

let durations: [(String, TimeInterval?)] = [
    ("45m", 2700), ("2h", 7200), ("1h30m", 5400), ("1d", 86400), ("90s", 90), ("2H", 7200), ("0h5m", 300),
    ("", nil), ("2", nil), ("h", nil), ("m2", nil), ("30m1h", nil), ("1h1h", nil), ("0m", nil), ("1.5h", nil), ("-1h", nil), ("2 h", nil), ("1w", nil),
]
for (text, seconds) in durations {
    check(Session.duration(text) == seconds, "'\(text)' is \(seconds.map { "\(Int($0)) s" } ?? "not a duration")")
}
let tomorrow = now.addingTimeInterval(86400)
check(Session.clock(tomorrow, now: now).count > Session.clock(tomorrow, now: tomorrow).count, "another day's end says its day")

// The watchdog gives sleep back when whoever armed it dies, here a stand-in
// that touches a file, and does nothing once told to stand down.
func fired(_ file: String) -> Bool {
    let deadline = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: file) && Date() < deadline { usleep(20_000) }
    defer { try? FileManager.default.removeItem(atPath: file) }
    return FileManager.default.fileExists(atPath: file)
}
let bark = NSTemporaryDirectory() + "wham-watchdog-\(getpid())"
let killed = Process(), killedOutput = Pipe()
killed.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
killed.arguments = ["--arm-and-die", bark]
killed.standardOutput = killedOutput
try killed.run()
killed.waitUntilExit()
let orphan = Int32(String(decoding: killedOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
check(killed.terminationReason == .uncaughtSignal && fired(bark), "killed with -9, the watchdog fires")
check(orphan > 0 && kill(orphan, 0) == 0, "even with a child of the dead process still running (it does not hold the pipe)")
if orphan > 0 { kill(orphan, SIGTERM) }
let calm = Watchdog()
calm.arm(command: "/usr/bin/touch '\(bark)'")
calm.arm(command: "/usr/bin/touch '\(bark)-twice'")
check(calm.isArmed, "armed")
// What a terminal sends a whole group on Ctrl-C, Ctrl-\\ or when it closes.
let shells = shell("pgrep -f 'stand-down.*\(bark)'").output.split(separator: "\n").compactMap { Int32($0) }
for pid in shells { for signal in [SIGINT, SIGQUIT, SIGHUP] { kill(pid, signal) } }
usleep(200_000)
check(shells.count == 1 && kill(shells[0], 0) == 0 && !fired(bark), "Ctrl-C, Ctrl-\\ and hangups do not set it off")
calm.standDown()
check(!calm.isArmed && !fired(bark) && !fired(bark + "-twice"), "stood down, it does nothing; armed twice, one watchdog")
usleep(200_000)
check(shells.allSatisfy { kill($0, 0) != 0 }, "and it is gone")

// The battery, as macOS reports it, and the stand-in the evals use.
let batt = shell("pmset -g batt").output
let power = Power.read()
if let percent = batt.range(of: #"\d+(?=%)"#, options: .regularExpression).map({ Int(batt[$0]) }) ?? nil {
    check(power.level.map { abs($0 - percent) <= 1 } == true && power.onBattery == batt.contains("'Battery Power'"),
          "battery read: \(power.level ?? -1)%, \(power.onBattery ? "on battery" : "plugged in") (pmset: \(percent)%)")
} else {
    check(power.level == nil && !power.onBattery, "no battery on this Mac, none read")
}
// The heat, as macOS's thermal daemon posts it.
let posted = shell("notifyutil -g \(Heat.name)").output.split(separator: " ").last.flatMap { UInt64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
check(Heat.level != nil && Heat.level == posted,
      "thermal pressure read: \(Heat.level.map(String.init) ?? "none") (notifyutil: \(posted.map(String.init) ?? "none"))")
let standIn = NSTemporaryDirectory() + "wham-power-\(getpid())"
try "battery 9 critical\n".write(toFile: standIn, atomically: true, encoding: .utf8)
setenv("WHAM_FAKE_POWER", standIn, 1)
let faked = Session.read(offAt: nil)
check(faked.onBattery && faked.battery == 9 && faked.critical, "WHAM_FAKE_POWER stands in for the battery and the heat")
try "ac\n".write(toFile: standIn, atomically: true, encoding: .utf8)
let plugged = Session.read(offAt: nil)
check(!plugged.onBattery && plugged.battery == nil && !plugged.critical, "and is read each time")
unsetenv("WHAM_FAKE_POWER")
try? FileManager.default.removeItem(atPath: standIn)

// The end of a timed session, shared through the app's preferences.
let saved = Session.offAt
let end = Date(timeIntervalSince1970: (now.timeIntervalSince1970 + 3600).rounded())
Session.offAt = end
check(Session.offAt == end && shell("defaults read sh.wham.app offAt").status == 0, "the end is shared through preferences")
Session.offAt = nil
check(Session.offAt == nil && shell("defaults read sh.wham.app offAt 2>/dev/null").status != 0, "and cleared")
Session.offAt = saved

// The command line.
check(CLI.commands.isSuperset(of: ["on", "off", "toggle", "status", "version", "help"]), "CLI knows its commands")
check(CLI.run(["version"]) == 0, "wham version succeeds")
check(CLI.run(["status"]) == (kernelAnswers ? 0 : 1), "wham status succeeds, or says it can't read the flag")
check(CLI.run(["nope"]) == 64, "an unknown command exits 64")
check(CLI.describe(true).contains("lid closed") && CLI.describe(false).contains("sleeps"), "status words")
check(CLI.describe(true, until: now).contains("until"), "a timed session says until when")
check(CLI.run(["on", "2x"]) == 64 && CLI.run(["on", "2h", "3h"]) == 64 && CLI.run(["off", "now"]) == 64 && CLI.run(["run"]) == 64,
      "bad arguments exit 64, before touching anything")
// `wham run` flips the flag where it can do so without asking (CI), or where it is already on.
if kernelAnswers && (Sleep.isDisabled == true || shell("true", root: true).status == 0) {
    let before = Sleep.isDisabled
    check(CLI.run(["run", "/bin/sh", "-c", "exit 3"]) == 3, "wham run exits with its command's status")
    check(CLI.run(["run", "/bin/sh", "-c", "kill -TERM $$"]) == 128 + SIGTERM, "or 128 + the signal that killed it")
    check(CLI.run(["run", "wham-no-such-command"]) == 127, "127 for a command that does not exist")
    check(Sleep.isDisabled == before, "and leaves sleep as it found it")
} else {
    print("skip wham run (it would ask for a password here)")
}

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
