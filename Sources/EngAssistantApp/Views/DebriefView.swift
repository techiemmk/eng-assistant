import SwiftUI
import Core

public struct DebriefView: View {
    @ObservedObject var viewModel: DebriefViewModel

    public init(viewModel: DebriefViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Debrief").font(.largeTitle).bold()

                if viewModel.isLoading {
                    ProgressView("Analyzing session...")
                } else if let err = viewModel.lastError {
                    Text(err).foregroundStyle(.red)
                } else if let debrief = viewModel.debrief {
                    sectionsFor(debrief)
                } else {
                    Text("No debrief loaded.")
                }
            }
            .padding()
        }
        .task {
            try? await viewModel.load()
        }
    }

    @ViewBuilder
    private func sectionsFor(_ debrief: Debrief) -> some View {
        Text(debrief.summary).font(.title3)

        GroupBox("Session Metrics") {
            HStack(spacing: 24) {
                metricColumn("Turns", "\(debrief.sessionMetrics.userTurnCount)")
                metricColumn("Words", "\(debrief.sessionMetrics.totalWordCount)")
                metricColumn("Fillers", "\(debrief.sessionMetrics.totalFillerCount)")
                metricColumn("Grammar", "\(debrief.sessionMetrics.totalGrammarIssues)")
                metricColumn("Unique-word ratio", String(format: "%.2f", debrief.sessionMetrics.averageUniqueWordRatio))
            }
            .padding(.vertical, 8)
        }

        if !debrief.newlyCreatedWeakSpots.isEmpty {
            GroupBox("New weak spots") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(debrief.newlyCreatedWeakSpots) { ws in
                        HStack {
                            Text("+ \(ws.pattern)").font(.body)
                            Spacer()
                            Text(ws.category.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !debrief.recurringWeakSpots.isEmpty {
            GroupBox("Recurring weak spots") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(debrief.recurringWeakSpots) { ws in
                        HStack {
                            Text("\u{2191} \(ws.pattern)")
                            Spacer()
                            Text("seen \(ws.occurrenceCount)\u{00D7}")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !debrief.suggestedDrills.isEmpty {
            GroupBox("Suggested drills") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(debrief.suggestedDrills, id: \.self) { drill in
                        Text("\u{2022} \(drill)")
                    }
                }
            }
        }

        if !debrief.allTurns.isEmpty {
            GroupBox("Transcript") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(debrief.allTurns) { turn in
                        HStack(alignment: .top) {
                            Text(turn.speaker == .user ? "You" : "AI")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(turn.text)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func metricColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).bold()
        }
    }
}
