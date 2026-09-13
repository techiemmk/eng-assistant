import SwiftUI
import Core

public struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(Theme.screenIcon)
                    .foregroundStyle(Theme.brand)
                Text("Settings").font(Theme.appTitle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)

            Form {
                Section {
                    Picker("Theme", selection: Binding(
                        get: { viewModel.appearance },
                        // Applied on pick rather than on Save: you choose a
                        // theme by looking at it.
                        set: { viewModel.selectAppearance($0) }
                    )) {
                        ForEach(AppearancePreference.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.iconName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                        .font(Theme.cardTitle)
                } footer: {
                    Text("System follows your Mac's light/dark setting.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "cpu.fill").foregroundStyle(Theme.brand).frame(width: 20)
                        TextField("Ollama model name", text: $viewModel.modelName)
                    }
                } header: {
                    Label("AI Model", systemImage: "brain.head.profile")
                        .font(Theme.cardTitle)
                }

                Section {
                    HStack {
                        Image(systemName: "terminal.fill").foregroundStyle(Theme.brand).frame(width: 20)
                        TextField("Path to whisper-cli", text: $viewModel.sttExecutablePath)
                    }
                    HStack {
                        Image(systemName: "doc.fill").foregroundStyle(Theme.brand).frame(width: 20)
                        TextField("Path to ggml model (.bin)", text: $viewModel.sttModelPath)
                    }
                    HStack {
                        Button {
                            viewModel.autodetectSTT()
                        } label: {
                            Label("Auto-detect", systemImage: "sparkle.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        if viewModel.isSTTConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                                .font(Theme.caption)
                        } else {
                            Label("Not configured — the app can't hear you yet", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                                .font(Theme.caption)
                        }
                    }
                } header: {
                    Label("Speech-to-text", systemImage: "waveform.badge.mic")
                        .font(Theme.cardTitle)
                } footer: {
                    Text("Install with `brew install whisper-cpp`, then drop a ggml model into "
                         + "~/Library/Application Support/EngAssistant/models/ and hit Auto-detect.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "wind").foregroundStyle(Theme.brand).frame(width: 20)
                        Picker("Default mode", selection: $viewModel.defaultMode) {
                            Label("Flow", systemImage: "wind").tag(SessionMode.flow)
                            Label("Coach", systemImage: "lightbulb.fill").tag(SessionMode.coach)
                        }
                    }
                } header: {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                        .font(Theme.cardTitle)
                }

                Section {
                    HStack {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(Theme.brand).frame(width: 20)
                        Stepper("Keep audio for \(viewModel.audioRetentionDays) days",
                                value: $viewModel.audioRetentionDays, in: 1...365)
                    }
                } header: {
                    Label("Audio", systemImage: "speaker.wave.2.fill")
                        .font(Theme.cardTitle)
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            Task { try? await viewModel.save() }
                        } label: {
                            Label("Save changes", systemImage: "checkmark.circle.fill")
                                .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if let n = viewModel.savedNotice {
                        Label(n, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .font(Theme.caption)
                    }
                    if let e = viewModel.lastError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                            .font(Theme.caption)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task { try? await viewModel.load() }
    }
}
