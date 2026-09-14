import SwiftUI
import Core

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    /// Autoclosed so `@StateObject` constructs the view model exactly once per
    /// view identity. Built eagerly, it was rebuilt on every body evaluation —
    /// and saving mutates the settings store, which *causes* one. The fresh
    /// instance had empty model/voice lists and default selections, and the
    /// `.task` below doesn't re-fire for a new object at the same identity, so
    /// the screen blanked the moment you pressed Save.
    public init(viewModel: @autoclosure @escaping () -> SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
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
                    Text("Applied straight away — no need to save.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "cpu.fill").foregroundStyle(Theme.brand).frame(width: 20)
                        if viewModel.selectableModels.isEmpty {
                            // Ollama unreachable — fall back to typing, so the
                            // model can still be set with the server stopped.
                            TextField("Ollama model name", text: $viewModel.modelName)
                        } else {
                            Picker("Model", selection: $viewModel.modelName) {
                                ForEach(viewModel.selectableModels, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                        }
                    }
                    HStack {
                        Button {
                            Task { await viewModel.refreshAvailableModels() }
                        } label: {
                            Label("Refresh list", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoadingModels)
                        Spacer()
                        if viewModel.isLoadingModels {
                            ActivityLabel(text: "Asking Ollama", systemImage: "server.rack",
                                          font: Theme.caption)
                        } else if viewModel.availableModels.isEmpty {
                            Label("Ollama unreachable — type the name", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                                .font(Theme.caption)
                        } else {
                            Label("\(viewModel.availableModels.count) installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                                .font(Theme.caption)
                        }
                    }
                } header: {
                    Label("AI Model", systemImage: "brain.head.profile")
                        .font(Theme.cardTitle)
                } footer: {
                    Text("Only models installed locally are listed — cloud models need an Ollama subscription and can't be used here.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(Theme.brand).frame(width: 20)
                        Picker("Voice", selection: $viewModel.ttsVoiceId) {
                            Text("System default").tag("")
                            ForEach(viewModel.selectableVoices) { voice in
                                Text(voice.pickerLabel).tag(voice.id)
                            }
                        }
                    }
                    HStack {
                        Button {
                            Task { await viewModel.previewVoice() }
                        } label: {
                            Label("Hear it", systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isPreviewingVoice)
                        Spacer()
                        if viewModel.isPreviewingVoice {
                            ActivityLabel(text: "Speaking", systemImage: "speaker.wave.2.fill",
                                          font: Theme.caption)
                        } else {
                            Text("\(viewModel.availableVoices.count) voices installed")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if viewModel.shouldSuggestBetterVoices {
                        // The honest headline: no amount of tuning in this app
                        // beats downloading one of Apple's better voices.
                        Label(
                            "All your installed voices are Apple's basic tier, which is why they sound robotic. "
                            + "For a much more natural voice, open System Settings → Accessibility → "
                            + "Spoken Content → System Voice → Manage Voices and download an English voice "
                            + "marked Premium (or Enhanced). Then come back and click Refresh.",
                            systemImage: "lightbulb.fill"
                        )
                        .font(Theme.caption)
                        .foregroundStyle(Theme.warning)
                    }
                    Button {
                        viewModel.refreshAvailableVoices()
                    } label: {
                        Label("Refresh voice list", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Label("AI Voice", systemImage: "person.wave.2.fill")
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
                            // Fades rather than vanishing abruptly. The only
                            // motion is the disappearance itself, which is the
                            // information — nothing here moves while it's up.
                            .transition(.opacity)
                    }
                    if let e = viewModel.lastError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                            .font(Theme.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.easeInOut(duration: 0.25), value: viewModel.savedNotice)
        }
        .task { try? await viewModel.load() }
    }
}
