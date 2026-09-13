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
                if let bootstrapError = appState.bootstrapError {
                    BootstrapErrorView(message: bootstrapError)
                } else if !appState.didCompleteOnboarding {
                    OnboardingView(viewModel: appState.onboardingVM) {
                        appState.markOnboardingComplete()
                    }
                } else if let container = appState.container, let settings = appState.settings {
                    ContentView(container: container, settings: settings)
                } else {
                    ProgressView("Initializing...")
                        .controlSize(.large)
                        .tint(Theme.brand)
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
    @Published var didCompleteOnboarding: Bool = false
    @Published var container: AppContainer?
    @Published var settings: AppSettingsStore?
    @Published var bootstrapError: String?
    let onboardingVM = OnboardingViewModel()

    func bootstrap() async {
        guard container == nil, bootstrapError == nil else { return }
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

            let days = store.audioRetentionDays
            Task.detached {
                let sweeper = AudioRetentionSweeper(layout: c.storageLayout, retentionDays: days)
                _ = try? sweeper.sweep()
            }
        } catch {
            bootstrapError = "Couldn't start \(Theme.appName): \(error.localizedDescription). Check the install — the .app bundle may be missing required resources."
            FileHandle.standardError.write(Data("[bootstrap] container init failed: \(error)\n".utf8))
        }
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
