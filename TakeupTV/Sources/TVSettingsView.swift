import SwiftUI

/// Settings under the still brand threads: branded without artwork. Typing
/// with a remote is miserable, so the Bonjour-discovered servers lead and the
/// address field is the fallback. No network section — the TV has no tunnel
/// and no offline story, just a health check.
struct TVSettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var discovery = LoomDiscovery()
    @State private var scanStatus: ScanStatus?
    @State private var scanError: String?
    @State private var healthLine: String?
    @State private var checking = false

    var body: some View {
        @Bindable var appEnvironment = appEnvironment
        ZStack {
            ThreeThreads(colors: [RGB(hexValue: 0xFF4D55), RGB(hexValue: 0x3FD1C4), RGB(hexValue: 0xA78BFA)])
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.top, TVLayout.verticalMargin)

                    RowLabel(text: "Server", color: .teal)
                        .padding(.top, 40)
                    TextField(
                        "Server address",
                        text: $appEnvironment.serverURLString,
                        prompt: Text("192.168.1.20:8097").foregroundStyle(Color.faint)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.top, 18)
                    HStack(spacing: 16) {
                        Button(checking ? "Checking…" : "Check connection") {
                            Task { await checkHealth() }
                        }
                        .buttonStyle(TVPillButtonStyle())
                        .disabled(checking || appEnvironment.client == nil)
                        if let healthLine {
                            Text(healthLine)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .padding(.top, 18)

                    RowLabel(text: "Discovered on network", color: .ember)
                        .padding(.top, 44)
                    if discovery.servers.isEmpty {
                        HStack(spacing: 14) {
                            ProgressView()
                                .tint(.teal)
                            Text("Looking for Loom…")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.muted)
                        }
                        .padding(.top, 18)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(discovery.servers) { server in
                                discoveredRow(server)
                            }
                        }
                        .padding(.top, 18)
                    }

                    RowLabel(text: "Library", color: .amber)
                        .padding(.top, 44)
                    Text(scanStatusLine)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 14)
                    Button("Scan libraries now") {
                        Task { await triggerScan() }
                    }
                    .buttonStyle(TVPillButtonStyle())
                    .disabled(scanStatus?.running == true || appEnvironment.client == nil)
                    .opacity(scanStatus?.running == true || appEnvironment.client == nil ? 0.5 : 1)
                    .padding(.top, 18)

                    RowLabel(text: "About")
                        .padding(.top, 44)
                    Text("Takeup is the take-up reel on a loom: the beam that winds finished cloth as it is woven.")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 14)
                }
                .padding(.horizontal, TVLayout.sideMargin)
                .padding(.bottom, TVLayout.verticalMargin)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.stage)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .task { await pollScanStatus() }
    }

    private var scanStatusLine: String {
        if let scanError { return "Scan status unavailable: \(scanError)" }
        guard let scanStatus else { return "Checking scan status..." }
        if scanStatus.running == true {
            let library = scanStatus.library.flatMap { $0.isEmpty ? nil : $0 } ?? "all libraries"
            return "Scanning \(library)..."
        }
        if let error = scanStatus.lastError, !error.isEmpty { return "Last scan failed: \(error)" }
        if let ended = scanStatus.lastEndedAt, !ended.isEmpty {
            return "Last scan finished \(formatTimestamp(ended))"
        }
        return "No scan has run yet"
    }

    private func checkHealth() async {
        guard let client = appEnvironment.client else { return }
        checking = true
        do {
            try await client.health()
            healthLine = "Loom is answering."
        } catch {
            healthLine = "Couldn't reach Loom: \(error.localizedDescription)"
        }
        checking = false
    }

    private func pollScanStatus() async {
        while !Task.isCancelled {
            await refreshScanStatus()
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
        }
    }

    private func triggerScan() async {
        guard let client = appEnvironment.client else { return }
        do {
            try await client.triggerScan()
            scanError = nil
            await refreshScanStatus()
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            scanError = error.localizedDescription
        }
    }

    private func refreshScanStatus() async {
        guard let client = appEnvironment.client else { return }
        do {
            scanStatus = try await client.scanStatus()
            scanError = nil
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            scanError = error.localizedDescription
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
        }
        .buttonStyle(TVRowButtonStyle())
    }
}
