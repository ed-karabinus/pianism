import Foundation
import PianismCore
import UserNotifications

/// ``PracticeNudges`` as a local notification that asks "Still practicing?", with the banner's answers as its
/// buttons (SES-3).
public final class UserNotificationNudges: NSObject, PracticeNudges, UNUserNotificationCenterDelegate {
    /// What an answer from the notification asks of the app.
    enum Answer: Equatable {
        case stillPracticing
        /// Opens Practice to the question or, with `pickingEnd`, to the session's end being picked.
        case open(pickingEnd: Bool)
    }

    static let category = "still-practicing"
    static let stillPracticing = "still-practicing.yes"
    static let stoppedEarlier = "still-practicing.stopped-earlier"
    static let sessionKey = "sessionID"

    private let answered: @MainActor @Sendable (UUID) -> Void
    private let opened: @MainActor @Sendable (_ sessionID: UUID, _ pickingEnd: Bool) -> Void

    /// Registers the notification's buttons and takes its answers: `answered` for "Still practicing", `opened`
    /// for "I stopped earlier" or a tap. An answer can launch the app, so create this as the app launches.
    public init(
        answered: @escaping @MainActor @Sendable (UUID) -> Void,
        opened: @escaping @MainActor @Sendable (_ sessionID: UUID, _ pickingEnd: Bool) -> Void
    ) {
        self.answered = answered
        self.opened = opened
        super.init()
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([Self.answers])
        center.delegate = self
    }

    public func canAskPermission() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    public func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Adds the notification without checking the settings first, unlike Apple's samples, as an add waiting on them
    /// could land after a cancel. Until notifications are allowed the system refuses it; the next refresh after they
    /// are adds it again.
    public func schedule(after delay: TimeInterval, sessionID: UUID) {
        UNUserNotificationCenter.current().add(Self.request(after: delay, sessionID: sessionID))
    }

    /// Also takes a delivered notification out of Notification Center, as the app now shows what it asked.
    public func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.category])
        center.removeDeliveredNotifications(withIdentifiers: [Self.category])
    }

    /// The notification's buttons. "I stopped earlier" opens the app, where the end is picked.
    static var answers: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(
                    identifier: stillPracticing, title: String(localized: "Still practicing", bundle: .module)),
                UNNotificationAction(
                    identifier: stoppedEarlier, title: String(localized: "I stopped earlier", bundle: .module),
                    options: .foreground),
            ],
            intentIdentifiers: [])
    }

    /// The notification for the session with this ID, after `delay` seconds. One at a time: each replaces the last.
    static func request(after delay: TimeInterval, sessionID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Still practicing?", bundle: .module)
        content.body = String(localized: "Pianism is still timing your session.", bundle: .module)
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = [sessionKey: sessionID.uuidString]
        // A time interval trigger rejects anything but a positive delay.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        return UNNotificationRequest(identifier: category, content: content, trigger: trigger)
    }

    /// What the notification's button with this identifier asks of the app, or `nil` when it was dismissed.
    static func answer(to action: String) -> Answer? {
        switch action {
        case stillPracticing: .stillPracticing
        case stoppedEarlier: .open(pickingEnd: true)
        case UNNotificationDefaultActionIdentifier: .open(pickingEnd: false)
        default: nil
        }
    }

    /// The completion-handler form, which the system calls on the main thread. The `async` form finishes off it,
    /// which UIKit traps on.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let id = (info[Self.sessionKey] as? String).flatMap(UUID.init(uuidString:)),
            let answer = Self.answer(to: response.actionIdentifier)
        {
            MainActor.assumeIsolated {
                switch answer {
                case .stillPracticing: answered(id)
                case .open(let pickingEnd): opened(id, pickingEnd)
                }
            }
        }
        completionHandler()
    }
}
