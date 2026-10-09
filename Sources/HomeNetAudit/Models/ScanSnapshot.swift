import Foundation

/// A complete, persistable record of one scan run. Everything the history and
/// diff features need lives here, so snapshots are fully self-contained.
struct ScanSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let localIP: String
    let gateway: String
    let devices: [Device]

    init(id: UUID = UUID(),
         date: Date = Date(),
         localIP: String,
         gateway: String,
         devices: [Device]) {
        self.id = id
        self.date = date
        self.localIP = localIP
        self.gateway = gateway
        self.devices = devices
    }

    var deviceCount: Int { devices.count }
    var findingCount: Int { devices.reduce(0) { $0 + $1.findings.count } }
    var highestSeverity: Severity? { devices.compactMap(\.highestSeverity).max() }

    /// A simple 0–100 posture score: start at 100 and subtract weighted
    /// penalties per finding, floored at 0. Deliberately transparent so the
    /// number is explainable to a non-technical user.
    var securityScore: Int {
        var penalty = 0
        for device in devices {
            for finding in device.findings {
                switch finding.severity {
                case .critical: penalty += 25
                case .high:     penalty += 12
                case .medium:   penalty += 6
                case .low:      penalty += 2
                case .info:     penalty += 0
                }
            }
        }
        return max(0, 100 - penalty)
    }

    var scoreGrade: String {
        switch securityScore {
        case 90...100: return "A"
        case 75..<90:  return "B"
        case 60..<75:  return "C"
        case 40..<60:  return "D"
        default:       return "F"
        }
    }
}
