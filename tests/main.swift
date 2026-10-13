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

// The journal goes to a folder of the tests' own (set before anything
// writes; the run above inherits it).
let journalDir = NSTemporaryDirectory() + "wham-journal-\(getpid())"
setenv("WHAM_LOG_DIR", journalDir, 1)

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("ok   \(message)")
    } else {
        print("FAIL \(message) (tests/main.swift:\(line))")
        failures += 1
    }
}

// The pitch of a stretch of the chime, from its autocorrelation: its first
// peak nearly as high as the highest, which may be a period or two further.
func pitch(_ samples: [Float], from start: Double, length: Double) -> Double {
    let a = Int(start * Chime.rate), n = Int(length * Chime.rate)
    let window = Array(samples[a..<min(a + n, samples.count)])
    let scores = (20...100).map { lag -> (lag: Int, score: Float) in
        var score: Float = 0
        for i in 0..<(window.count - lag) { score += window[i] * window[i + lag] }
        return (lag, score / Float(window.count - lag))
    }
    let best = scores.map(\.score).max() ?? 0
    let peaks = scores.indices.filter { i in
        scores[i].score >= 0.9 * best && (i == 0 || scores[i].score >= scores[i - 1].score)
            && (i == scores.count - 1 || scores[i].score >= scores[i + 1].score)
    }
    return Chime.rate / Double(scores[peaks.first ?? 0].lag)
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
// The menu's sounds: each its own, quieter than the switch's, in silence at
// both ends.
let sounds = Chime.Sound.all.map { (sound: $0, samples: Chime.samples($0)) }
check(Set(sounds.map(\.samples)).count == sounds.count && Set(sounds.map(\.sound.name)).count == sounds.count,
      "\(sounds.count) sounds, each its own")
for (sound, samples) in sounds where sound != .on && sound != .off {
    let peak = samples.map(abs).max() ?? 0
    check(peak >= 0.07 && peak <= 0.1001 && abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.001,
          "\(sound.name): under the switch's chime (peak \(String(format: "%.3f", peak))), in silence at both ends")
}

// Checked goes up, unchecked down, as the switch does; a refusal sits under
// the key's E5.
let checked = Chime.samples(.check(true)), unchecked = Chime.samples(.check(false))
let ups = [pitch(checked, from: 0.005, length: 0.03), pitch(checked, from: 0.045, length: 0.03)]
let downs = [pitch(unchecked, from: 0.005, length: 0.03), pitch(unchecked, from: 0.045, length: 0.03)]
check(ups[1] > ups[0] * 1.3 && downs[0] > downs[1] * 1.3, "check climbs (\(ups.map { Int($0) }) Hz), uncheck falls (\(downs.map { Int($0) }) Hz)")
let no = pitch(Chime.samples(.refused), from: 0.005, length: 0.04)
check(no < Chime.root * 0.95, "refused sounds under E5 (\(Int(no)) Hz)")

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
check(Sleep.installScript.contains("with prompt \"\(Sleep.prompt)\"") && !Sleep.prompt.contains("\"") && Sleep.prompt.contains("administrator"),
      "the password prompt says why Wham asks")
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
check(Update.isUpdate(to: "1.2.3", from: "1.2.2", ranBefore: true) && Update.isUpdate(to: "1.10.0", from: "1.9.9", ranBefore: true),
      "the first launch of a newer version says so")
check(Update.isUpdate(to: "1.2.3", from: nil, ranBefore: true), "after 1.2.2 or older, which kept no version, too")
check(!Update.isUpdate(to: "1.2.3", from: nil, ranBefore: false), "not on the first launch ever: that one says hello")
check(!Update.isUpdate(to: "1.2.3", from: "1.2.3", ranBefore: true) && !Update.isUpdate(to: "1.2.2", from: "1.2.3", ranBefore: true),
      "not on the same version again, nor an older one")
check(!Update.isUpdate(to: "dev", from: "1.2.3", ranBefore: true) && !Update.isUpdate(to: "dev", from: nil, ranBefore: true),
      "nor a build from source")

// Sessions end on their own: the heat first, then a low battery (on battery
// only), then the time.
let now = Date()
check(Session.end(.init(now: now)) == nil && Session.end(.init(now: now, offAt: now.addingTimeInterval(1))) == nil,
      "nothing ends a session early")
check(Session.end(.init(now: now, offAt: now)) == .time, "a timed session ends on time")
check(Session.end(.init(now: now, onBattery: true, battery: 11)) == nil && Session.end(.init(now: now, onBattery: true, battery: 10)) == .battery,
      "on battery, 10% ends it")
check(Session.end(.init(now: now, onBattery: true, battery: 21, batteryLimit: 20)) == nil
      && Session.end(.init(now: now, onBattery: true, battery: 20, batteryLimit: 20)) == .battery
      && Session.end(.init(now: now, onBattery: true, battery: 6, batteryLimit: 5)) == nil,
      "the battery limit moves where it ends")
check(Session.end(.init(now: now, onBattery: false, battery: 3)) == nil && Session.end(.init(now: now, onBattery: true, battery: nil)) == nil,
      "plugged in, or without a battery, the charge does not matter")
check(Session.end(.init(now: now, offAt: now, onBattery: true, battery: 3, critical: true)) == .heat, "the heat comes first")
check(Session.end(.init(now: now, onBattery: true, battery: 0, batteryLimit: Session.never)) == nil
      && Session.end(.init(now: now, onBattery: true, battery: 1, critical: true, batteryLimit: Session.never)) == .heat
      && Session.end(.init(now: now, offAt: now, onBattery: true, battery: 1, batteryLimit: Session.never)) == .time,
      "Battery Limit Never: the battery never ends it, the heat and the time still do")
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

// What is left of a timed session: in words, rounded up to the minute, and as
// the share of the switch's candy still there.
let lefts: [(TimeInterval, String)] = [
    (7200, "2 hr"), (7080, "1 hr 58 min"), (7079.5, "1 hr 58 min"), (3601, "1 hr 1 min"), (2700, "45 min"),
    (59, "1 min"), (0.2, "1 min"), (-3, "1 min"), (86400, "24 hr"),
]
for (seconds, words) in lefts {
    check(Session.timeLeft(seconds) == words, "\(seconds) s left: '\(Session.timeLeft(seconds))'")
}
// On whole seconds, so the sums below are exact.
let noon = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded())
let hourAgo = noon.addingTimeInterval(-3600), hourOn = noon.addingTimeInterval(3600)
check(Session.remaining(now: hourAgo, from: hourAgo, to: hourOn) == 1 && Session.remaining(now: noon, from: hourAgo, to: hourOn) == 0.5
      && Session.remaining(now: hourOn, from: hourAgo, to: hourOn) == 0 && Session.remaining(now: tomorrow, from: hourAgo, to: hourOn) == 0,
      "the candy drains from whole to nothing over the session")
