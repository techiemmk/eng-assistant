import Foundation

public enum ChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}
