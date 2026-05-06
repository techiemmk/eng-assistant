import SwiftUI
import Core

public struct PracticeView: View {
    @ObservedObject var viewModel: PracticeViewModel
    let onStart: (Scenario, SessionMode) -> Void

    public init(viewModel: PracticeViewModel, onStart: @escaping (Scenario, SessionMode) -> Void) {
        self.viewModel = viewModel
        self.onStart = onStart
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Practice").font(.largeTitle).bold()
                Spacer()
                Picker("Mode", selection: $viewModel.mode) {
                    Text("Flow").tag(SessionMode.flow)
                    Text("Coach").tag(SessionMode.coach)
                }.pickerStyle(.segmented).frame(width: 200)
            }

            HStack(spacing: 12) {
                domainChip(label: "All", value: nil)
                domainChip(label: "Work", value: .work)
                domainChip(label: "Networking", value: .networking)
                domainChip(label: "Social", value: .social)
                Spacer()
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 12) {
                    ForEach(viewModel.filteredScenarios) { scenario in
                        ScenarioCardView(
                            scenario: scenario,
                            isSelected: viewModel.selectedScenarioId == scenario.id,
                            onTap: { viewModel.selectedScenarioId = scenario.id }
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("Start Session") {
                    if let s = viewModel.selectedScenario {
                        onStart(s, viewModel.mode)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(viewModel.selectedScenario == nil)
                .controlSize(.large)
            }
        }
        .padding()
    }

    private func domainChip(label: String, value: ScenarioDomain?) -> some View {
        Button(label) {
            viewModel.domainFilter = value
        }
        .buttonStyle(.bordered)
        .tint(viewModel.domainFilter == value ? .accentColor : .secondary)
    }
}

private struct ScenarioCardView: View {
    let scenario: Scenario
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scenario.title).font(.headline)
                Text(scenario.persona)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack {
                    Text(scenario.domain.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.gray.opacity(0.15))
                        .clipShape(Capsule())
                    Text("Difficulty \(scenario.difficulty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
