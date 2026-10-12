import Foundation
import IOKit
import IOKit.ps

// What can end a session arrives from macOS as it happens, not polled: the
// power source (plugged in or not, and the charge), the Mac's temperature, the
// lid. Each calls `changed` on the main thread.
@MainActor
final class Watch {
    private let changed: () -> Void
    private var port: IONotificationPortRef?
    private var lid: io_object_t = 0

    // kIOPMMessageClamshellStateChange: iokit_family_msg(sub_iokit_powermanagement, 0x100).
    private nonisolated static let clamshellChanged: UInt32 = 0xE003_4100

    init(_ changed: @escaping () -> Void) {
        self.changed = changed
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<Watch>.fromOpaque(context).takeUnretainedValue().changed() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        // IOPMrootDomain tells its clients when the lid opens or closes.
        let root = IOServiceGetMatchingService(0, IOServiceMatching("IOPMrootDomain"))
        guard root != 0, let port = IONotificationPortCreate(0) else { return }
        defer { IOObjectRelease(root) }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { context, _, message, _ in
            guard let context, message == Watch.clamshellChanged else { return }
            MainActor.assumeIsolated { Unmanaged<Watch>.fromOpaque(context).takeUnretainedValue().changed() }
        }, context, &lid)
    }
}
