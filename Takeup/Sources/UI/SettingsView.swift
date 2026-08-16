import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var status: String?

    var body: some View {
        @Bindable var appEnvironment = appEnvironment
        Form {
            Section("Loom Server") {
                TextField("Server address", text: $appEnvironment.serverURLString, prompt: Text("192.168.1.20:8097"))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                if let status {
                    Text(status)
                        .foregroundStyle(status.hasPrefix("Connected") ? .green : .red)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func testConnection() async {
        guard let client = appEnvironment.client else {
            status = "Invalid server address"
            return
        }
        do {
            try await client.health()
            status = "Connected to \(client.baseURL.absoluteString)"
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}
