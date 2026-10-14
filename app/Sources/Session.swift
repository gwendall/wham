import CoreGraphics
import Foundation
import IOKit.ps
import notify

// While Wham is on, three things end it on their own, and Wham says which:
// the time it was given runs out, the battery runs low (on battery, or
// plugged into a charger too weak to keep up), or the Mac gets critically
// hot. Nothing to set up. A Mac that sleeps keeps its work; one that
// runs flat, or has to shut itself down to cool off, does not.
enum Session {
    enum End: Equatable { case time, battery, heat }

    // On battery, at or under this charge, Wham gives sleep back: 10% unless
    // the menu's Battery Limit says otherwise. 2% at the least: the flag also
    // holds off macOS's own sleep on a nearly flat battery, and a Mac that
    // runs flat loses what it had not saved, where one put to sleep keeps it.
    static let batteryLimits = [2, 5, 10, 20, 30]
    static let defaultBatteryLimit = 10

    struct Reading {
        var now = Date()
        var offAt: Date?
        var onBattery = false
        // Plugged in, and the battery runs down all the same: a charger or a
        // hub too weak for what the Mac is doing.
        var draining = false
        var battery: Int?
        var critical = false
        var batteryLimit = Session.defaultBatteryLimit
    }

    static func end(_ reading: Reading) -> End? {
        if reading.critical { return .heat }
        if reading.onBattery || reading.draining, let level = reading.battery, level <= reading.batteryLimit { return .battery }
        if let offAt = reading.offAt, reading.now >= offAt { return .time }
        return nil
    }

    // What the battery and the heat say. The evals stand in for both with a
    // file named in WHAM_FAKE_POWER, read each time: "battery 9", "ac 80",
    // "ac 80 critical", "ac 9 draining".
    static func read(offAt: Date?) -> Reading {
        if let path = ProcessInfo.processInfo.environment["WHAM_FAKE_POWER"] {
            let words = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(whereSeparator: \.isWhitespace)
            return Reading(offAt: offAt, onBattery: words.first == "battery", draining: words.contains("draining"),
                           battery: words.dropFirst().first.flatMap { Int($0) }, critical: words.contains("critical"), batteryLimit: batteryLimit)
        }
        let power = Power.read()
        return Reading(offAt: offAt, onBattery: power.onBattery, draining: power.draining, battery: power.level,
                       critical: Heat.critical, batteryLimit: batteryLimit)
    }

    // Why it ended, in a few words. Plugged in and draining all the same:
    // the charger is too weak for what the Mac is doing.
    static func why(_ end: End, battery: Int?, draining: Bool = false) -> String {
        switch end {
        case .time: return Words.say("Time is up")
        case .battery where draining: return Words.say("Battery at %@, your charger can't keep up", Words.percent(battery ?? batteryLimit))
        case .battery: return Words.say("Battery at %@", Words.percent(battery ?? batteryLimit))
        case .heat: return Words.say("Your Mac got too hot")
        }
    }

    // Why it will not start. Plugged in already, it does not ask to plug in.
    static func refusal(_ end: End, battery: Int?, draining: Bool = false) -> String {
        switch end {
        case .time: return Words.say("Time is up")
        case .battery where draining: return why(.battery, battery: battery, draining: true)
        case .battery: return Words.say("Battery at %@, plug in first", Words.percent(battery ?? batteryLimit))
        case .heat: return Words.say("Your Mac is too hot right now")
        }
    }

    // How long `wham on` lasts: "45m", "2h", "1h30m", "1d", "90s", a year at
    // most.
    static let longest: TimeInterval = 365 * 86400

    static func duration(_ text: String) -> TimeInterval? {
        let units: [Character: TimeInterval] = ["d": 86400, "h": 3600, "m": 60, "s": 1]
        let order: [Character] = ["d", "h", "m", "s"]
        var total: TimeInterval = 0, digits = "", last = -1
        for character in text.lowercased() {
            if character.isASCII && character.isNumber {
                digits.append(character)
                continue
            }
            // Each unit once, largest first, each after a number.
            guard let seconds = units[character], let index = order.firstIndex(of: character), index > last,
                  let number = Double(digits) else { return nil }
            total += number * seconds
            digits = ""
            last = index
        }
        return digits.isEmpty && total > 0 && total <= longest ? total : nil
    }

