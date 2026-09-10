import Combine
import Foundation

struct MicroPlanReminderSettings: Equatable, Sendable {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

struct MicroPlanReminderDay: Equatable, Sendable {
    let date: Date
    let occurrenceIndex: Int
    let hasOutcome: Bool
}

struct MicroPlanReminderRequest: Equatable, Sendable {
    let identifier: String
    let localDayKey: String
    let fireDate: Date
}

enum MicroPlanReminderPolicy {
    static let identifierPrefix = "zhiheng.micro-plan."

    static func requests(
        settings: MicroPlanReminderSettings,
        authorizationStatus: NotificationAuthorizationStatus,
        isLiveMode: Bool,
        plan: MicroPlan?,
        days: [MicroPlanReminderDay],
        referenceDate: Date,
        timeZone: TimeZone
    ) -> [MicroPlanReminderRequest] {
        guard settings.isEnabled,
              authorizationStatus.isEnabled,
              isLiveMode,
              let plan,
              plan.status == .active else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let planStart = calendar.startOfDay(for: plan.draft.startDate)
        let planEnd = plan.draft.endDateExclusive
        var seenDayKeys = Set<String>()

        return days.sorted { $0.date < $1.date }.compactMap { day in
            let dayStart = calendar.startOfDay(for: day.date)
            guard !day.hasOutcome,
                  dayStart >= planStart,
                  dayStart < planEnd,
                  let fireDate = calendar.date(
                    bySettingHour: plan.draft.scheduledTime.hour,
                    minute: plan.draft.scheduledTime.minute,
                    second: 0,
                    of: dayStart
                  ),
                  fireDate > referenceDate else { return nil }

            let localDayKey = SubjectiveLocalDay(
                date: fireDate,
                timeZone: timeZone
            ).storageKey
            guard seenDayKeys.insert(localDayKey).inserted else { return nil }
            return MicroPlanReminderRequest(
                identifier: identifierPrefix + localDayKey,
                localDayKey: localDayKey,
                fireDate: fireDate
            )
        }
    }
}

protocol MicroPlanReminderScheduling: Sendable {
    func replacePendingPlanReminders(
        with requests: [MicroPlanReminderRequest],
        timeZone: TimeZone
    ) async throws -> [MicroPlanReminderRequest]
}

@MainActor
final class MicroPlanReminderSession: ObservableObject {
    static let enabledKey = "microPlanReminder.enabled.v1"
    private static let maximumScannedDayCount = 60

    @Published private(set) var settings: MicroPlanReminderSettings
    @Published private(set) var nextReminderDate: Date?
    @Published private(set) var statusMessage: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isUpdating = false

    private let service: any CarePlanService
    private let authorizationSession: NotificationAuthorizationSession
    private let scheduler: any MicroPlanReminderScheduling
    private let preferences: UserDefaults
    private var updateRevision = 0

    init(
        service: any CarePlanService,
        authorizationSession: NotificationAuthorizationSession,
        scheduler: any MicroPlanReminderScheduling =
            SystemNotificationReminderScheduler(),
        preferences: UserDefaults = .standard
    ) {
        self.service = service
        self.authorizationSession = authorizationSession
        self.scheduler = scheduler
        self.preferences = preferences
        let isEnabled = preferences.bool(forKey: Self.enabledKey)
        settings = MicroPlanReminderSettings(isEnabled: isEnabled)
        statusMessage = isEnabled
            ? "正在确认下一次微计划提醒…"
            : "默认关闭；开启后才会按计划时间提醒。"
    }

