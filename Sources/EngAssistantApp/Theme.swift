import SwiftUI
import AppKit
import Core

/// Visual design tokens — used by every view so the look stays consistent.
///
/// Both the type scale and the palette live here on purpose. Views should never
/// reach for a raw `.font(.caption)` or `.foregroundStyle(.secondary)`: the
/// first makes text size untunable, and the second bypasses the light/dark
/// pairs defined below.
public enum Theme {
    /// Display name shown in window titles, nav bars, and onboarding.
    public static let appName = "Jul EngAssistant"

    /// SF Symbol used as the brand mark (sidebar, launch screen, onboarding
    /// hero, bootstrap error). A speech bubble holding a character, matching
    /// the app icon: two generic chat bubbles said "messaging", not "language".
    public static let appIconSymbol = "character.bubble.fill"

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
    // Every colour is a dynamic pair. `NSColor(name:dynamicProvider:)` resolves
    // per appearance at draw time, which keeps Theme's API static while still
    // following the appearance the user picked — no environment plumbing and no
    // second set of tokens. The light and dark variants are each held to 4.5:1
    // against their own card surface by ThemeLightPaletteTests.

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }

    /// Primary brand colour — a confident indigo, lightened in dark mode so it
    /// stays legible against a dark card.
    public static let brand = dynamic(
        light: (0.35, 0.27, 0.85),
        dark: (0.66, 0.59, 0.99)
    )

    /// The onboarding hero puts white text on this, so both stops have to clear
    /// 4.5:1 against white in either appearance — hence fixed, not dynamic.
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
    /// reaches ~3.7:1 on white, so the light variant is deepened considerably;
    /// dark mode can afford the brighter tone.
    public static let highlight = dynamic(
        light: (0.70, 0.35, 0.02),
        dark: (0.98, 0.70, 0.32)
    )

    /// Cards sit above the page: white on off-white in light mode, and one step
    /// lighter than the page in dark mode.
    public static let cardSurface = dynamic(
        light: (1.00, 1.00, 1.00),
        dark: (0.17, 0.17, 0.18)
    )
    public static let mutedSurface = dynamic(
        light: (0.957, 0.957, 0.973),
        dark: (0.11, 0.11, 0.12)
    )
    public static let separator = dynamic(
        light: (0.85, 0.85, 0.87),
        dark: (0.30, 0.30, 0.32)
    )

    public static let textPrimary = dynamic(
        light: (0.11, 0.11, 0.13),
        dark: (0.95, 0.95, 0.97)
    )
    public static let textSecondary = dynamic(
        light: (0.38, 0.38, 0.42),
        dark: (0.68, 0.68, 0.71)
    )

    public static let success = dynamic(
        light: (0.10, 0.48, 0.28),
        dark: (0.38, 0.84, 0.55)
    )
    public static let warning = dynamic(
        light: (0.62, 0.38, 0.02),
        dark: (0.98, 0.74, 0.28)
    )
    public static let danger = dynamic(
        light: (0.78, 0.16, 0.21),
        dark: (0.99, 0.50, 0.53)
    )

    // MARK: - Correction categories

    /// Grammar gets the loudest treatment — it's the category the user most
    /// wants pointed at, and the only one the persona prompt always requires.
    public static func correctionColor(_ category: WeakSpotCategory?) -> Color {
        switch category {
        case .grammar: return danger
        case .vocab: return dynamic(light: (0.13, 0.42, 0.75), dark: (0.48, 0.74, 0.99))
        case .filler: return dynamic(light: (0.42, 0.42, 0.47), dark: (0.70, 0.70, 0.75))
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

    // MARK: - Collection & domain icons

    public static func collectionIcon(_ collection: PracticeViewModel.Collection) -> String {
        switch collection {
        case .all: return "square.grid.2x2"
        case .domain(let domain): return domainIcon(domain)
        }
    }

    public static func domainIcon(_ domain: ScenarioDomain) -> String {
        switch domain {
        case .homeopathy: return "leaf.fill"
        case .medical: return "stethoscope"
        case .networking: return "person.2.wave.2.fill"
        case .social: return "party.popper.fill"
        case .corporate: return "briefcase.fill"
        }
    }

    /// Five distinct hues, each held to 4.5:1 against its own card surface in
    /// both appearances by `ThemePaletteTests`.
    public static func domainColor(_ domain: ScenarioDomain) -> Color {
        switch domain {
        case .homeopathy: return dynamic(light: (0.08, 0.42, 0.20), dark: (0.45, 0.85, 0.52))
        case .medical: return dynamic(light: (0.04, 0.38, 0.42), dark: (0.35, 0.85, 0.88))
        case .networking: return dynamic(light: (0.72, 0.33, 0.12), dark: (0.99, 0.65, 0.42))
        case .social: return dynamic(light: (0.48, 0.33, 0.88), dark: (0.75, 0.63, 0.99))
        case .corporate: return dynamic(light: (0.13, 0.45, 0.75), dark: (0.45, 0.72, 0.99))
        }
    }
}

public extension AppearancePreference {
    /// Always a concrete appearance — the app never leaves the choice to the
    /// Mac. Applied at the application level rather than via
    /// `preferredColorScheme`, so this is the only mapping needed.
    var nsAppearance: NSAppearance {
        switch self {
        case .light: return NSAppearance(named: .aqua)!
        case .dark: return NSAppearance(named: .darkAqua)!
        }
    }
}
