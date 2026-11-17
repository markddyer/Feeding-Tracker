// Makes the app icons from one square picture.
//
//   swift tools/make-app-icons.swift <picture.png or .svg> [output folder]
//
// The icon's picture today is tools/app-icon.svg. An SVG is drawn at 1024 x 1024 by Quick Look
// (qlmanage, which draws with WebKit, so its gradients and shadows come out as in a browser).
//
// Writes AppIcon.png (Feeding) and AppIcon-Dev.png (Feeding Dev, with a "DEV" band) for the phone
// and for the watch, all 1024 x 1024 with no transparency, as Apple asks. If the picture has dark rounded-off corners
// (a picture made to look like an icon), they are filled with the colours next to them first,
// because iOS and watchOS cut the corners off themselves. With no output folder, the icons go
// straight into the phone's and the watch's asset catalogs.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: swift tools/make-app-icons.swift <picture.png> [output folder]\n".data(using: .utf8)!)
    exit(2)
}
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("make-app-icons: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// 1. Read the picture into RGBA pixels (row 0 is the top). ImageIO can't read an SVG, so Quick
//    Look draws it into a PNG first.
var input = URL(fileURLWithPath: args[1])
if input.pathExtension.lowercased() == "svg" {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("make-app-icons-\(getpid())")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let quickLook = Process()
    quickLook.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    quickLook.arguments = ["-t", "-s", "1024", "-o", folder.path, input.path]
    quickLook.standardOutput = FileHandle.nullDevice
    quickLook.standardError = FileHandle.nullDevice
    do { try quickLook.run() } catch { fail("can't run qlmanage: \(error)") }
    quickLook.waitUntilExit()
    input = folder.appendingPathComponent(input.lastPathComponent + ".png")
    guard FileManager.default.fileExists(atPath: input.path) else { fail("Quick Look couldn't draw \(args[1])") }
}
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("can't read \(args[1])") }
let w = picture.width, h = picture.height
guard w == h else { fail("the picture must be square (it is \(w) x \(h))") }
var px = [UInt8](repeating: 0, count: w * h * 4)
px.withUnsafeMutableBytes { buffer in
    let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(picture, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// 2. Find the dark corners: dark pixels joined to a corner of the picture. Then the soft edge
//    between dark and light: greyish pixels joined to them, up to a short way out (where the
//    rounded border runs almost along the picture's edge, that soft edge is long), and a few
//    pixels more all round.
var outside = [Bool](repeating: false, count: w * h)
func brightness(_ i: Int) -> Int { (Int(px[i * 4]) + Int(px[i * 4 + 1]) + Int(px[i * 4 + 2])) / 3 }
func dark(_ i: Int) -> Bool { max(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) < 90 }
var stack = [0, w - 1, (h - 1) * w, h * w - 1].filter { dark($0) }
for i in stack { outside[i] = true }
while let i = stack.popLast() {
    let x = i % w, y = i / w
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
        let n = ny * w + nx
        if !outside[n] && dark(n) { outside[n] = true; stack.append(n) }
    }
}
var ring = (0..<(w * h)).filter { outside[$0] }
for _ in 0..<max(8, w / 30) {
    var next: [Int] = []
    for i in ring {
        let x = i % w, y = i / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let n = ny * w + nx
            if !outside[n] && brightness(n) < 215 { outside[n] = true; next.append(n) }
        }
    }
    if next.isEmpty { break }
    ring = next
}
let edge = max(2, w / 320)
var fill = outside
for _ in 0..<edge {
    var grown = fill
    for y in 0..<h { for x in 0..<w where fill[y * w + x] {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < w, ny < h { grown[ny * w + nx] = true }
        }
    } }
    fill = grown
}
let filled = fill.filter { $0 }.count
if filled > w * h / 4 { fail("more than a quarter of the picture is dark at its corners: is it the right picture?") }

