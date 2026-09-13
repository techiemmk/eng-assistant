import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// The chip row filters by domain *or* by practice track, because the work
/// domain now holds both office and clinical scenarios.
@MainActor
@Suite struct PracticeCollectionTests {
    private static func viewModel() throws -> PracticeViewModel {
        PracticeViewModel(catalog: try ScenarioCatalog.loadBuiltIn())
    }

    @Test func defaultsToShowingEverything() throws {
        let vm = try Self.viewModel()
        #expect(vm.collection == .all)
        #expect(vm.filteredScenarios.count == vm.scenarios.count)
    }

    @Test func offersAChipForEveryDomainPlusTheMedicalTrack() throws {
        let vm = try Self.viewModel()
        #expect(vm.collections.contains(.all))
        for domain in ScenarioDomain.allCases {
            #expect(vm.collections.contains(.domain(domain)), "no chip for \(domain)")
        }
        #expect(vm.collections.contains(.tag("medical")))
    }

    @Test func filteringByTagNarrowsToThatTrack() throws {
        let vm = try Self.viewModel()
        vm.collection = .tag("medical")
        #expect(!vm.filteredScenarios.isEmpty)
        #expect(vm.filteredScenarios.allSatisfy { $0.tags.contains("medical") })
    }

    /// Medical scenarios live in the work domain, so the work chip has to keep
    /// showing them — the tag chip is a narrowing, not a separate bucket.
    @Test func workDomainStillIncludesTheMedicalScenarios() throws {
        let vm = try Self.viewModel()
        vm.collection = .domain(.work)
        #expect(vm.filteredScenarios.contains { $0.tags.contains("medical") })
        #expect(vm.filteredScenarios.contains { !$0.tags.contains("medical") })
    }

    /// The legacy `domainFilter` accessor still has to behave, since it's what
    /// ContentView seeds the default mode through.
    @Test func domainFilterAccessorStaysInSyncWithCollection() throws {
        let vm = try Self.viewModel()
        vm.domainFilter = .social
        #expect(vm.collection == .domain(.social))
        #expect(vm.domainFilter == .social)

        vm.collection = .tag("medical")
        #expect(vm.domainFilter == nil, "a tag collection isn't a domain")

        vm.domainFilter = nil
        #expect(vm.collection == .all)
    }

    /// Switching filters must not leave the Start button armed on a scenario
    /// that's no longer on screen.
    @Test func selectionIsClearedWhenTheFilterHidesIt() throws {
        let vm = try Self.viewModel()
        let medical = vm.scenarios.first { $0.tags.contains("medical") }!
        vm.selectedScenarioId = medical.id

        vm.collection = .domain(.social)
        vm.pruneSelectionIfHidden()
        #expect(vm.selectedScenarioId == nil)
        #expect(vm.selectedScenario == nil)
    }

    @Test func selectionSurvivesAFilterThatStillShowsIt() throws {
        let vm = try Self.viewModel()
        let medical = vm.scenarios.first { $0.tags.contains("medical") }!
        vm.selectedScenarioId = medical.id

        vm.collection = .tag("medical")
        vm.pruneSelectionIfHidden()
        #expect(vm.selectedScenarioId == medical.id)
    }

    @Test func offersAChipForTheHomeopathyTrack() throws {
        let vm = try Self.viewModel()
        #expect(vm.collections.contains(.tag("homeopathy")))
    }

    @Test func filteringByHomeopathyExcludesTheClinicalTrack() throws {
        let vm = try Self.viewModel()
        vm.collection = .tag("homeopathy")
        #expect(!vm.filteredScenarios.isEmpty)
        #expect(vm.filteredScenarios.allSatisfy { $0.tags.contains("homeopathy") })
        #expect(vm.filteredScenarios.allSatisfy { !$0.tags.contains("medical") })
    }

    /// Both tracks live in the work domain, so the Work chip has to hold all
    /// three kinds — office, clinical, homeopathy.
    @Test func workDomainHoldsEveryTrack() throws {
        let vm = try Self.viewModel()
        vm.collection = .domain(.work)
        #expect(vm.filteredScenarios.contains { $0.tags.contains("medical") })
        #expect(vm.filteredScenarios.contains { $0.tags.contains("homeopathy") })
        #expect(vm.filteredScenarios.contains {
            !$0.tags.contains("medical") && !$0.tags.contains("homeopathy")
        })
    }

    @Test func chipLabelsAreHumanReadable() throws {
        #expect(PracticeViewModel.Collection.all.label == "All")
        #expect(PracticeViewModel.Collection.domain(.work).label == "Work")
        #expect(PracticeViewModel.Collection.tag("medical").label == "Medical")
        #expect(PracticeViewModel.Collection.tag("homeopathy").label == "Homeopathy")
    }

    /// Collections are used as ForEach identities, so their ids must be stable
    /// and distinct across the two kinds.
    @Test func collectionIdsAreDistinct() throws {
        let vm = try Self.viewModel()
        let ids = vm.collections.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate chip ids: \(ids)")
    }
}