    func setEnabled(
        _ isEnabled: Bool,
        isLiveMode: Bool,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        guard settings.isEnabled != isEnabled else { return }
        if isEnabled && !authorizationSession.authorizationStatus.isEnabled {
            errorMessage = "请先允许知衡发送通知，再开启微计划提醒。"
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
        var plan: MicroPlan?
        var days = [MicroPlanReminderDay]()
        var readFailed = false

        if settings.isEnabled && authorizationStatus.isEnabled && isLiveMode {
            do {
                plan = try await service.activePlan()
                if let plan, plan.status == .active {
                    days = try await loadReminderDays(
                        for: plan,
                        referenceDate: referenceDate,
                        timeZone: timeZone
                    )
                }
            } catch {
                plan = nil
                days = []
                readFailed = true
            }
        }

        let requests = MicroPlanReminderPolicy.requests(
            settings: settings,
            authorizationStatus: authorizationStatus,
            isLiveMode: isLiveMode,
            plan: plan,
            days: days,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        do {
            let scheduledRequests = try await scheduler.replacePendingPlanReminders(
                with: requests,
                timeZone: timeZone
            )
            guard revision == updateRevision else { return }
            nextReminderDate = scheduledRequests.first?.fireDate
            statusMessage = statusText(
                authorizationStatus: authorizationStatus,
                isLiveMode: isLiveMode,
                plan: plan,
                readFailed: readFailed,
                hadRequest: !requests.isEmpty,
                nextDate: scheduledRequests.first?.fireDate,
                timeZone: timeZone
            )
        } catch {
            guard revision == updateRevision else { return }
            nextReminderDate = nil
            errorMessage = settings.isEnabled
                ? "暂时无法安排微计划提醒，请稍后重试。"
                : "暂时无法确认微计划提醒已关闭，请稍后重试。"
            statusMessage = "没有把本次操作显示为已成功。"
        }
        if revision == updateRevision { isUpdating = false }
    }

    private func loadReminderDays(
        for plan: MicroPlan,
        referenceDate: Date,
        timeZone: TimeZone
    ) async throws -> [MicroPlanReminderDay] {
        let records = try await service.outcomeRecords(for: plan.draft.taskID)
        let recordedIndices = Set(records.map(\.occurrenceIndex))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var day = max(
            calendar.startOfDay(for: referenceDate),
            calendar.startOfDay(for: plan.draft.startDate)
        )
        var scannedDayCount = 0
        var result = [MicroPlanReminderDay]()

        while day < plan.draft.endDateExclusive {
            scannedDayCount += 1
            guard scannedDayCount <= Self.maximumScannedDayCount else {
                throw CarePlanServiceError.persistenceFailed
            }
            if let occurrenceIndex = try await service.occurrenceIndex(
                for: plan.draft.taskID,
                on: day
            ) {
                result.append(MicroPlanReminderDay(
                    date: day,
                    occurrenceIndex: occurrenceIndex,
                    hasOutcome: recordedIndices.contains(occurrenceIndex)
                ))
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                throw CarePlanServiceError.persistenceFailed
            }
            day = nextDay
        }
        return result
    }

    private func statusText(
        authorizationStatus: NotificationAuthorizationStatus,
        isLiveMode: Bool,
        plan: MicroPlan?,
        readFailed: Bool,
        hadRequest: Bool,
        nextDate: Date?,
        timeZone: TimeZone
    ) -> String {
        guard settings.isEnabled else {
            return "已关闭，不会发送微计划提醒。"
        }
        guard authorizationStatus.isEnabled else {
            return "提醒偏好已保留，但系统当前不允许发送通知。"
        }
        guard isLiveMode else {
            return "演示模式不会安排你的真实微计划提醒。"
        }
        guard !readFailed else {
            return "暂时无法读取微计划状态，因此没有安排提醒。"
        }
        guard let plan else {
            return "有进行中的微计划时，会按计划时间提醒。"
        }
        guard plan.status == .active else {
            return "计划暂停期间不会发送提醒，恢复后会重新安排。"
        }
        if hadRequest && nextDate == nil {
            return "受安静时间或提醒频率影响，当前计划提醒已跳过。"
        }
        guard let nextDate else {
            return "当前没有待发送的微计划提醒；已记录的日期不会重复提醒。"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return "下一次提醒：\(formatter.string(from: nextDate))。完成、跳过、暂停或结束后会自动更新。"
    }
}
