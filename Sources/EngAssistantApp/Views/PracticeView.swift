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
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice").font(Theme.appTitle)
                    Text("Pick a scenario, choose a mode, and start talking.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $viewModel.mode) {
                    Label("Flow", systemImage: "wind").tag(SessionMode.flow)
                    Label("Coach", systemImage: "lightbulb.fill").tag(SessionMode.coach)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            // Domain filters
            HStack(spacing: 8) {
                domainChip(label: "All", icon: "square.grid.2x2", value: nil)
                domainChip(label: "Work", icon: Theme.domainIcon(.work), value: .work)
                domainChip(label: "Networking", icon: Theme.domainIcon(.networking), value: .networking)
                domainChip(label: "Social", icon: Theme.domainIcon(.social), value: .social)
                Spacer()
            }

            // Scenario grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(viewModel.filteredScenarios) { scenario in
                        ScenarioCardView(
                            scenario: scenario,
                            isSelected: viewModel.selectedScenarioId == scenario.id,
                            onTap: { viewModel.selectedScenarioId = scenario.id }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            // Start button
            HStack {
                if let s = viewModel.selectedScenario {
                    HStack(spacing: 6) {
                        Image(systemName: Theme.domainIcon(s.domain))
                            .foregroundStyle(Theme.domainColor(s.domain))
                        Text("Ready: \(s.title)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    if let s = viewModel.selectedScenario {
                        onStart(s, viewModel.mode)
                    }
                } label: {
                    Label("Start session", systemImage: "play.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
                .disabled(viewModel.selectedScenario == nil)
            }
        }
        .padding(20)
    }

    private func domainChip(label: String, icon: String, value: ScenarioDomain?) -> some View {
        let isActive = viewModel.domainFilter == value
        return Button {
            viewModel.domainFilter = value
        } label: {
            Label(label, systemImage: icon)
                .font(Theme.chip)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? Theme.brand : .secondary)
    }
}

private struct ScenarioCardView: View {
    let scenario: Scenario
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    domainBadge
                    Spacer()
                    difficultyDots
                }
                Text(scenario.title)
                    .font(Theme.cardTitle)
                Text(scenario.persona)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if !scenario.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(scenario.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.gray.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Theme.brand.opacity(0.10) : Theme.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.brand : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? Theme.brand.opacity(0.25) : .black.opacity(0.04), radius: isSelected ? 6 : 2, y: isSelected ? 3 : 1)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var domainBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: Theme.domainIcon(scenario.domain))
            Text(scenario.domain.rawValue.capitalized)
        }
        .font(Theme.chip)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.domainColor(scenario.domain).opacity(0.18))
        .foregroundStyle(Theme.domainColor(scenario.domain))
        .clipShape(Capsule())
    }

    private var difficultyDots: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= scenario.difficulty ? Theme.brand : Color.gray.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
