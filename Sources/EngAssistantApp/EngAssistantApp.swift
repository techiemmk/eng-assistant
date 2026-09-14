import SwiftUI
import Core
import Persistence
import Adapters

@main
struct EngAssistantApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(Theme.appName) {
            Group {
                // A failure is shown the moment it happens — no reason to make
                // someone sit through the launch hold to read an error.
                if let bootstrapError = appState.bootstrapError {
                    BootstrapErrorView(message: bootstrapError)
                } else if appState.isLaunching {
                    LaunchView()
                } else if !appState.didCompleteOnboarding {
                    OnboardingView(viewModel: appState.onboardingVM) {
                        appState.markOnboardingComplete()
                    }
                } else if let container = appState.container, let settings = appState.settings {
                    ContentView(
                        container: container,
                        settings: settings,
                        unfinishedSession: appState.unfinishedSession,
                        takeUnfinishedSession: { appState.takeUnfinishedSession() },
                        discardUnfinishedSession: { appState.discardUnfinishedSession() }
                    )
                } else {
                    LaunchView()
                }
            }
            .tint(Theme.brand)
            .fontDesign(.rounded)
            // Appearance is driven solely by NSApp.appearance (see
            // AppAppearanceApplier), not preferredColorScheme. Setting it on the
            // application propagates to the window, its titlebar and menus, and
            // the SwiftUI content inside — and, unlike a modifier reading
            // `appState.settings`, it doesn't depend on this body observing a
            // nested ObservableObject, which SwiftUI wouldn't republish.
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.mutedSurface)
            .task {
                await appState.bootstrap()
            }

        }
        .windowResizability(.contentSize)
    }
}

/// Applies a theme choice to the whole application. Setting it here rather than
/// with `preferredColorScheme` covers the titlebar and menus too, which sit
/// outside the SwiftUI view tree; `nil` means "follow the Mac", which is how
/// AppKit spells the System option.
///
/// Injected rather than called as a global so it can be substituted — `NSApp`
/// is nil outside a real application process, including in tests.
public typealias AppearanceApplying = @MainActor (AppearancePreference) -> Void

public enum AppAppearanceApplier {
    public static let sharedApplication: AppearanceApplying = { preference in
        NSApp?.appearance = preference.nsAppearance
    }
}

@MainActor
final class AppState: ObservableObject {
    /// How long the launch screen stays up at minimum. Bootstrap is usually
    /// faster than this, so the number is a deliberate pause rather than a
    /// measurement — injectable so tests don't sit through it.
    ///
    /// `nonisolated` because it's read as a default argument of `init`, and
    /// default arguments are evaluated outside the actor. Safe to expose that
    /// way: it's an immutable `let` of a `Sendable` type.
    nonisolated static let defaultLaunchHold: Duration = .seconds(3)

    @Published var isLaunching: Bool = true
    /// A session still marked `.active` at launch: the app quit or crashed
    /// mid-conversation. `listActive()` has existed since the first version but
    /// nothing ever called it, so these accumulated invisibly.
    @Published var unfinishedSession: Session?
    @Published var didCompleteOnboarding: Bool = false
    @Published var container: AppContainer?
    @Published var settings: AppSettingsStore?
    @Published var bootstrapError: String?
    let onboardingVM = OnboardingViewModel()

    private let launchHold: Duration
    private let applyAppearance: AppearanceApplying

    init(
        launchHold: Duration = AppState.defaultLaunchHold,
        applyAppearance: @escaping AppearanceApplying = AppAppearanceApplier.sharedApplication
    ) {
        self.launchHold = launchHold
        self.applyAppearance = applyAppearance
    }

    func bootstrap() async {
        guard container == nil, bootstrapError == nil else { return }
        let started = ContinuousClock.now
        // Paint the launch screen in the default theme before the saved one is
        // known, so it doesn't start in the Mac's appearance and then snap.
        applyAppearance(AppDefaults.appearance)
        do {
            let c = try AppContainer()
            container = c

            // Hydrate saved settings before anything reads them, so the session
            // and debrief screens use the configured model, not a default.
            let store = c.makeSettingsStore()
            store.reload()
            settings = store
            onboardingVM.setModelName(store.modelName)

            // Hydrate onboarding-completion flag from persisted settings.
            if let v = try c.settingsRepository.get(.didCompleteOnboarding), v == "true" {
                didCompleteOnboarding = true
            }
            // Re-run setup checks now that the real model name is known.
            Task { await self.onboardingVM.runChecks() }

            // Most recent first, so a pile of old orphans offers the one the
            // user is most likely to actually want back.
            unfinishedSession = (try? c.sessionRepository.listActive())?
                .max { $0.startedAt < $1.startedAt }

            let days = store.audioRetentionDays
            Task.detached {
                let sweeper = AudioRetentionSweeper(layout: c.storageLayout, retentionDays: days)
                _ = try? sweeper.sweep()
            }

            await holdLaunchScreen(since: started)
            isLaunching = false
        } catch {
            bootstrapError = "Couldn't start \(Theme.appName): \(error.localizedDescription). Check the install — the .app bundle may be missing required resources."
            FileHandle.standardError.write(Data("[bootstrap] container init failed: \(error)\n".utf8))
            isLaunching = false
        }
    }

    /// Sleeps for whatever is left of the hold. Measuring the elapsed time
    /// rather than always sleeping means a slow first launch — migrations on a
    /// cold database — doesn't add three seconds on top of itself.
    private func holdLaunchScreen(since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        guard elapsed < launchHold else { return }
        try? await Task.sleep(for: launchHold - elapsed)
    }

    /// The user chose to continue the unfinished session; clear the offer so it
    /// isn't made twice in one launch.
    func takeUnfinishedSession() -> Session? {
        defer { unfinishedSession = nil }
        return unfinishedSession
    }

    /// The user declined. Marking it abandoned is what stops the same session
    /// being offered on every future launch.
    func discardUnfinishedSession() {
        guard let session = unfinishedSession, let container else { return }
        try? container.sessionRepository.abandon(id: session.id)
        unfinishedSession = nil
    }

    func markOnboardingComplete() {
        didCompleteOnboarding = true
        if let c = container {
            try? c.settingsRepository.set(.didCompleteOnboarding, value: "true")
        }
    }
}

struct BootstrapErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.screenIcon)
                    .foregroundStyle(Theme.danger)
                Text("\(Theme.appName) couldn't start")
                    .font(Theme.sectionTitle)
            }
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 580, height: 320)
    }
}
