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

    /// Records what the probe was handed. A captured `var` would be mutated
    /// from inside a `@Sendable` closure, which the compiler can't prove safe —
    /// same recorder pattern as `AppearanceRecorder` in the appearance tests.
    final class URLRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func record(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            urls.append(url)
        }

        var last: URL? {
            lock.lock()
            defer { lock.unlock() }
            return urls.last
        }
    }

    @Test func ollamaReachableProbesCorrectURL() async {
        let recorder = URLRecorder()
        let check = HealthCheck(probe: { url in
            recorder.record(url)
            return true
        })
        _ = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(recorder.last?.absoluteString == "http://localhost:11434/api/tags")
    }
}
