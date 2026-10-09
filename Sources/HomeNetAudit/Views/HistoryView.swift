import SwiftUI

/// Lists saved scans. Tapping one compares it against the chronologically
/// previous scan; each row can also export its own report.
struct HistoryView: View {
    @ObservedObject var model: ScanViewModel
    @State private var shareItem: ShareItem?

    var body: some View {
        List {
            if model.snapshots.isEmpty {
                ContentUnavailableView("No Saved Scans", systemImage: "clock.arrow.circlepath",
                                       description: Text("Run a scan and it will be saved here automatically."))
            }
            ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                let previous = model.snapshots[safe: index + 1]   // older scan
                NavigationLink {
                    if let previous {
                        DiffView(diff: ScanDiff.between(old: previous, new: snapshot))
                    } else {
                        DiffView(diff: ScanDiff())   // first scan: nothing to compare
                    }
                } label: {
                    row(snapshot)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { model.deleteSnapshot(snapshot) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { export(snapshot) } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }.tint(.blue)
                }
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
    }

    private func row(_ snapshot: ScanSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(snapshot.scoreGrade).font(.title2.bold())
                Text("\(snapshot.securityScore)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.date, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline.weight(.medium))
                Text("\(snapshot.deviceCount) devices · \(snapshot.findingCount) findings")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let sev = snapshot.highestSeverity, sev > .info { SeverityBadge(severity: sev) }
        }
    }

    private func export(_ snapshot: ScanSnapshot) {
        shareItem = ShareItem(url: ReportExporter.pdf(snapshot: snapshot))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
