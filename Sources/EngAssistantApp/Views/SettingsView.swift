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
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.brand)
                Text("Settings").font(Theme.appTitle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)

            Form {
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
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if let e = viewModel.lastError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task { try? await viewModel.load() }
    }
}
