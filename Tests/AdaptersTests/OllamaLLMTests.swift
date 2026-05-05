import Testing
import Foundation
import Core
@testable import Adapters

/// Stub HTTPClient that returns scripted byte chunks (each chunk is one
/// JSONL line ending in '\n').
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    var nextChunks: [Data] = []
    var nextError: Error?
    var lastURL: URL?
    var lastBody: Data?

    func postJSONStream(url: URL, body: Data, headers: [String : String]) async throws -> AsyncThrowingStream<Data, Error> {
        lastURL = url
        lastBody = body
        if let err = nextError { throw err }
        let chunks = nextChunks
        return AsyncThrowingStream { continuation in
            for c in chunks { continuation.yield(c) }
            continuation.finish()
        }
    }
}

@Suite struct OllamaLLMTests {
    private static func chunk(_ s: String) -> Data {
        Data((s + "\n").utf8)
    }

    @Test func streamsContentFromJSONLChunks() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [
            Self.chunk(#"{"message":{"role":"assistant","content":"Hello, "},"done":false}"#),
            Self.chunk(#"{"message":{"role":"assistant","content":"world!"},"done":false}"#),
            Self.chunk(#"{"message":{"role":"assistant","content":""},"done":true}"#),
        ]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        let stream = try await llm.respond(
            messages: [ChatMessage(role: .user, content: "hi")],
            options: LLMOptions(modelName: "qwen2.5:7b-instruct")
        )
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        #expect(collected == "Hello, world!")
    }

    @Test func sendsCorrectURLAndBodyShape() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [Self.chunk(#"{"message":{"content":""},"done":true}"#)]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        _ = try await llm.respond(
            messages: [
                ChatMessage(role: .system, content: "be brief"),
                ChatMessage(role: .user, content: "hi"),
            ],
            options: LLMOptions(modelName: "test-model", temperature: 0.5, maxTokens: 100)
        )
        #expect(client.lastURL?.absoluteString == "http://localhost:11434/api/chat")
        let body = try #require(client.lastBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["model"] as? String == "test-model")
        #expect(obj["stream"] as? Bool == true)
        let messages = try #require(obj["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["role"] as? String == "user")
    }

    @Test func ignoresMalformedJsonLines() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [
            Self.chunk(#"{"message":{"content":"OK "},"done":false}"#),
            Self.chunk("not-json\n"),
            Self.chunk(#"{"message":{"content":"continues."},"done":true}"#),
        ]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        let stream = try await llm.respond(
            messages: [ChatMessage(role: .user, content: "x")],
            options: LLMOptions(modelName: "m")
        )
        var collected = ""
        for try await c in stream { collected += c }
        #expect(collected == "OK continues.")
    }

    @Test func propagatesHTTPErrors() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.statusCode(503)
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        await #expect(throws: HTTPClientError.self) {
            _ = try await llm.respond(
                messages: [ChatMessage(role: .user, content: "x")],
                options: LLMOptions(modelName: "m")
            )
        }
    }
}
