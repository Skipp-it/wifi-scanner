import Foundation

/// TCP connect scanner for a single host.
enum PortScanner {

    /// Well-known ports relevant to home routers and IoT gear, with friendly
    /// names used in findings and the UI.
    static let commonPorts: [(port: Int, name: String)] = [
        (21, "FTP"), (22, "SSH"), (23, "Telnet"), (25, "SMTP"),
        (53, "DNS"), (80, "HTTP"), (110, "POP3"), (111, "RPC"),
        (135, "MSRPC"), (139, "NetBIOS"), (143, "IMAP"), (161, "SNMP"),
        (443, "HTTPS"), (445, "SMB"), (515, "LPD"), (548, "AFP"),
        (554, "RTSP"), (631, "IPP"), (993, "IMAPS"), (995, "POP3S"),
        (1080, "SOCKS"), (1883, "MQTT"), (1900, "SSDP/UPnP"), (2323, "Telnet-alt"),
        (3389, "RDP"), (5000, "UPnP/HTTP"), (5060, "SIP"), (5353, "mDNS"),
        (5900, "VNC"), (7547, "TR-069/CWMP"), (8080, "HTTP-alt"), (8081, "HTTP-alt"),
        (8443, "HTTPS-alt"), (8883, "MQTT-TLS"), (9000, "HTTP-alt"), (9100, "JetDirect"),
        (49152, "UPnP-alt")
    ]

    static let maxConcurrentPorts = 24

    static func scan(host: String,
                     ports: [(port: Int, name: String)] = commonPorts,
                     timeout: TimeInterval = 1.2) async -> [PortInfo] {
        var results: [PortInfo] = []

        await withTaskGroup(of: PortInfo?.self) { group in
            var iterator = ports.makeIterator()

            func addNext() {
                guard let entry = iterator.next() else { return }
                group.addTask {
                    let r = await TCPProbe.probe(host: host, port: UInt16(entry.port), timeout: timeout)
                    switch r {
                    case .open:
                        return PortInfo(port: entry.port, state: .open, serviceName: entry.name)
                    case .refused, .timeout, .failed:
                        return nil   // only report open ports in the device view
                    }
                }
            }

            for _ in 0..<min(maxConcurrentPorts, ports.count) { addNext() }
            for await info in group {
                if let info { results.append(info) }
                addNext()
            }
        }

        return results.sorted { $0.port < $1.port }
    }
}
