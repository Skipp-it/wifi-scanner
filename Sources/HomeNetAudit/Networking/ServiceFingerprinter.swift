import Foundation
import Network

/// What we learned by talking briefly to an open port.
struct Fingerprint {
    var banner: String?
    var httpServerHeader: String?
    var httpStatusLine: String?
    var httpWWWAuthenticate: String?   // reveals Basic-auth realms / login walls
    var tlsVersion: String?
    var tlsIsSelfSigned: Bool?
}

/// Light-touch fingerprinting: read whatever a service volunteers on connect,
/// and for HTTP(S) ports send a single HEAD request and parse the response
/// headers. No fuzzing, no auth attempts here.
enum ServiceFingerprinter {

    static func fingerprint(host: String, port: PortInfo, timeout: TimeInterval = 2.0) async -> Fingerprint {
        let isTLS = [443, 8443, 995, 993, 8883].contains(port.port)
        let isHTTP = [80, 8080, 8081, 5000, 9000, 443, 8443].contains(port.port)

        if isHTTP {
            return await httpProbe(host: host, port: UInt16(port.port), useTLS: isTLS, timeout: timeout)
        } else {
            let banner = await grabBanner(host: host, port: UInt16(port.port), timeout: timeout)
            return Fingerprint(banner: banner)
        }
    }

    // MARK: - Raw banner

    private static func grabBanner(host: String, port: UInt16, timeout: TimeInterval) async -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let conn = NWConnection(to: .hostPort(host: .init(host), port: nwPort), using: .tcp)

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let guard_ = Locked(false)
            func done(_ s: String?) {
                guard guard_.swap(true) == false else { return }
                conn.cancel()
                cont.resume(returning: s)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, _ in
                        if let data, !data.isEmpty {
                            done(String(decoding: data, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines))
                        } else {
                            done(nil)
                        }
                    }
                case .failed, .cancelled:
                    done(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { done(nil) }
        }
    }

    // MARK: - HTTP(S)

    private static func httpProbe(host: String, port: UInt16, useTLS: Bool, timeout: TimeInterval) async -> Fingerprint {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return Fingerprint() }

        let params: NWParameters
        var fp = Fingerprint()

        if useTLS {
            let tls = NWProtocolTLS.Options()
            // We deliberately DO NOT pin or reject certs here — the whole point
            // is to observe the server's TLS posture, including bad certs.
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, trust, complete in
                    // Accept so the handshake completes; we inspect afterward.
                    _ = trust
                    complete(true)
                },
                .global(qos: .utility)
            )
            params = NWParameters(tls: tls)
        } else {
            params = .tcp
        }

        let conn = NWConnection(to: .hostPort(host: .init(host), port: nwPort), using: params)

        return await withCheckedContinuation { (cont: CheckedContinuation<Fingerprint, Never>) in
            let guard_ = Locked(false)
            func done() {
                guard guard_.swap(true) == false else { return }
                conn.cancel()
                cont.resume(returning: fp)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if useTLS { fp.tlsVersion = Self.readTLSVersion(conn) }
                    let request = "HEAD / HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: HomeNetAudit/1.0\r\nConnection: close\r\n\r\n"
                    conn.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, _ in
                            if let data, !data.isEmpty {
                                Self.parseHTTP(String(decoding: data, as: UTF8.self), into: &fp)
                            }
                            done()
                        }
                    })
                case .failed, .cancelled:
                    done()
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { done() }
        }
    }

    private static func readTLSVersion(_ conn: NWConnection) -> String? {
        guard let meta = conn.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { return nil }
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(meta.securityProtocolMetadata)
        switch version {
        case .TLSv10: return "TLS 1.0"
        case .TLSv11: return "TLS 1.1"
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .DTLSv10: return "DTLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        @unknown default: return "unknown"
        }
    }

    private static func parseHTTP(_ response: String, into fp: inout Fingerprint) {
        let lines = response.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        for line in lines {
            if line.uppercased().hasPrefix("HTTP/") {
                fp.httpStatusLine = String(line)
            } else if line.lowercased().hasPrefix("server:") {
                fp.httpServerHeader = String(line.dropFirst("server:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("www-authenticate:") {
                fp.httpWWWAuthenticate = String(line.dropFirst("www-authenticate:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
