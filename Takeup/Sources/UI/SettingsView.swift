import SwiftUI

/// Settings under the still brand threads: branded without artwork. Section
/// labels are color-coded by thread, like the Android app.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(NetworkPolicy.self) private var network
    @State private var discovery = LoomDiscovery()

    var body: some View {
        @Bindable var appEnvironment = appEnvironment
        ZStack {
            ThreeThreads(colors: [RGB(hexValue: 0xFF4D55), RGB(hexValue: 0x3FD1C4), RGB(hexValue: 0xA78BFA)])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 16)

                    RowLabel(text: "Server", color: .teal)
                        .padding(.top, 24)
                    TextField("Server address", text: $appEnvironment.serverURLString, prompt: Text("192.168.1.20:8097").foregroundStyle(Color.faint))
                        .font(.bodyLarge)
                        .foregroundStyle(Color.ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.surface1.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
                        .padding(.top, 12)
                    RowLabel(text: "Network", color: .amber)
                        .padding(.top, 28)
                    HStack(spacing: 12) {
                        Circle()
                            .fill(reachColor)
                            .frame(width: 6, height: 6)
                        Text(reachSentence)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.muted)
                        Spacer(minLength: 8)
                        Button("Check") {
                            network.recheck()
                        }
                        .font(.labelLarge)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ink.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                    .padding(.top, 12)

                    RowLabel(text: "Discovered on network", color: .ember)
                        .padding(.top, 28)
                    if discovery.servers.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.teal)
                            Text("Looking for Loom…")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.muted)
                        }
                        .padding(.top, 12)
                    } else {
                        ForEach(discovery.servers) { server in
                            discoveredRow(server)
                        }
                    }

                    RowLabel(text: "About")
                        .padding(.top, 28)
                    Text("Takeup is the take-up reel on a loom: the beam that winds finished cloth as it is woven.")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    /// What the app currently knows about the route to Loom, in its own words
    /// rather than an exception's.
    private var reachSentence: String {
        switch network.reach {
        case .home: "Loom is answering on your home network."
        case .remote: "Loom is answering through the tunnel."
        case .offline: network.reason
        case .unknown: "Checking for Loom..."
        }
    }

    private var reachColor: Color {
        switch network.reach {
        case .home, .remote: .teal
        case .offline: .amber
        case .unknown: .faint
        }
    }

    private func discoveredRow(_ server: LoomDiscovery.Server) -> some View {
        Button {
            appEnvironment.serverURLString = server.urlString
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.titleSmall)
                        .foregroundStyle(Color.ink)
                    Text(server.urlString)
                        .font(.labelSmall)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                if appEnvironment.serverURLString == server.urlString {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.teal)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .padding(.top, 8)
    }
}
