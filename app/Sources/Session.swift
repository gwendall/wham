import CoreGraphics
import Foundation
import IOKit.ps
import notify

// While Wham is on, three things end it on their own, and Wham says which:
// the time it was given runs out, the battery runs low, or the Mac gets
// critically hot. Nothing to set up. A Mac that sleeps keeps its work; one that
// runs flat, or has to shut itself down to cool off, does not.
enum Session {
    enum End: Equatable { case time, battery, heat }

    // On battery, at or under this charge, Wham gives sleep back.
    static let batteryFloor = 10

    struct Reading {
        var now = Date()
        var offAt: Date?
        var onBattery = false
        var battery: Int?
        var critical = false
    }

    static func end(_ reading: Reading) -> End? {
        if reading.critical { return .heat }
        if reading.onBattery, let level = reading.battery, level <= batteryFloor { return .battery }
        if let offAt = reading.offAt, reading.now >= offAt { return .time }
        return nil
    }

    // What the battery and the heat say. The evals stand in for both with a
    // file named in WHAM_FAKE_POWER, read each time: "battery 9", "ac 80",
    // "ac 80 critical".
    static func read(offAt: Date?) -> Reading {
        if let path = ProcessInfo.processInfo.environment["WHAM_FAKE_POWER"] {
            let words = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(whereSeparator: \.isWhitespace)
            return Reading(offAt: offAt, onBattery: words.first == "battery", battery: words.dropFirst().first.flatMap { Int($0) },
                           critical: words.contains("critical"))
        }
        let power = Power.read()
        return Reading(offAt: offAt, onBattery: power.onBattery, battery: power.level,
                       critical: Heat.critical)
    }

    // Why it ended, in a few words.
    static func why(_ end: End, battery: Int?) -> String {
        switch end {
        case .time: return "Time is up"
        case .battery: return "Battery at \(battery ?? batteryFloor)%"
        case .heat: return "Your Mac got too hot"
        }
    }

    // Why it will not start.
    static func refusal(_ end: End, battery: Int?) -> String {
        switch end {
        case .time: return "Time is up"
        case .battery: return "Battery at \(battery ?? batteryFloor)%, plug in first"
        case .heat: return "Your Mac is too hot right now"
        }
    }

    // How long `wham on` lasts: "45m", "2h", "1h30m", "1d", "90s".
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
        return digits.isEmpty && total > 0 ? total : nil
    }

    // "16:40" today, "Tue 16:40" on another day, in the Mac's own format.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(date, inSameDayAs: now) ? "jmm" : "EEE jmm")
        return format.string(from: date)
    }

    // When a timed session ends. The app and the `wham` command share it
    // through the app's preferences; the command posts `changed` after writing.
    static let changed = Notification.Name("sh.wham.app.session")
    private static let domain = "sh.wham.app" as CFString
    static var offAt: Date? {
        get {
            CFPreferencesAppSynchronize(domain)
            return CFPreferencesCopyAppValue("offAt" as CFString, domain) as? Date
        }
        set {
            CFPreferencesSetAppValue("offAt" as CFString, newValue.map { $0 as NSDate }, domain)
            CFPreferencesAppSynchronize(domain)
        }
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
    // Whether the Mac runs on its battery, and the battery's charge in percent
    // (nil on a Mac without one).
    static func read() -> (onBattery: Bool, level: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = source == kIOPSBatteryPowerValue
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (onBattery, now * 100 / max)
        }
        return (onBattery, nil)
    }
}

// With sleep blocked, closing the lid may leave the Mac's own screen lit under
// it: warm, draining, and unlocked. Wham puts it to sleep, which also locks the
// Mac as its settings say. Only when the built-in screen is the only one
// connected, so a closed MacBook driving a monitor is left alone.
enum Screen {
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
