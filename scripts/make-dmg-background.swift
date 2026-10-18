#!/usr/bin/env swift
import AppKit
import Foundation

/// Draws the installer background, and writes the layout make-dmg.sh places
/// the icons with.
///
/// A **multi-representation TIFF**, not an @2x PNG pair. `@2x` is a convention
/// of the app-bundle image loader, not of the Finder — on a Retina display the
/// Finder silently takes the 1x and scales it, which on a soft gradient looks
/// like nothing is wrong at all.
///
/// The icon coordinates used to be written out twice, here and in make-dmg.sh,
/// held together by a comment. They are now emitted as a shell fragment that
/// make-dmg.sh sources, so moving an icon moves the arrow that points at it.

let width = 660.0
let height = 420.0

/// What the window actually shows.
///
/// `--window-size` counts the whole window, title bar included, and the Finder
/// anchors the picture at the top of the *content* view — so the last stripe of
/// the image falls off the bottom and every vertical measurement taken against
/// `height` lands low. Centring against 420 is what put the icons two thirds of
/// the way down a window with an empty band above them.
///
/// Measured off a mounted image rather than assumed: 420 of window leaves 388
/// of content on Tahoe.
let titleBar = 32.0
let visible = height - titleBar

let iconSize = 128.0
/// Room for the name the Finder draws under each icon, which is not ours to
/// place and has to be budgeted for anyway.
let labelHeight = 17.0
let labelGap = 5.0
let captionSize = 13.0

/// The icon and the name under it, centred in the window as one thing. Centring
/// the icon alone hangs the pair low, because the name only ever grows downward.
let iconBlock = iconSize + labelGap + labelHeight
let iconY = (visible - iconBlock) / 2 + iconSize / 2

/// The caption sits near the floor rather than under the icons: it is a footer,
/// and tucked just beneath the names it competes with them for the same glance.
let captionTop = visible - 34 - captionSize

/// Symmetric about the middle, so the pair reads as one object rather than as
/// two things that happen to be in the same window.
let appX = width / 2 - 165
let dropX = width / 2 + 165

// The ramp off the app icon itself, sampled along its stroke: magenta at the
// bottom left through coral to amber at the top right. The arrow carries it,
// so the one saturated thing on a white window is the brand.
let brandStart = NSColor(srgbRed: 0.894, green: 0.286, blue: 0.733, alpha: 1)
let brandMid = NSColor(srgbRed: 0.941, green: 0.498, blue: 0.478, alpha: 1)
let brandEnd = NSColor(srgbRed: 0.996, green: 0.753, blue: 0.090, alpha: 1)

/// A wide, soft wash of one colour. Several of these are what makes the white
/// warm rather than clinical, at an alpha low enough that the icons still read
/// as the brightest thing in the window.
func wash(_ color: NSColor, at centre: NSPoint, radius: CGFloat, alpha: CGFloat) {
    let gradient = NSGradient(colors: [
        color.withAlphaComponent(alpha),
        color.withAlphaComponent(0),
    ])!
    gradient.draw(
        fromCenter: centre, radius: 0,
        toCenter: centre, radius: radius,
        options: [])
}

/// Weight of the arrow's stroke. The mark's own line is heavy for its length
/// and that is most of what makes it recognisable; a hairline with the right
/// colours on it reads as a generic arrow.
let strokeWidth = 9.0

