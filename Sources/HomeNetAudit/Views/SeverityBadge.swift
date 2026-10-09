import SwiftUI

extension Severity {
    var color: Color {
        switch self {
        case .info: return .secondary
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

/// Small colored pill used in lists and detail headers.
struct SeverityBadge: View {
    let severity: Severity
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: severity.symbolName)
            Text(count.map { "\($0) \(severity.label)" } ?? severity.label)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(severity.color.opacity(0.18), in: Capsule())
        .foregroundStyle(severity.color)
    }
}
