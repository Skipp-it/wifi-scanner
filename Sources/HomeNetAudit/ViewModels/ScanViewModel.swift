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

        // Populate network info early so the UI can show IP/router during the scan.
        networkInfo = LocalNetwork.current()
        guard networkInfo != nil else {
            errorMessage = "Couldn't read the local network. Make sure you're on Wi‑Fi (not cellular) and have granted Local Network permission in Settings."
            return
        }

        let options = AuditEngine.Options(checkDefaultCredentials: checkDefaultCredentials)
        let snapshot: ScanSnapshot?
        do {
            snapshot = try await ScanService().run(options: options) { [weak self] prog, devs in
                Task { @MainActor in
                    guard let self else { return }
                    self.progress = prog
                    if !devs.isEmpty { self.devices = devs }
                }
            }
        } catch {
            errorMessage = "Couldn't read the local network. Make sure you're on Wi‑Fi (not cellular) and have granted Local Network permission in Settings."
            return
        }

        guard let snapshot else { return }   // cancelled

        // Persist this run and compute the diff against the previous scan.
        devices = snapshot.devices
        if let previous = snapshots.first {
            lastDiff = ScanDiff.between(old: previous, new: snapshot)
        }
        store.save(snapshot)
        snapshots.insert(snapshot, at: 0)
    }
}