    // "16:40" today, "Tue 16:40" on another day, in the Mac's own format.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let format = DateFormatter()
        format.locale = Words.locale
        format.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(date, inSameDayAs: now) ? "jmm" : "EEE jmm")
        return format.string(from: date)
    }

    // What is left of a timed session, in words: "1 hr 58 min", "2 hr",
    // "45 min". Rounded up, so the last minute says 1 min, never 0. An end
    // further than a session can last (another tool's) counts as that far.
    static func timeLeft(_ seconds: TimeInterval) -> String {
        let bounded = seconds.isNaN ? 0 : min(max(seconds, 0), longest)
        let minutes = max(1, Int((bounded / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return Words.say("%d min", rest) }
        return rest == 0 ? Words.say("%d hr", hours) : Words.say("%1$d hr %2$d min", hours, rest)
    }

    // The share of a timed session still to run, from 1 at its start to 0 at
    // its end, for the switch's track. 1 when untimed or its start is unknown.
    static func remaining(now: Date = Date(), from start: Date?, to end: Date?) -> Double {
        guard let start, let end, end > start else { return 1 }
        return min(1, max(0, end.timeIntervalSince(now) / end.timeIntervalSince(start)))
    }

    // A timed session's last minutes: the switch says so once, lid open.
    static let warning: TimeInterval = 300

    // When to say so: five minutes before the end, for a session that runs at
    // least twice that, so a short one does not warn right as it starts.
    static func warnAt(from start: Date?, to end: Date?) -> Date? {
        guard let end else { return nil }
        if let start, end.timeIntervalSince(start) < 2 * warning { return nil }
        return end.addingTimeInterval(-warning)
    }

    // The app and the `wham` command share the session's end and start, and
    // the battery limit, through the app's preferences; the command posts
    // `changed` after writing. The tests keep theirs in a domain of their own
    // (WHAM_PREFS): a Wham running on the same Mac reads these every tick.
    static let changed = Notification.Name("sh.wham.app.session")
    static let domain = (ProcessInfo.processInfo.environment["WHAM_PREFS"] ?? "sh.wham.app") as CFString

    // Starts a timed session's clock now, ending at `end`, or drops it (nil).
    static func setEnd(_ end: Date?, now: Date = Date()) {
        onAt = end == nil ? nil : now
        offAt = end
    }

    static var offAt: Date? {
        get { date("offAt") }
        set { set("offAt", newValue.map { $0 as NSDate }) }
    }

    static var onAt: Date? {
        get { date("onAt") }
        set { set("onAt", newValue.map { $0 as NSDate }) }
    }

    // Only the menu's values count: anything else is the default. Never (0),
    // which Wham 1.5 to 1.7 offered, is the lowest one now.
    static var batteryLimit: Int {
        get {
            CFPreferencesAppSynchronize(domain)
            let value = CFPreferencesCopyAppValue("batteryLimit" as CFString, domain) as? Int
            if value == 0 { return batteryLimits[0] }
            return value.flatMap { batteryLimits.contains($0) ? $0 : nil } ?? defaultBatteryLimit
        }
        set { set("batteryLimit", newValue == defaultBatteryLimit ? nil : newValue as NSNumber) }
    }

    private static func date(_ key: String) -> Date? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain) as? Date
    }

    private static func set(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

// How hot the Mac is. ProcessInfo's thermal state, or the pressure level that
// macOS's thermal daemon posts through notify(3), which ProcessInfo does not
// always follow: 3 is trapping, 4 sleeping (OSThermalPressureLevel).
enum Heat {
    static let name = "com.apple.system.thermalpressurelevel"
    private static let token: Int32? = {
        var token: Int32 = 0
        return notify_register_check(name, &token) == 0 ? token : nil
    }()

    static var level: UInt64? {
        var level: UInt64 = 0
        guard let token, notify_get_state(token, &level) == 0 else { return nil }
        return level
    }

    static var critical: Bool { ProcessInfo.processInfo.thermalState == .critical || (level ?? 0) >= 3 }
}

enum Power {
    // Whether the Mac runs on its battery, whether it is plugged in with its
    // battery running down all the same (not charging, its current flowing
    // out), and the battery's charge in percent (nil on a Mac without one).
    static func read() -> (onBattery: Bool, draining: Bool, level: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, false, nil) }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = source == kIOPSBatteryPowerValue
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let draining = !onBattery && description[kIOPSIsChargingKey] as? Bool == false && (description[kIOPSCurrentKey] as? Int ?? 0) < 0
            return (onBattery, draining, now * 100 / max)
        }
        return (onBattery, false, nil)
    }
}

// With sleep blocked, closing the lid may leave the Mac's own screen lit under
// it: warm, draining, and unlocked. Wham puts it to sleep, which also locks the
// Mac as its settings say. Only when the built-in screen is the only one
// connected, so a closed MacBook driving a monitor is left alone.
enum Screen {
    // The displays connected, the Mac's own included.
    static var count: Int {
        var count: UInt32 = 0
        return CGGetOnlineDisplayList(0, nil, &count) == .success ? Int(count) : 0
    }

    static var builtInAloneAndLit: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success, count > 0 else { return false }
        let online = ids.prefix(Int(count))
        return online.allSatisfy { CGDisplayIsBuiltin($0) != 0 }
            && online.contains { CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    static func sleep() {
        Sleep.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}
