import SwiftUI
import GSIntelligence

/// Minimal demo screen exercising the three things you test during integration:
///   1. Get Session  — seal a token (sandbox=unencrypted, live=encrypted JWE)
///   2. Get Device ID — the stable Keychain-backed identifier
///   3. Render the decoded signal JSON (sandbox mode only) for eyeballing
struct ContentView: View {
    @State private var token: String = ""
    @State private var deviceId: String = ""
    @State private var signalJson: String = ""
    @State private var status: String = "Idle"
    @State private var busy = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Status: \(status)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: getSession) {
                        Label("Get Session", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)

                    Button(action: getDeviceId) {
                        Label("Get Device ID", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)

                    if !token.isEmpty {
                        section("Token (send to YOUR backend)", token)
                    }
                    if !deviceId.isEmpty {
                        section("Device ID", deviceId)
                    }
                    if !signalJson.isEmpty {
                        section("Decoded signals (sandbox)", signalJson)
                    }
                }
                .padding()
            }
            .navigationTitle("GS Intelligence Demo")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private func getSession() {
        busy = true
        status = "Collecting signals…"
        Task {
            do {
                let session = try await GS.getSession()
                await MainActor.run {
                    token = session
                    signalJson = Self.decodeSandboxPayload(session) ?? ""
                    status = "Session ready"
                    busy = false
                }
            } catch {
                await MainActor.run {
                    status = "Error: \(error)"
                    busy = false
                }
            }
        }
    }

    private func getDeviceId() {
        deviceId = GS.getDeviceId()
        status = "Device ID read"
    }

    /// In sandbox mode the token is `gsds_sandbox.<base64url(payload)>`.
    /// Decode the second segment so we can pretty-print the signal envelope.
    private static func decodeSandboxPayload(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 2, parts[0] == "gsds_sandbox" else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard
            let data = Data(base64Encoded: b64),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

#Preview {
    ContentView()
}
