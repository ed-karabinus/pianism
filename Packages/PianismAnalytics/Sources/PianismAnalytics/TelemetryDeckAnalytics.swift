import Foundation
import PianismCore
import TelemetryDeck

/// Sends signals to TelemetryDeck while analytics is on (ADR 0011).
///
/// The SDK doesn't start until analytics is first on. Once started, it can't safely stop: `TelemetryDeck.terminate()`
/// leaves scheduled work behind that calls its shared manager, which traps in Debug and, in Release, makes a new one with
/// no App ID. And `analyticsDisabled` stops new signals, but not ones already queued. So turning off sets that, and also
/// swaps in a network that discards everything, which empties the queue without anything leaving the device.
@MainActor
public final class TelemetryDeckAnalytics: Analytics {
    private let appID: String
    private let urlSession: URLSession
    private let transmitInterval: TimeInterval?
    private let discarding: URLSession
    private var config: TelemetryDeck.Config?

    /// The last two are for tests: a fake network, and not waiting the SDK's 10 s to send.
    public init(appID: String, urlSession: URLSession = .shared, transmitInterval: TimeInterval? = nil) {
        self.appID = appID
        self.urlSession = urlSession
        self.transmitInterval = transmitInterval
        discarding = DiscardingNetwork.session()
    }

    public func setEnabled(_ enabled: Bool) {
        if let config {
            config.analyticsDisabled = !enabled
            config.urlSession = enabled ? urlSession : discarding
        } else if enabled {
            let config = makeConfig()
            self.config = config
            TelemetryDeck.initialize(config: config)
        }
    }

    public func send(_ signal: AnalyticsSignal) {
        // Not started: the SDK would trap in Debug, and make a manager with no App ID in Release. Once started, its
        // `analyticsDisabled` covers being off.
        guard config != nil else { return }
        TelemetryDeck.signal(signal.name, parameters: signal.parameters)
    }

    func makeConfig() -> TelemetryDeck.Config {
        let config = TelemetryDeck.Config(appID: appID)
        config.urlSession = urlSession
        // They send more than ADR 0011 lists, such as an automatic signal for a new install.
        config.sessionStatsEnabled = false
        if let transmitInterval { config.transmitInterval = transmitInterval }
        return config
    }
}

/// Answers every request with success without going anywhere, so the SDK counts its queue as sent and forgets it.
final class DiscardingNetwork: URLProtocol, @unchecked Sendable {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscardingNetwork.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(filePath: "/")
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
