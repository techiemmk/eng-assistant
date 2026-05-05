import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct WeakSpotExtractorTests {
    @Test func parsesValidJsonArray() async throws {
        let json = """
            {"patterns":[
                {"pattern":"uses 'more better' instead of 'better'","category":"grammar"},
                {"pattern":"stutters on conditionals","category":"fluency"}
            ]}
            """
        let llm = FakeLLMProvider(scriptedReplies: [json])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "Some text.")
        #expect(result.count == 2)
        #expect(result[0].pattern == "uses 'more better' instead of 'better'")
        #expect(result[0].category == .grammar)
        #expect(result[1].category == .fluency)
    }

    @Test func emptyTranscriptReturnsEmpty() async throws {
        let llm = FakeLLMProvider(scriptedReplies: [""])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "")
        #expect(result.isEmpty)
    }

    @Test func malformedJsonReturnsEmptyAndDoesNotThrow() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["I see issues with conditionals and tense."])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "anything")
        #expect(result.isEmpty)
    }

    @Test func unknownCategoryFallsBackToGrammar() async throws {
        let json = """
            {"patterns":[{"pattern":"x","category":"weird-unknown"}]}
            """
        let llm = FakeLLMProvider(scriptedReplies: [json])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "anything")
        #expect(result.count == 1)
        #expect(result[0].category == .grammar)
    }
}
