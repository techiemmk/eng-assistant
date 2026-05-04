import Testing
@testable import Core

@Suite struct ChatHistoryTests {
    @Test func startsWithSystemMessageOnly() {
        let history = ChatHistory(systemPrompt: "system", maxCharacterBudget: 1000)
        let msgs = history.messages()
        #expect(msgs.count == 1)
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content == "system")
    }

    @Test func appendsUserAndAssistantTurns() {
        var history = ChatHistory(systemPrompt: "s", maxCharacterBudget: 1000)
        history.append(role: .user, content: "u1")
        history.append(role: .assistant, content: "a1")
        let msgs = history.messages()
        #expect(msgs.map(\.role) == [.system, .user, .assistant])
        #expect(msgs.map(\.content) == ["s", "u1", "a1"])
    }

    @Test func dropsOldestUserAssistantPairWhenOverBudget() {
        // Each message is 101 chars (100 'x' + 1 digit). 6 messages = 606. Budget 450.
        // Drop one pair (202 chars) → 404, which is ≤ 450, loop stops.
        var history = ChatHistory(systemPrompt: "system", maxCharacterBudget: 450)
        let big = String(repeating: "x", count: 100)
        history.append(role: .user, content: big + "1")
        history.append(role: .assistant, content: big + "1")
        history.append(role: .user, content: big + "2")
        history.append(role: .assistant, content: big + "2")
        history.append(role: .user, content: big + "3")
        history.append(role: .assistant, content: big + "3")
        let msgs = history.messages()
        #expect(msgs.count == 5)
        #expect(msgs[1].content.hasSuffix("2"))
        #expect(msgs[2].content.hasSuffix("2"))
        #expect(msgs[3].content.hasSuffix("3"))
        #expect(msgs[4].content.hasSuffix("3"))
    }

    @Test func neverDropsTheSystemMessage() {
        var history = ChatHistory(systemPrompt: String(repeating: "S", count: 500), maxCharacterBudget: 100)
        history.append(role: .user, content: "u")
        history.append(role: .assistant, content: "a")
        let msgs = history.messages()
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content.count == 500)
    }

    @Test func handlesUnpairedTrailingUserMessage() {
        var history = ChatHistory(systemPrompt: "s", maxCharacterBudget: 50)
        let big = String(repeating: "x", count: 30)
        history.append(role: .user, content: "u1" + big)
        history.append(role: .assistant, content: "a1" + big)
        history.append(role: .user, content: "u2" + big)
        let msgs = history.messages()
        #expect(msgs.count == 2)
        #expect(msgs[0].role == .system)
        #expect(msgs[1].content.hasPrefix("u2"))
    }
}
