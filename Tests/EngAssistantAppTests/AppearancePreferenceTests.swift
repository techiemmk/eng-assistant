import Testing
import SwiftUI
import AppKit
import Core
@testable import EngAssistantApp

/// The theme switch has to survive a relaunch and take effect without one.
@MainActor
@Suite struct AppearancePreferenceTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    /// Light is the default, and there is no "follow the Mac" option — the app
    /// always picks one.
    @Test func defaultsToLight() {
        let store = AppSettingsStore(persister: InMemoryPersister())
        store.reload(autodetect: Self.noLocator)
        #expect(store.appearance == .light)
        #expect(AppDefaults.appearance == .light)
    }

    @Test func onlyLightAndDarkAreOffered() {
        #expect(AppearancePreference.allCases == [.light, .dark])
    }

    @Test func reloadRestoresASavedPreference() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.appearance.rawValue] = "dark"
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)
        #expect(store.appearance == .dark)
    }

    /// Covers a database written before the System option was removed, as well
    /// as anything else unrecognised.
    @Test func reloadFallsBackToLightForAnUnrecognisedValue() {
        for stored in ["system", "sepia", ""] {
            let persister = InMemoryPersister()
            persister.store[AppSettingKey.appearance.rawValue] = stored
            let store = AppSettingsStore(persister: persister)
            store.reload(autodetect: Self.noLocator)
            #expect(store.appearance == .light, "'\(stored)' should fall back to light")
        }
    }

    /// Picking a theme applies and persists immediately — you're choosing it by
    /// looking at the result, so waiting for Save would be wrong.
    @Test func selectingAThemeAppliesAndPersistsWithoutSaving() {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)

        let settingsVM = SettingsViewModel(persister: persister, store: store, locator: Self.noLocator)
        settingsVM.selectAppearance(.dark)

        #expect(store.appearance == .dark)
        #expect(persister.store[AppSettingKey.appearance.rawValue] == "dark")
    }

    @Test func selectingAThemeWorksWithoutALiveStore() {
        let persister = InMemoryPersister()
        let settingsVM = SettingsViewModel(persister: persister, locator: Self.noLocator)
        settingsVM.selectAppearance(.light)
        #expect(persister.store[AppSettingKey.appearance.rawValue] == "light")
    }

    @Test func savingAlsoCarriesTheTheme() async throws {
        let persister = InMemoryPersister()
        let store = AppSettingsStore(persister: persister)
        store.reload(autodetect: Self.noLocator)

        let settingsVM = SettingsViewModel(persister: persister, store: store, locator: Self.noLocator)
        settingsVM.appearance = .dark
        try await settingsVM.save()
        #expect(store.appearance == .dark)
    }

    @Test func loadHydratesTheSettingsScreen() async throws {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.appearance.rawValue] = "light"
        let vm = SettingsViewModel(persister: persister, locator: Self.noLocator)
        try await vm.load()
        #expect(vm.appearance == .light)
    }

    /// Both map to a concrete AppKit appearance — nothing is left to the Mac.
    @Test func bothOptionsMapToConcreteAppearances() {
        #expect(AppearancePreference.light.nsAppearance.name == .aqua)
        #expect(AppearancePreference.dark.nsAppearance.name == .darkAqua)
    }

    @Test func everyOptionIsOfferableInTheUI() {
        #expect(AppearancePreference.allCases.count == 2)
        for option in AppearancePreference.allCases {
            #expect(!option.label.isEmpty)
            #expect(!option.iconName.isEmpty)
        }
    }
}

/// The switch has to reach the *application*, not just a view modifier — the
/// titlebar and menus live outside the SwiftUI tree, and the App's body can't
/// observe the settings store (it's a nested ObservableObject, which SwiftUI
/// doesn't republish). The applier is injected because `NSApp` is nil outside a
/// real application process.
@MainActor
@Suite struct AppAppearanceApplierTests {
    final class InMemoryPersister: SettingsPersisting, @unchecked Sendable {
        var store: [String: String] = [:]
        func get(_ key: AppSettingKey) throws -> String? { store[key.rawValue] }
        func set(_ key: AppSettingKey, value: String) throws { store[key.rawValue] = value }
    }

    /// Records what the host was asked to render in.
    @MainActor
    final class AppearanceRecorder {
        var applied: [AppearancePreference] = []
        lazy var applier: AppearanceApplying = { [weak self] preference in
            self?.applied.append(preference)
        }
    }

    private static let noLocator = STTLocator(
        modelsDirectory: URL(fileURLWithPath: "/nonexistent-models"),
        executableCandidates: []
    )

    @Test func pickingAThemeRepaintsImmediately() {
        let recorder = AppearanceRecorder()
        let store = AppSettingsStore(
            persister: InMemoryPersister(),
            applyAppearance: recorder.applier
        )
        store.applyAppearance(.dark)
        #expect(recorder.applied.last == .dark)
    }

    /// Launching with a saved preference has to honour it, not wait for the
    /// Settings screen to be opened.
    @Test func reloadAppliesTheSavedPreferenceAtLaunch() {
        let persister = InMemoryPersister()
        persister.store[AppSettingKey.appearance.rawValue] = "dark"
        let recorder = AppearanceRecorder()
        let store = AppSettingsStore(persister: persister, applyAppearance: recorder.applier)

        store.reload(autodetect: Self.noLocator)

        #expect(recorder.applied == [.dark])
    }

    @Test func launchingWithNoPreferenceAppliesLight() {
        let recorder = AppearanceRecorder()
        let store = AppSettingsStore(persister: InMemoryPersister(), applyAppearance: recorder.applier)
        store.reload(autodetect: Self.noLocator)
        #expect(recorder.applied == [.light])
    }

    /// Saving the Settings form is the other path a theme can change through.
    @Test func savingSettingsAlsoRepaints() async throws {
        let persister = InMemoryPersister()
        let recorder = AppearanceRecorder()
        let store = AppSettingsStore(persister: persister, applyAppearance: recorder.applier)
        store.reload(autodetect: Self.noLocator)

        let settingsVM = SettingsViewModel(persister: persister, store: store, locator: Self.noLocator)
        settingsVM.appearance = .light
        try await settingsVM.save()

        #expect(recorder.applied.last == .light)
    }

    @Test func darkMapsToAppKitDarkAqua() {
        #expect(AppearancePreference.dark.nsAppearance.name == .darkAqua)
    }
}
