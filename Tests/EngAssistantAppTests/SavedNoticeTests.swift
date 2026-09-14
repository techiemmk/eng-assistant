import Testing
import Foundation
import Core
import Adapters
@testable import EngAssistantApp

/// "Saved." used to stay on screen indefinitely — the only way to dismiss it
/// was to navigate away and back, which rebuilt the view model. It now clears
/// itself. Errors are deliberately excluded: they're actionable.
@MainActor
@Suite struct SavedNoticeTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        var failOnSet = false
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws {
            if failOnSet { throw Boom() }
            store[key.rawValue] = value
        }
    }

    struct Boom: Error {}

    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    /// A locator that "finds" things, to exercise the autodetect notice.
    private static let findingLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: ["/bin/sh"]
    )

    private static func makeViewModel(
        persister: InMemoryPersister = InMemoryPersister(),
        notice: Duration = .milliseconds(80),
        locator: STTLocator = noLocator
    ) -> SettingsViewModel {
        SettingsViewModel(
            persister: persister,
            locator: locator,
            healthCheck: HealthCheck(probe: { _ in false }, bodyProbe: { _ in nil }),
            noticeDuration: notice,
            voiceCatalog: { [] }
        )
    }

    /// Polls rather than sleeping a fixed time, so the test doesn't race the
    /// expiry task on a loaded machine.
    private func waitForNoticeToClear(_ vm: SettingsViewModel, within: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now.advanced(by: within)
        while vm.savedNotice != nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func savingShowsTheNoticeImmediately() async throws {
        let vm = Self.makeViewModel()
        try await vm.save()
        #expect(vm.savedNotice == "Saved.")
    }

    @Test func theNoticeClearsItself() async throws {
        let vm = Self.makeViewModel()
        try await vm.save()
        #expect(vm.savedNotice != nil)

        await waitForNoticeToClear(vm)

        #expect(vm.savedNotice == nil, "the notice never expired")
    }

    /// A second save must restart the clock, not inherit the first timer and
    /// vanish early.
    @Test func savingAgainRestartsTheTimer() async throws {
        let vm = Self.makeViewModel(notice: .milliseconds(300))
        try await vm.save()
        try await Task.sleep(for: .milliseconds(200))

        try await vm.save()
        // Had the first timer survived, it would fire ~100ms from here.
        try await Task.sleep(for: .milliseconds(160))
        #expect(vm.savedNotice == "Saved.", "an older timer cleared the newer notice")

        await waitForNoticeToClear(vm)
        #expect(vm.savedNotice == nil)
    }

    /// Errors are actionable, so they stay until the user resolves them.
    @Test func errorsDoNotExpire() async throws {
        let persister = InMemoryPersister()
        persister.failOnSet = true
        let vm = Self.makeViewModel(persister: persister, notice: .milliseconds(50))

        await #expect(throws: (any Error).self) { try await vm.save() }
        #expect(vm.lastError != nil)

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.lastError != nil, "an error message expired — it should persist")
    }

    /// A failed save shows no confirmation at all.
    @Test func aFailedSaveShowsNoNotice() async throws {
        let persister = InMemoryPersister()
        persister.failOnSet = true
        let vm = Self.makeViewModel(persister: persister)
        await #expect(throws: (any Error).self) { try await vm.save() }
        #expect(vm.savedNotice == nil)
    }

    /// Autodetect uses the same notice, so it expires the same way.
    @Test func theAutodetectNoticeAlsoClearsItself() async throws {
        let vm = Self.makeViewModel(locator: Self.findingLocator)
        vm.autodetectSTT()
        #expect(vm.savedNotice?.contains("Found") == true)

        await waitForNoticeToClear(vm)

        #expect(vm.savedNotice == nil)
    }

    /// A failed autodetect reports an error and leaves no stale confirmation
    /// from an earlier success.
    @Test func aFailedAutodetectClearsAnyStandingNotice() async throws {
        let vm = Self.makeViewModel(notice: .seconds(30))
        try await vm.save()
        #expect(vm.savedNotice == "Saved.")

        vm.autodetectSTT()

        #expect(vm.savedNotice == nil, "a stale confirmation survived a failed autodetect")
        #expect(vm.lastError?.contains("whisper-cpp") == true)
    }

    @Test func theShippedDurationIsAFewSeconds() {
        #expect(SettingsViewModel.defaultNoticeDuration == .seconds(3))
    }
}
