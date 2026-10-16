import XCTest

/// Spike #17: a widget button starts a session and its Live Activity without opening the app.
/// Drives SpringBoard to add the widget, so it depends on the Home Screen's labels in this iOS.
final class WidgetSpikeTests: XCTestCase {
    @MainActor
    var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    @MainActor
    func testWidgetStartsSessionWithoutOpeningApp() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["practice.status"].waitForExistence(timeout: 10))
        app.terminate()

        XCUIDevice.shared.press(.home)
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 2)
        sleep(1)
        try tap("Edit", step: "1 edit menu")
        try tap("Add Widget", step: "2 widget gallery")
        // Searching took 17 minutes in SpringBoard's tree; scrolling the A-Z list to the cell is quick.
        let pianism = springboard.cells["Pianism"].firstMatch
        for _ in 0..<6 where !pianism.waitForExistence(timeout: 2) || !pianism.isHittable {
            springboard.swipeUp()
        }
        dump("3 scrolled to Pianism")
        try tap("Pianism", step: "4 Pianism widgets")
        // "Add Widget" here has no label any query matches, so tap where it is on iPhone 17.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
        sleep(3)
        dump("5 added")
        try tap("Done", step: "6 done")

        try tap("Start", step: "7 tapped Start")
        sleep(3)
        dump("8 after Start")
        let state = app.state
        add(XCTAttachment(string: "App state after the widget tap: \(state.rawValue)"))
        XCTAssertNotEqual(state, .runningForeground, "The widget opened the app")

        app.activate()
        XCTAssertTrue(app.staticTexts["practice.status"].waitForExistence(timeout: 10))
        dump("9 app opened")
        XCTAssertEqual(app.staticTexts["practice.status"].label, "Practicing")
    }

    /// Taps the first SpringBoard element with `label`, of the kinds Home Screen editing uses.
    @MainActor
    private func tap(_ label: String, step: String) throws {
        for query in [springboard.buttons, springboard.menuItems, springboard.cells, springboard.staticTexts] {
            let element = query[label].firstMatch
            if element.waitForExistence(timeout: 2) {
                element.tap()
                sleep(2)
                dump(step)
                return
            }
        }
        dump(step + " (not found)")
        throw XCTSkip("No '\(label)' in SpringBoard at step \(step)")
    }

    @MainActor
    private func dump(_ step: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = step
        shot.lifetime = .keepAlways
        add(shot)
    }
}
