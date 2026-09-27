import Foundation
import Observation

/// App-wide state: the configured Loom server and the API client built from it.
/// Mirrors Takeup Android's ServerConfig-in-DataStore, using UserDefaults.
///
/// The iPad wires in NetworkPolicy (its offline/Tailscale brain); the TV app
/// has no offline story — it lives on the Loom LAN — so its requests always go
/// out and failures surface as plain errors.
@Observable
@MainActor
final class AppEnvironment {
    private static let serverKey = "loom.server.url"

#if os(iOS)
    /// Owned here so there is exactly one; TakeupApp injects it into the
    /// SwiftUI environment for screens to read.
    let network = NetworkPolicy()
#endif

    @ObservationIgnored private let clientSession: URLSession?

    var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverKey)
            updateNetworkAddress()
        }
    }

    init(clientSession: URLSession? = nil) {
        self.clientSession = clientSession
        // No default: the server address lives in Settings, never in the repo.
        serverURLString = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
        updateNetworkAddress()
    }

    private func updateNetworkAddress() {
#if os(iOS)
        network.serverURL = serverURL
        network.recheck()
#endif
    }

    var serverURL: URL? {
        Self.normalize(serverURLString)
    }

    static func normalize(_ address: String) -> URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard var components = URLComponents(string: raw) else { return nil }
        // Only cleartext LAN addresses get Loom's default port. An https name
        // (a ts.net host, say) is already whole, and :8097 would break it.
        if components.scheme == "http", components.port == nil { components.port = 8097 }
        return components.url
    }

    var client: LoomClient? {
        serverURL.map { url in
#if os(iOS)
            var client = LoomClient(baseURL: url, blocked: network.blockedGate)
#else
            var client = LoomClient(baseURL: url)
#endif
            if let clientSession { client.session = clientSession }
            return client
        }
    }
}
