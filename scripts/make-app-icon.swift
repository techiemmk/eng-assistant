#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns. Run from the repo root:
//
//     swift scripts/make-app-icon.swift
//
// The icon is drawn in code rather than committed as a binary blob alone, so
// the design is reviewable and a colour change is a one-line edit. The .icns it
// produces is committed too, so building the app doesn't require running this.
//
// Design: the app is for practising *spoken* English, so the mark is a speech
// bubble with a letter in it — talking plus the alphabet. The gradient matches
// Theme.gradientStops exactly, so the icon, the onboarding hero and the launch
// screen are all the same indigo.

import AppKit
import Foundation

// MARK: - Brand

/// Kept in sync with `Theme.gradientStops` in Sources/EngAssistantApp/Theme.swift.
let gradientTop = NSColor(srgbRed: 0.38, green: 0.30, blue: 0.90, alpha: 1)
let gradientBottom = NSColor(srgbRed: 0.50, green: 0.30, blue: 0.88, alpha: 1)
/// The letter sits in the bubble in a deeper indigo than the background so it
/// reads as ink on paper rather than a hole in the gradient.
let letterColor = NSColor(srgbRed: 0.27, green: 0.20, blue: 0.70, alpha: 1)

// MARK: - Drawing

/// Draws the icon at `size` points into a bitmap.
///
/// Proportions follow Apple's macOS grid: the shape occupies the middle ~80% of
/// the canvas, leaving the margin the system expects for alignment with other
/// app icons in the Dock.
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)

    // --- the squircle ---
    let inset = size * 0.10
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // 0.225 of the shape's width is the macOS 11+ corner proportion.
    let plateRadius = plate.width * 0.225
    let plateShape = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    context.cgContext.saveGState()
    plateShape.addClip()
    NSGradient(starting: gradientTop, ending: gradientBottom)!
        .draw(in: plate, angle: -60)
    context.cgContext.restoreGState()

    // --- the speech bubble ---
    // Sized so the letter inside it is still a distinct mark at 32pt, where the
    // whole icon is about the width of a fingernail.
    let bubbleWidth = size * 0.54
    let bubbleHeight = size * 0.41
    let bubble = NSRect(
        x: (size - bubbleWidth) / 2,
        y: size * 0.33,
        width: bubbleWidth,
        height: bubbleHeight
    )
    let bubbleRadius = bubbleHeight * 0.30

    let bubbleShape = NSBezierPath(
        roundedRect: bubble,
        xRadius: bubbleRadius,
        yRadius: bubbleRadius
    )

    // The tail is what makes the rounded rectangle read as speech rather than
    // as a card. A symmetric taper straight down from the lower-left, curved on
    // both flanks so it looks drawn rather than clipped — an asymmetric wedge
    // reads as a glitch at icon sizes.
    let tailRootX = bubble.minX + bubble.width * 0.20
    let tailRootWidth = bubble.width * 0.22
    let tailDepth = bubble.height * 0.30
    let apex = NSPoint(x: tailRootX + tailRootWidth * 0.18, y: bubble.minY - tailDepth)

    let tail = NSBezierPath()
    // Start a hair inside the bubble so the two fills merge without a seam.
    tail.move(to: NSPoint(x: tailRootX, y: bubble.minY + bubbleRadius * 0.5))
    tail.curve(
        to: apex,
        controlPoint1: NSPoint(x: tailRootX, y: bubble.minY - tailDepth * 0.45),
        controlPoint2: NSPoint(x: apex.x - tailRootWidth * 0.10, y: apex.y)
    )
    tail.curve(
        to: NSPoint(x: tailRootX + tailRootWidth, y: bubble.minY + bubbleRadius * 0.5),
        controlPoint1: NSPoint(x: apex.x + tailRootWidth * 0.34, y: apex.y + tailDepth * 0.10),
        controlPoint2: NSPoint(x: tailRootX + tailRootWidth, y: bubble.minY - tailDepth * 0.35)
    )
    tail.close()
    bubbleShape.append(tail)

    NSColor.white.setFill()
    bubbleShape.fill()

    // --- the letter ---
    // A single "A" rather than "Aa" or "ABC": at 16pt anything more collapses
    // into a grey smudge, and one letterform still says "alphabet".
    let fontSize = bubbleHeight * 0.74
    let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let roundedFont = NSFontDescriptor(name: baseFont.fontName, size: fontSize)
        .withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: fontSize) }
        ?? baseFont

    let letter = NSAttributedString(
        string: "A",
        attributes: [.font: roundedFont, .foregroundColor: letterColor]
    )
    let letterSize = letter.size()
    letter.draw(at: NSPoint(
        x: bubble.midX - letterSize.width / 2,
        // Nudged up slightly: the bubble's visual centre sits above its
        // geometric centre once the tail is attached.
        y: bubble.midY - letterSize.height / 2 + bubble.height * 0.04
    ))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

/// The sizes `iconutil` expects, as (points, scale) pairs.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
let resources = root.appendingPathComponent("Resources", isDirectory: true)

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

for variant in variants {
    let pixels = CGFloat(variant.points * variant.scale)
    let rep = renderIcon(size: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(pixels)px\n".utf8))
        exit(1)
    }
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try png.write(to: iconset.appendingPathComponent(name))
    print("  \(name)  (\(Int(pixels))px)")
}

// A standalone preview, handy for eyeballing the design without opening the app.
for previewSize in [512, 128, 32] {
    let preview = renderIcon(size: CGFloat(previewSize))
    if let png = preview.representation(using: .png, properties: [:]) {
        try png.write(to: root.appendingPathComponent("build/AppIcon-preview-\(previewSize).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("✓ wrote Resources/AppIcon.icns")
