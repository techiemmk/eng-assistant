import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// The Sessions list's side of deleting: the row goes away immediately, the
/// audio goes first, and a failure leaves the row where it is.
@MainActor
@Suite struct SessionDeleteViewModelTests {
    final class Store: SessionPersisting, @unchecked Sendable {
        var sessions: [Session] = []
        var deleteError: Error?
        var deleted: [UUID] = []
        func create(_ session: Session) throws { sessions.append(session) }
        func find(id: UUID) throws -> Session? { sessions.first { $0.id == id } }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {}
        func reactivate(id: UUID) throws {}
        func abandon(id: UUID) throws {
            guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
            sessions[i].status = .abandoned
            sessions[i].endedAt = Date()
        }
        func delete(id: UUID) throws {
            if let deleteError { throw deleteError }
            deleted.append(id)
            sessions.removeAll { $0.id == id }
        }
        func listActive() throws -> [Session] { sessions.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] { Array(sessions.prefix(limit)) }
    }

    final class AudioStore: AudioFilePersisting, @unchecked Sendable {
        var deleted: [UUID] = []
        var deleteError: Error?
        func write(audio: Data, sessionId: UUID, turnIndex: Int, speaker: Speaker) throws -> String { "" }
        func deleteAll(forSession sessionId: UUID) throws {
            if let deleteError { throw deleteError }
            deleted.append(sessionId)
        }
    }

    struct Boom: Error {}

    private static func session(_ scenarioId: String = "work-standup-01") -> Session {
        Session(id: UUID(), scenarioId: scenarioId, startedAt: Date(), endedAt: nil,
                mode: .flow, status: .ended, summary: nil, personaSnapshot: "p")
    }

    private static func makeViewModel(
        store: Store,
        audio: AudioStore
    ) throws -> SessionsHistoryViewModel {
        SessionsHistoryViewModel(
            persister: store,
            audioPersister: audio,
            catalog: try ScenarioCatalog.loadBuiltIn()
        )
    }

    @Test func deleteRemovesTheRowImmediately() async throws {
        let store = Store(); let audio = AudioStore()
        let doomed = Self.session()
        let keeper = Self.session()
        store.sessions = [doomed, keeper]
        let vm = try Self.makeViewModel(store: store, audio: audio)
        try await vm.load()
        #expect(vm.sessions.count == 2)

        await vm.delete(doomed)

        #expect(vm.sessions.map(\.id) == [keeper.id])
        #expect(store.deleted == [doomed.id])
        #expect(vm.lastError == nil)
    }

    @Test func deleteAlsoRemovesTheRecordings() async throws {
        let store = Store(); let audio = AudioStore()
        let doomed = Self.session()
        store.sessions = [doomed]
        let vm = try Self.makeViewModel(store: store, audio: audio)
        try await vm.load()

        await vm.delete(doomed)

        #expect(audio.deleted == [doomed.id])
    }

    /// Audio is deleted first on purpose: if that fails the row survives, so
    /// the clips are still reachable to try again rather than orphaned.
    @Test func aFailedAudioDeleteLeavesTheSessionInPlace() async throws {
        let store = Store(); let audio = AudioStore()
        audio.deleteError = Boom()
        let doomed = Self.session()
        store.sessions = [doomed]
        let vm = try Self.makeViewModel(store: store, audio: audio)
        try await vm.load()

        await vm.delete(doomed)

        #expect(vm.sessions.count == 1, "the row should survive a failed delete")
        #expect(store.deleted.isEmpty, "the database must not be touched")
        #expect(vm.lastError?.contains("Could not delete") == true)
    }

    @Test func aFailedDatabaseDeleteSurfacesAnError() async throws {
        let store = Store(); let audio = AudioStore()
        store.deleteError = Boom()
        let doomed = Self.session()
        store.sessions = [doomed]
        let vm = try Self.makeViewModel(store: store, audio: audio)
        try await vm.load()

        await vm.delete(doomed)

        #expect(vm.sessions.count == 1)
        #expect(vm.lastError != nil)
    }

    /// A previous error must not linger once a delete succeeds.
    @Test func aSuccessfulDeleteClearsAnEarlierError() async throws {
        let store = Store(); let audio = AudioStore()
        let first = Self.session()
        let second = Self.session()
        store.sessions = [first, second]
        let vm = try Self.makeViewModel(store: store, audio: audio)
        try await vm.load()

        store.deleteError = Boom()
        await vm.delete(first)
        #expect(vm.lastError != nil)

        store.deleteError = nil
        await vm.delete(first)
        #expect(vm.lastError == nil)
    }

    /// Deleting works without an audio persister wired in — the app supplies
    /// one, but the view model shouldn't require it.
    @Test func deleteWorksWithoutAnAudioPersister() async throws {
        let store = Store()
        let doomed = Self.session()
        store.sessions = [doomed]
        let vm = SessionsHistoryViewModel(persister: store)
        try await vm.load()

        await vm.delete(doomed)

        #expect(vm.sessions.isEmpty)
        #expect(store.deleted == [doomed.id])
    }
}
