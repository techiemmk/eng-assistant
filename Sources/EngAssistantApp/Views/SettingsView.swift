import SwiftUI
import Core

public struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("AI Model") {
                TextField("Ollama model name", text: $viewModel.modelName)
            }
            Section("Defaults") {
                Picker("Default mode", selection: $viewModel.defaultMode) {
                    Text("Flow").tag(SessionMode.flow)
                    Text("Coach").tag(SessionMode.coach)
                }
            }
            Section("Audio") {
                Stepper("Keep audio for \(viewModel.audioRetentionDays) days",
                        value: $viewModel.audioRetentionDays, in: 1...365)
            }
            Section {
                Button("Save") {
                    Task { try? await viewModel.save() }
                }
                if let n = viewModel.savedNotice {
                    Text(n).foregroundStyle(.green).font(.caption)
                }
                if let e = viewModel.lastError {
                    Text(e).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { try? await viewModel.load() }
    }
}
