import Foundation
import Core

public actor FakeLLMProvider: LLMProvider {
    private var scripted: [[String]]    // each call uses one inner array of token chunks
    public private(set) var receivedMessages: [ChatMessage] = []

    /// `scriptedReplies` is one full reply (split into token chunks) for the
    /// next `respond` call. Pass an array of arrays for multi-call scripts.
    public init(scriptedReplies: [String]) {
        self.scripted = [scriptedReplies]
    }

    public init(scriptedReplyBatches: [[String]]) {
        self.scripted = scriptedReplyBatches
    }

    public func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
        receivedMessages = messages
        guard !scripted.isEmpty else {
            throw FakeLLMProviderError.scriptExhausted
        }
        let chunks = scripted.removeFirst()
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

public enum FakeLLMProviderError: Error, Equatable {
    case scriptExhausted
}
