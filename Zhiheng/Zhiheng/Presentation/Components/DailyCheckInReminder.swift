import Combine
import Foundation
import UserNotifications

struct DailyCheckInReminderSettings: Equatable, Sendable {
    static let defaultHour = 20
    static let defaultMinute = 0

    var isEnabled: Bool
    var hour: Int
    var minute: Int

    init(
        isEnabled: Bool = false,
        hour: Int = defaultHour,
        minute: Int = defaultMinute
    ) {
        self.isEnabled = isEnabled
        self.hour = (0...23).contains(hour) ? hour : Self.defaultHour
        self.minute = (0...59).contains(minute) ? minute : Self.defaultMinute
    }
}

struct DailyCheckInReminderRequest: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
}

enum DailyCheckInReminderPolicy {
    static let identifierPrefix = "zhiheng.daily-check-in."
    static let rollingDayCount = 30

    static func requests(
        settings: DailyCheckInReminderSettings,
        authorizationStatus: NotificationAuthorizationStatus,
        isLiveMode: Bool,
        hasCheckInToday: Bool?,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> [DailyCheckInReminderRequest] {
        guard settings.isEnabled,
              authorizationStatus.isEnabled,
              isLiveMode,
              let hasCheckInToday else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: referenceDate)
        guard let todayFireDate = calendar.date(
            bySettingHour: settings.hour,
            minute: settings.minute,
            second: 0,
            of: today
        ) else { return [] }

        let startsTomorrow = hasCheckInToday || todayFireDate <= referenceDate
        let firstOffset = startsTomorrow ? 1 : 0

        return (0..<rollingDayCount).compactMap { offset in
            guard let day = calendar.date(
                byAdding: .day,
                value: firstOffset + offset,
                to: today
            ), let fireDate = calendar.date(
                bySettingHour: settings.hour,
                minute: settings.minute,
                second: 0,
                of: day
            ) else { return nil }
            let localDay = SubjectiveLocalDay(date: fireDate, timeZone: timeZone)
            return DailyCheckInReminderRequest(
                identifier: identifierPrefix + localDay.storageKey,
                fireDate: fireDate
            )
        }
    }
}

protocol DailyCheckInReminderScheduling: Sendable {
    func replacePendingReminders(
        with requests: [DailyCheckInReminderRequest],
        timeZone: TimeZone
    ) async throws -> [DailyCheckInReminderRequest]
}

enum NotificationDailyBudget {
    static func dailyCheckInRequests(
        _ requests: [DailyCheckInReminderRequest],
        reservingMicroPlanIdentifiers identifiers: [String]
    ) -> [DailyCheckInReminderRequest] {
        let reservedDayKeys = dayKeys(
            in: identifiers,
            prefixes: [
                MicroPlanReminderPolicy.identifierPrefix,
                LowFrequencyTrendReminderPolicy.identifierPrefix
            ]
        )
        return requests.filter { request in
            let dayKey = String(request.identifier.dropFirst(
                DailyCheckInReminderPolicy.identifierPrefix.count
            ))
            return !reservedDayKeys.contains(dayKey)
        }
    }

    static func trendRequests(
        _ requests: [LowFrequencyTrendReminderRequest],
        reservingMicroPlanIdentifiers identifiers: [String]
    ) -> [LowFrequencyTrendReminderRequest] {
        let reservedDayKeys = dayKeys(
            in: identifiers,
            prefixes: [MicroPlanReminderPolicy.identifierPrefix]
        )
        return requests.filter { !reservedDayKeys.contains($0.localDayKey) }
    }

    private static func dayKeys(
        in identifiers: [String],
        prefixes: [String]
    ) -> Set<String> {
        Set(identifiers.compactMap { identifier -> String? in
            guard let prefix = prefixes.first(where: identifier.hasPrefix) else {
                return nil
            }
            return String(identifier.dropFirst(prefix.count))
        })
    }
}

