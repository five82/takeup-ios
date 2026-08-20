import Foundation
import Network
import Observation

/// True when [server] and [local] agree on the first `prefixLength` bits, which
/// is what puts two addresses on one subnet.
func inSameSubnet(server: [UInt8], local: [UInt8], prefixLength: Int) -> Bool {
    guard server.count == local.count else { return false }
    guard prefixLength > 0, prefixLength <= local.count * 8 else { return false }
    var bits = prefixLength
    for index in local.indices {
        if bits <= 0 { break }
        let mask: UInt8 = bits >= 8 ? 0xFF : ~(0xFF >> UInt8(bits))
        if server[index] & mask != local[index] & mask { return false }
        bits -= 8
    }
    return true
}

/// Whether `address` is Tailscale's, and not merely a tunnel's.
///
/// 100.64.0.0/10 is carrier-grade NAT space, which Tailscale draws its
/// addresses from - but so do other things, so the range alone proves nothing.
/// Callers must also insist the address sits on a tunnel device: other VPNs
/// take a utun slot too but number it out of RFC 1918, which leaves the pair of
/// tests meaning Tailscale and nothing else.
func isTailnetAddress(_ address: [UInt8]) -> Bool {
    address.count == 4 && address[0] == 100 && (64...127).contains(address[1])
}

/// What a probe that was actually made adds up to. Answering from Loom's own
/// subnet is the only thing that counts as being home; answering from anywhere
/// else got there over the tunnel.
func reachFrom(answered: Bool, onHomeSubnet: Bool) -> NetworkPolicy.Reach {
    if !answered { return .offline }
    return onHomeSubnet ? .home : .remote
}

/// Policy alone, before anything is asked of the network. Being neither on
/// Loom's subnet nor on the tailnet is not a preference - there is no path to
/// Loom from there, so no setting can open it.
func networkBlocked(onHomeSubnet: Bool, onTailnet: Bool) -> Bool {
    !(onHomeSubnet || onTailnet)
}

/// Why the app is offline, in the app's own voice rather than an exception's.
func offlineReason(onHomeSubnet: Bool, onTailnet: Bool) -> String {
    if !onHomeSubnet && !onTailnet {
        return "You are away from home and Tailscale isn't connected."
    }
    return "Loom isn't answering."
}

/// A transport failure rather than an answer. A LoomError means Loom replied
/// with an HTTP error, which is never offline: retrying or queueing the same
/// write cannot improve it.
func isOfflineError(_ error: Error) -> Bool {
    if error is LoomError { return false }
    if error is CancellationError { return false }
    // Cancellation is the app's own doing, not the network's: SwiftUI tears a
    // `.task` down whenever its id changes, and URLSession reports that as a
    // URLError like any other transport failure. Reading it as offline was
    // enough to latch the offline screen at every launch - the first probe
    // moved reach off `unknown`, which cancelled the load already in flight,
    // whose cancellation then "proved" the server was gone.
    if let urlError = error as? URLError, urlError.code == .cancelled { return false }
    return error is URLError
}

/// The blocked flag as LoomClient sees it: a lock-protected box, because the
/// client runs off the main actor while the policy that decides it lives on it.
final class NetworkGate: @unchecked Sendable {
    private let lock = NSLock()
    private var blocked = false

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    fileprivate func set(_ value: Bool) {
        lock.lock()
        blocked = value
        lock.unlock()
    }
}

/// Whether Loom is reachable, decided before the app asks anything of it.
///
/// Loom is a LAN server, so "online" is not a property of the iPad having
/// internet - it is whether this particular network can hand us Loom. One gate
/// answers that without a single packet: a network that is neither Loom's
/// subnet nor the tailnet has no route to Loom at all, which makes `gate`
/// blocked, the single flag LoomClient reads.
///
/// The gate is measured rather than declared. A switch saying remote use is
/// permitted is a different claim from the tunnel being up: with it on, a
/// strange Wi-Fi with Tailscale disconnected reads exactly like being at home,
/// and every request goes out to a LAN address nothing is listening at.
///
/// Past that, one short probe settles it. It deliberately does not go through
/// LoomClient: that client refuses calls while blocked, and a probe that can be
/// refused would make offline a state the app could never leave.
@Observable
@MainActor
final class NetworkPolicy {
    /// `unknown` only lasts until the first probe answers; every screen treats
    /// it as "still looking", not as offline.
    enum Reach {
        case unknown, home, remote, offline
    }

