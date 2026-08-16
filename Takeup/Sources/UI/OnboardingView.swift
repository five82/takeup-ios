import SwiftUI

/// First-run screen shown while no Loom server is configured. Offers
/// Bonjour-discovered servers and manual entry; commits the address only
/// after a successful health check.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var discovery = LoomDiscovery()
    @State private var draft = ""
    @State private var connecting = false
    @State private var connectError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Takeup")
                .font(.largeTitle.weight(.bold))
            Text("Connect to your Loom server")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if !discovery.servers.isEmpty {
                    ForEach(discovery.servers) { server in
                        Button {
                            Task { await connect(to: server.urlString) }
                        } label: {
                            HStack {
                                Image(systemName: "server.rack")
                                VStack(alignment: .leading) {
                                    Text(server.name).font(.body.weight(.medium))
                                    Text(server.urlString).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                            .padding()
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for Loom on your network…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    TextField("192.168.1.20:8097", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onSubmit { Task { await connect(to: draft) } }
                    Button("Connect") {
                        Task { await connect(to: draft) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                }

                if connecting {
                    ProgressView()
                }
                if let connectError {
                    Text(connectError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 440)

            Spacer()
            Spacer()
        }
        .padding()
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private func connect(to address: String) async {
        guard let url = AppEnvironment.normalize(address) else {
            connectError = "That doesn't look like a server address."
            return
        }
        connecting = true
        connectError = nil
        do {
            try await LoomClient(baseURL: url).health()
            // Committing the address flips RootView over to the main UI.
            appEnvironment.serverURLString = address
        } catch {
            connectError = "Couldn't reach Loom there: \(error.localizedDescription)"
        }
        connecting = false
    }
}
