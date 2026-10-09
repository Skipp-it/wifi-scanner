import SwiftUI

/// Renders a `ScanDiff` as a human-readable "what changed" report.
struct DiffView: View {
    let diff: ScanDiff

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Score change")
                    Spacer()
                    Text(diff.scoreDelta >= 0 ? "+\(diff.scoreDelta)" : "\(diff.scoreDelta)")
                        .font(.headline)
                        .foregroundStyle(diff.scoreDelta >= 0 ? .green : .red)
                }
                if !diff.hasChanges {
                    Label("No changes since the previous scan.", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
            }

            changeSection("New devices", diff.newDevices.map(\.displayName),
                          symbol: "plus.circle.fill", tint: .red)
            changeSection("Devices gone", diff.removedDevices.map(\.displayName),
                          symbol: "minus.circle.fill", tint: .secondary)

            portSection("Ports newly opened", diff.portsOpened, symbol: "lock.open.fill", tint: .red)
            portSection("Ports now closed", diff.portsClosed, symbol: "lock.fill", tint: .green)

            findingSection("New issues", diff.findingsIntroduced, tint: .red)
            findingSection("Resolved issues", diff.findingsResolved, tint: .green)
        }
        .navigationTitle("What Changed")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func changeSection(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))") {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: symbol).foregroundStyle(tint)
                }
            }
        }
    }

    @ViewBuilder
    private func portSection(_ title: String, _ items: [ScanDiff.PortChange], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))") {
                ForEach(items) { change in
                    Label("\(change.ip) · port \(change.port) \(change.serviceName ?? "")",
                          systemImage: symbol).foregroundStyle(tint)
                }
            }
        }
    }

    @ViewBuilder
    private func findingSection(_ title: String, _ items: [ScanDiff.FindingChange], tint: Color) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))") {
                ForEach(items) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(change.finding.title, systemImage: change.finding.severity.symbolName)
                            .foregroundStyle(tint)
                        Text(change.ip).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