    private(set) var reach: Reach = .unknown

    /// Seeded true: no server configured yet counts as home, because
    /// onboarding has to be able to reach a Loom it has not been told about.
    private(set) var onHomeSubnet = true

    private(set) var onTailnet = false

    /// The address to judge and probe; AppEnvironment keeps it in step with the
    /// configured server and rechecks. Nil means nothing is configured yet.
    @ObservationIgnored var serverURL: URL?

    /// Current wording for why there is no Loom, for whichever screen asks.
    var reason: String {
        offlineReason(onHomeSubnet: onHomeSubnet, onTailnet: onTailnet)
    }

    private nonisolated let gate = NetworkGate()

    /// The gate LoomClient checks before every request; callable from any actor.
    nonisolated var blockedGate: @Sendable () -> Bool {
        let gate = self.gate
        return { gate.isBlocked }
    }

    // Short on purpose: this decides how long a screen waits before it can
    // honestly say it is offline, so it must not sit on the app's timeout.
    private static let probeTimeout: TimeInterval = 1.5
    private static let probeDebounce: Duration = .milliseconds(300)
    private static let probeAttempts = 3
    private static let probeRetryGap: Duration = .milliseconds(250)

    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = probeTimeout
        config.timeoutIntervalForResource = probeTimeout
        return URLSession(configuration: config)
    }()

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var probeTask: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    /// Re-decides from scratch. Safe to call as often as a screen likes.
    func recheck() {
        probeTask?.cancel()
        guard let url = serverURL else {
            // Nothing configured is settled without a packet.
            probeTask = nil
            readFacts()
            reach = .offline
            return
        }
        probeTask = Task { [weak self] in
            // Path updates arrive in bursts as an interface settles, and a
            // manual retry is not worth telling apart from one of those.
            try? await Task.sleep(for: Self.probeDebounce)
            guard !Task.isCancelled, let self else { return }
            // Read after the debounce, not before it. Wi-Fi is momentarily
            // addressless right after a launch or a wake, and judging from
            // that first snapshot declared the app offline - with the gate
            // shut behind it - before the interface had finished coming up.
            self.readFacts()
            if networkBlocked(onHomeSubnet: self.onHomeSubnet, onTailnet: self.onTailnet) {
                // No route at all: nothing to learn from a packet.
                self.reach = .offline
                return
            }
            let answered = await Self.probe(url)
            guard !Task.isCancelled else { return }
            self.reach = reachFrom(answered: answered, onHomeSubnet: self.onHomeSubnet)
        }
    }

    /// Where this device sits, and the gate that follows from it.
    private func readFacts() {
        onHomeSubnet = Self.serverHostOnLocalSubnet(serverURL)
        onTailnet = Self.tailnetInterfaceUp()
        gate.set(networkBlocked(onHomeSubnet: onHomeSubnet, onTailnet: onTailnet))
    }

    /// A real request answered, which is stronger evidence than any probe: the
    /// server is up whatever a 1.5-second health check made of it. Lets one
    /// screen's successful retry lift the whole app out of offline, instead of
    /// leaving every other screen answering from downloads.
    func markReachable() {
        guard reach == .offline || reach == .unknown else { return }
        probeTask?.cancel()
        probeTask = nil
        readFacts()
        reach = onHomeSubnet ? .home : .remote
    }

    /// Drops straight to offline on a failed request, so a screen that has just
    /// watched a call time out does not wait on a probe to agree with it.
    func markUnreachable() {
        probeTask?.cancel()
        probeTask = nil
        reach = .offline
    }

    /// One slow connect is not evidence that Loom is gone. The first LAN
    /// request after a launch or a wake regularly outruns a timeout this
    /// short - the radio is still associating, and the local-network
    /// permission check adds to it - so a single attempt was deciding the
    /// question far more often than the server actually being down.
    private static func probe(_ baseURL: URL) async -> Bool {
        for attempt in 0..<probeAttempts {
            if attempt > 0 {
                try? await Task.sleep(for: probeRetryGap)
            }
            if Task.isCancelled { return false }
            if await probeOnce(baseURL) { return true }
        }
        return false
    }

    private static func probeOnce(_ baseURL: URL) async -> Bool {
        let url = baseURL.appending(path: "api/v1/health")
        guard let (data, response) = try? await probeSession.data(from: url) else { return false }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { return false }
        // A stranger's device sitting at the same address on a network that
        // happens to share Loom's subnet must not read as Loom, so the body has
        // to look like Loom's JSON, not merely be a 200.
        guard let body = String(data: data, encoding: .utf8) else { return false }
        return body.drop(while: { $0.isWhitespace }).first == "{"
    }

    // MARK: - Interfaces

    private struct LocalAddress {
        let name: String
        let isUp: Bool
        let isLoopback: Bool
        let bytes: [UInt8]
        let prefixLength: Int
    }

    /// Whether any local interface shares a subnet with the configured server.
    private static func serverHostOnLocalSubnet(_ serverURL: URL?) -> Bool {
        guard let host = serverURL?.host() else { return true }
        // A hostname would need DNS to compare, and a LAN name only resolves at
        // home anyway; treat it as home rather than block the app on a lookup.
        guard let server = numericAddressBytes(host) else { return true }
        // Fails OPEN, unlike the tailnet check below: with no evidence either
        // way, both land on "assume home".
        guard let addresses = localAddresses() else { return true }
        return addresses.contains { address in
            // Tailscale carries a route to the home subnet but holds no address
            // on it, so the tunnel cannot read as being home. The name check is
            // belt and braces for a tunnel that assigns one.
            address.isUp && !address.isLoopback && !address.name.hasPrefix("utun")
                && inSameSubnet(server: server, local: address.bytes, prefixLength: address.prefixLength)
        }
    }

    /// Whether Tailscale is up, by the address it puts on its own tun device.
    /// Both halves matter: see `isTailnetAddress`.
    private static func tailnetInterfaceUp() -> Bool {
        // No answer means no evidence of a tunnel, so this one fails CLOSED.
        guard let addresses = localAddresses() else { return false }
        return addresses.contains { address in
            address.isUp && address.name.hasPrefix("utun") && isTailnetAddress(address.bytes)
        }
    }

    /// Nil, not empty, when the list cannot be read: the two callers differ.
    private static func localAddresses() -> [LocalAddress]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var result: [LocalAddress] = []
        for entry in sequence(first: head, next: { $0.pointee.ifa_next }) {
            guard let sockaddr = entry.pointee.ifa_addr,
                  let bytes = addressBytes(sockaddr),
                  let netmask = entry.pointee.ifa_netmask,
                  let prefixLength = prefixLength(of: netmask)
            else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            result.append(LocalAddress(
                name: String(cString: entry.pointee.ifa_name),
                isUp: flags & IFF_UP != 0,
                isLoopback: flags & IFF_LOOPBACK != 0,
                bytes: bytes,
                prefixLength: prefixLength
            ))
        }
        return result
    }

    /// The address in network byte order, which is already big-endian bytes.
    private static func addressBytes(_ sockaddr: UnsafeMutablePointer<sockaddr>) -> [UInt8]? {
        switch Int32(sockaddr.pointee.sa_family) {
        case AF_INET:
            let address = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            return withUnsafeBytes(of: address.s_addr) { Array($0) }
        case AF_INET6:
            let address = sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr
            }
            return withUnsafeBytes(of: address) { Array($0) }
        default:
            return nil
        }
    }

    private static func prefixLength(of netmask: UnsafeMutablePointer<sockaddr>) -> Int? {
        guard let bytes = addressBytes(netmask) else { return nil }
        var bits = 0
        for byte in bytes {
            guard byte == 0xFF else {
                bits += (~byte).leadingZeroBitCount
                break
            }
            bits += 8
        }
        return bits
    }

    static func numericAddressBytes(_ host: String) -> [UInt8]? {
        // URL hosts wrap IPv6 literals in brackets that inet_pton rejects.
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var v4 = in_addr()
        if inet_pton(AF_INET, bare, &v4) == 1 {
            return withUnsafeBytes(of: v4.s_addr) { Array($0) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, bare, &v6) == 1 {
            return withUnsafeBytes(of: v6) { Array($0) }
        }
        return nil
    }
}
