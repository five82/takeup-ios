import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var discovery = LoomDiscovery()
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
            Section("Discovered on Network") {
                if discovery.servers.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for Loom…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(discovery.servers) { server in
                        Button {
                            appEnvironment.serverURLString = server.urlString
                            status = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                    Text(server.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appEnvironment.serverURLString == server.urlString {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
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
