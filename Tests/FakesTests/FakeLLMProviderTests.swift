import Testing
import Foundation
import Core
@testable import Fakes

@Suite struct FakeLLMProviderTests {
    @Test func emitsScriptedTokensInOrder() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["Hello, ", "how can I ", "help today?"])
        var collected = ""
        let stream = try await fake.respond(
            messages: [ChatMessage(role: .user, content: "hi")],
            options: LLMOptions(modelName: "fake")
        )
        for try await chunk in stream {
            collected += chunk
        }
        #expect(collected == "Hello, how can I help today?")
    }

    @Test func recordsReceivedMessages() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["ok"])
        let messages = [
            ChatMessage(role: .system, content: "be brief"),
            ChatMessage(role: .user, content: "hi"),
        ]
        _ = try await fake.respond(messages: messages, options: LLMOptions(modelName: "fake"))
        let received = await fake.receivedMessages
        #expect(received == messages)
    }

    @Test func throwsAfterScriptedRepliesExhausted() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["one"])
        _ = try await fake.respond(messages: [], options: LLMOptions(modelName: "fake"))
        await #expect(throws: FakeLLMProviderError.self) {
            _ = try await fake.respond(messages: [], options: LLMOptions(modelName: "fake"))
        }
    }
}
