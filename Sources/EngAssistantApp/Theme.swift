import SwiftUI
import Core

/// Visual design tokens — used by every view so the look stays consistent.
public enum Theme {
    /// Display name shown in window titles, nav bars, and onboarding.
    public static let appName = "Jul EngAssistant"

    /// SF Symbol used as the brand mark (onboarding hero + bootstrap error).
    public static let appIconSymbol = "bubble.left.and.bubble.right.fill"

    // MARK: - Colors
    /// Primary brand color — a confident indigo. Reads well in light and dark mode.
    public static let brand = Color(red: 0.40, green: 0.32, blue: 0.93)

    /// Subtle gradient for backgrounds & hero sections.
    public static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.40, green: 0.32, blue: 0.93),
            Color(red: 0.62, green: 0.38, blue: 0.95),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm accent for tips / corrections / highlights.
    public static let highlight = Color(red: 1.00, green: 0.58, blue: 0.20)

    /// Soft surface tint for card backgrounds (auto-adapts to dark mode).
    public static let cardSurface = Color(nsColor: .controlBackgroundColor)
    public static let mutedSurface = Color(nsColor: .windowBackgroundColor)

    // MARK: - Fonts
    public static let appTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let sectionTitle = Font.system(.title2, design: .rounded, weight: .semibold)
    public static let cardTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let metricNumber = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    public static let chip = Font.system(.caption, design: .rounded, weight: .medium)

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
        case .work: return Color(red: 0.20, green: 0.55, blue: 0.85)
        case .networking: return Color(red: 0.95, green: 0.50, blue: 0.30)
        case .social: return Color(red: 0.55, green: 0.40, blue: 0.95)
        }
    }
}
