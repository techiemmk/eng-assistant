import Foundation

public struct ScenarioCatalog: Sendable {
    public let allScenarios: [Scenario]

    public init(allScenarios: [Scenario]) {
        self.allScenarios = allScenarios
    }

    public static func loadBuiltIn() throws -> ScenarioCatalog {
        guard let url = Bundle.module.url(forResource: "built-in-scenarios", withExtension: "json") else {
            throw ScenarioCatalogError.bundledResourceMissing("built-in-scenarios.json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([Scenario].self, from: data)
        return ScenarioCatalog(allScenarios: decoded)
    }

    public func scenarios(in domain: ScenarioDomain) -> [Scenario] {
        allScenarios.filter { $0.domain == domain }
    }

    public func scenarios(withTag tag: String) -> [Scenario] {
        allScenarios.filter { $0.tags.contains(tag) }
    }

    public func scenario(id: String) -> Scenario? {
        allScenarios.first { $0.id == id }
    }
}

public enum ScenarioCatalogError: Error, Equatable {
    case bundledResourceMissing(String)
}
