import Foundation
import Core

@MainActor
public final class SessionsHistoryViewModel: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String? = nil

    private let persister: SessionPersisting
    private let limit: Int

    public init(persister: SessionPersisting, limit: Int = 50) {
        self.persister = persister
        self.limit = limit
    }

    public func load() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try persister.listRecent(limit: limit)
            lastError = nil
        } catch {
            lastError = "Could not load history: \(error)"
            throw error
        }
    }
}
