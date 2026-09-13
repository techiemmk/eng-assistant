import Foundation
import Core

@MainActor
public final class PracticeViewModel: ObservableObject {
    /// What the chip row above the scenario grid selects. Domains alone stopped
    /// being enough once the work domain held both office and clinical
    /// scenarios, so a collection can also be a tag.
    public enum Collection: Hashable, Identifiable {
        case all
        case domain(ScenarioDomain)
        case tag(String)

        public var id: String {
            switch self {
            case .all: return "all"
            case .domain(let domain): return "domain:\(domain.rawValue)"
            case .tag(let tag): return "tag:\(tag)"
            }
        }

        public var label: String {
            switch self {
            case .all: return "All"
            case .domain(let domain): return domain.rawValue.capitalized
            case .tag(let tag): return tag.capitalized
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

    /// The chips to offer: every domain, plus a chip for each tag that marks a
    /// distinct practice track. Only tracks actually present in the catalog
    /// appear, so removing the medical scenarios removes the chip with them.
    public var collections: [Collection] {
        var result: [Collection] = [.all]
        result += ScenarioDomain.allCases
            .filter { domain in scenarios.contains { $0.domain == domain } }
            .map(Collection.domain)
        result += Self.trackTags
            .filter { tag in scenarios.contains { $0.tags.contains(tag) } }
            .map(Collection.tag)
        return result
    }

    /// Tags that represent a whole practice track rather than a loose label.
    /// Kept disjoint on purpose — a scenario carries one track tag, so the
    /// chips partition the catalog rather than overlapping.
    public static let trackTags = ["medical", "homeopathy"]

    public var filteredScenarios: [Scenario] {
        switch collection {
        case .all:
            return scenarios
        case .domain(let domain):
            return scenarios.filter { $0.domain == domain }
        case .tag(let tag):
            return scenarios.filter { $0.tags.contains(tag) }
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
