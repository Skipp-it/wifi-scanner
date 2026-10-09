import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {

    @Published var progress = ScanProgress()
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var networkInfo: LocalNetworkInfo?

    /// Saved scans (newest first) and the diff from the most recent run.
    @Published var snapshots: [ScanSnapshot] = []
    @Published var lastDiff: ScanDiff?

    /// User setting — the default-credential probe is off unless explicitly enabled.
    @AppStorage("checkDefaultCredentials") var checkDefaultCredentials = false

    private let store = ScanStore()
    private var scanTask: Task<Void, Never>?

    init() {
        snapshots = store.loadAll()
    }

    /// A snapshot of the current on-screen results, for ad-hoc export.
    var currentSnapshot: ScanSnapshot? {
        guard let info = networkInfo else { return nil }
        return ScanSnapshot(localIP: info.localIP, gateway: info.likelyGateway, devices: devices)
    }

    func deleteSnapshot(_ snapshot: ScanSnapshot) {
        store.delete(snapshot)
        snapshots.removeAll { $0.id == snapshot.id }
    }

    var allFindings: [Finding] {
        devices.flatMap(\.findings).sorted { $0.severity > $1.severity }
    }

    var findingCountsBySeverity: [Severity: Int] {
        Dictionary(grouping: allFindings, by: \.severity).mapValues(\.count)
    }

    func startScan() {
        guard !isScanning else { return }
        errorMessage = nil
        devices = []
        isScanning = true

        scanTask = Task { await runScan() }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progress.phase = "Cancelled"
    }

    private func runScan() async {
        defer { isScanning = false }

        // 1. Figure out the subnet.
        progress = ScanProgress(phase: "Reading network…")
        guard let info = LocalNetwork.current() else {
            errorMessage = "Couldn't read the local network. Make sure you're on Wi‑Fi (not cellular) and have granted Local Network permission in Settings."
            return
        }
        networkInfo = info
        progress.hostsTotal = info.hostAddresses.count

        // 2. Bonjour browse (in parallel with the ping sweep).
        async let bonjour = BonjourBrowser().browse(duration: 4.0)

        // 3. Host discovery sweep.
        progress.phase = "Discovering hosts…"
        let alive = await HostDiscovery.discover(hosts: info.hostAddresses) { [weak self] done, _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress.hostsScanned = done
                self.progress.fraction = self.progress.hostsTotal > 0
                    ? Double(done) / Double(self.progress.hostsTotal) * 0.4 : 0
            }
        }
        if Task.isCancelled { return }

        // Ensure the gateway is always audited even if the sweep missed it.
        var targets = alive
        if !targets.contains(info.likelyGateway) { targets.insert(info.likelyGateway, at: 0) }

        let bonjourResults = await bonjour
        let bonjourByName = bonjourResults   // name→type map kept for display

        // 4. Audit each live host.
        progress.phase = "Auditing \(targets.count) devices…"
        let engine = AuditEngine(options: .init(checkDefaultCredentials: checkDefaultCredentials))

        var completed = 0
        for ip in targets {
            if Task.isCancelled { return }
            let isGateway = (ip == info.likelyGateway)
            let services = bonjourByName.map { "\($0.name) [\($0.type)]" }

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
        }

        // Persist this run and compute the diff against the previous scan.
        let snapshot = ScanSnapshot(localIP: info.localIP, gateway: info.likelyGateway, devices: devices)
        if let previous = snapshots.first {
            lastDiff = ScanDiff.between(old: previous, new: snapshot)
        }
        store.save(snapshot)
        snapshots.insert(snapshot, at: 0)

        progress.phase = "Done"
        progress.fraction = 1.0
    }
}
