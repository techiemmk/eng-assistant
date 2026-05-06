import Testing
import Foundation
import Adapters
@testable import EngAssistantApp

@Suite struct HealthCheckTests {
    final class StubHTTPClient: HTTPClient, @unchecked Sendable {
        var nextResponse: Data?
        var nextError: Error?
        func postJSONStream(url: URL, body: Data, headers: [String : String]) async throws -> AsyncThrowingStream<Data, Error> {
            if let err = nextError { throw err }
            return AsyncThrowingStream { continuation in
                if let r = nextResponse { continuation.yield(r) }
                continuation.finish()
            }
        }
    }

    @Test func ollamaReachableSucceedsOnAnyResponse() async throws {
        let client = StubHTTPClient()
        client.nextResponse = Data("{}".utf8)
        let check = HealthCheck(httpClient: client)
        let result = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(result == true)
    }

    @Test func ollamaUnreachableReturnsFalseOnError() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.transport("connection refused")
        let check = HealthCheck(httpClient: client)
        let result = await check.ollamaReachable(baseURL: URL(string: "http://localhost:11434")!)
        #expect(result == false)
    }
}
