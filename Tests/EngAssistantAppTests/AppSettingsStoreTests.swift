import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// `llm_model_name` was written by the Settings screen and never read back, so
/// every session used the hardcoded default. These cover the read path.
@MainActor
@Suite struct AppSettingsStoreTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    /// A locator that finds nothing, so auto-detection can't mask what the
    /// persister returned.
    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    @Test func reloadReadsThePersistedModelName() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.llmModelName.rawValue] = "llama3.2:latest"
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.modelName == "llama3.2:latest")
    }

    @Test func reloadFallsBackToDefaultsForUnsetKeys() {
        let store = AppSettingsStore(persister: InMemoryPersister())
        store.reload(autodetect: Self.noLocator)
        #expect(store.modelName == AppDefaults.llmModelName)
        #expect(store.defaultMode == AppDefaults.defaultMode)
        #expect(store.audioRetentionDays == AppDefaults.audioRetentionDays)
        #expect(store.isSTTConfigured == false)
    }

    @Test func reloadIgnoresEmptyAndInvalidValues() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.llmModelName.rawValue] = ""
        persister.store[AppSettingKey.audioRetentionDays.rawValue] = "0"
        persister.store[AppSettingKey.defaultMode.rawValue] = "nonsense"
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.modelName == AppDefaults.llmModelName)
        #expect(store.audioRetentionDays == AppDefaults.audioRetentionDays)
        #expect(store.defaultMode == AppDefaults.defaultMode)
    }

    @Test func reloadReadsBothSTTPaths() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.sttExecutablePath.rawValue] = "/opt/homebrew/bin/whisper-cli"
        persister.store[AppSettingKey.sttModelPath.rawValue] = "/models/ggml-base.en.bin"
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.isSTTConfigured)
        #expect(store.sttExecutablePath == "/opt/homebrew/bin/whisper-cli")
    }

    /// One path alone isn't enough to build the Whisper adapter.
    @Test func oneSTTPathIsNotConfigured() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.sttExecutablePath.rawValue] = "/opt/homebrew/bin/whisper-cli"
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.isSTTConfigured == false)
    }

    @Test func saveFromSettingsScreenUpdatesTheLiveStore() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.modelName == AppDefaults.llmModelName)

        let settingsVM = SettingsViewModel(persister: persister, store: store, locator: Self.noLocator)
        settingsVM.modelName = "llama3.2:latest"
        settingsVM.defaultMode = .coach
        try await settingsVM.save()

        // No relaunch needed — the next session picks the new model up.
        #expect(store.modelName == "llama3.2:latest")
        #expect(store.defaultMode == .coach)
        #expect(persister.store[AppSettingKey.llmModelName.rawValue] == "llama3.2:latest")
    }

    @Test func applyingAnEmptyModelNameKeepsTheDefault() {
        let store = AppSettingsStore(persister: InMemoryPersister())
        store.apply(
            modelName: "",
            defaultMode: .flow,
            audioRetentionDays: 30,
            sttExecutablePath: "",
            sttModelPath: ""
        )
        #expect(store.modelName == AppDefaults.llmModelName)
    }

    @Test func settingsScreenPersistsSTTPaths() async throws {
        let persister = InMemoryPersister()
        let vm = SettingsViewModel(persister: persister, locator: Self.noLocator)
        vm.sttExecutablePath = "/opt/homebrew/bin/whisper-cli"
        vm.sttModelPath = "/models/ggml-base.en.bin"
        try await vm.save()
        #expect(persister.store[AppSettingKey.sttExecutablePath.rawValue] == "/opt/homebrew/bin/whisper-cli")
        #expect(persister.store[AppSettingKey.sttModelPath.rawValue] == "/models/ggml-base.en.bin")
    }
}

@Suite struct STTLocatorTests {
    @Test func findsTheFirstExecutableCandidateThatExists() {
        // /bin/sh stands in for a whisper binary: it's executable everywhere.
        let locator = STTLocator(executableCandidates: ["/nonexistent/whisper-cli", "/bin/sh"])
        #expect(locator.findExecutable() == "/bin/sh")
    }

    @Test func findsNothingWhenNoCandidateExists() {
        let locator = STTLocator(executableCandidates: ["/nonexistent/whisper-cli"])
        #expect(locator.findExecutable() == nil)
    }

    @Test func picksTheLargestModelFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stt-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(repeating: 0, count: 100).write(to: dir.appendingPathComponent("ggml-tiny.en.bin"))
        try Data(repeating: 0, count: 5_000).write(to: dir.appendingPathComponent("ggml-base.en.bin"))
        try Data(repeating: 0, count: 9_000).write(to: dir.appendingPathComponent("notes.txt"))

        let locator = STTLocator(modelsDirectory: dir, executableCandidates: [])
        #expect(locator.findModel()?.hasSuffix("ggml-base.en.bin") == true)
    }

    @Test func findsNoModelInAMissingDirectory() {
        let locator = STTLocator(
            modelsDirectory: URL(fileURLWithPath: "/nonexistent-models-dir"),
            executableCandidates: []
        )
        #expect(locator.findModel() == nil)
    }
}
