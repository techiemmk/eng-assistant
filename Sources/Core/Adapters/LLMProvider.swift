import Foundation

public struct LLMOptions: Equatable, Sendable {
    public var modelName: String
    public var temperature: Double
    public var maxTokens: Int

    public init(modelName: String, temperature: Double = 0.7, maxTokens: Int = 512) {
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public protocol LLMProvider: Sendable {
    /// Streams reply tokens. The stream yields chunks of text; the caller
    /// concatenates them. The stream finishes (without throwing) when the
    /// reply is complete.
    func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error>
}