check(Session.remaining(now: noon, from: nil, to: hourOn) == 1 && Session.remaining(now: noon, from: hourAgo, to: nil) == 1,
      "untimed, or its start unknown: whole")
check(Session.warnAt(from: noon, to: hourOn) == noon.addingTimeInterval(3300) && Session.warnAt(from: nil, to: hourOn) == noon.addingTimeInterval(3300),
      "warned five minutes before the end")
check(Session.warnAt(from: noon, to: noon.addingTimeInterval(599)) == nil && Session.warnAt(from: noon, to: nil) == nil,
      "not for a session under ten minutes, nor an untimed one")

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
func barkedLines() -> [String] { Journal.tail(50).filter { $0.contains(" watchdog[") && $0.contains(" fired for=\(killed.processIdentifier) status=0") } }
// The shell writes its line just after its command ran.
let barkDeadline = Date().addingTimeInterval(2)
while barkedLines().isEmpty && Date() < barkDeadline { usleep(20_000) }
let barked = barkedLines()
check(barked.count == 1 && barked[0].range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4} watchdog\[\d+\] "#, options: .regularExpression) != nil,
      "and says so in the journal (\(barked.first ?? "no line"))")
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

// A timed session's end and start, and the battery limit, shared through the
// app's preferences. Put back as they were.
let saved = (Session.offAt, Session.onAt), savedLimit = Session.batteryLimit
let start = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded())
let end = start.addingTimeInterval(3600)
Session.setEnd(end, now: start)
check(Session.offAt == end && Session.onAt == start && shell("defaults read sh.wham.app offAt").status == 0
      && shell("defaults read sh.wham.app onAt").status == 0, "the end and the start are shared through preferences")
Session.setEnd(nil)
check(Session.offAt == nil && Session.onAt == nil && shell("defaults read sh.wham.app offAt 2>/dev/null").status != 0
      && shell("defaults read sh.wham.app onAt 2>/dev/null").status != 0, "and cleared")
