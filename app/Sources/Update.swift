import Foundation

// Wham keeps itself up to date. A few times a day it asks GitHub which release
// is the latest. When that one is newer, it downloads it, makes sure Wham's
// developer signed it and that it runs, and swaps it in for this copy. The
// request carries nothing about the Mac or its user. With "Update
// Automatically" off, Wham still asks, but only offers the new version in its
// menu; "Check for Updates" asks at once. Blocking calls: run them off the
// main thread.
enum Update {
    // Defaults can point it elsewhere (`-updateBase http://...` at launch): the
    // end-to-end test serves releases from this Mac. The signature check below
    // still holds, so only Wham itself can come from there.
    static var base: String { UserDefaults.standard.string(forKey: "updateBase") ?? "https://github.com/gwendall/wham" }

    // The only apps Wham installs over itself: Wham, signed by its developer.
    static let requirement = #"identifier "sh.wham.app" and anchor apple generic and certificate leaf[subject.OU] = "NQCA86NEA3""#

    static var isOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "noAutoUpdate") }
        set { UserDefaults.standard.set(!newValue, forKey: "noAutoUpdate") }
    }

    // GitHub answers /releases/latest with a redirect to /releases/tag/v1.2.0.
    static func latest() -> String? {
        output("/usr/bin/curl", ["-fsS", "--max-time", "30", "-o", "/dev/null", "-w", "%{redirect_url}", base + "/releases/latest"])
            .flatMap(version(fromTag:))
    }

    static func version(fromTag url: String) -> String? {
        guard let range = url.range(of: "/tag/v") else { return nil }
        let version = String(url[range.upperBound...])
        return numbers(version) == nil ? nil : version
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = numbers(candidate), let old = numbers(current) else { return false }
        for i in 0..<max(new.count, old.count) where (i < new.count ? new[i] : 0) != (i < old.count ? old[i] : 0) {
            return (i < new.count ? new[i] : 0) > (i < old.count ? old[i] : 0)
        }
        return false
    }

    // The first launch of a newer version on a Mac that ran Wham before, which
    // its note under the switch says. 1.2.2 and older kept no version: a Mac
    // that ran one of those and now runs this was updated too.
    static func isUpdate(to current: String, from last: String?, ranBefore: Bool) -> Bool {
        guard ranBefore, numbers(current) != nil else { return false }
        guard let last else { return true }
        return isNewer(current, than: last)
    }

    static func isGenuine(_ app: URL) -> Bool {
        Sleep.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=" + requirement, app.path]) == 0
    }

    // This copy can replace itself: signed by its developer (a build from
    // source never updates) and in a folder its user may write to.
    static func canReplace(_ app: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) && isGenuine(app)
    }

    // Downloads `version` and puts it where `app` is.
    static func install(_ version: String, over app: URL) -> Bool {
        let files = FileManager.default
        // A folder on the app's own volume, so the swap is a rename.
        guard let folder = try? files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true) else {
            return false
        }
        defer { try? files.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("Wham.zip")
        let fresh = folder.appendingPathComponent("Wham.app")
        guard Sleep.run("/usr/bin/curl", ["-fsSL", "--max-time", "300", "-o", zip.path, "\(base)/releases/download/v\(version)/Wham.zip"]) == 0,
              Sleep.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path]) == 0,
              isGenuine(fresh),
              output(fresh.appendingPathComponent("Contents/MacOS/Wham").path, ["version"]) == "wham \(version)"
        else { return false }
        return (try? files.replaceItemAt(app, withItemAt: fresh)) != nil
    }

    private static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...4).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parts.compactMap { $0 }
    }

    private static func output(_ path: String, _ args: [String]) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
