import SwiftUI
import Core
import Persistence
import Adapters

@main
struct EngAssistantApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("EngAssistant") {
            Group {
                if let bootstrapError = appState.bootstrapError {
                    BootstrapErrorView(message: bootstrapError)
                } else if !appState.didCompleteOnboarding {
                    OnboardingView(viewModel: appState.onboardingVM) {
                        appState.markOnboardingComplete()
                    }
                } else if let container = appState.container {
                    ContentView(container: container)
                } else {
                    ProgressView("Initializing...")
                }
            }
            .task {
                await appState.bootstrap()
            }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var didCompleteOnboarding: Bool = false
    @Published var container: AppContainer?
    @Published var bootstrapError: String?
    let onboardingVM = OnboardingViewModel()

    func bootstrap() async {
        guard container == nil, bootstrapError == nil else { return }
        do {
            let c = try AppContainer()
            container = c
            // Hydrate onboarding-completion flag from persisted settings.
            if let v = try c.settingsRepository.get(.didCompleteOnboarding), v == "true" {
                didCompleteOnboarding = true
            }
            // Read retention setting and run sweeper in the background.
            let days: Int
            if let s = try c.settingsRepository.get(.audioRetentionDays), let d = Int(s) {
                days = d
            } else {
                days = 30
            }
            Task.detached {
                let sweeper = AudioRetentionSweeper(layout: c.storageLayout, retentionDays: days)
                _ = try? sweeper.sweep()
            }
        } catch {
            bootstrapError = "Couldn't start EngAssistant: \(error.localizedDescription). Check the install — the .app bundle may be missing required resources."
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
        VStack(alignment: .leading, spacing: 16) {
            Label("EngAssistant couldn't start", systemImage: "exclamationmark.triangle.fill")
                .font(.title2).bold()
                .foregroundStyle(.red)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480, height: 240)
    }
}
