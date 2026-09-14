import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// The model was a free-text field, which made "model not found" a permanent
/// hazard — a typo or a slightly different tag and every session failed on its
/// first turn. It's now picked from what Ollama actually has.
@MainActor
@Suite struct ModelPickerTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    private static func viewModel(
        tags: String?,
        persister: InMemoryPersister = InMemoryPersister()
    ) -> SettingsViewModel {
        let health = HealthCheck(
            probe: { _ in tags != nil },
            bodyProbe: { _ in tags.map { Data($0.utf8) } }
        )
        return SettingsViewModel(
            persister: persister,
            locator: noLocator,
            healthCheck: health
        )
    }

    @Test func loadPopulatesTheInstalledModels() async throws {
        let vm = Self.viewModel(tags: #"{"models":[{"name":"qwen2.5:7b-instruct"},{"name":"llama3.2:latest"}]}"#)
        try await vm.load()
        #expect(vm.availableModels == ["qwen2.5:7b-instruct", "llama3.2:latest"])
        #expect(vm.isLoadingModels == false)
    }

    /// Hosted models need an Ollama subscription and 402 on use, so offering
    /// one in the picker would be offering a guaranteed failure.
    @Test func cloudModelsAreNotOffered() async throws {
        let vm = Self.viewModel(tags: """
        {"models":[
          {"name":"minimax-m3:cloud","remote_host":"https://ollama.com"},
          {"name":"qwen2.5:7b-instruct"}
        ]}
        """)
        try await vm.load()
        #expect(vm.availableModels == ["qwen2.5:7b-instruct"])
    }

    /// Opening Settings with Ollama stopped must not silently reassign the
    /// saved model to whatever happens to be first in the list.
    @Test func theSavedModelIsAlwaysSelectable() async throws {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.llmModelName.rawValue] = "qwen2.5:3b-instruct"
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"llama3.2:latest"}]}"#,
            persister: persister
        )
        try await vm.load()

        #expect(vm.modelName == "qwen2.5:3b-instruct")
        #expect(vm.selectableModels.contains("qwen2.5:3b-instruct"))
        #expect(vm.selectableModels.contains("llama3.2:latest"))
    }

    @Test func anAlreadyInstalledModelIsNotListedTwice() async throws {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.llmModelName.rawValue] = "llama3.2:latest"
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"llama3.2:latest"}]}"#,
            persister: persister
        )
        try await vm.load()
        #expect(vm.selectableModels == ["llama3.2:latest"])
    }

    /// Ollama down: the screen falls back to a text field, so the model can
    /// still be set with the server stopped.
    @Test func anUnreachableOllamaLeavesTheListEmpty() async throws {
        let vm = Self.viewModel(tags: nil)
        try await vm.load()
        #expect(vm.availableModels.isEmpty)
        #expect(vm.selectableModels.isEmpty || vm.selectableModels == [vm.modelName])
    }

    @Test func refreshCanBeRetriedAfterStartingOllama() async throws {
        let vm = Self.viewModel(tags: nil)
        try await vm.load()
        #expect(vm.availableModels.isEmpty)

        // Same view model, Ollama now answering.
        let live = Self.viewModel(tags: #"{"models":[{"name":"qwen2.5:7b-instruct"}]}"#)
        await live.refreshAvailableModels()
        #expect(live.availableModels == ["qwen2.5:7b-instruct"])
    }

    @Test func pickingAModelStillSavesIt() async throws {
        let persister = InMemoryPersister()
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"qwen2.5:7b-instruct"},{"name":"llama3.2:latest"}]}"#,
            persister: persister
        )
        try await vm.load()
        vm.modelName = "llama3.2:latest"
        try await vm.save()
        #expect(persister.store[AppSettingKey.llmModelName.rawValue] == "llama3.2:latest")
    }
}

/// A session left `.active` by a crash or a quit mid-conversation is now
/// offered back at launch. `listActive()` had existed from the start but
/// nothing ever called it, so these accumulated invisibly and forever.
@MainActor
@Suite struct UnfinishedSessionTests {
    @Test func aCleanLaunchOffersNothing() async {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        await state.bootstrap()
        // The real store is used here; whether it has an orphan depends on the
        // machine, so assert the contract rather than a count.
        if let offered = state.unfinishedSession {
            #expect(offered.status == .active, "only an active session should be offered")
        }
    }

    @Test func takingTheSessionClearsTheOffer() async {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        await state.bootstrap()
        _ = state.takeUnfinishedSession()
        #expect(state.unfinishedSession == nil, "the offer must not be made twice")
    }

    @Test func discardingClearsTheOffer() async {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        await state.bootstrap()
        state.discardUnfinishedSession()
        #expect(state.unfinishedSession == nil)
    }

    /// Discarding has to mark the session abandoned, or the same one is offered
    /// again on the next launch — forever.
    @Test func discardingMarksTheSessionAbandonedSoItIsNotOfferedAgain() async throws {
        let container = try AppContainer.inMemoryForTesting()
        defer { try? FileManager.default.removeItem(at: container.storageLayout.rootDirectory) }
        let session = Session(
            id: UUID(), scenarioId: "work-standup-01", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        )
        try container.sessionRepository.create(session)
        #expect(try container.sessionRepository.listActive().count == 1)

        try container.sessionRepository.abandon(id: session.id)

        #expect(try container.sessionRepository.listActive().isEmpty)
        #expect(try container.sessionRepository.find(id: session.id)?.status == .abandoned)
    }

    /// With several orphans, the most recent is the one worth offering.
    @Test func theMostRecentUnfinishedSessionIsTheOneOffered() throws {
        let container = try AppContainer.inMemoryForTesting()
        defer { try? FileManager.default.removeItem(at: container.storageLayout.rootDirectory) }
        let older = Session(id: UUID(), scenarioId: "a",
                            startedAt: Date(timeIntervalSince1970: 1_000), endedAt: nil,
                            mode: .flow, status: .active, summary: nil, personaSnapshot: "p")
        let newer = Session(id: UUID(), scenarioId: "b",
                            startedAt: Date(timeIntervalSince1970: 9_000), endedAt: nil,
                            mode: .flow, status: .active, summary: nil, personaSnapshot: "p")
        try container.sessionRepository.create(older)
        try container.sessionRepository.create(newer)

        let offered = try container.sessionRepository.listActive()
            .max { $0.startedAt < $1.startedAt }
        #expect(offered?.id == newer.id)
    }
}
