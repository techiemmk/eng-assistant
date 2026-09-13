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
        let byteStream: AsyncThrowingStream<Data, Error>
        do {
            byteStream = try await httpClient.postJSONStream(url: url, body: bodyData, headers: [:])
        } catch {
            throw Self.mapError(error, model: options.modelName)
        }

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

extension OllamaLLM {
    /// Turns Ollama's bare HTTP statuses into errors that name the cause and the
    /// fix. Ollama answers `/api/chat` with 404 when the requested model isn't
    /// installed and 402 for a cloud model the account can't use — both are
    /// setup problems, not transport failures, and "statusCode(404)" tells the
    /// user nothing. Anything else propagates unchanged.
    static func mapError(_ error: Error, model: String) -> Error {
        guard case HTTPClientError.statusCode(let code) = error else { return error }
        switch code {
        case 404: return OllamaLLMError.modelNotInstalled(model: model)
        case 402: return OllamaLLMError.modelRequiresSubscription(model: model)
        default: return error
        }
    }
}

public enum OllamaLLMError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled(model: String)
    case modelRequiresSubscription(model: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let model):
            return "Ollama doesn't have the model '\(model)'. Install it with `ollama pull \(model)`, "
                + "or point Settings at a model you already have (`ollama list`)."
        case .modelRequiresSubscription(let model):
            return "'\(model)' is a hosted Ollama model and this account has no credits for it. "
                + "Pick a local model in Settings — e.g. `ollama pull qwen2.5:7b-instruct`."
        }
    }
}
