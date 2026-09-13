import SwiftUI
import Core
import Persistence
import Adapters

@main
struct EngAssistantApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
            // Theme's palette is fixed light values, so the window has to be
            // light too — otherwise system dark mode would keep rendering the
            // controls, form backgrounds, and text fields dark around it.
            .preferredColorScheme(.light)
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

/// Exists only to pin the app's appearance. `preferredColorScheme(.light)`
/// covers the SwiftUI content, but the window titlebar and menus follow the
/// *app* appearance — so on a Mac set to dark, a light window would sit under a
/// dark titlebar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
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
