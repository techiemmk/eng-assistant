import Foundation

public protocol SettingsPersisting: Sendable {
    func get(_ key: AppSettingKey) throws -> String?
    func set(_ key: AppSettingKey, value: String) throws
}
