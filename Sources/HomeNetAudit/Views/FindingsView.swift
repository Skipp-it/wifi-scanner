import SwiftUI

struct FindingsView: View {
    let findings: [Finding]

    var body: some View {
        List {
            ForEach(findings) { FindingRow(finding: $0) }
        }
        .navigationTitle("Findings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Expandable row rendering one finding with its guidance.
struct FindingRow: View {
    let finding: Finding
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                detail("What this means", finding.detail)
                detail("Recommendation", finding.recommendation)
                if let ref = finding.reference {
                    detail("Reference", ref)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: finding.severity.symbolName)
                    .foregroundStyle(finding.severity.color)
                Text(finding.title).font(.subheadline.weight(.medium))
                Spacer()
            }
        }
    }

    private func detail(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(body).font(.callout)
        }
    }
}
