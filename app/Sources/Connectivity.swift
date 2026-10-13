import CoreWLAN
import Foundation
import Network

// While Wham keeps the Mac awake, the network as the Mac sees it, for the
// journal: whether it is up and through what, and the Wi-Fi link's state and
// strength. A Mac awake under a closed lid that loses its network is the
// question this answers. Never a network's name or an address: CoreWLAN gives
// neither without the Location permission, which Wham does not ask for, and
// Wham does not ask for them anyway. Events as they come, a line only when
// something changed, and a sample when Wham asks (the lid, every ten minutes
// while it is closed).
@MainActor
final class Connectivity: NSObject {
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "sh.wham.network", qos: .utility)
    private let events = Events()

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        // Called at once with the network as it is, then on each change.
        monitor.pathUpdateHandler = { [events] path in events.seen(path) }
        monitor.start(queue: queue)
        self.monitor = monitor
        queue.async { [events] in events.watchWiFi(true) }
    }

    func stop() {
        guard let monitor else { return }
        monitor.cancel()
        self.monitor = nil
        queue.async { [events] in events.watchWiFi(false) }
    }

    // The Wi-Fi link as it is now, and why it is asked.
    func sample(_ why: String) {
        queue.async { [events] in events.wifi(why) }
    }

    // On the network's queue (CoreWLAN's own for its events, which only
    // write): what it last said, to say only what changed.
    private final class Events: NSObject, CWEventDelegate, @unchecked Sendable {
        private var lastPath: String?
        private var client: CWWiFiClient?

        func seen(_ path: NWPath) {
            let fields = Self.describe(path)
            let summary = Journal.text("network", fields)
            guard summary != lastPath else { return }
            lastPath = summary
            Journal.note("network", fields)
        }

        func watchWiFi(_ on: Bool) {
            if on {
                let client = CWWiFiClient.shared()
                client.delegate = self
                try? client.startMonitoringEvent(with: .linkDidChange)
                try? client.startMonitoringEvent(with: .powerDidChange)
                self.client = client
                wifi("start")
            } else {
                try? client?.stopMonitoringAllEvents()
                client?.delegate = nil
                client = nil
                lastPath = nil
            }
        }

        func wifi(_ why: String) {
            Journal.note("wifi", [("why", why)] + Self.describe(CWWiFiClient.shared().interface()))
        }

        // CoreWLAN calls these on a queue of its own.
        func linkDidChangeForWiFiInterface(withName interfaceName: String) {
            Journal.note("wifi", [("why", "link")] + Self.describe(CWWiFiClient.shared().interface()))
        }

        func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
            Journal.note("wifi", [("why", "power")] + Self.describe(CWWiFiClient.shared().interface()))
        }

        // "up via=wifi interfaces=en0 expensive=yes": expensive is how macOS
        // marks a phone's hotspot.
        static func describe(_ path: NWPath) -> [(String, Any?)] {
            let status: String
            switch path.status {
            case .satisfied: status = "up"
            case .unsatisfied: status = "down"
            case .requiresConnection: status = "waiting"
            @unknown default: status = "unknown"
            }
            let kinds: [(NWInterface.InterfaceType, String)] = [(.wifi, "wifi"), (.wiredEthernet, "wired"), (.cellular, "cellular"), (.other, "other")]
            let via = kinds.first { path.usesInterfaceType($0.0) }?.1
            var reason: String?
            if path.status != .satisfied {
                switch path.unsatisfiedReason {
                case .notAvailable: reason = "no-network"
                case .cellularDenied: reason = "cellular-denied"
                case .wifiDenied: reason = "wifi-denied"
                case .localNetworkDenied: reason = "local-network-denied"
                default: reason = nil
                }
            }
            return [("status", status), ("via", via), ("interfaces", path.availableInterfaces.map(\.name).joined(separator: ",")),
                    ("expensive", path.isExpensive), ("constrained", path.isConstrained),
                    ("ipv4", path.supportsIPv4), ("ipv6", path.supportsIPv6), ("dns", path.supportsDNS), ("reason", reason)]
        }

        // "power=yes active=yes rssi=-61 noise=-92 rate=866 band=5GHz
        // channel=44 width=80MHz phy=ac": no name, no address.
        static func describe(_ wifi: CWInterface?) -> [(String, Any?)] {
            guard let wifi else { return [("interface", "none")] }
            let channel = wifi.wlanChannel()
            let band: String? = channel.map {
                switch $0.channelBand.rawValue {
                case 1: return "2.4GHz"
                case 2: return "5GHz"
                case 3: return "6GHz"
                default: return "unknown"
                }
            }
            let widths = [1: "20MHz", 2: "40MHz", 3: "80MHz", 4: "160MHz"]
            let phys = [1: "a", 2: "b", 3: "g", 4: "n", 5: "ac", 6: "ax", 7: "be"]
            let active = wifi.serviceActive()
            let phy = wifi.activePHYMode().rawValue
            return [("power", wifi.powerOn()), ("active", active),
                    ("rssi", active ? wifi.rssiValue() : nil), ("noise", active ? wifi.noiseMeasurement() : nil),
                    ("rate", active ? Int(wifi.transmitRate()) : nil), ("band", band), ("channel", channel?.channelNumber),
                    ("width", channel.map { widths[$0.channelWidth.rawValue] ?? "unknown" }),
                    ("phy", phy == 0 ? nil : phys[phy] ?? "\(phy)")]
        }
    }
}
