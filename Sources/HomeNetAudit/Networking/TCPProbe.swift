import Foundation
import Network

/// Result of a single TCP connect attempt.
enum TCPProbeResult {
    case open            // handshake completed
    case refused         // RST — host is up, port closed
    case timeout         // no response in time (filtered / host down)
    case failed(String)  // other transport error
}

/// Thin async wrapper around a single `NWConnection` TCP connect.
///
/// This is a *connect scan*: we open a normal TCP connection and immediately
/// learn whether the port is open, refused, or silent. No raw sockets, no
/// half-open SYN scanning (impossible on iOS). Fully within App Store rules.
enum TCPProbe {

    static func probe(host: String,
                      port: UInt16,
                      timeout: TimeInterval = 1.2) async -> TCPProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return .failed("invalid port")
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)

        let params = NWParameters.tcp
        // Fail fast rather than retransmitting for the OS default ~minute.
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = Int(timeout.rounded(.up))
            tcp.noDelay = true
        }
        params.prohibitExpensivePaths = false

        let connection = NWConnection(to: endpoint, using: params)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<TCPProbeResult, Never>) in
                let finished = Locked(false)

                func finish(_ result: TCPProbeResult) {
                    guard finished.swap(true) == false else { return }
                    connection.cancel()
                    cont.resume(returning: result)
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(.open)
                    case .failed(let error):
                        finish(Self.classify(error))
                    case .waiting(let error):
                        // "waiting" means the path is up but the connect can't
                        // proceed — typically connection refused. Treat as a
                        // definitive answer instead of hanging.
                        finish(Self.classify(error))
                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .userInitiated))

                // Hard timeout backstop independent of TCP's own timer.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 0.3) {
                    finish(.timeout)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private static func classify(_ error: NWError) -> TCPProbeResult {
        if case let .posix(code) = error {
            switch code {
            case .ECONNREFUSED: return .refused
            case .ETIMEDOUT:    return .timeout
            case .EHOSTUNREACH, .ENETUNREACH: return .timeout
            default:            return .failed("\(code)")
            }
        }
        return .failed("\(error)")
    }
}

/// Minimal thread-safe boolean flag for the single-resume guard above.
final class Locked<Value> {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }

    /// Sets a new value, returning the previous one, atomically.
    func swap(_ newValue: Value) -> Value {
        lock.lock(); defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