// 3. Fill them in, ring by ring from the light side: each pixel takes the average of the
//    pixels next to it that already have a colour.
var frontier = (0..<(w * h)).filter { i in
    guard fill[i] else { return false }
    let x = i % w, y = i / w
    return [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
        let nx = x + dx, ny = y + dy
        return nx >= 0 && ny >= 0 && nx < w && ny < h && !fill[ny * w + nx]
    }
}
while !frontier.isEmpty {
    var colours: [(Int, [UInt8])] = []
    for i in frontier {
        let x = i % w, y = i / w
        var sum = [0, 0, 0], count = 0
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h, !fill[ny * w + nx] else { continue }
            let n = (ny * w + nx) * 4
            sum[0] += Int(px[n]); sum[1] += Int(px[n + 1]); sum[2] += Int(px[n + 2]); count += 1
        } }
        colours.append((i, sum.map { UInt8($0 / max(count, 1)) }))
    }
    for (i, c) in colours { px[i * 4] = c[0]; px[i * 4 + 1] = c[1]; px[i * 4 + 2] = c[2]; px[i * 4 + 3] = 255; fill[i] = false }
    var next = Set<Int>()
    for (i, _) in colours {
        let x = i % w, y = i / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < w, ny < h, fill[ny * w + nx] { next.insert(ny * w + nx) }
        }
    }
    frontier = Array(next)
}
let cleaned: CGImage = px.withUnsafeMutableBytes { buffer in
    CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

// 4. Draw at 1024 x 1024, with no transparency. The watch cuts the icon to a circle, so there the
//    picture is drawn smaller (scale), and the space round it is the picture's own edge pixels,
//    stretched out.
let size = 1024
func icon(dev: Bool, scale: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    let s = CGFloat(size), m = (s * (1 - scale)).rounded() / 2
    if m > 0 {
        let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)].map { x, y in (0..<3).map { Int(px[(y * w + x) * 4 + $0]) } }
        let average = (0..<3).map { c in CGFloat(corners.map { $0[c] }.reduce(0, +)) / 4 / 255 }
        ctx.setFillColor(CGColor(srgbRed: average[0], green: average[1], blue: average[2], alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // Pixel rects are from the top; drawing rects are from the bottom.
        ctx.draw(cleaned.cropping(to: CGRect(x: 0, y: 0, width: w, height: 1))!, in: CGRect(x: m, y: s - m, width: s - 2 * m, height: m))
        ctx.draw(cleaned.cropping(to: CGRect(x: 0, y: h - 1, width: w, height: 1))!, in: CGRect(x: m, y: 0, width: s - 2 * m, height: m))
        ctx.draw(cleaned.cropping(to: CGRect(x: 0, y: 0, width: 1, height: h))!, in: CGRect(x: 0, y: m, width: m, height: s - 2 * m))
        ctx.draw(cleaned.cropping(to: CGRect(x: w - 1, y: 0, width: 1, height: h))!, in: CGRect(x: s - m, y: m, width: m, height: s - 2 * m))
    }
    ctx.draw(cleaned, in: CGRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m))
    if dev {
        // A band along the bottom in the app's text brown, with "DEV" in its cream, in Fredoka
        // (DESIGN.md), so Feeding Dev is easy to tell from Feeding on the Home Screen.
        let band = CGFloat(size) * 0.15
        ctx.setFillColor(CGColor(srgbRed: 0x3A / 255, green: 0x2A / 255, blue: 0x1E / 255, alpha: 0.94))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(size), height: band))
        let fontURL = repo.appendingPathComponent("App/Fonts/Fredoka.ttf")
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
              let base = descriptors.first else { fail("can't read \(fontURL.path)") }
        let semibold = CTFontDescriptorCreateCopyWithAttributes(base, [
            kCTFontVariationAttribute: [0x7767_6874 as NSNumber: 600 as NSNumber],  // 'wght' 600
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(semibold, band * 0.62, nil)
        let text = NSAttributedString(string: "DEV", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0xFF / 255, green: 0xF4 / 255, blue: 0xE2 / 255, alpha: 1),
            NSAttributedString.Key(kCTKernAttributeName as String): band * 0.06,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
                                   y: (band - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }
    return ctx.makeImage()!
}

func save(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("can't write \(url.path)") }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fail("can't write \(url.path)") }
    print("wrote \(url.path)")
}

// The watch cuts the icon to a circle. The baby's head (tools/app-icon.svg) sits well inside it, so
// the watch's copy is full size. For a picture with shapes near its edges, draw it smaller here:
// the user's earlier picture, with round badges near the edges, needed 0.92.
let watchScale: CGFloat = 1
let icons = [
    ("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", icon(dev: false, scale: 1)),
    ("App/Assets.xcassets/AppIcon-Dev.appiconset/AppIcon-Dev.png", icon(dev: true, scale: 1)),
    ("Watch/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", icon(dev: false, scale: watchScale)),
    ("Watch/App/Assets.xcassets/AppIcon-Dev.appiconset/AppIcon-Dev.png", icon(dev: true, scale: watchScale)),
]
for (path, image) in icons {
    if args.count >= 3 {
        // A test run: flat names in the folder given, "Watch" first for the watch's.
        let name = (path.hasPrefix("Watch/") ? "Watch" : "") + URL(fileURLWithPath: path).lastPathComponent
        save(image, to: URL(fileURLWithPath: args[2]).appendingPathComponent(name))
    } else {
        save(image, to: repo.appendingPathComponent(path))
    }
}
print("filled \(filled) corner pixels of \(w * h)")
