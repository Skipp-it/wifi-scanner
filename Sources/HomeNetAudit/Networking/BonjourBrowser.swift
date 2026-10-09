import Foundation
import Network

/// Enumerates Bonjour / mDNS services advertised on the LAN.
///
/// Many IoT devices (cameras, speakers, printers, smart-home hubs) advertise
/// themselves via mDNS. Mapping those advertisements to IPs enriches the
/// device inventory and often reveals a device's type and model outright.
final class BonjourBrowser {

    struct Discovered {
        let name: String
        let type: String
        var resolvedHost: String?
    }

    private var browsers: [NWBrowser] = []

    /// Service types worth browsing on a typical home network. Mirrors the
    /// NSBonjourServices entries in Info.plist (iOS only lets you browse types
    /// you declared there).
    static let serviceTypes = [
        "_http._tcp", "_https._tcp", "_ssh._tcp",
        "_printer._tcp", "_ipp._tcp",
        "_airplay._tcp", "_raop._tcp",
        "_homekit._tcp", "_hap._tcp",
        "_googlecast._tcp", "_smb._tcp",
        "_afpovertcp._tcp", "_rtsp._tcp"
    ]

    /// Browses all known types for `duration` seconds and returns what it found.
    func browse(duration: TimeInterval = 4.0) async -> [Discovered] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Discovered], Never>) in
            let results = LockedBox<[String: Discovered]>([:])

            for type in Self.serviceTypes {
                let params = NWParameters()
                params.includePeerToPeer = true
                let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

                browser.browseResultsChangedHandler = { found, _ in
                    for result in found {
                        if case let .service(name, serviceType, _, _) = result.endpoint {
                            results.mutate { $0["\(name).\(serviceType)"] = Discovered(name: name, type: serviceType) }
                        }
                    }
                }
                browser.start(queue: .global(qos: .utility))
                self.browsers.append(browser)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
                self.browsers.forEach { $0.cancel() }
                self.browsers.removeAll()
                cont.resume(returning: Array(results.value.values))
            }
        }
    }
}

/// Small thread-safe box for accumulating results off the main actor.
final class LockedBox<Value> {
    private var _value: Value
    private let lock = NSLock()
    init(_ value: Value) { _value = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return _value }
    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }; body(&_value)
    }
}