/// The arrow, drawn the way the mark draws its own.
///
/// The head is **two strokes meeting at a rounded corner**, not a filled
/// triangle — open barbs at a right angle to each other, symmetric about the
/// shaft, with the same cap, join and weight as the line they finish. That
/// corner is the one shape the app icon is, and a solid triangle on the end of
/// a thin rule was the generic arrow any installer could have had.
func arrowPath(from x1: CGFloat, to x2: CGFloat, y: CGFloat) -> NSBezierPath {
    /// How far back each barb reaches. Measured along itself, so the two sit
    /// at 45° either side and the head stays as wide as it is long.
    let barb = 25.0
    let reach = barb / 2.0.squareRoot()

    let path = NSBezierPath()
    path.move(to: NSPoint(x: x1, y: y))
    path.line(to: NSPoint(x: x2, y: y))

    path.move(to: NSPoint(x: x2 - reach, y: y + reach))
    path.line(to: NSPoint(x: x2, y: y))
    path.line(to: NSPoint(x: x2 - reach, y: y - reach))
    return path
}

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

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)

    // Not flat white. A window that is one value edge to edge looks unfinished
    // next to the Finder's own chrome, and the icons have nothing to sit on.
    NSGradient(colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.965, green: 0.961, blue: 0.976, alpha: 1),
    ])!.draw(in: canvas, angle: -90)

    // The canvas origin is bottom-left; every layout constant above is measured
    // from the top, the way create-dmg takes them.
    let rowY = height - iconY

    // Barely there, and that is the point: white was the ask. These are here
    // so the window is not a flat sheet under two icons, and at this alpha you
    // notice them only by covering them up.
    wash(brandStart, at: NSPoint(x: appX, y: rowY), radius: 240, alpha: 0.05)
    wash(brandEnd, at: NSPoint(x: dropX, y: rowY), radius: 240, alpha: 0.045)

    // Stroked into an outline first, then used as a clip for the gradient.
    // `NSBezierPath` can only stroke one flat colour, and the whole point of
    // this arrow is that the brand ramp runs along it the way it runs along
    // the mark — magenta leaving the app, amber arriving at the folder.
    let arrow = arrowPath(from: appX + 100, to: dropX - 98, y: rowY)
    let outline = arrow.cgPath.copy(
        strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.addPath(outline)
    context.clip()
    NSGradient(colors: [brandStart, brandMid, brandEnd])!
        .draw(in: outline.boundingBoxOfPath, angle: 0)
    context.restoreGState()

    let caption = "Drag Notch Metrics to your Applications folder"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: captionSize, weight: .medium),
        // Dark on white. The old copy was white on a dark gradient, and so were
        // the Finder's own icon labels — except the Finder draws those dark in
        // a disk image whatever the background is, which is why "NotchMetrics"
        // and "Applications" were charcoal on near-black.
        .foregroundColor: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 0.62),
    ]
    let size = caption.size(withAttributes: attributes)
    caption.draw(
        at: NSPoint(x: (width - size.width) / 2, y: height - captionTop - captionSize),
        withAttributes: attributes)

    return rep
}

let reps = [draw(scale: 1), draw(scale: 2)]
guard
    let data = NSBitmapImageRep.representationOfImageReps(
        in: reps, using: .tiff, properties: [:])
else {
    FileHandle.standardError.write(Data("could not encode the TIFF\n".utf8))
    exit(1)
}

let output =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "apps/mac/Resources/dmg-background.tiff")
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output)
print("wrote \(output.path) (1x and 2x)")

// Sourced by make-dmg.sh. Generated beside the image it belongs to, so the
// arrow drawn above and the icons the Finder places can only ever agree.
let layout = """
# Generated by scripts/make-dmg-background.swift. Do not edit.
#
# Where the icons go in the window the background was drawn for. Regenerate
# both together: moving an icon here without redrawing leaves an arrow
# pointing at nothing.
DMG_WINDOW_W=\(Int(width))
DMG_WINDOW_H=\(Int(height))
DMG_ICON_SIZE=\(Int(iconSize))
DMG_ICON_Y=\(Int(iconY.rounded()))
DMG_APP_X=\(Int(appX.rounded()))
DMG_DROP_X=\(Int(dropX.rounded()))

"""
let layoutURL = output.deletingLastPathComponent().appendingPathComponent("dmg-layout.sh")
try layout.write(to: layoutURL, atomically: true, encoding: .utf8)
print("wrote \(layoutURL.path)")