Session.offAt = saved.0
Session.onAt = saved.1
Session.batteryLimit = 20
check(Session.batteryLimit == 20 && shell("defaults read sh.wham.app batteryLimit").output.hasPrefix("20"), "the battery limit is shared")
check(CLI.help.contains("at 20% or less"), "wham help says the limit")
_ = shell("defaults write sh.wham.app batteryLimit -int 7")
check(Session.batteryLimit == Session.defaultBatteryLimit, "a limit the menu does not offer counts as the default")
Session.batteryLimit = Session.never
check(Session.batteryLimit == Session.never && shell("defaults read sh.wham.app batteryLimit").output.hasPrefix("0")
      && CLI.help.contains("until the battery runs out") && !CLI.help.contains("% or less"), "Never is kept, and wham help says it")
Session.batteryLimit = Session.defaultBatteryLimit
check(shell("defaults read sh.wham.app batteryLimit 2>/dev/null").status != 0, "the default is not stored")
Session.batteryLimit = savedLimit

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
    let ran = Journal.tail(200).filter { $0.contains(" run") }
    check(ran.contains { $0.contains("run-ended program=sh status=3 ") }
          && !ran.contains { $0.contains("exit 3") || $0.contains(" -c") || $0.contains("$$") },
          "the journal names the program wham run ran, not its arguments")
    check(Sleep.isDisabled == before, "and leaves sleep as it found it")
} else {
    print("skip wham run (it would ask for a password here)")
}

// The journal: one line per event, "date time.ms zone source[pid] event
// key=value", quoted where a value has a space, the user's names taken out,
// two files of `limit` at most, only its user can read them.
check(Journal.text("flag", [("on", true), ("why", "menu 2h"), ("sudo", nil as Int32?), ("took", "84ms"), ("left", 3.5)])
      == #"flag on=yes why="menu 2h" took=84ms left=3.5"#, "a line: the event, its fields, nil left out")
check(Journal.quote("say \"hi\"\nnow") == #""say \"hi\" now""# && Journal.quote("a=b") == #""a=b""# && Journal.quote("plain") == "plain",
      "quotes, on one line")
check(Journal.scrub(NSHomeDirectory() + "/Applications/Wham.app, \(NSUserName())") == "~/Applications/Wham.app, <user>",
      "the home folder and the user's name taken out")
check(Journal.stamp(Date()).range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} [+-]\d{4}$"#, options: .regularExpression) != nil,
      "dated to the millisecond, with the zone (\(Journal.stamp(Date())))")
try? FileManager.default.removeItem(atPath: journalDir)
Journal.note("test", ["n": 1])
Journal.flush()
let firstLine = (try? String(contentsOf: Journal.file, encoding: .utf8)) ?? ""
check(firstLine.hasSuffix(" cli[\(getpid())] test n=1\n") || firstLine.hasSuffix(" app[\(getpid())] test n=1\n"),
      "written to WHAM_LOG_DIR, with who wrote it (\(firstLine.trimmingCharacters(in: .newlines)))")
let modes = [journalDir, Journal.file.path].map { (try? FileManager.default.attributesOfItem(atPath: $0)[.posixPermissions] as? Int) ?? -1 }
check(modes == [0o700, 0o600], "only its user can read it (\(modes.map { String($0, radix: 8) }))")
let filler = String(repeating: "x", count: 200)
for n in 0..<3000 { Journal.note("fill", [("n", n), ("pad", filler)]) }
Journal.flush()
let sizes = [Journal.file, Journal.older].map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? -1 }
check(sizes.allSatisfy { $0 > 0 && $0 <= Journal.limit }, "past its limit, it goes on in a new file and keeps one older (\(sizes) bytes)")
let lastLines = Journal.tail(3)
check(lastLines.count == 3 && lastLines[2].contains("fill n=2999 ") && lastLines[0].contains("fill n=2997 "), "wham log reads the last lines, in order")
check(CLI.run(["log", "2"]) == 0 && CLI.run(["log", "x"]) == 64 && CLI.run(["log", "0"]) == 64, "wham log takes a count")
Journal.markStopped()
check(Journal.markRunning() == nil, "a run after one that quit: clean")
let unclean = Journal.markRunning()
check(unclean.map { abs($0.timeIntervalSinceNow) < 5 } == true, "after one that did not quit: says when that one started")
Journal.markStopped()
try? FileManager.default.removeItem(atPath: journalDir)

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
