// Captures the expanded notch, one PNG per demo preset.
//
// A script rather than a shell one-liner because the only honest way to frame
// the panel is to ask the window server where it is: the notch window is
// borderless, sits above the menu bar and has no title, so `screencapture -R`
// against a guessed rectangle clips the shadow off one shot and includes a
// strip of wallpaper in the next.
//
//   swift scripts/shoot-notch.swift revenue analytics marketing developer ai
//
// Needs Screen Recording permission for whatever runs it, and a built Debug
// app — see the `mac-dev` skill.

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
let app = root.appendingPathComponent(
    "apps/mac/build/NotchMetrics.xcarchive/Products/Applications/NotchMetrics.app/Contents/MacOS/NotchMetrics")
let outDir = root.appendingPathComponent(".context/shots")

let presets = CommandLine.arguments.dropFirst().isEmpty
    ? ["revenue", "analytics", "marketing", "developer", "ai"]
    : Array(CommandLine.arguments.dropFirst())

func run(_ path: String, _ args: [String], env: [String: String]? = nil) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    if let env { process.environment = ProcessInfo.processInfo.environment.merging(env) { _, b in b } }
    try? process.run()
    process.waitUntilExit()
}

/// The notch panel: the app's largest on-screen window.
///
/// Matched by size rather than by name because the panel has no title, and by
/// owner rather than by pid because the launched process re-execs itself.
func notchWindow() -> (id: Int, rect: CGRect)? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let mine = info.compactMap { window -> (Int, CGRect)? in
        guard (window[kCGWindowOwnerName as String] as? String) == "Notch Metrics",
              let id = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return (id, rect)
    }
    return mine.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
}

/// Trims the fully transparent margin off a capture, in place.
///
/// The notch window is as tall as the screen it can grow into, so a two-row
/// panel leaves a few hundred rows of nothing under it. Cropping to the alpha
/// rather than to a measured height because the panel's own height depends on
/// the preset, and a fixed crop would shave the shoulders off a taller one.
func trimTransparentMargin(_ url: URL) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let data = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data)
    else { return }

    let (width, height, stride) = (image.width, image.height, image.bytesPerRow)
    // Little-endian BGRA, which is what the window server hands back: alpha is
    // the fourth byte of each pixel either way.
    let alphaOffset = 3
    // Not `> 0`. `screencapture -o` drops the window server's shadow but not
    // the panel's own, so a sixth of the capture below the panel is a barely
    // visible grey wash — which reads as dirt the moment the PNG is dropped
    // on anything other than the desktop it was taken over.
    let solid: UInt8 = 64
    var top = height, bottom = -1, left = width, right = -1

    for y in 0..<height {
        for x in 0..<width where bytes[y * stride + x * 4 + alphaOffset] >= solid {
            top = min(top, y)
            bottom = max(bottom, y)
            left = min(left, x)
            right = max(right, x)
        }
    }
    guard bottom >= top, right >= left else { return }

    let crop = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    guard let cropped = image.cropping(to: crop),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, cropped, nil)
    CGImageDestinationFinalize(destination)
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for preset in presets {
    run("/usr/bin/pkill", ["-x", "NotchMetrics"])
    Thread.sleep(forTimeInterval: 1)

    let process = Process()
    process.executableURL = app
    process.environment = ProcessInfo.processInfo.environment.merging([
        "NOTCH_DEBUG_EXPAND": "1",
        "NOTCH_DEBUG_DEMO": preset,
        // Somewhere disposable: the demo must not write its layout over
        // whatever the machine taking the screenshot is actually using.
        "NOTCH_SUPPORT_DIR": NSTemporaryDirectory() + "notch-shots/\(preset)",
    ]) { _, b in b }
    try process.run()

    // The charts animate in. Long enough for the last of them to settle.
    Thread.sleep(forTimeInterval: 4)

    guard let window = notchWindow() else {
        FileHandle.standardError.write("no notch window for \(preset)\n".data(using: .utf8)!)
        process.terminate()
        continue
    }

    let out = outDir.appendingPathComponent("notch-\(preset).png")
    // `-o` drops the window shadow, which is a soft grey halo baked into the
    // alpha — fine over the desktop it was captured on and wrong over
    // anything else, which is the whole point of a transparent PNG.
    run("/usr/sbin/screencapture", ["-x", "-o", "-l\(window.id)", out.path])
    trimTransparentMargin(out)
    print("\(preset)\t\(out.path)")

    process.terminate()
}

run("/usr/bin/pkill", ["-x", "NotchMetrics"])
