import SwiftUI
import Core

public struct LiveSessionView: View {
    @ObservedObject var viewModel: LiveSessionViewModel
    let onEnd: (UUID) -> Void

    public init(viewModel: LiveSessionViewModel, onEnd: @escaping (UUID) -> Void) {
        self.viewModel = viewModel
        self.onEnd = onEnd
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            weakSpotTargets
            Divider()
            transcriptScroll
            if let err = viewModel.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            controlBar
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.domainColor(viewModel.scenario.domain).opacity(0.20))
                    .frame(width: 44, height: 44)
                Image(systemName: Theme.domainIcon(viewModel.scenario.domain))
                    .foregroundStyle(Theme.domainColor(viewModel.scenario.domain))
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.scenario.title).font(Theme.sectionTitle)
                Text(viewModel.scenario.persona)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    modeBadge
                    if viewModel.isListening {
                        Label("Listening — speak now", systemImage: "waveform")
                            .font(Theme.chip)
                            .foregroundStyle(.green)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    } else if viewModel.isProcessing {
                        Label("Working...", systemImage: "ellipsis")
                            .font(Theme.chip)
                            .foregroundStyle(Theme.brand)
                    } else if viewModel.isActive {
                        Label("Your turn", systemImage: "circle.fill")
                            .font(Theme.chip)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(18)
    }

    /// Coach mode is told to watch for the user's recurring mistakes; showing
    /// them makes that visible instead of implicit.
    @ViewBuilder
    private var weakSpotTargets: some View {
        if viewModel.mode == .coach, !viewModel.activeWeakSpots.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Watching for your recurring mistakes", systemImage: "scope")
                    .font(Theme.chip)
                    .foregroundStyle(.secondary)
                FlowingChips(weakSpots: viewModel.activeWeakSpots)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private var modeBadge: some View {
        let isCoach = viewModel.mode == .coach
        return Label(isCoach ? "Coach mode" : "Flow mode", systemImage: isCoach ? "lightbulb.fill" : "wind")
            .font(Theme.chip)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((isCoach ? Theme.highlight : Theme.brand).opacity(0.15))
            .foregroundStyle(isCoach ? Theme.highlight : Theme.brand)
            .clipShape(Capsule())
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.transcript) { turn in
                        TurnBubbleView(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)
            .background(Theme.mutedSurface)
            .onChange(of: viewModel.transcript.count) { _, _ in
                if let last = viewModel.transcript.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleListening() }
            } label: {
                Label(
                    viewModel.isListening ? "Stop & send" : "Push to talk",
                    systemImage: viewModel.isListening ? "stop.fill" : "mic.fill"
                )
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.isListening ? .red : Theme.brand)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!viewModel.isActive || viewModel.isProcessing)

            Text(viewModel.isListening
                 ? "Tap again when you're done — or just pause and it sends itself."
                 : "Tap to record your reply. Space works too.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task {
                    if let id = try? await viewModel.end() {
                        onEnd(id)
                    }
                }
            } label: {
                Label("End session", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.isActive)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardSurface)
    }
}

/// Wraps the weak-spot chips onto as many rows as they need — with five of
/// them, a single HStack would push the header wider than the window.
private struct FlowingChips: View {
    let weakSpots: [WeakSpot]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(weakSpots)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    row(chunk)
                }
            }
        }
    }

    private var chunks: [[WeakSpot]] {
        stride(from: 0, to: weakSpots.count, by: 2).map {
            Array(weakSpots[$0..<min($0 + 2, weakSpots.count)])
        }
    }

    private func row(_ items: [WeakSpot]) -> some View {
        HStack(spacing: 6) {
            ForEach(items) { chip($0) }
        }
    }

    private func chip(_ weakSpot: WeakSpot) -> some View {
        let color = Theme.correctionColor(weakSpot.category)
        return HStack(spacing: 4) {
            Image(systemName: Theme.correctionIcon(weakSpot.category))
                .font(.system(size: 9))
            Text(weakSpot.pattern)
                .lineLimit(1)
            if weakSpot.occurrenceCount > 1 {
                Text("\(weakSpot.occurrenceCount)x")
                    .font(.system(size: 9, design: .rounded).weight(.bold))
                    .opacity(0.75)
            }
        }
        .font(Theme.chip)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct TurnBubbleView: View {
    let turn: LiveSessionViewModel.DisplayTurn

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if turn.speaker == .user { Spacer(minLength: 40) }
            if turn.speaker == .ai { avatar }
            VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 6) {
                Text(turn.speaker == .user ? "You" : "AI")
                    .font(.caption).foregroundStyle(.secondary)
                Text(highlightedText)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(turn.speaker == .user ? Theme.brand.opacity(0.18) : Theme.cardSurface)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ForEach(turn.corrections.indices, id: \.self) { i in
                    correctionRow(turn.corrections[i])
                }
            }
            .frame(maxWidth: 480, alignment: turn.speaker == .user ? .trailing : .leading)
            if turn.speaker == .user { avatar }
            if turn.speaker == .ai { Spacer(minLength: 40) }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(turn.speaker == .user ? Theme.brand.opacity(0.18) : Color.gray.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: turn.speaker == .user ? "person.fill" : "sparkles")
                .font(.caption)
                .foregroundStyle(turn.speaker == .user ? Theme.brand : .secondary)
        }
    }

    private func correctionRow(_ correction: Correction) -> some View {
        let color = Theme.correctionColor(correction.category)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: Theme.correctionIcon(correction.category))
                .foregroundStyle(color)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(Theme.correctionLabel(correction.category).uppercased())
                    .font(.system(size: 9, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
                Text(correction.message)
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Marks the wording a correction called out, so the mistake is visible in
    /// the sentence the user actually said rather than only described below it.
    /// Falls back to plain text when nothing matched.
    private var highlightedText: AttributedString {
        var attributed = AttributedString(turn.text)
        for correction in turn.corrections {
            guard let phrase = correction.offendingText, !phrase.isEmpty,
                  let range = attributed.range(of: phrase, options: .caseInsensitive)
            else { continue }
            let color = Theme.correctionColor(correction.category)
            attributed[range].foregroundColor = color
            attributed[range].underlineStyle = .single
            attributed[range].backgroundColor = color.opacity(0.18)
        }
        return attributed
    }
}
