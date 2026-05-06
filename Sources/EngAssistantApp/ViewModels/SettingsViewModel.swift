import Foundation
import Core

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var modelName: String = "qwen2.5:7b-instruct"
    @Published public var defaultMode: SessionMode = .flow
    @Published public var audioRetentionDays: Int = 30

    @Published public private(set) var savedNotice: String? = nil
    @Published public private(set) var lastError: String? = nil

    private let persister: SettingsPersisting

    public init(persister: SettingsPersisting) {
        self.persister = persister
    }

    public func load() async throws {
        do {
            if let v = try persister.get(.llmModelName), !v.isEmpty {
                modelName = v
            }
            if let v = try persister.get(.defaultMode), let m = SessionMode(rawValue: v) {
                defaultMode = m
            }
            if let v = try persister.get(.audioRetentionDays), let d = Int(v), d > 0 {
                audioRetentionDays = d
            }
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
            throw error
        }
    }

    public func save() async throws {
        do {
            try persister.set(.llmModelName, value: modelName)
            try persister.set(.defaultMode, value: defaultMode.rawValue)
            try persister.set(.audioRetentionDays, value: String(audioRetentionDays))
            savedNotice = "Saved."
            lastError = nil
        } catch {
            lastError = "Save failed: \(error)"
            throw error
        }
    }
}
