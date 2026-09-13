import Foundation
import Core

@MainActor
public final class SessionsHistoryViewModel: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String? = nil

    private let persister: SessionPersisting
    private let catalog: ScenarioCatalog?
    private let limit: Int

    public init(persister: SessionPersisting, catalog: ScenarioCatalog? = nil, limit: Int = 50) {
        self.persister = persister
        self.catalog = catalog
        self.limit = limit
    }

    /// The scenario's real title, so a row reads "Daily Engineering Standup"
    /// rather than "work-standup-01". Falls back to the raw id for a scenario
    /// that has since been removed from the catalog.
    public func title(for session: Session) -> String {
        catalog?.scenario(id: session.scenarioId)?.title ?? session.scenarioId
    }

    /// Whether the scenario still exists — a session whose scenario is gone
    /// can't be continued, because there'd be no persona to resume into.
    public func canContinue(_ session: Session) -> Bool {
        guard let catalog else { return true }
        return catalog.scenario(id: session.scenarioId) != nil
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
