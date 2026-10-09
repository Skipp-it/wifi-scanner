import Foundation

/// Headless scan pipeline shared by the foreground view model and the
/// background monitor. Runs discovery → audit and returns a `ScanSnapshot`.
///
/// It performs no UI work and no persistence — callers decide what to do with
/// the snapshot. Incremental progress + the growing device list are reported
/// through `onUpdate`; a UI caller marshals those onto the main actor itself.
struct ScanService {

    enum Failure: Error { case networkUnavailable }

    func run(options: AuditEngine.Options,
             bonjourDuration: TimeInterval = 4.0,
             onUpdate: (ScanProgress, [Device]) -> Void = { _, _ in }) async throws -> ScanSnapshot? {

        var progress = ScanProgress(phase: "Reading network…")
        onUpdate(progress, [])

        // 1. Subnet.
        guard let info = LocalNetwork.current() else { throw Failure.networkUnavailable }
        progress.hostsTotal = info.hostAddresses.count

        // 2. Bonjour browse runs concurrently with the discovery sweep.
        async let bonjour = BonjourBrowser().browse(duration: bonjourDuration)

        // 3. Host discovery.
        progress.phase = "Discovering hosts…"
        onUpdate(progress, [])
        let alive = await HostDiscovery.discover(hosts: info.hostAddresses) { done, _ in
            progress.hostsScanned = done
            progress.fraction = progress.hostsTotal > 0
                ? Double(done) / Double(progress.hostsTotal) * 0.4 : 0
            onUpdate(progress, [])
        }
        if Task.isCancelled { return nil }

        // Always include the gateway even if the sweep missed it.
        var targets = alive
        if !targets.contains(info.likelyGateway) { targets.insert(info.likelyGateway, at: 0) }

        let bonjourResults = await bonjour

        // 4. Audit each live host.
        progress.phase = "Auditing \(targets.count) devices…"
        let engine = AuditEngine(options: options)

        var devices: [Device] = []
        var completed = 0
        for ip in targets {
            if Task.isCancelled { return nil }
            let isGateway = (ip == info.likelyGateway)
            let services = bonjourResults.map { "\($0.name) [\($0.type)]" }

            let device = await engine.audit(
                ip: ip,
                isGateway: isGateway,
                bonjourServices: isGateway ? services : [],
                hostname: nil
            )
            devices.append(device)
            devices.sort { ($0.isGateway ? 1 : 0, $0.highestSeverity ?? .info) > ($1.isGateway ? 1 : 0, $1.highestSeverity ?? .info) }

            completed += 1
            progress.devicesFound = devices.count
            progress.fraction = 0.4 + (Double(completed) / Double(max(targets.count, 1))) * 0.6
            onUpdate(progress, devices)
        }

        progress.phase = "Done"
        progress.fraction = 1.0
        onUpdate(progress, devices)

        return ScanSnapshot(localIP: info.localIP, gateway: info.likelyGateway, devices: devices)
    }
}
