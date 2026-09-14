import Foundation
import Core

@MainActor
public final class PracticeViewModel: ObservableObject {
    /// What the chip row above the scenario grid selects: everything, or one
    /// practice domain.
    ///
    /// This briefly also carried a `tag` case, back when the single broad
    /// `work` domain had to be sliced up by tag to be navigable. Splitting
    /// `work` into `corporate` / `medical` / `homeopathy` made that
    /// unnecessary — domains partition the catalog on their own now.
    public enum Collection: Hashable, Identifiable {
        case all
        case domain(ScenarioDomain)

        public var id: String {
            switch self {
            case .all: return "all"
            case .domain(let domain): return "domain:\(domain.rawValue)"
            }
        }

        public var label: String {
            switch self {
            case .all: return "All"
            case .domain(let domain): return domain.label
            }
        }
    }

    public let scenarios: [Scenario]

    @Published public var mode: SessionMode
    @Published public var collection: Collection = .all
    @Published public var selectedScenarioId: String? = nil

    public init(catalog: ScenarioCatalog, mode: SessionMode = AppDefaults.defaultMode) {
        self.scenarios = catalog.allScenarios
        self.mode = mode
    }

    /// Kept so existing callers and tests can still think in domains.
    public var domainFilter: ScenarioDomain? {
        get {
            if case .domain(let domain) = collection { return domain }
            return nil
        }
        set {
            collection = newValue.map(Collection.domain) ?? .all
        }
    }

    /// The chips to offer, in `ScenarioDomain.displayOrder`. A domain with no
    /// scenarios is skipped rather than shown empty, so deleting a whole
    /// practice area removes its chip with it.
    public var collections: [Collection] {
        [.all] + ScenarioDomain.displayOrder
            .filter { domain in scenarios.contains { $0.domain == domain } }
            .map(Collection.domain)
    }

    public var filteredScenarios: [Scenario] {
        switch collection {
        case .all:
            return scenarios
        case .domain(let domain):
            return scenarios.filter { $0.domain == domain }
        }
    }

    public var selectedScenario: Scenario? {
        guard let id = selectedScenarioId else { return nil }
        return scenarios.first { $0.id == id }
    }

    /// Clears a selection that the current filter no longer shows, so the Start
    /// button can't fire on a scenario that's scrolled out of existence.
    public func pruneSelectionIfHidden() {
        guard let id = selectedScenarioId else { return }
        if !filteredScenarios.contains(where: { $0.id == id }) {
            selectedScenarioId = nil
        }
    }
}
