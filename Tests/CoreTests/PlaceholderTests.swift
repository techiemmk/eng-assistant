import Testing
@testable import Core

@Suite struct PlaceholderTests {
    @Test func versionPresent() {
        #expect(!CoreModule.version.isEmpty)
    }
}
