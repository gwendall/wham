import Foundation

// Wham's checks, without Xcode's test runner: compiled with the app's pure
// sources by scripts/test.sh, they exit non-zero on the first failure.
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
    check(installed.status == 0 && (attributes?[.posixPermissions] as? Int) == 0o440 && (attributes?[.ownerAccountName] as? String) == "root"
          && (try? String(contentsOfFile: target, encoding: .utf8)) == Sleep.rule() + "\n",
          "as root the rule lands, 0440 root, exactly the rule")
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
}

// The command line.
check(CLI.commands.isSuperset(of: ["on", "off", "toggle", "status", "version", "help"]), "CLI knows its commands")
check(CLI.run(["version"]) == 0, "wham version succeeds")
check(CLI.run(["status"]) == (kernelAnswers ? 0 : 1), "wham status succeeds, or says it can't read the flag")
check(CLI.run(["nope"]) == 64, "an unknown command exits 64")
check(CLI.describe(true).contains("lid closed") && CLI.describe(false).contains("sleeps"), "status words")

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
