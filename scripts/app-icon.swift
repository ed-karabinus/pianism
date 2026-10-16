// Draws the app icon, B0 "Timer keys" (picked 2026-10-16): three piano keys, the C-D-E group with its
// two black keys, inside a three-quarter amber ring. Writes the three 1024-pixel appearances the
// asset catalog uses. Run from the repository root: swift scripts/app-icon.swift
import AppKit

struct Palette {
    var background: NSColor
    var track: NSColor
    var ring: NSColor
    var whiteKey: NSColor
    var blackKey: NSColor
}

func hex(_ value: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

let appearances: [(file: String, palette: Palette)] = [
    ("AppIcon.png", Palette(background: hex(0x1C2433), track: hex(0x2B3547), ring: hex(0xE8A33D),
                            whiteKey: hex(0xF3EEE4), blackKey: hex(0x1C2433))),
    ("AppIcon-Dark.png", Palette(background: hex(0x0E121A), track: hex(0x222A38), ring: hex(0xE8A33D),
                                 whiteKey: hex(0xF3EEE4), blackKey: hex(0x0E121A))),
    // Tinted: grayscale on black; iOS colours it with the person's tint.
    ("AppIcon-Tinted.png", Palette(background: hex(0x000000), track: hex(0x3A3A3A), ring: hex(0xD8D8D8),
                                   whiteKey: hex(0xFFFFFF), blackKey: hex(0x000000))),
]

/// The key group's size relative to B0 on the design board: larger, so it reads at 29 points.
let keyScale: CGFloat = 1.18

func draw(_ palette: Palette, in context: CGContext, size: CGFloat) {
    let unit = size / 100  // The design board's 100-unit square.
    context.setFillColor(palette.background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let center = CGPoint(x: 50 * unit, y: 50 * unit)
    context.setLineWidth(7 * unit)
    context.setStrokeColor(palette.track.cgColor)
    context.addArc(center: center, radius: 31 * unit, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.strokePath()
    // Three quarters of the ring, clockwise from the top (Core Graphics' y axis points up).
    context.setStrokeColor(palette.ring.cgColor)
    context.setLineCap(.round)
    context.addArc(center: center, radius: 31 * unit, startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi,
                   clockwise: true)
    context.strokePath()

    // Keys, on the board's coordinates (y down), scaled about the centre.
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat,
              _ color: NSColor) {
        let scaled = CGRect(x: 50 + (x - 50) * keyScale, y: 50 + (y - 50) * keyScale,
                            width: width * keyScale, height: height * keyScale)
        let flipped = CGRect(x: scaled.minX * unit, y: (100 - scaled.maxY) * unit,
                             width: scaled.width * unit, height: scaled.height * unit)
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: flipped, cornerWidth: radius * keyScale * unit,
                               cornerHeight: radius * keyScale * unit, transform: nil))
        context.fillPath()
    }
    for x: CGFloat in [36.4, 46, 55.6] { rect(x, 38, 8, 24, 1.6, palette.whiteKey) }
    for x: CGFloat in [42.7, 52.3] { rect(x, 38, 5, 14, 1, palette.blackKey) }
}

struct IconError: Error {}

let size: CGFloat = 1024
let folder = URL(filePath: "App/Assets.xcassets/AppIcon.appiconset")
for (file, palette) in appearances {
    // Opaque RGB: App Store icons can't have an alpha channel.
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw IconError() }
    draw(palette, in: context, size: size)
    guard let image = context.makeImage(),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw IconError() }
    try png.write(to: folder.appending(path: file))
    print("Wrote", file)
}
