import Testing
import Foundation
import Core
@testable import EngAssistantApp

@MainActor
@Suite struct SettingsViewModelTests {
    final class InMemorySettingsPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    @Test func loadHydratesFromPersister() async throws {
        let persister = InMemorySettingsPersister()
        persister.store[AppSettingKey.llmModelName.rawValue] = "qwen2.5:14b"
        persister.store[AppSettingKey.defaultMode.rawValue] = "coach"
        persister.store[AppSettingKey.audioRetentionDays.rawValue] = "14"
        let vm = SettingsViewModel(persister: persister)
        try await vm.load()
        #expect(vm.modelName == "qwen2.5:14b")
        #expect(vm.defaultMode == .coach)
        #expect(vm.audioRetentionDays == 14)
    }

    @Test func saveWritesAllFieldsToPersister() async throws {
        let persister = InMemorySettingsPersister()
        let vm = SettingsViewModel(persister: persister)
        vm.modelName = "test-model"
        vm.defaultMode = .coach
        vm.audioRetentionDays = 7
        try await vm.save()
        #expect(persister.store[AppSettingKey.llmModelName.rawValue] == "test-model")
        #expect(persister.store[AppSettingKey.defaultMode.rawValue] == "coach")
        #expect(persister.store[AppSettingKey.audioRetentionDays.rawValue] == "7")
    }

    @Test func loadAppliesDefaultsForMissingKeys() async throws {
        let persister = InMemorySettingsPersister()
        let vm = SettingsViewModel(persister: persister)
        try await vm.load()
        #expect(!vm.modelName.isEmpty)
        #expect(vm.audioRetentionDays > 0)
    }
}
