import Testing
import AppKit
import Foundation
@testable import EngAssistantApp

/// The bundle shipped with no icon for its whole life, which fails silently —
/// macOS just substitutes the generic placeholder. These assert the artefact
/// exists and is usable, so it can't quietly go missing again.
@Suite struct AppIconTests {
    /// Walks up from the test binary to the repo root. `#filePath` is the
    /// reliable anchor: the working directory during `swift test` isn't.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // .../Tests/EngAssistantAppTests/AppIconTests.swift
            .deletingLastPathComponent()          // .../Tests/EngAssistantAppTests
            .deletingLastPathComponent()          // .../Tests
            .deletingLastPathComponent()          // repo root
    }

    private static var iconURL: URL {
        repoRoot.appendingPathComponent("Resources/AppIcon.icns")
    }

    @Test func iconIsCommittedToTheRepo() {
        #expect(FileManager.default.fileExists(atPath: Self.iconURL.path),
                "Resources/AppIcon.icns is missing — run: swift scripts/make-app-icon.swift")
    }

    @Test func iconIsAUsableImage() throws {
        let image = try #require(NSImage(contentsOf: Self.iconURL),
                                 "AppIcon.icns could not be decoded")
        #expect(image.size.width > 0)
        #expect(image.size.height == image.size.width, "icon should be square")
    }

    /// The Dock, Finder, and the app switcher all pull different sizes out of
    /// the same file, so every rung of the ladder has to be present.
    @Test func iconCarriesEverySizeMacOSAsksFor() throws {
        let image = try #require(NSImage(contentsOf: Self.iconURL))
        let widths = Set(image.representations.map { $0.pixelsWide })
        for required in [16, 32, 64, 128, 256, 512, 1024] {
            #expect(widths.contains(required), "no \(required)px representation; have \(widths.sorted())")
        }
    }

    /// Info.plist names the icon, and the build script copies it in. If the
    /// key and the filename ever disagree, the app silently loses its icon.
    @Test func infoPlistNamesTheIconFile() throws {
        let plistURL = Self.repoRoot.appendingPathComponent("Sources/EngAssistantApp/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist["CFBundleIconName"] as? String == "AppIcon")
    }

    /// The brand mark should say "language", not "messaging".
    @Test func brandSymbolExistsOnThisSystem() {
        #expect(NSImage(systemSymbolName: Theme.appIconSymbol, accessibilityDescription: nil) != nil,
                "\(Theme.appIconSymbol) isn't available — the brand mark would render blank")
    }

    @Test func brandSymbolIsACharacterBubble() {
        #expect(Theme.appIconSymbol == "character.bubble.fill")
    }
}
