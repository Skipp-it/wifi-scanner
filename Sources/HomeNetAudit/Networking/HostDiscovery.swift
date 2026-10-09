import Foundation

/// Discovers live hosts on the subnet.
///
/// Without ICMP, liveness is inferred from TCP: if a connect to *any* probe
/// port either succeeds (open) or is actively refused (RST), the host is up.
/// Only silence on every probe port is treated as "down / filtered".
enum HostDiscovery {

    /// A compact set of ports that almost any live device answers on with at
    /// least a refusal. Kept small so a /24 sweep stays fast.
    static let probePorts: [UInt16] = [80, 443, 22, 53, 139, 445, 7, 548, 8080, 9100]

    /// Concurrency cap — enough to sweep a /24 quickly without exhausting the
    /// per-process file-descriptor budget.
    static let maxConcurrentHosts = 48

    static func discover(hosts: [String],
                         onHostChecked: @escaping (_ done: Int, _ alive: Bool) -> Void) async -> [String] {
        var alive: [String] = []
        var done = 0

        await withTaskGroup(of: (String, Bool).self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let host = iterator.next() else { return }
                inFlight += 1
                group.addTask { (host, await isAlive(host)) }
            }

            for _ in 0..<min(maxConcurrentHosts, hosts.count) { addNext() }

            for await (host, isUp) in group {
                inFlight -= 1
                done += 1
                if isUp { alive.append(host) }
                onHostChecked(done, isUp)
                addNext()
            }
            _ = inFlight
        }

        return alive.sorted { (LocalNetwork.ipv4ToUInt32($0) ?? 0) < (LocalNetwork.ipv4ToUInt32($1) ?? 0) }
    }

    /// Probes the host across `probePorts` concurrently; returns at the first
    /// definitive signal (open or refused) without waiting for the rest.
    private static func isAlive(_ host: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for port in probePorts {
                group.addTask {
                    switch await TCPProbe.probe(host: host, port: port, timeout: 0.9) {
                    case .open, .refused: return true
                    case .timeout, .failed: return false
                    }
                }
            }
            for await up in group where up {
                group.cancelAll()
                return true
            }
            return false
        }
    }
}
