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

    @Test func explicitSchemeIsKept() {
        #expect(AppEnvironment.normalize("https://loom.example")?.absoluteString == "https://loom.example:8097")
    }

    @Test func whitespaceIsTrimmed() {
        #expect(AppEnvironment.normalize("  loom.local \n")?.absoluteString == "http://loom.local:8097")
    }

    @Test func emptyAddressYieldsNil() {
        #expect(AppEnvironment.normalize("") == nil)
        #expect(AppEnvironment.normalize("   ") == nil)
    }
}
