import Testing
import Foundation
import Core
@testable import EngAssistantApp

@MainActor
@Suite struct PracticeViewModelTests {
    @Test func loadsAllScenariosFromCatalog() async throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let vm = PracticeViewModel(catalog: catalog)
        #expect(vm.scenarios.count == catalog.allScenarios.count)
    }

    @Test func defaultModeIsFlow() async throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let vm = PracticeViewModel(catalog: catalog)
        #expect(vm.mode == .flow)
    }

    @Test func togglingModeUpdatesStoredValue() async throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let vm = PracticeViewModel(catalog: catalog)
        vm.mode = .coach
        #expect(vm.mode == .coach)
    }

    @Test func filteringByDomainNarrowsResults() async throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let vm = PracticeViewModel(catalog: catalog)
        vm.domainFilter = .work
        #expect(vm.filteredScenarios.allSatisfy { $0.domain == .work })
        #expect(vm.filteredScenarios.count >= 2)
    }

    @Test func selectingNoFilterShowsEverything() async throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let vm = PracticeViewModel(catalog: catalog)
        vm.domainFilter = nil
        #expect(vm.filteredScenarios.count == catalog.allScenarios.count)
    }
}
