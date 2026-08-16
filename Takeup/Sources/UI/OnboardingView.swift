import SwiftUI

/// First run breathes in the brand threads; every screen after this takes
/// its color from the library instead. Offers Bonjour-discovered servers and
/// manual entry; commits the address only after a successful health check.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var discovery = LoomDiscovery()
    @State private var draft = ""
    @State private var connecting = false
    @State private var connectError: String?

    var body: some View {
        ZStack {
            ThreeThreads(
                colors: [RGB(hexValue: 0xFF4D55), RGB(hexValue: 0x3FD1C4), RGB(hexValue: 0xA78BFA)],
                drifting: true
            )
            VStack(spacing: 0) {
                Spacer()

                Selvedge()
                    .frame(width: 96)
                Text("Takeup")
                    .font(.displayLarge)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 18)
                Text("a client for Loom")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 4)

                VStack(spacing: 12) {
                    if !discovery.servers.isEmpty {
                        ForEach(discovery.servers) { server in
                            Button {
                                Task { await connect(to: server.urlString) }
                            } label: {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(Color.teal)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.titleSmall)
                                            .foregroundStyle(Color.ink)
                                        Text(server.urlString)
                                            .font(.labelSmall)
                                            .foregroundStyle(Color.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(Color.muted)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(0.10), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.lift)
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.teal)
                            Text("Looking for Loom on your network…")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.muted)
                        }
                        .padding(.vertical, 4)
                    }

                    TextField("Server address", text: $draft, prompt: Text("192.168.1.20:8097").foregroundStyle(Color.faint))
                        .font(.bodyLarge)
                        .foregroundStyle(Color.ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
                        .onSubmit { Task { await connect(to: draft) } }

                    Button {
                        Task { await connect(to: draft) }
                    } label: {
                        Text("Connect")
                            .font(.labelLarge)
                            .foregroundStyle(Color(hexValue: 0x33060A))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.ember, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty || connecting ? 0.5 : 1)

                    if connecting {
                        ProgressView()
                            .tint(.teal)
                    }
                    if let connectError {
                        Text(connectError)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.ember)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 440)
                .padding(.top, 36)

                Spacer()
                Spacer()
            }
            .padding(32)
        }
        .background(Color.stage)
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
