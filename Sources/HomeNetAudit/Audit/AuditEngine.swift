import Foundation

/// Orchestrates a full audit of one device: port scan → fingerprint →
/// rule evaluation → optional default-credential check → classification.
struct AuditEngine {

    /// User-controlled options for a scan run.
    struct Options {
        var checkDefaultCredentials: Bool = false
        var portScanTimeout: TimeInterval = 1.2
    }

    let options: Options

    /// Fully audits a single host that discovery already marked as alive.
    func audit(ip: String,
               isGateway: Bool,
               bonjourServices: [String],
               hostname: String?) async -> Device {

        let openPorts = await PortScanner.scan(host: ip, timeout: options.portScanTimeout)

        var enrichedPorts: [PortInfo] = []
        var findings: [Finding] = []

        // Fingerprint + evaluate each open port, concurrently.
        await withTaskGroup(of: (PortInfo, Fingerprint).self) { group in
            for port in openPorts {
                group.addTask {
                    let fp = await ServiceFingerprinter.fingerprint(host: ip, port: port)
                    return (port, fp)
                }
            }
            for await (port, fp) in group {
                var p = port
                p.banner = fp.httpServerHeader ?? fp.banner
                enrichedPorts.append(p)
                findings += VulnerabilityRules.evaluatePort(p, fingerprint: fp, isGateway: isGateway)
            }
        }
        enrichedPorts.sort { $0.port < $1.port }

        var device = Device(
            ipAddress: ip,
            hostname: hostname,
            kind: classify(ports: enrichedPorts, bonjour: bonjourServices, isGateway: isGateway),
            isGateway: isGateway,
            bonjourServices: bonjourServices,
            openPorts: enrichedPorts,
            findings: findings
        )

        device.findings += VulnerabilityRules.evaluateDevice(device)

        // Opt-in default-credential check against the primary web admin port.
        if options.checkDefaultCredentials {
            if let finding = await runCredentialCheck(host: ip, ports: enrichedPorts) {
                device.findings.append(finding)
            }
        }

        device.findings.sort { $0.severity > $1.severity }
        return device
    }

    private func runCredentialCheck(host: String, ports: [PortInfo]) async -> Finding? {
        // Prefer HTTPS admin, else HTTP.
        let httpsPort = ports.first { [443, 8443].contains($0.port) }?.port
        let httpPort = ports.first { [80, 8080, 8081, 5000].contains($0.port) }?.port

        for (port, tls) in [(httpsPort, true), (httpPort, false)] {
            guard let port else { continue }
            if let cred = await DefaultCredentialCheck.check(host: host, port: port, useTLS: tls) {
                let shownPass = cred.password.isEmpty ? "(blank)" : cred.password
                return Finding(
                    severity: .critical,
                    title: "Default credentials accepted",
                    detail: "The admin interface on port \(port) accepted a well-known factory default login (\(cred.username) / \(shownPass)). Anyone on the network can take full control of this device.",
                    recommendation: "Immediately set a strong, unique administrator password. If possible, also rename the default admin account.",
                    reference: "CWE-1392")
            }
        }
        return nil
    }

    // MARK: - Classification

    private func classify(ports: [PortInfo], bonjour: [String], isGateway: Bool) -> DeviceKind {
        if isGateway { return .router }
        let b = bonjour.joined(separator: " ").lowercased()
        let openSet = Set(ports.map(\.port))

        if b.contains("_raop") || b.contains("_airplay") || b.contains("_googlecast") { return .mediaPlayer }
        if b.contains("_hap") || b.contains("_homekit") { return .smartHome }
        if b.contains("_printer") || b.contains("_ipp") || openSet.contains(9100) || openSet.contains(631) { return .printer }
        if b.contains("_rtsp") || openSet.contains(554) { return .camera }
        if b.contains("_smb") || b.contains("_afpovertcp") || openSet.contains(445) || openSet.contains(548) { return .nas }
        if openSet.contains(22) && (openSet.contains(80) || openSet.contains(443)) { return .computer }
        return .unknown
    }
}
