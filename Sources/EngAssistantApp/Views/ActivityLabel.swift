import SwiftUI

/// A status label that shows it's alive: the icon pulses and the trailing dots
/// cycle. Used wherever the app is busy and the wait is long enough that a
/// static "Working..." reads as a freeze — LLM turns take seconds.
///
/// The animation is driven by `TimelineView` rather than a repeating
/// `withAnimation`, so it stays in step no matter when the label appears and
/// stops dead when the view goes away.
struct ActivityLabel: View {
    let text: String
    let systemImage: String
    var color: Color = Theme.brand
    var font: Font = Theme.chip
    /// Seconds per dot step. One dot every ~0.4s reads as working, not frantic.
    var step: Double = 0.4

    var body: some View {
        TimelineView(.periodic(from: .now, by: step)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / step)
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .opacity(breathe(tick))
                Text(text)
                // Reserving all three dots' width stops the label from
                // shuffling its neighbours as the count changes.
                Text(String(repeating: "•", count: dotCount(tick)))
                    .frame(width: dotsWidth, alignment: .leading)
                    .opacity(0.75)
            }
            .font(font)
            .foregroundStyle(color)
            .animation(.easeInOut(duration: step), value: tick)
        }
        .accessibilityLabel("\(text) in progress")
    }

    private var dotsWidth: CGFloat { 18 }

    private func dotCount(_ tick: Int) -> Int {
        // 1, 2, 3, 1, 2, 3 …
        tick % 3 + 1
    }

    private func breathe(_ tick: Int) -> Double {
        // Two-step fade, offset from the dots so the whole thing doesn't blink
        // in unison.
        tick % 2 == 0 ? 1.0 : 0.45
    }
}

/// The listening counterpart: a row of bars that rise and fall, so an open mic
/// looks different from a busy spinner at a glance.
struct ListeningIndicator: View {
    var color: Color = Theme.success
    var font: Font = Theme.chip
    private let step = 0.18
    private let barCount = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: step)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / step)
            HStack(spacing: 5) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(width: 2.5, height: height(tick: tick, index: index))
                    }
                }
                .frame(height: 14)
                .animation(.easeInOut(duration: step), value: tick)
                Text("Listening — speak now")
            }
            .font(font)
            .foregroundStyle(color)
        }
        .accessibilityLabel("Listening, speak now")
    }

    /// Each bar is offset in the cycle so the row travels rather than throbs.
    private func height(tick: Int, index: Int) -> CGFloat {
        let phase = (tick + index) % 4
        switch phase {
        case 0: return 5
        case 1: return 10
        case 2: return 14
        default: return 9
        }
    }
}
