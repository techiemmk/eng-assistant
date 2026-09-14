import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// The chip row is All plus one chip per practice domain, in a deliberate
/// order. These cover that order, that every chip leads somewhere, and that
/// between them the chips reach every scenario.
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

    /// The chip row is All followed by the domains in `displayOrder`. The order
    /// is deliberate, so it's asserted exactly rather than as a set.
    @Test func chipsAppearInTheRequestedOrder() throws {
        let vm = try Self.viewModel()
        #expect(vm.collections == [
            .all,
            .domain(.homeopathy),
            .domain(.medical),
            .domain(.networking),
            .domain(.social),
            .domain(.workplace),
        ])
    }

    @Test func chipLabelsReadAsRequested() throws {
        let vm = try Self.viewModel()
        #expect(vm.collections.map(\.label) == [
            "All", "Homeopathy", "Medical", "Networking", "Social", "Workplace",
        ])
    }

    /// `work` was replaced, not hidden. The chip is gone, and Workplace is
    /// what took over the scenarios that were in it.
    @Test func thereIsNoWorkChip() throws {
        let vm = try Self.viewModel()
        #expect(!vm.collections.map(\.label).contains("Work"))
        #expect(vm.collections.contains(.domain(.workplace)))
    }

    @Test func filteringByWorkplaceShowsOnlyTheOfficeScenarios() throws {
        let vm = try Self.viewModel()
        vm.collection = .domain(.workplace)
        let ids = vm.filteredScenarios.map(\.id)
        #expect(ids.sorted() == ["work-1on1-01", "work-standup-01"])
    }

    @Test func filteringByHomeopathyExcludesTheClinicalScenarios() throws {
        let vm = try Self.viewModel()
        vm.collection = .domain(.homeopathy)
        #expect(!vm.filteredScenarios.isEmpty)
        #expect(vm.filteredScenarios.allSatisfy { $0.domain == .homeopathy })
    }

    @Test func filteringByMedicalExcludesHomeopathy() throws {
        let vm = try Self.viewModel()
        vm.collection = .domain(.medical)
        #expect(!vm.filteredScenarios.isEmpty)
        #expect(vm.filteredScenarios.allSatisfy { $0.domain == .medical })
    }

    /// Every chip must lead somewhere. An empty chip is a dead end the user
    /// can tap.
    @Test func noChipIsEmpty() throws {
        let vm = try Self.viewModel()
        for collection in vm.collections {
            vm.collection = collection
            #expect(!vm.filteredScenarios.isEmpty, "\(collection.label) shows nothing")
        }
    }

    /// Selecting each chip in turn should account for the whole catalog.
    @Test func theChipsBetweenThemCoverEveryScenario() throws {
        let vm = try Self.viewModel()
        var seen = Set<String>()
        for collection in vm.collections where collection != .all {
            vm.collection = collection
            seen.formUnion(vm.filteredScenarios.map(\.id))
        }
        #expect(seen.count == vm.scenarios.count, "some scenario has no chip")
    }

    /// The legacy `domainFilter` accessor still has to behave — ContentView
    /// seeds the default mode through it.
    @Test func domainFilterAccessorStaysInSyncWithCollection() throws {
        let vm = try Self.viewModel()
        vm.domainFilter = .social
        #expect(vm.collection == .domain(.social))
        #expect(vm.domainFilter == .social)

        vm.domainFilter = nil
        #expect(vm.collection == .all)
        #expect(vm.domainFilter == nil)
    }

    /// Switching filters must not leave the Start button armed on a scenario
    /// that's no longer on screen.
    @Test func selectionIsClearedWhenTheFilterHidesIt() throws {
        let vm = try Self.viewModel()
        let homeopathy = vm.scenarios.first { $0.domain == .homeopathy }!
        vm.selectedScenarioId = homeopathy.id

        vm.collection = .domain(.social)
        vm.pruneSelectionIfHidden()
        #expect(vm.selectedScenarioId == nil)
        #expect(vm.selectedScenario == nil)
    }

    @Test func selectionSurvivesAFilterThatStillShowsIt() throws {
        let vm = try Self.viewModel()
        let homeopathy = vm.scenarios.first { $0.domain == .homeopathy }!
        vm.selectedScenarioId = homeopathy.id

        vm.collection = .domain(.homeopathy)
        vm.pruneSelectionIfHidden()
        #expect(vm.selectedScenarioId == homeopathy.id)
    }

    /// Collections are ForEach identities, so their ids must be distinct.
    @Test func collectionIdsAreDistinct() throws {
        let vm = try Self.viewModel()
        let ids = vm.collections.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate chip ids: \(ids)")
    }
}
