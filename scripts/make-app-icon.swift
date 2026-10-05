#!/usr/bin/env swift
import AppKit
import Foundation

/// Builds `AppIcon.appiconset` from a single 1024px source.
///
/// The supplied artwork is a full-bleed square. A macOS icon is not: it is a
/// squircle inset inside a transparent canvas, and shipping the square
/// unmasked gives an app whose icon has sharp corners and overruns every other
/// icon in the Dock.
///
/// Apple's grid puts the icon body in 824 of 1024 points, with a corner radius
/// of roughly 185 at that size. Those two numbers are the whole job.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <source.png> <AppIcon.appiconset>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDir = URL(fileURLWithPath: arguments[2])

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("could not read \(sourceURL.path)\n".utf8))
    exit(1)
}

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// Draws the source masked to a squircle, inset inside a transparent canvas.
func render(side: Int) -> Data? {
    let canvas = CGFloat(side)
    // 824/1024 of the canvas, which is Apple's macOS icon grid.
    let body = (canvas * 824 / 1024).rounded()
    let origin = ((canvas - body) / 2).rounded()
    let radius = body * 185 / 824

    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: origin, y: origin, width: body, height: body)
    // `xRadius`/`yRadius` on NSBezierPath is a rounded rect rather than a true
    // continuous-curvature squircle. At icon sizes the difference is a pixel
    // or two, and it avoids hand-rolling a superellipse.
    let mask = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    mask.addClip()
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    guard let rep = NSBitmapImageRep(
        focusedViewRect: NSRect(x: 0, y: 0, width: canvas, height: canvas))
    else { return nil }
    return rep.representation(using: .png, properties: [:])
}

struct Entry { let size: Int; let scale: Int }

let entries = [
    Entry(size: 16, scale: 1), Entry(size: 16, scale: 2),
    Entry(size: 32, scale: 1), Entry(size: 32, scale: 2),
    Entry(size: 128, scale: 1), Entry(size: 128, scale: 2),
    Entry(size: 256, scale: 1), Entry(size: 256, scale: 2),
    Entry(size: 512, scale: 1), Entry(size: 512, scale: 2),
]

var manifest: [[String: String]] = []

for entry in entries {
    let pixels = entry.size * entry.scale
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    guard let data = render(side: pixels) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: outputDir.appendingPathComponent(name))
    manifest.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(entry.scale)x",
        "size": "\(entry.size)x\(entry.size)",
    ])
}

let contents: [String: Any] = [
    "images": manifest,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

print("wrote \(entries.count) icons to \(outputDir.path)")
