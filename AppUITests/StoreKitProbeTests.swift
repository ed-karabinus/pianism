import StoreKit
import StoreKitTest
import XCTest

/// THROWAWAY: can a UI test under xcodebuild drive real StoreKit in the app?
final class StoreKitProbeTests: UITestCase {
    @MainActor
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PIANISM_SKIP_WELCOME"] = "1"
        app.launchEnvironment["PIANISM_STOREKIT_PROBE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func label(_ app: XCUIApplication, _ id: String) -> String {
        app.staticTexts[id].firstMatch.label
    }

    @MainActor
    private func report(_ app: XCUIApplication, _ step: String) {
        print(
            "PROBE \(step): price=\(label(app, "probe.price")) entitled=\(label(app, "probe.entitled")) error=\(label(app, "probe.error"))"
        )
    }

    @MainActor
    private func wait(_ app: XCUIApplication, _ id: String, is value: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        let element = app.staticTexts[id].firstMatch
        return XCTNSPredicateExpectation(predicate: predicate, object: element).expectationResult(timeout: timeout)
    }

    @MainActor
    func testAPurchaseAndRefund() async throws {
        let session = try SKTestSession(configurationFileNamed: "Pianism")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
        let app = launched()
        let priced = wait(app, "probe.price", is: "$14.99")
        report(app, "launched")
        XCTAssertTrue(priced, "No price")
        XCTAssertTrue(wait(app, "probe.entitled", is: "no"), "Should start without Pro")
        app.buttons["probe.buy"].tap()
        let bought = wait(app, "probe.entitled", is: "yes", timeout: 30)
        report(app, "bought")
        XCTAssertTrue(bought, "The purchase didn't unlock")
        let transactions = session.allTransactions()
        print("PROBE transactions: \(transactions.count)")
        let first = try XCTUnwrap(transactions.first)
        try session.refundTransaction(identifier: first.identifier)
        let refunded = wait(app, "probe.entitled", is: "no", timeout: 30)
        report(app, "refunded")
        XCTAssertTrue(refunded, "The refund didn't reach the app")
    }

    @MainActor
    func testAskToBuyWaitsThenUnlocks() async throws {
        let session = try SKTestSession(configurationFileNamed: "Pianism")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = true
        let app = launched()
        XCTAssertTrue(wait(app, "probe.entitled", is: "no"), "Should start without Pro")
        app.buttons["probe.buy"].tap()
        let pending = wait(app, "probe.error", is: "pending", timeout: 30)
        report(app, "asked")
        XCTAssertTrue(pending, "The purchase didn't wait for approval")
        XCTAssertTrue(wait(app, "probe.entitled", is: "no"), "A pending purchase shouldn't unlock")
        let first = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: first.identifier)
        let approved = wait(app, "probe.entitled", is: "yes", timeout: 30)
        report(app, "approved")
        XCTAssertTrue(approved, "Approval didn't reach the app")
    }

    @MainActor
    func testEntitlementSurvivesAnUnreachableStore() async throws {
        let session = try SKTestSession(configurationFileNamed: "Pianism")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
        try await session.buyProduct(identifier: "com.edkarabinus.Pianism.pro")
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let app = launched()
        let entitled = wait(app, "probe.entitled", is: "yes")
        report(app, "store unreachable")
        let errorShown = app.staticTexts["probe.error"].firstMatch.label.hasPrefix("products:")
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        XCTAssertTrue(errorShown, "The simulated error didn't reach the app")
        XCTAssertTrue(entitled, "Pro needs the store")
    }

    @MainActor
    func testBoughtBeforeLaunch() async throws {
        let session = try SKTestSession(configurationFileNamed: "Pianism")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
        try await session.buyProduct(identifier: "com.edkarabinus.Pianism.pro")
        let app = launched()
        let entitled = wait(app, "probe.entitled", is: "yes")
        report(app, "launched after buying")
        XCTAssertTrue(entitled, "A purchase made elsewhere didn't show at launch")
    }
}

extension XCTNSPredicateExpectation {
    fileprivate func expectationResult(timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [self], timeout: timeout) == .completed
    }
}
