import Foundation
import Testing
@testable import Takeup

struct NetworkPolicyTests {
    private func bytes(_ values: Int...) -> [UInt8] { values.map { UInt8($0) } }

    @Test func aFreshInstallOnTheHomeNetworkIsNotBlocked() {
        // The seeded facts must not read as "refuse everything": onboarding
        // itself runs through this gate before anything is saved.
        #expect(!networkBlocked(onHomeSubnet: true, onTailnet: false))
    }

    @Test func anotherSubnetIsBlockedUntilTheTunnelIsUp() {
        #expect(networkBlocked(onHomeSubnet: false, onTailnet: false))
        #expect(!networkBlocked(onHomeSubnet: false, onTailnet: true))
    }

    @Test func aProbeThatAnswersIsHomeOnlyFromLoomsOwnSubnet() {
        #expect(reachFrom(answered: true, onHomeSubnet: true) == .home)
        #expect(reachFrom(answered: true, onHomeSubnet: false) == .remote)
        #expect(reachFrom(answered: false, onHomeSubnet: true) == .offline)
        #expect(reachFrom(answered: false, onHomeSubnet: false) == .offline)
    }

    @Test func theReasonNamesTheGateThatIsClosed() {
        #expect(offlineReason(onHomeSubnet: false, onTailnet: false)
            == "You are away from home and Tailscale isn't connected.")
        // A route exists and still nothing: now it really is the server.
        #expect(offlineReason(onHomeSubnet: true, onTailnet: false) == "Loom isn't answering.")
        #expect(offlineReason(onHomeSubnet: false, onTailnet: true) == "Loom isn't answering.")
    }

    @Test func a24BitPrefixSeparatesOneHomeNetworkFromAnother() {
        let loom = bytes(192, 168, 1, 20)
        #expect(inSameSubnet(server: loom, local: bytes(192, 168, 1, 57), prefixLength: 24))
        #expect(!inSameSubnet(server: loom, local: bytes(192, 168, 4, 57), prefixLength: 24))
        // A friend's LAN that happens to be 192.168.1.x does match here; the
        // probe's body check is what keeps their device from reading as Loom.
        #expect(inSameSubnet(server: loom, local: bytes(192, 168, 1, 99), prefixLength: 24))
    }

    @Test func aPrefixThatIsNotAWholeNumberOfBytesStillMasksCorrectly() {
        let loom = bytes(10, 0, 3, 5)
        #expect(inSameSubnet(server: loom, local: bytes(10, 0, 2, 9), prefixLength: 22))
        #expect(!inSameSubnet(server: loom, local: bytes(10, 0, 4, 9), prefixLength: 22))
    }

    @Test func aTunnelsOwnHostRouteNeverContainsTheServer() {
        // Tailscale hands out a 100.x address as a /32, so nothing shares it.
        #expect(!inSameSubnet(server: bytes(192, 168, 1, 20), local: bytes(100, 84, 12, 3), prefixLength: 32))
    }

    @Test func addressesOfDifferentFamiliesAreNeverOnOneSubnet() {
        #expect(!inSameSubnet(server: bytes(192, 168, 1, 20), local: [UInt8](repeating: 0, count: 16), prefixLength: 24))
    }

    @Test func aNonsensePrefixIsNotAMatch() {
        let loom = bytes(192, 168, 1, 20)
        #expect(!inSameSubnet(server: loom, local: loom, prefixLength: 0))
        #expect(!inSameSubnet(server: loom, local: loom, prefixLength: -1))
        #expect(!inSameSubnet(server: loom, local: loom, prefixLength: 33))
    }

    @Test func theTailnetRangeIsTailscalesOwnAddress() {
        #expect(isTailnetAddress(bytes(100, 73, 96, 93)))
        // The ends of 100.64.0.0/10.
        #expect(isTailnetAddress(bytes(100, 64, 0, 0)))
        #expect(isTailnetAddress(bytes(100, 127, 255, 255)))
        #expect(!isTailnetAddress(bytes(100, 63, 255, 255)))
        #expect(!isTailnetAddress(bytes(100, 128, 0, 0)))
    }

    @Test func theVPNsThatAreNotTailscaleDoNotMatch() {
        // Mullvad takes a utun slot too, but numbers it out of RFC 1918.
        #expect(!isTailnetAddress(bytes(10, 159, 206, 81)))
        // A 100.x first octet alone is not the range - 100.5.x.x is public.
        #expect(!isTailnetAddress(bytes(100, 5, 1, 1)))
        #expect(!isTailnetAddress([UInt8](repeating: 0, count: 16)))
    }

    @Test func aBlockedRequestReadsAsBeingOffline() {
        // What makes the app fall back to downloads rather than show an error.
        #expect(isOfflineError(URLError(.notConnectedToInternet)))
        #expect(isOfflineError(URLError(.timedOut)))
    }

    @Test func anAnswerFromLoomIsNeverOffline() {
        #expect(!isOfflineError(LoomError(statusCode: 404, serverMessage: nil)))
        #expect(!isOfflineError(CancellationError()))
    }

    @Test func aRequestTheAppItselfCancelledIsNeverOffline() {
        // SwiftUI tears a `.task` down whenever its id changes, and URLSession
        // reports that as URLError.cancelled. Counting it as offline latched
        // the offline screen at every launch: the first probe moved reach off
        // `unknown`, cancelling the load already in flight, whose cancellation
        // then stood in as proof that the server was gone.
        #expect(!isOfflineError(URLError(.cancelled)))
    }
}
