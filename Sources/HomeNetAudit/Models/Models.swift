import Foundation

/// Severity of an audit finding, ordered so higher raw values sort first.
enum Severity: Int, Codable, CaseIterable, Comparable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .info: return "Info"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    /// SF Symbol + semantic color handled in the view layer; kept here as a hint.
    var symbolName: String {
        switch self {
        case .info: return "info.circle"
        case .low: return "exclamationmark.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

/// State of a single TCP port after scanning.
enum PortState: String, Codable {
    case open
    case closed      // actively refused — host is up
    case filtered    // no response within timeout
}

struct PortInfo: Identifiable, Codable, Hashable {
    var id: Int { port }
    let port: Int
    var state: PortState
    /// Human name for the well-known service, e.g. "HTTP".
    var serviceName: String?
    /// Anything the service volunteered: banner text, HTTP Server header, etc.
    var banner: String?
}

/// A single security observation about a device.
struct Finding: Identifiable, Codable, Hashable {
    let id: UUID
    var severity: Severity
    var title: String
    var detail: String
    /// Actionable remediation guidance for the owner.
    var recommendation: String
    /// Optional reference (CWE/CVE/vendor doc) shown in the UI.
    var reference: String?

    init(id: UUID = UUID(),
         severity: Severity,
         title: String,
         detail: String,
         recommendation: String,
         reference: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.recommendation = recommendation
        self.reference = reference
    }
}

/// Best-effort device classification from fingerprints.
enum DeviceKind: String, Codable {
    case router
    case printer
    case camera
    case nas
    case mediaPlayer
    case smartHome
    case computer
    case phone
    case unknown

    var symbolName: String {
        switch self {
        case .router: return "wifi.router"
        case .printer: return "printer"
        case .camera: return "video"
        case .nas: return "externaldrive.connected.to.line.below"
        case .mediaPlayer: return "play.tv"
        case .smartHome: return "homekit"
        case .computer: return "desktopcomputer"
        case .phone: return "iphone"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

/// A discovered device plus everything we learned about it.
struct Device: Identifiable, Codable, Hashable {
    let id: UUID
    let ipAddress: String
    var hostname: String?
    var kind: DeviceKind
    var isGateway: Bool
    var bonjourServices: [String]
    var openPorts: [PortInfo]
    var findings: [Finding]

    init(id: UUID = UUID(),
         ipAddress: String,
         hostname: String? = nil,
         kind: DeviceKind = .unknown,
         isGateway: Bool = false,
         bonjourServices: [String] = [],
         openPorts: [PortInfo] = [],
         findings: [Finding] = []) {
        self.id = id
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.kind = kind
        self.isGateway = isGateway
        self.bonjourServices = bonjourServices
        self.openPorts = openPorts
        self.findings = findings
    }

    var highestSeverity: Severity? { findings.map(\.severity).max() }

    var displayName: String {
        if isGateway { return hostname ?? "Router (\(ipAddress))" }
        return hostname ?? ipAddress
    }
}

/// Overall progress reported to the UI during a scan.
struct ScanProgress: Equatable {
    var phase: String = "Idle"
    var hostsScanned: Int = 0
    var hostsTotal: Int = 0
    var devicesFound: Int = 0
    var fraction: Double = 0
}
