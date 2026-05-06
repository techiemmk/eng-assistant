import Foundation
import Core

@MainActor
public final class PracticeViewModel: ObservableObject {
    public let scenarios: [Scenario]

    @Published public var mode: SessionMode = .flow
    @Published public var domainFilter: ScenarioDomain? = nil
    @Published public var selectedScenarioId: String? = nil

    public init(catalog: ScenarioCatalog) {
        self.scenarios = catalog.allScenarios
    }

    public var filteredScenarios: [Scenario] {
        guard let filter = domainFilter else { return scenarios }
        return scenarios.filter { $0.domain == filter }
    }

    public var selectedScenario: Scenario? {
        guard let id = selectedScenarioId else { return nil }
        return scenarios.first { $0.id == id }
    }
}
