import XCTest

/// The Home Screen widget as SpringBoard shows it. The widget can't be tapped on a simulator (ADR 0010), but it can be
/// added and looked at, so its colors can be checked against the app's.
final class WidgetTests: UITestCase {
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// GLN-2, NFR-3: in light mode the widget's Start is the app's darker blue, which passes the contrast check, not the
    /// system blue WidgetKit gives a widget's button by itself (device check L12, fixed in #246: about 2.6:1 on its
    /// circle, under the 3:1 an icon needs).
    @MainActor
    func testTheWidgetsStartIsTheAppsDarkerBlue() throws {
        try skipUnlessSoaking(
            "it drives SpringBoard's own screens to add the widget, which a pull request shouldn't wait on")

        // Given the widget on the Home Screen, after a launch has registered it, with no session left by another test
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_RESET"] = "1"
        app.launchEnvironment["PIANISM_SKIP_WELCOME"] = "1"
        app.launch()
        kill(app)
        XCUIDevice.shared.press(.home)
        let start = springboard.buttons["Start"]
        if !start.appears(within: 5) { addTheWidget() }
        XCTAssertTrue(start.appears(within: 10), "The widget's Start didn't show on the Home Screen")

        // When its colors are read from a screenshot: the widget's background just above it, and the icon's own blue,
        // the commonest blue with next to no red around it (both blues have none, unlike the Home Screen's other colors),
        // as the icon is one flat color and only its edges blend. The
        // search area is twice the button's size, as an iPad's Home Screen draws widgets smaller than SpringBoard
        // reports them.
        let screenshot = XCUIScreen.main.screenshot()
        let frame = start.frame
        let background = try XCTUnwrap(
            pixels(in: screenshot, within: CGRect(x: frame.midX, y: frame.minY - 6, width: 1, height: 1)).first)
        try XCTSkipIf(background.luminance < 0.5, "The simulator is in dark mode, where both blues are the system blue")
        let around = frame.insetBy(dx: -frame.width / 2, dy: -frame.height / 2)
        let icon = try XCTUnwrap(
            commonest(pixels(in: screenshot, within: around).filter { $0.red < 0.2 && $0.blue > 0.6 }),
            "No blue icon around Start at \(frame)")
        attachScreenshot(of: springboard, named: "The widget's Start: \(icon) on \(background)")

        // Then the icon is the darker blue, read here as #0054C7, not the system blue, read as #0088FF without the fix
        // (iPhone simulator, iOS 27.2, 2026-11-12): their green parts are 84 and 136, so 110 splits them.
        XCTAssertLessThan(icon.green, 110.0 / 255, "Start is the system blue, not the app's darker blue: \(icon)")
    }

    /// GLN-2, SES-4: once a session reaches the cap with the app closed, the widget says "Ended", as the Live Activity
    /// does, not "Practicing" above its stopped clock, and offers Start again (device check W9, 2026-11-13; the owner
    /// picked "Ended" with Start the same day). Start itself can't be tapped on a simulator (ADR 0010); a model test
    /// covers what it does after the cap.
    @MainActor
    func testTheWidgetSaysEndedOnceASessionReachesTheCap() throws {
        try skipUnlessSoaking("it waits out a cap on real time, and drives SpringBoard's own screens to add the widget")

        // Given the widget on the Home Screen, added first, as that can take longer than the cap, and then a session
        // started with a 30-second cap and the app closed
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_RESET"] = "1"
        app.launchEnvironment["PIANISM_SKIP_WELCOME"] = "1"
        app.launch()
        kill(app)
        XCUIDevice.shared.press(.home)
        if !springboard.buttons["Start"].appears(within: 5) { addTheWidget() }
        XCTAssertTrue(springboard.buttons["Start"].appears(within: 10), "The widget's Start didn't show")
        app.launchEnvironment["PIANISM_RESET"] = nil
        app.launchEnvironment["PIANISM_CAP_SECONDS"] = "30"
        app.launch()
        app.buttons["practice.start"].tap()
        kill(app)
        XCUIDevice.shared.press(.home)
        let practicing = springboard.staticTexts["Practicing"]
        XCTAssertTrue(practicing.appears(within: 10), "The widget didn't show the session")

        // When the cap passes, with a margin for a slow reload
        let ended = springboard.staticTexts["Ended"].appears(within: 60)

        // Then the widget says the session ended, and offers Start
        attachScreenshot(of: springboard, named: "The widget past the cap")
        XCTAssertTrue(ended, "The widget didn't say \"Ended\" past the cap")
        XCTAssertFalse(practicing.exists, "The widget still said \"Practicing\" past the cap")
        XCTAssertTrue(springboard.buttons["Start"].exists, "The widget didn't offer Start past the cap")
    }

    /// Adds the small Practice widget through the Home Screen's edit mode and its widget gallery.
    @MainActor
    private func addTheWidget() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 2)
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.appears(within: 5), "The Home Screen didn't go into edit mode")
        edit.tap()
        labeled("Add Widget").tap()
        let search = springboard.searchFields["Search Widgets"]
        XCTAssertTrue(search.appears(within: 5), "The widget gallery didn't open")
        search.tap()
        search.typeText("Pianism")
        let pianism = springboard.cells["Pianism"]
        XCTAssertTrue(pianism.appears(within: 5), "The gallery didn't find Pianism's widget")
        pianism.tap()
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch
        XCTAssertTrue(add.appears(within: 5), "The gallery didn't offer to add the widget")
        add.tap()
        let done = springboard.buttons["Done"]
        if done.appears(within: 5) { done.tap() }
    }

    @MainActor
    private func labeled(_ label: String) -> XCUIElement {
        let element = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(element.appears(within: 5), "\"\(label)\" didn't show")
        return element
    }

    private func commonest(_ colors: [RGB]) -> RGB? {
        Dictionary(grouping: colors, by: \.description).max { $0.value.count < $1.value.count }?.value.first
    }

    /// The colors of the screenshot's pixels within `rect`, in points, in sRGB.
    @MainActor
    private func pixels(in screenshot: XCUIScreenshot, within rect: CGRect) throws -> [RGB] {
        let image = screenshot.image
        let cgImage = try XCTUnwrap(image.cgImage)
        let area = CGRect(
            x: rect.minX * image.scale, y: rect.minY * image.scale, width: rect.width * image.scale,
            height: rect.height * image.scale
        ).integral
        let cropped = try XCTUnwrap(cgImage.cropping(to: area))
        let width = cropped.width
        let height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).map {
            RGB(red: Double(bytes[$0]) / 255, green: Double(bytes[$0 + 1]) / 255, blue: Double(bytes[$0 + 2]) / 255)
        }
    }
}

private struct RGB: CustomStringConvertible {
    let red: Double
    let green: Double
    let blue: Double

    /// Relative luminance, roughly: enough to tell a light background from a dark one.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var description: String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
