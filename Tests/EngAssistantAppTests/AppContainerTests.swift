import Testing
import Foundation
import Core
import Persistence
@testable import EngAssistantApp

@Suite struct AppContainerTests {
    @Test func openInMemoryProducesUsableRepositories() throws {
        let container = try AppContainer.inMemoryForTesting()
        let session = Session(
            id: UUID(), scenarioId: "x",
            startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active,
            summary: nil, personaSnapshot: "p"
        )
        try container.sessionRepository.create(session)
        let fetched = try container.sessionRepository.find(id: session.id)
        #expect(fetched?.id == session.id)
    }

    @Test func scenarioCatalogIsAvailable() throws {
        let container = try AppContainer.inMemoryForTesting()
        #expect(container.scenarioCatalog.allScenarios.count >= 6)
    }
}
