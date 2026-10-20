import Foundation
import Testing
import UserNotifications

@testable import PianismSystem

struct UserNotificationNudgesTests {
    @Test("SES-3: the notification's buttons are the banner's answers, and only \"I stopped earlier\" opens the app")
    func buttonsAreTheBannersAnswers() {
        let actions = UserNotificationNudges.answers.actions

        #expect(actions.map(\.title) == ["Still practicing", "I stopped earlier"])
        #expect(actions.map(\.options) == [[], .foreground])
        #expect(
            actions.map { UserNotificationNudges.answer(to: $0.identifier) } == [
                .stillPracticing, .open(pickingEnd: true),
            ])
    }

    @Test("SES-3: a tap opens Practice to the question, and a dismissal asks nothing of the app")
    func tapOpensTheQuestion() {
        #expect(UserNotificationNudges.answer(to: UNNotificationDefaultActionIdentifier) == .open(pickingEnd: false))
        #expect(UserNotificationNudges.answer(to: UNNotificationDismissActionIdentifier) == nil)
    }

    @Test("SES-3: the notification asks about its session after the delay, with the answers' buttons")
    func requestNamesTheSession() throws {
        let id = UUID()

        let request = UserNotificationNudges.request(after: 600, sessionID: id)

        #expect(request.content.title == "Still practicing?")
        #expect(request.content.categoryIdentifier == UserNotificationNudges.answers.identifier)
        #expect(request.content.userInfo[UserNotificationNudges.sessionKey] as? String == id.uuidString)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 600)
        #expect(!trigger.repeats)
    }

    @Test("SES-3: each notification replaces the last, so a session has one at most")
    func requestsReplaceEachOther() {
        let first = UserNotificationNudges.request(after: 600, sessionID: UUID())
        let second = UserNotificationNudges.request(after: 300, sessionID: UUID())

        #expect(first.identifier == second.identifier)
    }

    @Test("SES-3: a delay that has run out still schedules, a second later, as a trigger needs a positive one")
    func delayIsPositive() throws {
        let request = UserNotificationNudges.request(after: 0, sessionID: UUID())

        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 1)
    }
}
