import Testing
@testable import Takeup

@MainActor
struct AppEnvironmentTests {
    @Test func bareHostGainsSchemeAndPort() {
        #expect(AppEnvironment.normalize("192.168.1.10")?.absoluteString == "http://192.168.1.10:8097")
    }

    @Test func explicitPortIsKept() {
        #expect(AppEnvironment.normalize("192.168.1.10:9000")?.absoluteString == "http://192.168.1.10:9000")
    }

    @Test func httpsIsLeftWhole() {
        // A ts.net-style name serves on 443; appending Loom's LAN port breaks it.
        #expect(AppEnvironment.normalize("https://loom.example")?.absoluteString == "https://loom.example")
        #expect(AppEnvironment.normalize("https://loom.example:8443")?.absoluteString == "https://loom.example:8443")
    }

    @Test func httpWithoutAPortGetsLoomsDefault() {
        #expect(AppEnvironment.normalize("http://loom.local")?.absoluteString == "http://loom.local:8097")
    }

    @Test func whitespaceIsTrimmed() {
        #expect(AppEnvironment.normalize("  loom.local \n")?.absoluteString == "http://loom.local:8097")
    }

    @Test func emptyAddressYieldsNil() {
        #expect(AppEnvironment.normalize("") == nil)
        #expect(AppEnvironment.normalize("   ") == nil)
    }
}
