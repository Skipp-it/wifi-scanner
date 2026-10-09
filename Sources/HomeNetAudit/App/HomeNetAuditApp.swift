import SwiftUI

@main
struct HomeNetAuditApp: App {
    @AppStorage("didAcceptAuthorizedUse") private var didAccept = false

    var body: some Scene {
        WindowGroup {
            if didAccept {
                ContentView()
            } else {
                ConsentGate(didAccept: $didAccept)
            }
        }
    }
}
