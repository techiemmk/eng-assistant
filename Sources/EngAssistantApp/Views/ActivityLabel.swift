import SwiftUI

/// A status label for work that takes long enough that a completely static
/// message reads as a freeze — LLM turns take seconds.
///
/// The words never move and never re-render. Only three fixed dots change
/// opacity in sequence, so the layout is constant: no reflow, no crossfade.
/// Getting that wrong is what made an earlier version look like the text was
/// dancing — it animated the whole row (SwiftUI can't interpolate text, so it
/// crossfades) and grew the dot string, which reflowed everything beside it.
struct ActivityLabel: View {
    let text: String
    let systemImage: String
    var color: Color = Theme.brand
    var font: Font = Theme.chip
    /// Seconds per dot step. One step every ~0.45s reads as working, not frantic.
    var step: Double = 0.45

    private let dotCount = 3

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
            dots
        }
        .font(font)
        .foregroundStyle(color)
        // The label as a whole is one accessibility element; the dots are
        // decoration and would otherwise be read out as three blank images.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) in progress")
    }

    /// Shapes rather than "•" glyphs, so the size doesn't depend on the font
    /// metrics and the row can't be pushed around by a larger type scale.
    private var dots: some View {
        TimelineView(.periodic(from: .now, by: step)) { context in
            let active = Int(context.date.timeIntervalSinceReferenceDate / step) % dotCount
            HStack(spacing: 3) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .opacity(index == active ? 1.0 : 0.28)
                }
            }
        }
        // Reserve the exact final size so the dots occupy the same box forever.
        .frame(width: CGFloat(dotCount) * 4 + CGFloat(dotCount - 1) * 3, height: 4)
    }
}

/// The listening counterpart: a row of bars that rise and fall, so an open mic
/// looks different from a busy spinner at a glance. As above, the caption sits
/// outside the timeline so only the bars move.
struct ListeningIndicator: View {
    var color: Color = Theme.success
    var font: Font = Theme.chip
    private let step = 0.18
    private let barCount = 4

    var body: some View {
        HStack(spacing: 6) {
            bars
            Text("Listening — speak now")
        }
        .font(font)
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening, speak now")
    }

    private var bars: some View {
        TimelineView(.periodic(from: .now, by: step)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / step)
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height(tick: tick, index: index))
                }
            }
            .animation(.easeInOut(duration: step), value: tick)
        }
        // Fixed box: the bars change height inside it, they don't resize it.
        .frame(width: CGFloat(barCount) * 2.5 + CGFloat(barCount - 1) * 2, height: 14)
    }

    /// Each bar is offset in the cycle so the row travels rather than throbs.
    private func height(tick: Int, index: Int) -> CGFloat {
        switch (tick + index) % 4 {
        case 0: return 5
        case 1: return 10
        case 2: return 14
        default: return 9
        }
    }
}
