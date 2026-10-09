import Foundation
import UIKit

/// Produces shareable JSON and PDF reports from a scan snapshot, written to
/// the temporary directory and returned as file URLs for the share sheet.
enum ReportExporter {

    enum ExportError: Error { case encodingFailed }

    // MARK: - JSON

    static func json(snapshot: ScanSnapshot) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)

        let url = tempURL(name: fileName(snapshot, ext: "json"))
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - PDF

    static func pdf(snapshot: ScanSnapshot) -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @72dpi
        let margin: CGFloat = 48
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = tempURL(name: fileName(snapshot, ext: "pdf"))

        try? renderer.writePDF(to: url) { ctx in
            var y: CGFloat = margin
            ctx.beginPage()

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > pageRect.height - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat = 6) {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                newPageIfNeeded(bounding.height)
                (text as NSString).draw(with: CGRect(x: margin, y: y, width: contentWidth, height: bounding.height),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                y += bounding.height + spacingAfter
            }

            func rule(_ spacing: CGFloat = 10) {
                newPageIfNeeded(spacing)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
                UIColor.separator.setStroke(); path.lineWidth = 0.5; path.stroke()
                y += spacing
            }

            // Header
            draw("HomeNetAudit — Security Report", font: .boldSystemFont(ofSize: 22), spacingAfter: 2)
            let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
            draw("Generated \(df.string(from: snapshot.date))", font: .systemFont(ofSize: 11), color: .darkGray)
            draw("Network \(snapshot.localIP)  ·  Router \(snapshot.gateway)", font: .systemFont(ofSize: 11), color: .darkGray)
            rule()

            // Score
            draw("Security Score: \(snapshot.securityScore)/100  (Grade \(snapshot.scoreGrade))",
                 font: .boldSystemFont(ofSize: 16))
            draw("\(snapshot.deviceCount) devices · \(snapshot.findingCount) findings", font: .systemFont(ofSize: 12), color: .darkGray)
            rule()

            // Per device
            for device in snapshot.devices.sorted(by: { ($0.highestSeverity ?? .info) > ($1.highestSeverity ?? .info) }) {
                draw(device.displayName + (device.isGateway ? "  (Router)" : ""),
                     font: .boldSystemFont(ofSize: 14), spacingAfter: 2)
                let ports = device.openPorts.map { "\($0.port) \($0.serviceName ?? "")".trimmingCharacters(in: .whitespaces) }
                    .joined(separator: ", ")
                draw("IP \(device.ipAddress) · Type \(device.kind.rawValue) · Open: \(ports.isEmpty ? "none" : ports)",
                     font: .systemFont(ofSize: 10), color: .darkGray)

                if device.findings.isEmpty {
                    draw("• No findings.", font: .systemFont(ofSize: 11), color: .systemGreen)
                } else {
                    for f in device.findings.sorted(by: { $0.severity > $1.severity }) {
                        draw("• [\(f.severity.label)] \(f.title)", font: .boldSystemFont(ofSize: 11),
                             color: uiColor(for: f.severity), spacingAfter: 1)
                        draw("   \(f.detail)", font: .systemFont(ofSize: 10), color: .black, spacingAfter: 1)
                        draw("   Fix: \(f.recommendation)", font: .italicSystemFont(ofSize: 10), color: .darkGray)
                    }
                }
                rule(8)
            }

            draw("Authorized-use audit of the owner's own network. Light-touch assessment; no exploitation performed.",
                 font: .italicSystemFont(ofSize: 9), color: .gray)
        }

        return url
    }

    // MARK: - Helpers

    private static func uiColor(for severity: Severity) -> UIColor {
        switch severity {
        case .info: return .gray
        case .low: return .systemYellow
        case .medium: return .systemOrange
        case .high: return .systemRed
        case .critical: return .systemPurple
        }
    }

    private static func fileName(_ s: ScanSnapshot, ext: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"
        return "HomeNetAudit-\(f.string(from: s.date)).\(ext)"
    }

    private static func tempURL(name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
