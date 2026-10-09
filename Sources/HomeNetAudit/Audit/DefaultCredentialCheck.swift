import Foundation

/// Opt-in check for well-known factory-default credentials on an HTTP admin
/// interface of a device **you own**.
///
/// Scope & safety:
/// - Runs ONLY when the user explicitly enables it in settings.
/// - Tries a *small* curated list of vendor factory defaults, not a brute force.
/// - Stops at the first success and reports it; it never iterates a password
///   dictionary or targets non-default accounts.
/// - Honors HTTP Basic auth only (the most common router/IoT scheme). Form
///   logins are intentionally out of scope to avoid anything resembling
///   credential stuffing.
///
/// The goal is defensive: surface "this device still has its out-of-the-box
/// password" so the owner changes it.
enum DefaultCredentialCheck {

    struct Credential: Decodable { let username: String; let password: String }

    /// Loads the bundled curated default-credential list.
    static func loadDefaults() -> [Credential] {
        guard let url = Bundle.main.url(forResource: "default_credentials", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let creds = try? JSONDecoder().decode([Credential].self, from: data)
        else { return fallbackDefaults }
        return creds
    }

    /// Minimal fallback if the bundled JSON is missing.
    private static let fallbackDefaults: [Credential] = [
        .init(username: "admin", password: "admin"),
        .init(username: "admin", password: "password"),
        .init(username: "admin", password: ""),
        .init(username: "root", password: "root")
    ]

    /// Attempts the default pairs against `http(s)://host:port/`. Returns the
    /// first pair that is accepted, or nil.
    static func check(host: String, port: Int, useTLS: Bool) async -> Credential? {
        let scheme = useTLS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/") else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        // Accept self-signed certs on the user's own LAN device.
        let session = URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)

        // Baseline: does the root require auth at all?
        guard await requiresAuth(url: url, session: session) else { return nil }

        for cred in loadDefaults() {
            if Task.isCancelled { break }
            if await accepts(url: url, cred: cred, session: session) {
                return cred
            }
        }
        return nil
    }

    private static func requiresAuth(url: URL, session: URLSession) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 401
    }

    private static func accepts(url: URL, cred: Credential, session: URLSession) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let token = Data("\(cred.username):\(cred.password)".utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        // 2xx/3xx after presenting credentials ⇒ accepted. Still 401 ⇒ rejected.
        return (200..<400).contains(http.statusCode)
    }
}

/// Accepts any server certificate — appropriate only because this tool talks
/// exclusively to the user's own LAN devices, which commonly ship self-signed
/// certs. Never reuse this delegate for general internet traffic.
private final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
