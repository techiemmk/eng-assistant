import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct GrammarJudgeTests {
    @Test func parsesValidJsonResponse() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 2}"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "I are happy and goes home")
        #expect(count == 2)
    }

    @Test func toleratesExtraWhitespaceAndQuotes() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["  { \"grammarIssueCount\" : 5 }  \n"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 5)
    }

    @Test func returnsZeroOnMalformedJson() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["I think there are about 3 errors."])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 0)
    }

    @Test func returnsZeroOnNegativeOrAbsurdValue() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": -3}"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 0)
    }
}
