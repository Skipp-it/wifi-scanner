import Foundation

/// Describes the local IPv4 network the device is attached to.
struct LocalNetworkInfo {
    let localIP: String
    let netmask: String
    /// All host addresses in the subnet, excluding network + broadcast.
    let hostAddresses: [String]
    /// Conventional gateway guess (first usable address, e.g. x.y.z.1).
    let likelyGateway: String
}

enum LocalNetwork {

    /// Reads the Wi‑Fi interface (en0) IPv4 address + netmask via getifaddrs,
    /// then enumerates every host address in that subnet.
    ///
    /// Caps enumeration at /22 (1022 hosts) so an unusually large netmask
    /// can't produce a scan that never ends. Home networks are almost always
    /// /24.
    static func current(maxHosts: Int = 1022) -> LocalNetworkInfo? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var ip: String?
        var mask: String?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            let family = ifa.ifa_addr.pointee.sa_family
            let name = String(cString: ifa.ifa_name)

            // en0 is Wi‑Fi on iOS hardware. Only IPv4 (AF_INET) here.
            if family == UInt8(AF_INET), name == "en0" {
                ip = Self.stringFromSockaddr(ifa.ifa_addr)
                mask = Self.stringFromSockaddr(ifa.ifa_netmask)
            }
            cursor = ifa.ifa_next
        }

        guard let localIP = ip, let netmask = mask,
              let ipU = ipv4ToUInt32(localIP),
              let maskU = ipv4ToUInt32(netmask), maskU != 0
        else { return nil }

        let network = ipU & maskU
        let broadcast = network | ~maskU
        let hostCount = Int(broadcast - network) - 1   // minus network + broadcast
        guard hostCount > 0 else { return nil }

        let limited = min(hostCount, maxHosts)
        var hosts: [String] = []
        hosts.reserveCapacity(limited)
        for offset in 1...limited {
            hosts.append(uint32ToIPv4(network + UInt32(offset)))
        }

        return LocalNetworkInfo(
            localIP: localIP,
            netmask: netmask,
            hostAddresses: hosts,
            likelyGateway: uint32ToIPv4(network + 1)
        )
    }

    // MARK: - sockaddr → String

    private static func stringFromSockaddr(_ sa: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let sa else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                                 &host, socklen_t(host.count),
                                 nil, 0, NI_NUMERICHOST)
        return result == 0 ? String(cString: host) : nil
    }

    // MARK: - IPv4 <-> UInt32 (network math)

    static func ipv4ToUInt32(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    static func uint32ToIPv4(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}
