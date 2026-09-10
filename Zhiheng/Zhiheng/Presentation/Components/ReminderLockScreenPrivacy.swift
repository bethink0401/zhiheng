import Foundation
import UserNotifications

enum ReminderNotificationKind: CaseIterable, Sendable {
    case dailyCheckIn
    case microPlan
    case lowFrequencyTrend
}

struct ReminderLockScreenPublicContent: Equatable, Sendable {
    let title: String
    let body: String
}

enum ReminderLockScreenPrivacyPolicy {
    static let neutralContent = ReminderLockScreenPublicContent(
        title: "知衡提醒",
        body: "打开知衡查看。"
    )

    static func publicContent(
        for kind: ReminderNotificationKind
    ) -> ReminderLockScreenPublicContent {
        switch kind {
        case .dailyCheckIn, .microPlan, .lowFrequencyTrend:
            neutralContent
        }
    }

    static func makeSystemContent(
        for kind: ReminderNotificationKind
    ) -> UNMutableNotificationContent {
        let publicContent = publicContent(for: kind)
        let content = UNMutableNotificationContent()
        content.title = publicContent.title
        content.subtitle = ""
        content.body = publicContent.body
        content.sound = .default
        content.badge = nil
        content.launchImageName = ""
        content.userInfo = [:]
        content.attachments = []
        content.categoryIdentifier = ""
        content.threadIdentifier = ""
        content.targetContentIdentifier = nil
        return content
    }
}
