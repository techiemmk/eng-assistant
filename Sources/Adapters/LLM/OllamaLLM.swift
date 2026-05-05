import Foundation
import Core

public struct OllamaLLM: LLMProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL

    public init(httpClient: HTTPClient, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    public func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("chat")
        let body: [String: Any] = [
            "model": options.modelName,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "options": [
                "temperature": options.temperature,
                "num_predict": options.maxTokens,
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let byteStream = try await httpClient.postJSONStream(url: url, body: bodyData, headers: [:])

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in byteStream {
                        // Each chunk is typically one JSONL line; defensively split on '\n'.
                        let lines = chunk.split(separator: 0x0A, omittingEmptySubsequences: true)
                        for line in lines {
                            let lineData = Data(line)
                            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                                continue
                            }
                            if let message = obj["message"] as? [String: Any],
                               let content = message["content"] as? String,
                               !content.isEmpty {
                                continuation.yield(content)
                            }
                            if obj["done"] as? Bool == true {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
