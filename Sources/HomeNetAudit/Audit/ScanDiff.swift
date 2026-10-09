import Foundation

/// The difference between two scans, keyed by IP address (stable enough on a
/// home network, especially with DHCP reservations). Powers the "what changed
/// on my network" feature and the basis for future push alerts.
struct ScanDiff {

    struct PortChange: Identifiable, Hashable {
        let id = UUID()
        let ip: String
        let port: Int
        let serviceName: String?
    }

    struct FindingChange: Identifiable, Hashable {
        let id = UUID()
        let ip: String
        let finding: Finding
    }

    var newDevices: [Device] = []
    var removedDevices: [Device] = []
    var portsOpened: [PortChange] = []
    var portsClosed: [PortChange] = []
    var findingsIntroduced: [FindingChange] = []
    var findingsResolved: [FindingChange] = []

    var scoreDelta: Int = 0   // new score minus old score

    var hasChanges: Bool {
        !(newDevices.isEmpty && removedDevices.isEmpty &&
          portsOpened.isEmpty && portsClosed.isEmpty &&
          findingsIntroduced.isEmpty && findingsResolved.isEmpty)
    }

    /// Count of changes that make the network *less* safe — the headline number.
    var regressions: Int { newDevices.count + portsOpened.count + findingsIntroduced.count }

    static func between(old: ScanSnapshot, new: ScanSnapshot) -> ScanDiff {
        var diff = ScanDiff()
        diff.scoreDelta = new.securityScore - old.securityScore

        let oldByIP = Dictionary(old.devices.map { ($0.ipAddress, $0) }, uniquingKeysWith: { a, _ in a })
        let newByIP = Dictionary(new.devices.map { ($0.ipAddress, $0) }, uniquingKeysWith: { a, _ in a })

        diff.newDevices = new.devices.filter { oldByIP[$0.ipAddress] == nil }
        diff.removedDevices = old.devices.filter { newByIP[$0.ipAddress] == nil }

        // Compare devices present in both scans.
        for (ip, newDevice) in newByIP {
            guard let oldDevice = oldByIP[ip] else { continue }

            let oldPorts = Set(oldDevice.openPorts.map(\.port))
            let newPorts = Set(newDevice.openPorts.map(\.port))

            for p in newDevice.openPorts where !oldPorts.contains(p.port) {
                diff.portsOpened.append(.init(ip: ip, port: p.port, serviceName: p.serviceName))
            }
            for p in oldDevice.openPorts where !newPorts.contains(p.port) {
                diff.portsClosed.append(.init(ip: ip, port: p.port, serviceName: p.serviceName))
            }

            let oldTitles = Set(oldDevice.findings.map(\.title))
            let newTitles = Set(newDevice.findings.map(\.title))

            for f in newDevice.findings where !oldTitles.contains(f.title) {
                diff.findingsIntroduced.append(.init(ip: ip, finding: f))
            }
            for f in oldDevice.findings where !newTitles.contains(f.title) {
                diff.findingsResolved.append(.init(ip: ip, finding: f))
            }
        }

        // Treat every finding on a brand-new device as introduced, too.
        for device in diff.newDevices {
            for f in device.findings {
                diff.findingsIntroduced.append(.init(ip: device.ipAddress, finding: f))
            }
        }

        return diff
    }
}
