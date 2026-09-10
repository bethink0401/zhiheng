import UserNotifications
import XCTest
@testable import Zhiheng

final class ReminderLockScreenPrivacyTests: XCTestCase {
    func testEveryReminderKindUsesExactlyTheSameNeutralPublicCopy() {
        let contents = ReminderNotificationKind.allCases.map {
            ReminderLockScreenPrivacyPolicy.publicContent(for: $0)
        }

        XCTAssertEqual(Set(contents.map(\.title)), ["知衡提醒"])
        XCTAssertEqual(Set(contents.map(\.body)), ["打开知衡查看。"])
    }

    func testPublicCopyDoesNotRevealReminderTypeOrHealthDetails() {
        let visibleCopy = [
            ReminderLockScreenPrivacyPolicy.neutralContent.title,
            ReminderLockScreenPrivacyPolicy.neutralContent.body
        ].joined(separator: " ")
        let forbiddenFragments = [
            "感受", "签到", "计划", "行动", "完成", "跳过", "反馈",
            "趋势", "观察", "变化", "数据", "指标", "数值", "来源",
            "精力", "压力", "症状", "睡眠", "心率", "HRV", "步数",
            "血氧", "体温", "呼吸", "异常", "风险", "AI", "%"
        ]

        for fragment in forbiddenFragments {
            XCTAssertFalse(visibleCopy.contains(fragment), "锁屏不得包含：\(fragment)")
        }
        XCTAssertFalse(visibleCopy.contains(where: \.isNumber))
    }

    func testSystemContentContainsOnlyPublicTitleBodyAndDefaultSound() {
        for kind in ReminderNotificationKind.allCases {
            let content = ReminderLockScreenPrivacyPolicy.makeSystemContent(for: kind)

            XCTAssertEqual(content.title, "知衡提醒")
            XCTAssertEqual(content.subtitle, "")
            XCTAssertEqual(content.body, "打开知衡查看。")
            XCTAssertNotNil(content.sound)
            XCTAssertNil(content.badge)
        }
    }

    func testSystemContentCarriesNoPrivatePayloadOrAttachment() {
        for kind in ReminderNotificationKind.allCases {
            let content = ReminderLockScreenPrivacyPolicy.makeSystemContent(for: kind)

            XCTAssertTrue(content.userInfo.isEmpty)
            XCTAssertTrue(content.attachments.isEmpty)
            XCTAssertEqual(content.launchImageName, "")
            XCTAssertNil(content.targetContentIdentifier)
        }
    }

    func testSystemContentAddsNoCategoryOrThreadThatCouldRevealType() {
        for kind in ReminderNotificationKind.allCases {
            let content = ReminderLockScreenPrivacyPolicy.makeSystemContent(for: kind)

            XCTAssertEqual(content.categoryIdentifier, "")
            XCTAssertEqual(content.threadIdentifier, "")
        }
    }

    func testPrivacyExplanationShowsTheExactDefaultLockScreenPreview() {
        XCTAssertTrue(NotificationPermissionCopy.lockScreenPrivacy.contains("知衡提醒"))
        XCTAssertTrue(NotificationPermissionCopy.lockScreenPrivacy.contains("打开知衡查看"))
        XCTAssertTrue(NotificationPermissionCopy.lockScreenPrivacy.contains("不显示提醒类型"))
    }
}
