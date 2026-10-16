// Draws the app icon, B0 "Timer keys" (picked 2026-10-16): three piano keys, the C-D-E group with its
// two black keys, inside a three-quarter amber ring. Writes the three 1024-pixel appearances the
// asset catalog uses. Run from the repository root: swift scripts/app-icon.swift
import AppKit

struct Palette {
    /// Also the black keys' colour, as on the design board.
    var background: CGColor
    var track: CGColor
    var ring: CGColor
    var whiteKey: CGColor
}

func hex(_ value: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

// The colours the owner approved on his iPhone.
let appearances: [(file: String, palette: Palette)] = [
    (
        "AppIcon.png",
        Palette(background: hex(0x1C2433), track: hex(0x2B3547), ring: hex(0xE8A33D), whiteKey: hex(0xF3EEE4))
    ),
    (
        "AppIcon-Dark.png",
        Palette(background: hex(0x0E121A), track: hex(0x222A38), ring: hex(0xE8A33D), whiteKey: hex(0xF3EEE4))
    ),
    // Tinted: grayscale on black; iOS colours it with the person's tint.
    (
        "AppIcon-Tinted.png",
        Palette(background: hex(0x000000), track: hex(0x3A3A3A), ring: hex(0xD8D8D8), whiteKey: hex(0xFFFFFF))
    ),
]

/// The key group's size relative to B0 on the design board: larger, so it reads at 29 points.
let keyScale: CGFloat = 1.18

/// Draws on the design board's 100-unit square, y pointing down, as in its SVG.
func draw(_ palette: Palette, in context: CGContext, size: CGFloat) {
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: size / 100, y: -size / 100)
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

    context.setLineWidth(7)
    context.setStrokeColor(palette.track)
    context.strokeEllipse(in: CGRect(x: 19, y: 19, width: 62, height: 62))
    // Three quarters of the ring from the top. With y pointing down, this turns clockwise on screen.
    context.setStrokeColor(palette.ring)
    context.setLineCap(.round)
    context.addArc(center: CGPoint(x: 50, y: 50), radius: 31, startAngle: -.pi / 2, endAngle: .pi, clockwise: false)
    context.strokePath()

    context.translateBy(x: 50, y: 50)
    context.scaleBy(x: keyScale, y: keyScale)
    context.translateBy(x: -50, y: -50)
    func key(_ x: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, color: CGColor) {
        context.setFillColor(color)
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: x, y: 38, width: width, height: height), cornerWidth: radius,
                cornerHeight: radius, transform: nil))
        context.fillPath()
    }
    for x: CGFloat in [36.4, 46, 55.6] { key(x, width: 8, height: 24, radius: 1.6, color: palette.whiteKey) }
    for x: CGFloat in [42.7, 52.3] { key(x, width: 5, height: 14, radius: 1, color: palette.background) }
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
