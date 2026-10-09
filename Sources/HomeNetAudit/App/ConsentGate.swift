import SwiftUI

/// First-run gate requiring the user to affirm they are only testing networks
/// they own or are authorized to test. Scanning and credential checks on
/// networks you don't control can be unlawful, so this is non-skippable.
struct ConsentGate: View {
    @Binding var didAccept: Bool
    @State private var confirmed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            Text("Authorized Use Only")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                bullet("HomeNetAudit scans the Wi‑Fi network you're connected to and inspects devices for common security weaknesses.")
                bullet("Only scan networks and devices you personally own, or have explicit written permission to test.")
                bullet("Port scanning and credential checks against networks you don't control may be illegal where you live.")
                bullet("Checks are light-touch: the app reads what services reveal. It does not exploit vulnerabilities.")
            }
            .padding()
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

            Toggle(isOn: $confirmed) {
                Text("I confirm I am authorized to test the network I will scan.")
                    .font(.callout)
            }
            .padding(.horizontal, 4)

            Button {
                didAccept = true
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!confirmed)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 560)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            Text(text).font(.callout)
        }
    }
}
