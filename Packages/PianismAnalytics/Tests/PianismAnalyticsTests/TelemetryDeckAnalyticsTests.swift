import Foundation
import PianismCore
import TelemetryDeck
import Testing

@testable import PianismAnalytics

/// Records what the SDK posts, in place of the network.
private final class FakeNetwork: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String] = []

    static var posted: [String] {
        lock.withLock { bodies }
    }

    static func reset() {
        lock.withLock { bodies = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        Self.lock.withLock { Self.bodies.append(String(decoding: body, as: UTF8.self)) }
        let url = request.url ?? URL(filePath: "/")
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// One at a time, as the SDK is a single shared manager and the fake network is shared too. A test can still reach into
/// the next: the SDK starts a session 0.5 s after each `initialize`, on whichever manager is current then, and a post
/// made just before a test turns off can land after the next one's reset. So a test that expects nothing at all resets
/// again after `settle()`.
@Suite(.serialized)
@MainActor
struct TelemetryDeckAnalyticsTests {
    private let analytics: TelemetryDeckAnalytics

    init() {
        FakeNetwork.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeNetwork.self]
        analytics = TelemetryDeckAnalytics(
            appID: "00000000-0000-0000-0000-000000000000", urlSession: URLSession(configuration: configuration),
            transmitInterval: 0.1)
    }

    /// What ADR 0011 lists the SDK adding to every signal, from its source. Only some show on a Mac, where this runs,
    /// but a new version adding one in common code fails here, so the ADR changes first.
    private static let listed: Set<String> = Set(
        [
            "Accessibility.isBoldTextEnabled", "Accessibility.isDarkerSystemColorsEnabled",
            "Accessibility.isInvertColorsEnabled", "Accessibility.isReduceMotionEnabled",
            "Accessibility.isReduceTransparencyEnabled", "Accessibility.preferredContentSizeCategory",
            "Accessibility.shouldDifferentiateWithoutColor", "Acquisition.firstSessionDate",
            "AppInfo.buildNumber", "AppInfo.version", "AppInfo.versionAndBuildNumber", "Calendar.dayOfMonth",
            "Calendar.dayOfWeek", "Calendar.dayOfYear", "Calendar.hourOfDay", "Calendar.isWeekend",
            "Calendar.monthOfYear", "Calendar.quarterOfYear", "Calendar.weekOfYear", "Device.architecture",
            "Device.modelName", "Device.operatingSystem", "Device.orientation", "Device.platform",
            "Device.screenResolutionHeight", "Device.screenResolutionWidth", "Device.screenScaleFactor",
            "Device.systemMajorMinorVersion", "Device.systemMajorVersion", "Device.systemVersion",
            "Device.timeZone", "Retention.averageSessionSeconds", "Retention.distinctDaysUsed",
            "Retention.distinctDaysUsedLastMonth", "Retention.previousSessionSeconds",
            "Retention.totalSessionsCount", "RunContext.extensionIdentifier", "RunContext.isAppStore",
            "RunContext.isDebug", "RunContext.isSimulator", "RunContext.isTestFlight", "RunContext.language",
            "RunContext.locale", "RunContext.targetEnvironment", "SDK.name", "SDK.nameAndVersion",
            "SDK.version", "UserPreference.colorScheme", "UserPreference.language",
            "UserPreference.layoutDirection", "UserPreference.region",
        ].map { "TelemetryDeck." + $0 }
    ).union([
        "appLanguage", "appVersion", "architecture", "buildNumber", "extensionIdentifier", "isAppStore",
        "isDebug", "isSimulator", "isTestFlight", "locale", "majorMinorSystemVersion", "majorSystemVersion",
        "modelName", "operatingSystem", "platform", "preferredLanguage", "region", "systemVersion",
        "targetEnvironment", "telemetryClientVersion",
        "source",
    ])

    private var posted: String { FakeNetwork.posted.joined() }

    private func waitForPost(of text: String) async throws {
        for _ in 0..<100 where !posted.contains(text) {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Long enough for anything still on its way to have gone, at the short interval above, past the SDK's 0.5 s delay
    /// before a session starts.
    private func settle() async throws {
        try await Task.sleep(for: .seconds(1.5))
    }

    @Test func whileOnASignalReachesTheNetworkWithItsDetails() async throws {
        analytics.setEnabled(true)
        analytics.send(.sessionSaved(.midi))
        try await waitForPost(of: "Practice.sessionSaved")
        analytics.setEnabled(false)
        #expect(posted.contains("Practice.sessionSaved"))
        #expect(posted.contains(#""source":"midi""#))
    }

    /// The app opening is on the ADR's list.
    @Test func aSessionStartSignalIsSent() async throws {
        analytics.setEnabled(true)
        try await waitForPost(of: "TelemetryDeck.Session.started")
        analytics.setEnabled(false)
        #expect(posted.contains("TelemetryDeck.Session.started"))
    }

    /// The SDK's session statistics, which send a new-install signal, aren't. It remembers an install across test runs,
    /// so the setting is what can be checked.
    @Test func theSDKsSessionStatisticsAreOff() {
        #expect(!analytics.makeConfig().sessionStatsEnabled)
    }

    @Test func aSignalCarriesOnlyWhatTheADRLists() async throws {
        struct Posted: Decodable { let payload: [String: String] }
        analytics.setEnabled(true)
        analytics.send(.sessionSaved(.midi))
        try await waitForPost(of: "Practice.sessionSaved")
        analytics.setEnabled(false)
        let signals = try FakeNetwork.posted.flatMap { try JSONDecoder().decode([Posted].self, from: Data($0.utf8)) }
        #expect(!signals.isEmpty)
        #expect(Set(signals.flatMap(\.payload.keys)).subtracting(Self.listed).isEmpty)
    }

    /// With the SDK not started at all, as when analytics is off at launch. Sending would trap here, in a Debug build.
    @Test func neverTurnedOnNothingGoesOut() async throws {
        try await settle()
        FakeNetwork.reset()
        TelemetryDeck.terminate()
        analytics.send(.firstLaunch)
        try await settle()
        #expect(FakeNetwork.posted.isEmpty)
    }

    /// The network used while off answers without going anywhere. This address doesn't exist, so a real one would fail.
    @Test func whileOffTheNetworkGoesNowhere() async throws {
        let url = try #require(URL(string: "https://pianism.invalid/"))
        let (_, response) = try await DiscardingNetwork.session().data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    /// The switch's promise: a signal still queued when analytics is turned off doesn't go, and it's gone for good.
    @Test func turningOffDiscardsWhatWasQueued() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.send(.firstLaunch)
        analytics.setEnabled(false)
        try await settle()
        #expect(!posted.contains("Install.firstLaunch"))
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        #expect(!posted.contains("Install.firstLaunch"))
    }

    /// As when the app comes back from the background, which starts a new session.
    @Test func whileOffNothingFurtherGoesOut() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        try await settle()
        FakeNetwork.reset()
        analytics.send(.activationReached)
        TelemetryDeck.generateNewSession()
        TelemetryDeck.signal("Anything")
        try await settle()
        #expect(FakeNetwork.posted.isEmpty)
    }

    /// Such as a new session when the app comes back: it isn't kept for when analytics is next on.
    @Test func whatHappensWhileOffStaysGoneOnceBackOn() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        TelemetryDeck.signal("Anything")
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        #expect(!posted.contains("Anything"))
    }

    @Test func turningOnAgainSends() async throws {
        analytics.setEnabled(true)
        analytics.setEnabled(false)
        analytics.setEnabled(true)
        analytics.send(.activationReached)
        try await waitForPost(of: "Activation.reached")
        analytics.setEnabled(false)
        #expect(posted.contains("Activation.reached"))
    }
}
