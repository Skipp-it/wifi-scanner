import SwiftUI

struct ContentView: View {
    @StateObject private var model = ScanViewModel()
    @State private var showSettings = false
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if let diff = model.lastDiff, diff.hasChanges { diffLink(diff) }
                if !model.devices.isEmpty { devicesSection }
                if !model.allFindings.isEmpty { findingsLink }
                historyLink
            }
            .navigationTitle("HomeNetAudit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack { exportMenu; scanButton }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
            .overlay { if model.devices.isEmpty && !model.isScanning { emptyState } }
        }
    }

    private func diffLink(_ diff: ScanDiff) -> some View {
        Section {
            NavigationLink { DiffView(diff: diff) } label: {
                Label {
                    Text(diff.regressions > 0
                         ? "\(diff.regressions) new risk\(diff.regressions == 1 ? "" : "s") since last scan"
                         : "Network changed since last scan")
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(diff.regressions > 0 ? .red : .primary)
            }
        }
    }

    private var historyLink: some View {
        Section {
            NavigationLink { HistoryView(model: model) } label: {
                Label("Scan History (\(model.snapshots.count))", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button { exportCurrent(asPDF: true) } label: { Label("Export PDF", systemImage: "doc.richtext") }
            Button { exportCurrent(asPDF: false) } label: { Label("Export JSON", systemImage: "curlybraces") }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(model.currentSnapshot == nil || model.devices.isEmpty)
    }

    private func exportCurrent(asPDF: Bool) {
        guard let snapshot = model.currentSnapshot else { return }
        if asPDF {
            shareItem = ShareItem(url: ReportExporter.pdf(snapshot: snapshot))
        } else if let url = try? ReportExporter.json(snapshot: snapshot) {
            shareItem = ShareItem(url: url)
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            if model.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.progress.fraction)
                    Text(model.progress.phase).font(.caption).foregroundStyle(.secondary)
                    if model.progress.hostsTotal > 0 {
                        Text("Swept \(model.progress.hostsScanned)/\(model.progress.hostsTotal) addresses · \(model.progress.devicesFound) devices")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let info = model.networkInfo {
                LabeledContent("Your IP", value: info.localIP)
                LabeledContent("Router", value: info.likelyGateway)
            }
            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.red)
            }
            if !model.allFindings.isEmpty {
                severityRow
            }
        }
    }

    private var severityRow: some View {
        let counts = model.findingCountsBySeverity
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Severity.allCases.reversed(), id: \.self) { sev in
                    if let c = counts[sev], c > 0 { SeverityBadge(severity: sev, count: c) }
                }
            }
        }
    }

    private var devicesSection: some View {
        Section("Devices (\(model.devices.count))") {
            ForEach(model.devices) { device in
                NavigationLink(value: device) {
                    DeviceRow(device: device)
                }
            }
        }
        .navigationDestination(for: Device.self) { DeviceDetailView(device: $0) }
    }

    private var findingsLink: some View {
        Section {
            NavigationLink { FindingsView(findings: model.allFindings) } label: {
                Label("All Findings (\(model.allFindings.count))", systemImage: "list.bullet.clipboard")
            }
        }
    }

    // MARK: - Pieces

    private var scanButton: some View {
        Group {
            if model.isScanning {
                Button(role: .cancel) { model.cancelScan() } label: { Text("Stop") }
            } else {
                Button { model.startScan() } label: { Label("Scan", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ready to Audit", systemImage: "wifi.router")
        } description: {
            Text("Join the Wi‑Fi you want to test, then tap Scan. First scan will ask for Local Network permission.")
        } actions: {
            Button { model.startScan() } label: { Text("Start Scan") }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct DeviceRow: View {
    let device: Device
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .font(.title3).frame(width: 30)
                .foregroundStyle(device.isGateway ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName).font(.body)
                Text("\(device.openPorts.count) open ports · \(device.ipAddress)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let sev = device.highestSeverity, sev > .info {
                SeverityBadge(severity: sev)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Check for default credentials", isOn: $model.checkDefaultCredentials)
                } footer: {
                    Text("When on, HomeNetAudit will try a short list of well-known factory-default logins against the web admin interface of discovered devices. Use only on devices you own.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
