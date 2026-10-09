import SwiftUI

struct DeviceDetailView: View {
    let device: Device

    var body: some View {
        List {
            Section {
                LabeledContent("IP Address", value: device.ipAddress)
                LabeledContent("Type", value: device.kind.rawValue.capitalized)
                if device.isGateway { Label("This is your router / gateway", systemImage: "wifi.router") }
            }

            if !device.findings.isEmpty {
                Section("Findings (\(device.findings.count))") {
                    ForEach(device.findings) { FindingRow(finding: $0) }
                }
            }

            Section("Open Ports (\(device.openPorts.count))") {
                if device.openPorts.isEmpty {
                    Text("No common ports open — good.").foregroundStyle(.secondary)
                }
                ForEach(device.openPorts) { port in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(port.port)").font(.body.monospaced().weight(.semibold))
                            Text(port.serviceName ?? "unknown").foregroundStyle(.secondary)
                        }
                        if let banner = port.banner, !banner.isEmpty {
                            Text(banner).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }

            if !device.bonjourServices.isEmpty {
                Section("Advertised Services (Bonjour)") {
                    ForEach(device.bonjourServices, id: \.self) { Text($0).font(.caption) }
                }
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
