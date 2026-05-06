import SwiftUI
import Core

public struct DebriefView: View {
    @ObservedObject var viewModel: DebriefViewModel

    public init(viewModel: DebriefViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.brand)
                    Text("Debrief").font(Theme.appTitle)
                }

                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.regular)
                        Text("Analyzing your session...")
                            .foregroundStyle(.secondary)
                    }
                } else if let err = viewModel.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if let debrief = viewModel.debrief {
                    sectionsFor(debrief)
                } else {
                    Text("No debrief loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .task {
            try? await viewModel.load()
        }
    }

    @ViewBuilder
    private func sectionsFor(_ debrief: Debrief) -> some View {
        // Summary card
        Text(debrief.summary)
            .font(Theme.sectionTitle)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandGradient.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        sectionHeader("Session metrics", icon: "chart.bar.fill")
        HStack(spacing: 14) {
            metricCard("Turns", "\(debrief.sessionMetrics.userTurnCount)", icon: "bubble.left.and.bubble.right.fill")
            metricCard("Words", "\(debrief.sessionMetrics.totalWordCount)", icon: "text.alignleft")
            metricCard("Fillers", "\(debrief.sessionMetrics.totalFillerCount)", icon: "ellipsis.bubble.fill")
            metricCard("Grammar", "\(debrief.sessionMetrics.totalGrammarIssues)", icon: "exclamationmark.bubble.fill")
            metricCard("Vocab range", String(format: "%.2f", debrief.sessionMetrics.averageUniqueWordRatio), icon: "books.vertical.fill")
        }

        if !debrief.newlyCreatedWeakSpots.isEmpty {
            sectionHeader("New weak spots", icon: "plus.circle.fill", tint: Theme.highlight)
            VStack(spacing: 8) {
                ForEach(debrief.newlyCreatedWeakSpots) { ws in
                    weakSpotRow(ws, leadingIcon: "plus")
                }
            }
        }

        if !debrief.recurringWeakSpots.isEmpty {
            sectionHeader("Recurring weak spots", icon: "arrow.up.circle.fill", tint: Theme.brand)
            VStack(spacing: 8) {
                ForEach(debrief.recurringWeakSpots) { ws in
                    weakSpotRow(ws, leadingIcon: "arrow.up", trailing: "seen \(ws.occurrenceCount)\u{00D7}")
                }
            }
        }

        if !debrief.suggestedDrills.isEmpty {
            sectionHeader("Suggested drills", icon: "sparkles")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(debrief.suggestedDrills, id: \.self) { drill in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Theme.brand)
                            .padding(.top, 7)
                        Text(drill)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        if !debrief.allTurns.isEmpty {
            sectionHeader("Transcript", icon: "text.bubble.fill")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(debrief.allTurns) { turn in
                    HStack(alignment: .top, spacing: 10) {
                        Text(turn.speaker == .user ? "You" : "AI")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(turn.speaker == .user ? Theme.brand : .secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(turn.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(turn.speaker == .user ? Theme.brand.opacity(0.06) : Theme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint == .primary ? Theme.brand : tint)
            Text(title).font(Theme.sectionTitle)
        }
        .padding(.top, 4)
    }

    private func metricCard(_ label: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Theme.brand)
                Spacer()
            }
            Text(value).font(Theme.metricNumber)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func weakSpotRow(_ ws: WeakSpot, leadingIcon: String, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: leadingIcon)
                .font(.caption)
                .foregroundStyle(Theme.brand)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.pattern)
                Text(ws.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
