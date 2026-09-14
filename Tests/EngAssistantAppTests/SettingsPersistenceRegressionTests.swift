import Testing
import Foundation
import Core
import Adapters
@testable import EngAssistantApp

/// Regression cover for a reported bug: pressing Save blanked the Settings
/// screen — the model list read "Ollama unreachable", the voice list read
/// "0 voices installed", and the voice selection snapped back to
/// "System default".
///
/// Cause: saving mutates `AppSettingsStore`, which `ContentView` observes, so
/// its body re-evaluated and rebuilt `SettingsViewModel` from scratch. The
/// fresh object had empty lists and default fields, and `SettingsView`'s
/// `.task` doesn't re-fire for a new object at the same view identity, so
/// `load()` never ran again.
///
/// The structural fix is `@StateObject` ownership in the view, which can't be
/// asserted here. What *can* be asserted is the second layer: a newly built
/// view model seeded from the store is never blank, so the symptom cannot
/// return even if something rebuilds it.
@MainActor
@Suite struct SettingsPersistenceRegressionTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    private static let sampleVoices = [
        InstalledVoice(id: "com.apple.voice.premium.en-GB.Serena", name: "Serena",
                       language: "en-GB", quality: .premium),
        InstalledVoice(id: "com.apple.voice.compact.en-GB.Daniel", name: "Daniel",
                       language: "en-GB", quality: .standard),
    ]

    private static func makeViewModel(
        persister: InMemoryPersister,
        store: AppSettingsStore?
    ) -> SettingsViewModel {
        SettingsViewModel(
            persister: persister,
            store: store,
            locator: noLocator,
            healthCheck: HealthCheck(
                probe: { _ in true },
                bodyProbe: { _ in Data(#"{"models":[{"name":"qwen2.5:7b-instruct"}]}"#.utf8) }
            ),
            voiceCatalog: { sampleVoices }
        )
    }

    /// The exact reported sequence: load, choose a voice and a model, save —
    /// then a rebuild happens. The rebuilt screen must still show the choice.
    @Test func savingThenRebuildingKeepsTheChosenVoice() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let first = Self.makeViewModel(persister: persister, store: store)
        try await first.load()
        first.ttsVoiceId = "com.apple.voice.premium.en-GB.Serena"
        first.modelName = "qwen2.5:7b-instruct"
        try await first.save()

        // What ContentView used to do on every body evaluation.
        let rebuilt = Self.makeViewModel(persister: persister, store: store)

        #expect(rebuilt.ttsVoiceId == "com.apple.voice.premium.en-GB.Serena",
                "the voice reverted to System default after save")
        #expect(rebuilt.modelName == "qwen2.5:7b-instruct")
    }

    /// The store is the live copy the rest of the app reads, so it has to carry
    /// the saved voice too — that's what the session actually speaks with.
    @Test func savingPushesTheVoiceIntoTheLiveStore() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let vm = Self.makeViewModel(persister: persister, store: store)
        try await vm.load()
        vm.ttsVoiceId = "com.apple.voice.compact.en-GB.Daniel"
        try await vm.save()

        #expect(store.ttsVoiceId == "com.apple.voice.compact.en-GB.Daniel")
        #expect(store.ttsVoice.id == "com.apple.voice.compact.en-GB.Daniel")
        #expect(persister.store[AppSettingKey.ttsVoiceName.rawValue]
                == "com.apple.voice.compact.en-GB.Daniel")
    }

    /// Every other field has to survive a rebuild too, not just the voice.
    @Test func savingThenRebuildingKeepsEverySetting() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let first = Self.makeViewModel(persister: persister, store: store)
        try await first.load()
        first.defaultMode = .coach
        first.audioRetentionDays = 7
        first.sttExecutablePath = "/opt/homebrew/bin/whisper-cli"
        first.sttModelPath = "/models/ggml-base.en.bin"
        try await first.save()

        let rebuilt = Self.makeViewModel(persister: persister, store: store)
        #expect(rebuilt.defaultMode == .coach)
        #expect(rebuilt.audioRetentionDays == 7)
        #expect(rebuilt.sttExecutablePath == "/opt/homebrew/bin/whisper-cli")
        #expect(rebuilt.sttModelPath == "/models/ggml-base.en.bin")
    }

    /// Changing the theme also mutates the store, so it triggered the same
    /// rebuild — the lists blanked just from switching light to dark.
    @Test func changingTheThemeDoesNotLoseOtherSettings() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let vm = Self.makeViewModel(persister: persister, store: store)
        try await vm.load()
        vm.ttsVoiceId = "com.apple.voice.premium.en-GB.Serena"
        try await vm.save()
        vm.selectAppearance(.dark)

        let rebuilt = Self.makeViewModel(persister: persister, store: store)
        #expect(rebuilt.appearance == .dark)
        #expect(rebuilt.ttsVoiceId == "com.apple.voice.premium.en-GB.Serena")
    }

    /// A saved voice that is no longer installed must stay selected rather than
    /// silently snapping to another entry.
    @Test func anUninstalledSavedVoiceRemainsSelectable() async throws {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.ttsVoiceName.rawValue] = "com.apple.voice.premium.en-AU.Gone"
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let vm = Self.makeViewModel(persister: persister, store: store)
        try await vm.load()

        #expect(vm.ttsVoiceId == "com.apple.voice.premium.en-AU.Gone")
        #expect(vm.selectableVoices.contains { $0.id == "com.apple.voice.premium.en-AU.Gone" })
    }

    /// Without a store there's nothing to seed from, so `load()` remains the
    /// only path — this documents that the seeding is an addition, not a
    /// replacement.
    @Test func aViewModelWithNoStoreStillLoadsFromThePersister() async throws {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.ttsVoiceName.rawValue] = "com.apple.voice.compact.en-GB.Daniel"
        let vm = Self.makeViewModel(persister: persister, store: nil)

        #expect(vm.ttsVoiceId == "")
        try await vm.load()
        #expect(vm.ttsVoiceId == "com.apple.voice.compact.en-GB.Daniel")
    }

    /// And the lists themselves must be populated after a load, which is what
    /// the two error captions in the screenshot were reporting.
    @Test func loadPopulatesBothListsSoNeitherCaptionShows() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister, applyAppearance: { _ in })
        store.reload(autodetect: Self.noLocator)

        let vm = Self.makeViewModel(persister: persister, store: store)
        try await vm.load()

        #expect(!vm.availableModels.isEmpty, "would render 'Ollama unreachable'")
        #expect(!vm.availableVoices.isEmpty, "would render '0 voices installed'")
    }
}
