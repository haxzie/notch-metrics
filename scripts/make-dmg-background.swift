#!/usr/bin/env swift
import AppKit
import Foundation

/// Draws the installer background.
///
/// A **multi-representation TIFF**, not an @2x PNG pair. `@2x` is a convention
/// of the app-bundle image loader, not of the Finder — on a Retina display the
/// Finder silently takes the 1x and scales it, which on a soft gradient looks
/// like nothing is wrong at all.
///
/// The icon coordinates below are the same ones make-dmg.sh passes to
/// create-dmg. Keeping them in one place is why this is a script rather than a
/// committed image: art and layout cannot drift apart.

let width = 660.0
let height = 420.0
let iconY = 250.0
let appX = 165.0
let dropX = 495.0

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let pixelsWide = Int(width * scale)
    let pixelsHigh = Int(height * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // The brand gradient, darkened — the window has to stay a background, and
    // the two icons sit on top of it.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.07, green: 0.06, blue: 0.11, alpha: 1),
        NSColor(srgbRed: 0.14, green: 0.06, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.08, blue: 0.06, alpha: 1),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 35)

    // The arrow between the app and the Applications alias. Drawn from the
    // same constants create-dmg places the icons with, so it always points at
    // the right thing.
    let arrow = NSBezierPath()
    // The canvas origin is bottom-left; the icon Y that create-dmg takes is
    // measured from the top.
    let y = height - iconY
    arrow.move(to: NSPoint(x: appX + 95, y: y))
    arrow.line(to: NSPoint(x: dropX - 95, y: y))
    arrow.lineWidth = 3
    NSColor.white.withAlphaComponent(0.35).setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: dropX - 95, y: y))
    head.line(to: NSPoint(x: dropX - 110, y: y + 8))
    head.line(to: NSPoint(x: dropX - 110, y: y - 8))
    head.close()
    NSColor.white.withAlphaComponent(0.35).setFill()
    head.fill()

    let title = "Drag Notch Metrics to your Applications folder"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.55),
    ]
    let size = title.size(withAttributes: attributes)
    title.draw(at: NSPoint(x: (width - size.width) / 2, y: 54), withAttributes: attributes)

    return rep
}

let reps = [draw(scale: 1), draw(scale: 2)]
guard let data = NSBitmapImageRep.representationOfImageReps(
    in: reps, using: .tiff, properties: [:])
else {
    FileHandle.standardError.write(Data("could not encode the TIFF\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "apps/mac/Resources/dmg-background.tiff")
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output)
print("wrote \(output.path) (1x and 2x)")