actor SystemNotificationReminderScheduler:
    DailyCheckInReminderScheduling,
    MicroPlanReminderScheduling,
    LowFrequencyTrendReminderScheduling {
    private let center: UNUserNotificationCenter
    private let deliverySettingsStore: NotificationDeliverySettingsStore

    init(
        center: UNUserNotificationCenter = .current(),
        deliverySettingsStore: NotificationDeliverySettingsStore = .init()
    ) {
        self.center = center
        self.deliverySettingsStore = deliverySettingsStore
    }

    func replacePendingReminders(
        with requests: [DailyCheckInReminderRequest],
        timeZone: TimeZone
    ) async throws -> [DailyCheckInReminderRequest] {
        let pending = await pendingIdentifiers()
        let existing = pending
            .filter { $0.hasPrefix(DailyCheckInReminderPolicy.identifierPrefix) }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }
        let budgetedRequests = NotificationDailyBudget.dailyCheckInRequests(
            requests,
            reservingMicroPlanIdentifiers: pending
        )
        let deliverySettings = deliverySettingsStore.current()
        let higherPriorityIdentifiers = pending.filter {
            $0.hasPrefix(MicroPlanReminderPolicy.identifierPrefix)
                || $0.hasPrefix(LowFrequencyTrendReminderPolicy.identifierPrefix)
        }
        let allowedIdentifiers = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: budgetedRequests.map {
                NotificationDeliveryCandidate(
                    identifier: $0.identifier,
                    fireDate: $0.fireDate
                )
            },
            reservingHigherPriorityIdentifiers: higherPriorityIdentifiers,
            settings: deliverySettings,
            timeZone: timeZone
        )
        let deliverableRequests = budgetedRequests.filter {
            allowedIdentifiers.contains($0.identifier)
        }
        guard !deliverableRequests.isEmpty else { return [] }

        var addedIdentifiers: [String] = []
        do {
            for reminder in deliverableRequests {
                try await add(
                    identifier: reminder.identifier,
                    fireDate: reminder.fireDate,
                    kind: .dailyCheckIn,
                    timeZone: timeZone
                )
                addedIdentifiers.append(reminder.identifier)
            }
            return deliverableRequests
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: addedIdentifiers)
            throw error
        }
    }

    func replacePendingPlanReminders(
        with requests: [MicroPlanReminderRequest],
        timeZone: TimeZone
    ) async throws -> [MicroPlanReminderRequest] {
        let pending = await pendingIdentifiers()
        let existing = pending.filter {
            $0.hasPrefix(MicroPlanReminderPolicy.identifierPrefix)
        }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }
        let deliverySettings = deliverySettingsStore.current()
        let allowedIdentifiers = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: requests.map {
                NotificationDeliveryCandidate(
                    identifier: $0.identifier,
                    fireDate: $0.fireDate
                )
            },
            reservingHigherPriorityIdentifiers: [],
            settings: deliverySettings,
            timeZone: timeZone
        )
        let deliverableRequests = requests.filter {
            allowedIdentifiers.contains($0.identifier)
        }
        guard !deliverableRequests.isEmpty else { return [] }

        var addedIdentifiers: [String] = []
        do {
            for reminder in deliverableRequests {
                try await add(
                    identifier: reminder.identifier,
                    fireDate: reminder.fireDate,
                    kind: .microPlan,
                    timeZone: timeZone
                )
                addedIdentifiers.append(reminder.identifier)
            }
            let lowerPriorityIdentifiers = NotificationDeliveryPolicy
                .lowerPriorityIdentifiersToRemove(
                    from: pending,
                    matchingPrefixes: [
                        LowFrequencyTrendReminderPolicy.identifierPrefix,
                        DailyCheckInReminderPolicy.identifierPrefix
                    ],
                    for: deliverableRequests.map {
                        NotificationDeliveryCandidate(
                            identifier: $0.identifier,
                            fireDate: $0.fireDate
                        )
                    },
                    settings: deliverySettings,
                    timeZone: timeZone
                )
            center.removePendingNotificationRequests(
                withIdentifiers: lowerPriorityIdentifiers
            )
            return deliverableRequests
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: addedIdentifiers)
            throw error
        }
    }

    func replacePendingTrendReminders(
        with requests: [LowFrequencyTrendReminderRequest],
        timeZone: TimeZone
    ) async throws -> [LowFrequencyTrendReminderRequest] {
        let pending = await pendingIdentifiers()
        let existing = pending.filter {
            $0.hasPrefix(LowFrequencyTrendReminderPolicy.identifierPrefix)
        }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }
        let budgetedRequests = NotificationDailyBudget.trendRequests(
            requests,
            reservingMicroPlanIdentifiers: pending
        )
        let deliverySettings = deliverySettingsStore.current()
        let higherPriorityIdentifiers = pending.filter {
            $0.hasPrefix(MicroPlanReminderPolicy.identifierPrefix)
        }
        let allowedIdentifiers = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: budgetedRequests.map {
                NotificationDeliveryCandidate(
                    identifier: $0.identifier,
                    fireDate: $0.fireDate
                )
            },
            reservingHigherPriorityIdentifiers: higherPriorityIdentifiers,
            settings: deliverySettings,
            timeZone: timeZone
        )
        let deliverableRequests = budgetedRequests.filter {
            allowedIdentifiers.contains($0.identifier)
        }
        guard !deliverableRequests.isEmpty else { return [] }

        var addedIdentifiers: [String] = []
        do {
            for reminder in deliverableRequests {
                try await add(
                    identifier: reminder.identifier,
                    fireDate: reminder.fireDate,
                    kind: .lowFrequencyTrend,
                    timeZone: timeZone
                )
                addedIdentifiers.append(reminder.identifier)
            }
            let dailyIdentifiers = NotificationDeliveryPolicy
                .lowerPriorityIdentifiersToRemove(
                    from: pending,
                    matchingPrefixes: [
                        DailyCheckInReminderPolicy.identifierPrefix
                    ],
                    for: deliverableRequests.map {
                        NotificationDeliveryCandidate(
                            identifier: $0.identifier,
                            fireDate: $0.fireDate
                        )
                    },
                    settings: deliverySettings,
                    timeZone: timeZone
                )
            center.removePendingNotificationRequests(withIdentifiers: dailyIdentifiers)
            return deliverableRequests
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: addedIdentifiers)
            throw error
        }
    }

    private func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    private func add(
        identifier: String,
        fireDate: Date,
        kind: ReminderNotificationKind,
        timeZone: TimeZone
    ) async throws {
        let content = ReminderLockScreenPrivacyPolicy.makeSystemContent(for: kind)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.calendar = calendar
        components.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class DailyCheckInReminderSession: ObservableObject {
    static let enabledKey = "dailyCheckInReminder.enabled.v1"
    static let hourKey = "dailyCheckInReminder.hour.v1"
    static let minuteKey = "dailyCheckInReminder.minute.v1"

    @Published private(set) var settings: DailyCheckInReminderSettings
    @Published private(set) var nextReminderDate: Date?
    @Published private(set) var statusMessage: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isUpdating = false

    private let store: any SubjectiveRecordStore
    private let authorizationSession: NotificationAuthorizationSession
    private let scheduler: any DailyCheckInReminderScheduling
    private let preferences: UserDefaults
    private var updateRevision = 0

    init(
        store: any SubjectiveRecordStore,
        authorizationSession: NotificationAuthorizationSession,
        scheduler: any DailyCheckInReminderScheduling =
            SystemNotificationReminderScheduler(),
        preferences: UserDefaults = .standard
    ) {
        self.store = store
        self.authorizationSession = authorizationSession
        self.scheduler = scheduler
        self.preferences = preferences
        let storedHour = preferences.object(forKey: Self.hourKey) as? Int
        let storedMinute = preferences.object(forKey: Self.minuteKey) as? Int
        settings = DailyCheckInReminderSettings(
            isEnabled: preferences.bool(forKey: Self.enabledKey),
            hour: storedHour ?? DailyCheckInReminderSettings.defaultHour,
            minute: storedMinute ?? DailyCheckInReminderSettings.defaultMinute
        )
        statusMessage = preferences.bool(forKey: Self.enabledKey)
            ? "正在确认下一次提醒…"
            : "默认关闭；开启后才会安排每日感受提醒。"
    }

    var selectedTime: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(
            bySettingHour: settings.hour,
            minute: settings.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    func setEnabled(
        _ isEnabled: Bool,
        isLiveMode: Bool,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        guard settings.isEnabled != isEnabled else { return }
        if isEnabled && !authorizationSession.authorizationStatus.isEnabled {
            errorMessage = "请先允许知衡发送通知，再开启每日感受提醒。"
            return
        }
        settings.isEnabled = isEnabled
        preferences.set(isEnabled, forKey: Self.enabledKey)
        await synchronize(
            isLiveMode: isLiveMode,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
    }

    func updateTime(
        from date: Date,
        isLiveMode: Bool,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        let updated = DailyCheckInReminderSettings(
            isEnabled: settings.isEnabled,
            hour: hour,
            minute: minute
        )
        guard updated != settings else { return }
        settings = updated
        preferences.set(updated.hour, forKey: Self.hourKey)
        preferences.set(updated.minute, forKey: Self.minuteKey)
        await synchronize(
            isLiveMode: isLiveMode,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
    }

    func synchronize(
        isLiveMode: Bool,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        updateRevision += 1
        let revision = updateRevision
        isUpdating = true
        errorMessage = nil

        let authorizationStatus = authorizationSession.authorizationStatus
        let hasCheckInToday: Bool?
        if settings.isEnabled && authorizationStatus.isEnabled && isLiveMode {
            do {
                let day = SubjectiveLocalDay(date: referenceDate, timeZone: timeZone)
                hasCheckInToday = try store.checkIn(on: day) != nil
            } catch {
                hasCheckInToday = nil
            }
        } else {
            hasCheckInToday = false
        }

        let requests = DailyCheckInReminderPolicy.requests(
            settings: settings,
            authorizationStatus: authorizationStatus,
            isLiveMode: isLiveMode,
            hasCheckInToday: hasCheckInToday,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        do {
            let scheduledRequests = try await scheduler.replacePendingReminders(
                with: requests,
                timeZone: timeZone
            )
            guard revision == updateRevision else { return }
            nextReminderDate = scheduledRequests.first?.fireDate
            statusMessage = statusText(
                authorizationStatus: authorizationStatus,
                isLiveMode: isLiveMode,
                hasCheckInToday: hasCheckInToday,
                nextDate: scheduledRequests.first?.fireDate,
                timeZone: timeZone
            )
        } catch {
            guard revision == updateRevision else { return }
            nextReminderDate = nil
            errorMessage = settings.isEnabled
                ? "暂时无法安排每日感受提醒，请稍后重试。"
                : "暂时无法确认提醒已关闭，请稍后重试。"
            statusMessage = "没有把本次操作显示为已成功。"
        }
        if revision == updateRevision { isUpdating = false }
    }

    private func statusText(
        authorizationStatus: NotificationAuthorizationStatus,
        isLiveMode: Bool,
        hasCheckInToday: Bool?,
        nextDate: Date?,
        timeZone: TimeZone
    ) -> String {
        guard settings.isEnabled else {
            return "已关闭，不会发送每日感受提醒。"
        }
        guard authorizationStatus.isEnabled else {
            return "提醒偏好已保留，但系统当前不允许发送通知。"
        }
        guard isLiveMode else {
            return "演示模式不会安排你的真实每日感受提醒。"
        }
        guard hasCheckInToday != nil else {
            return "暂时无法确认今天是否已记录，因此没有安排提醒。"
        }
        guard let nextDate else {
            return "暂时没有可安排的提醒时间。"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return "下一次提醒：\(formatter.string(from: nextDate))。签到后会自动跳过当天剩余提醒。"
    }
}
