import SwiftUI

@main
struct GSDemoApp: App {
    init() {
        // Step 1 — configure once at app start.
        // Use sandbox: true with a gk_test_ key to inspect the raw signal
        // envelope (unencrypted). Switch to false + a live key for encrypted
        // tokens that fraud-check decrypts.
        GS.configure(
            clientId: "YOUR_CLIENT_ID",
            gps: .prompt,
            behavior: true,
            persistence: true,
            sandbox: true,
            debug: true
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
