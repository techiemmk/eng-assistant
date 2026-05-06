import Testing
@testable import EngAssistantApp

@Suite struct AppPlaceholderTests {
    @Test func appCompiles() {
        // The presence of `EngAssistantApp` (the App struct) is asserted by the test
        // target depending on the executable target — if compilation fails the test
        // suite won't link. This is a smoke test for the build wiring.
        _ = EngAssistantApp.self
    }
}
