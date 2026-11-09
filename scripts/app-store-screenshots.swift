// Puts a headline above each App Store screenshot, on the app's blue (#56, captions picked 2026-11-08). Reads
// `<number> <name>.png` from the first folder, as ScreenshotTests names them, and writes `<number>.png` at the same
// size to the second, the size App Store Connect takes for that device.
// Run from the repository root: swift scripts/app-store-screenshots.swift <plain folder> <captioned folder>
import AppKit

/// Each headline, and a quieter line under those showing Pro, as App Review asks a listing to say what needs a
/// purchase (guideline 2.3.2; picked 2026-11-08). The week leads, as it works with any piano, like the subtitle's
/// "Time it with a tap or a piano" (picked 2026-11-09).
let headlines: [String: (headline: String, pro: String?)] = [
    "1": ("A weekly goal that fits you", nil),
    "2": ("Your piano starts the timer", "First 5 free, then with Pianism Pro"),
    "3": ("Every session, day by day", nil),
    "4": ("See where your time goes", "With Pianism Pro"),
    "5": ("Tag pieces and skills", nil),
]
/// The app's AccentColor in light mode.
let blue = CGColor(srgbRed: 0, green: 0.33, blue: 0.78, alpha: 1)

func captioned(_ shot: CGImage, _ headline: String, pro: String?) -> CGImage? {
    let width = CGFloat(shot.width)
    let height = CGFloat(shot.height)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    // No alpha channel, which App Store Connect refuses.
    context.setFillColor(blue)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // The headline in the top fifth, the screenshot below it, scaled to fit with a margin, its corners rounded.
    let band = height * 0.2
    let margin = width * 0.07
    let scale = min((width - 2 * margin) / width, (height - band - margin) / height)
    let frame = CGRect(
        x: (width - width * scale) / 2, y: margin, width: width * scale, height: height * scale)
    context.saveGState()
    context.setShadow(offset: .zero, blur: width * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    // An iPad's corners are much tighter than an iPhone's, and would otherwise cut into its status bar.
    let radius = frame.width * (height / width > 1.6 ? 0.08 : 0.035)
    let corners = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(corners)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(corners)
    context.clip()
    context.draw(shot, in: frame)
    context.restoreGState()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    // From the band, so the headline and its Pro line fit above the screenshot on either device.
    let size = band * 0.17
    let text = NSMutableAttributedString(
        string: headline,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    if let pro {
        text.append(
            NSAttributedString(
                string: "\n" + pro,
                attributes: [
                    .font: NSFont.systemFont(ofSize: size * 0.6, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph,
                ]))
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let box = CGRect(x: margin, y: height - band, width: width - 2 * margin, height: band - margin * 0.5)
    let fitted = text.boundingRect(with: box.size, options: [.usesLineFragmentOrigin])
    let centred = CGRect(
        x: box.minX, y: box.minY + (box.height - fitted.height) / 2, width: box.width, height: fitted.height)
    text.draw(with: centred, options: [.usesLineFragmentOrigin])
    NSGraphicsContext.current = nil
    return context.makeImage()
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift scripts/app-store-screenshots.swift <plain folder> <captioned folder>")
    exit(1)
}
let input = URL(filePath: arguments[1])
let output = URL(filePath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var written = 0
for file in try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
where file.pathExtension == "png" {
    let number = String(file.lastPathComponent.prefix { $0 != " " })
    guard let caption = headlines[number],
        let source = CGImageSourceCreateWithURL(file as CFURL, nil),
        let shot = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let image = captioned(shot, caption.headline, pro: caption.pro),
        let destination = CGImageDestinationCreateWithURL(
            output.appending(path: "\(number).png") as CFURL, "public.png" as CFString, 1, nil)
    else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) { written += 1 }
}
print("Wrote \(written) of \(headlines.count) screenshots to \(output.path())")
exit(written == headlines.count ? 0 : 1)
