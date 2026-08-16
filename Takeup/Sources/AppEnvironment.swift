import Foundation
import Observation

/// App-wide state: the configured Loom server and the API client built from it.
/// Mirrors Takeup Android's ServerConfig-in-DataStore, using UserDefaults.
@Observable
@MainActor
final class AppEnvironment {
    private static let serverKey = "loom.server.url"

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverKey) }
    }

    init() {
        // No default: the server address lives in Settings, never in the repo.
        serverURLString = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
    }

    var serverURL: URL? {
        Self.normalize(serverURLString)
    }

    static func normalize(_ address: String) -> URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard var components = URLComponents(string: raw) else { return nil }
        if components.port == nil { components.port = 8097 }
        return components.url
    }

    var client: LoomClient? {
        serverURL.map { LoomClient(baseURL: $0) }
    }
}
