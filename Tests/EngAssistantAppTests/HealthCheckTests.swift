import Testing
import Foundation
@testable import EngAssistantApp

@Suite struct HealthCheckTests {
    @Test func ollamaReachableTrueWhenProbeReturnsTrue() async {
        let check = HealthCheck(probe: { _ in true })
        let result = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(result == true)
    }

    @Test func ollamaReachableFalseWhenProbeReturnsFalse() async {
        let check = HealthCheck(probe: { _ in false })
        let result = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(result == false)
    }

    @Test func ollamaReachableProbesCorrectURL() async {
        var probedURL: URL?
        let check = HealthCheck(probe: { url in
            probedURL = url
            return true
        })
        _ = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(probedURL?.absoluteString == "http://localhost:11434/api/tags")
    }
}
