import SwiftUI
import Core

/// Visual design tokens — used by every view so the look stays consistent.
///
/// Both the type scale and the palette live here on purpose. Views should never
/// reach for a raw `.font(.caption)` or `.foregroundStyle(.secondary)`: the
/// first makes text size untunable, and the second resolves against the system
/// appearance, which fights a deliberately light palette.
public enum Theme {
    /// Display name shown in window titles, nav bars, and onboarding.
    public static let appName = "Jul EngAssistant"

    /// SF Symbol used as the brand mark (onboarding hero + bootstrap error).
    public static let appIconSymbol = "bubble.left.and.bubble.right.fill"

    // MARK: - Type scale

    /// One knob for overall text size. Every font token below is multiplied by
    /// it, so nudging this is the whole job — 1.15 for a touch larger, 0.9 to
    /// go back toward macOS defaults.
    public static let textScale: CGFloat = 1.0

    /// Point sizes, kept separate from the `Font` values so they can be
    /// asserted on — `Font` is opaque, so a test can't read a size back out of
    /// one. Absolute rather than semantic (`.caption`, `.title2`) because
    /// macOS's semantic ramp tops out small — body is 13pt — and a personal
    /// practice app is read at arm's length, not skimmed.
    public enum Size {
        public static let appTitle: CGFloat = 30
        public static let sectionTitle: CGFloat = 22
        public static let cardTitle: CGFloat = 18
        /// Transcript text and anything else read word by word.
        public static let body: CGFloat = 17
        /// Supporting prose: persona blurbs, scenario descriptions, hints.
        public static let secondaryBody: CGFloat = 15
        public static let caption: CGFloat = 13
        /// Uppercase category labels above a correction.
        public static let microLabel: CGFloat = 11
        public static let metricNumber: CGFloat = 26

        /// What each token replaced, so a test can prove nothing shrank.
        /// These are AppKit's resolved sizes for the semantic styles the views
        /// used before: .largeTitle 26, .title2 17, .headline 13, .body 13,
        /// .callout 12, .caption 10, .caption2 10.
        public static let macOSDefaults: [(name: String, now: CGFloat, before: CGFloat)] = [
            ("appTitle", appTitle, 26),
            ("sectionTitle", sectionTitle, 17),
            ("cardTitle", cardTitle, 13),
            ("body", body, 13),
            ("secondaryBody", secondaryBody, 12),
            ("caption", caption, 10),
            ("microLabel", microLabel, 10),
            ("metricNumber", metricNumber, 17),
        ]

        public static func scaled(_ size: CGFloat) -> CGFloat {
            (size * textScale).rounded()
        }
    }

    private static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: Size.scaled(size), weight: weight, design: .rounded)
    }

    public static let appTitle = rounded(Size.appTitle, .bold)
    public static let sectionTitle = rounded(Size.sectionTitle, .semibold)
    public static let cardTitle = rounded(Size.cardTitle, .semibold)
    public static let body = rounded(Size.body)
    public static let secondaryBody = rounded(Size.secondaryBody)
    public static let caption = rounded(Size.caption)
    public static let captionBold = rounded(Size.caption, .semibold)
    public static let chip = rounded(Size.caption, .medium)
    public static let microLabel = rounded(Size.microLabel, .bold)
    public static let metricNumber = Font.system(
        size: Size.scaled(Size.metricNumber), weight: .bold, design: .rounded
    ).monospacedDigit()

    // MARK: - Icon sizes

    public static func icon(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: Size.scaled(size), weight: weight)
    }

    public static let heroIcon = icon(60)
    public static let screenIcon = icon(26)
    public static let rowIcon = icon(19)
    public static let inlineIcon = icon(12, weight: .medium)

    // MARK: - Colors
    //
    // The app is locked to a light appearance (see `preferredColorScheme` in
    // EngAssistantApp), so these are fixed light values rather than
    // `nsColor`-backed ones that would flip with the system setting.

    /// Primary brand color — a confident indigo. Darkened slightly from the
    /// original so it holds contrast as text on white.
    public static let brand = Color(red: 0.35, green: 0.27, blue: 0.85)

    /// Subtle gradient for backgrounds & hero sections. The onboarding hero
    /// puts white text on it, so both stops have to clear 4.5:1 against white
    /// — the lighter end used to land at 4.2:1.
    public static let gradientStops = [
        Color(red: 0.38, green: 0.30, blue: 0.90),
        Color(red: 0.50, green: 0.30, blue: 0.88),
    ]

    public static let brandGradient = LinearGradient(
        colors: gradientStops,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm accent for tips / corrections / highlights. A bright orange only
    /// reaches ~3.7:1 on white, so this is deepened to clear 4.5:1 — see
    /// ThemeLightPaletteTests.
    public static let highlight = Color(red: 0.70, green: 0.35, blue: 0.02)

    /// Cards sit on white; the page behind them is a soft off-white so the
    /// elevation reads without needing heavy shadows.
    public static let cardSurface = Color.white
    public static let mutedSurface = Color(red: 0.957, green: 0.957, blue: 0.973)
    public static let separator = Color(red: 0.85, green: 0.85, blue: 0.87)

    /// Text colors, explicit so they don't invert under system dark mode.
    public static let textPrimary = Color(red: 0.11, green: 0.11, blue: 0.13)
    public static let textSecondary = Color(red: 0.38, green: 0.38, blue: 0.42)

    /// Status colors, tuned for contrast on a light surface.
    public static let success = Color(red: 0.10, green: 0.48, blue: 0.28)
    public static let warning = Color(red: 0.62, green: 0.38, blue: 0.02)
    public static let danger = Color(red: 0.78, green: 0.16, blue: 0.21)

    // MARK: - Correction categories

    /// Grammar gets the loudest treatment — it's the category the user most
    /// wants pointed at, and the only one the persona prompt always requires.
    public static func correctionColor(_ category: WeakSpotCategory?) -> Color {
        switch category {
        case .grammar: return danger
        case .vocab: return Color(red: 0.13, green: 0.42, blue: 0.75)
        case .filler: return Color(red: 0.42, green: 0.42, blue: 0.47)
        case .fluency: return success
        case nil: return highlight
        }
    }

    public static func correctionIcon(_ category: WeakSpotCategory?) -> String {
        switch category {
        case .grammar: return "text.badge.xmark"
        case .vocab: return "character.book.closed.fill"
        case .filler: return "wind"
        case .fluency: return "waveform.path"
        case nil: return "lightbulb.fill"
        }
    }

    public static func correctionLabel(_ category: WeakSpotCategory?) -> String {
        switch category {
        case .grammar: return "Grammar"
        case .vocab: return "Word choice"
        case .filler: return "Filler"
        case .fluency: return "Fluency"
        case nil: return "Tip"
        }
    }

    // MARK: - Domain icons
    public static func domainIcon(_ domain: ScenarioDomain) -> String {
        switch domain {
        case .work: return "briefcase.fill"
        case .networking: return "person.2.wave.2.fill"
        case .social: return "party.popper.fill"
        }
    }

    public static func domainColor(_ domain: ScenarioDomain) -> Color {
        switch domain {
        case .work: return Color(red: 0.13, green: 0.45, blue: 0.75)
        case .networking: return Color(red: 0.72, green: 0.33, blue: 0.12)
        case .social: return Color(red: 0.48, green: 0.33, blue: 0.88)
        }
    }
}
