import Combine
import CryptoKit
import Foundation

struct LowFrequencyTrendReminderSettings: Equatable, Sendable {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

struct LowFrequencyTrendCandidate: Equatable, Sendable {
    let metric: HealthMetricType
    let direction: HealthMetricTrendDirection
    /// A one-way digest of rule version, metric and direction. No value is stored.
    let semanticKey: String
    let interactionIdentity: InsightInteractionIdentity
}

enum LowFrequencyTrendCandidateResult: Equatable, Sendable {
    case candidate(LowFrequencyTrendCandidate)
    case noQualifiedTrend
    case unavailable
}

enum LowFrequencyTrendCandidateRule {
    static let version = "s13-low-frequency-trend-v1"

    static func decide(factSet: InsightFactSet) -> LowFrequencyTrendCandidateResult {
        guard factSet.dataMode == .live else { return .unavailable }
        let metricOrder = Dictionary(uniqueKeysWithValues:
            HealthMetricType.allCases.enumerated().map { ($0.element, $0.offset) }
        )
        let candidates = factSet.facts.compactMap { fact -> (InsightFact, Double, HealthMetricTrendDirection)? in
            guard case let .evaluated(trend, sources) = fact.evidence,
                  case .trend(.sustainedChange) = trend.state,
                  trend.currentValidDayCount >= HealthDataQualityThresholds.shortTermMinimumValidDays,
                  trend.baselineValidDayCount >= HealthDataQualityThresholds.baselineMinimumValidDays,
                  trend.sourceIsStable,
                  !trend.isolatedOutlierExcluded,
                  sources.count == 1,
                  let change = trend.relativeChange,
                  change.isFinite,
                  change != 0,
                  let threshold = trend.effectiveRelativeThreshold,
                  threshold.isFinite,
                  threshold > 0 else { return nil }
            return (fact, abs(change) / threshold, change > 0 ? .higher : .lower)
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            return (metricOrder[left.0.metric] ?? .max) < (metricOrder[right.0.metric] ?? .max)
        }

        guard let (fact, _, direction) = candidates.first else {
            return factSet.facts.contains(where: {
                if case .evaluated = $0.evidence { return true }
                return false
            }) ? .noQualifiedTrend : .unavailable
        }
        let topic = InsightInteractionTopic.metricChange(fact.metric)
        let digest = digestName([
            version,
            topic.storageKey,
            direction.rawValue
        ].joined(separator: "\u{1F}"))
        return .candidate(LowFrequencyTrendCandidate(
            metric: fact.metric,
            direction: direction,
            semanticKey: digest.hex,
            interactionIdentity: InsightInteractionIdentity(
                insightID: digest.uuid,
                topic: topic,
                dataMode: .live
            )
        ))
    }

    private static func digestName(_ name: String) -> (hex: String, uuid: UUID) {
        let hash = Array(SHA256.hash(data: Data(name.utf8)))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return (hash.map { String(format: "%02x", $0) }.joined(), uuid)
    }
}

protocol LowFrequencyTrendCandidateProviding: Sendable {
    func candidate(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> LowFrequencyTrendCandidateResult
}

struct LocalLowFrequencyTrendCandidateProvider: LowFrequencyTrendCandidateProviding {
    func candidate(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> LowFrequencyTrendCandidateResult {
        guard let factSet = try? InsightFactGenerator.generate(
            snapshot: snapshot,
            loadedInterval: loadedInterval,
            access: access,
            dataMode: dataMode,
            referenceDate: referenceDate,
            timeZone: timeZone
        ) else { return .unavailable }
        return LowFrequencyTrendCandidateRule.decide(factSet: factSet)
    }
}

struct LowFrequencyTrendReminderRequest: Equatable, Sendable {
    let identifier: String
    let localDayKey: String
    let fireDate: Date
    let semanticKey: String
}

enum LowFrequencyTrendReminderPolicy {
    static let identifierPrefix = "zhiheng.low-frequency-trend."
    static let defaultHour = 10

    static func request(
        settings: LowFrequencyTrendReminderSettings,
        authorizationStatus: NotificationAuthorizationStatus,
        isLiveMode: Bool,
        candidate: LowFrequencyTrendCandidate?,
        remindersDisabled: Bool?,
        handledSemanticKeys: Set<String>,
        pendingSemanticKey: String?,
        pendingFireDate: Date?,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> LowFrequencyTrendReminderRequest? {
        guard settings.isEnabled,
              authorizationStatus.isEnabled,
              isLiveMode,
              let candidate,
              remindersDisabled == false else { return nil }

        if handledSemanticKeys.contains(candidate.semanticKey) {
            guard pendingSemanticKey == candidate.semanticKey,
                  let pendingFireDate,
                  pendingFireDate > referenceDate else { return nil }
            return makeRequest(
                candidate: candidate,
                fireDate: pendingFireDate,
                timeZone: timeZone
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: referenceDate)
        guard let todayFireDate = calendar.date(
            bySettingHour: defaultHour,
            minute: 0,
            second: 0,
            of: today
        ) else { return nil }
        let fireDate: Date
        if todayFireDate > referenceDate {
            fireDate = todayFireDate
        } else {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  let tomorrowFireDate = calendar.date(
                    bySettingHour: defaultHour,
                    minute: 0,
                    second: 0,
                    of: tomorrow
                  ) else { return nil }
            fireDate = tomorrowFireDate
        }
        return makeRequest(candidate: candidate, fireDate: fireDate, timeZone: timeZone)
    }

    private static func makeRequest(
        candidate: LowFrequencyTrendCandidate,
        fireDate: Date,
        timeZone: TimeZone
    ) -> LowFrequencyTrendReminderRequest {
        let localDayKey = SubjectiveLocalDay(date: fireDate, timeZone: timeZone).storageKey
        return LowFrequencyTrendReminderRequest(
            identifier: identifierPrefix + localDayKey,
            localDayKey: localDayKey,
            fireDate: fireDate,
            semanticKey: candidate.semanticKey
        )
    }
}

protocol LowFrequencyTrendReminderScheduling: Sendable {
    func replacePendingTrendReminders(
        with requests: [LowFrequencyTrendReminderRequest],
        timeZone: TimeZone
    ) async throws -> [LowFrequencyTrendReminderRequest]
}

@MainActor
final class LowFrequencyTrendReminderSession: ObservableObject {
    static let enabledKey = "lowFrequencyTrendReminder.enabled.v1"
    static let handledSemanticKeysKey = "lowFrequencyTrendReminder.handledSemanticKeys.v1"
    static let pendingSemanticKeyKey = "lowFrequencyTrendReminder.pendingSemanticKey.v1"
    static let pendingFireDateKey = "lowFrequencyTrendReminder.pendingFireDate.v1"

    @Published private(set) var settings: LowFrequencyTrendReminderSettings
    @Published private(set) var nextReminderDate: Date?
    @Published private(set) var statusMessage: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isUpdating = false

    private let interactionStore: any InsightInteractionStore
    private let authorizationSession: NotificationAuthorizationSession
    private let scheduler: any LowFrequencyTrendReminderScheduling
    private let candidateProvider: any LowFrequencyTrendCandidateProviding
    private let preferences: UserDefaults
    private var updateRevision = 0

    init(
        interactionStore: any InsightInteractionStore,
        authorizationSession: NotificationAuthorizationSession,
        scheduler: any LowFrequencyTrendReminderScheduling =
            SystemNotificationReminderScheduler(),
        candidateProvider: any LowFrequencyTrendCandidateProviding =
            LocalLowFrequencyTrendCandidateProvider(),
        preferences: UserDefaults = .standard
    ) {
        self.interactionStore = interactionStore
        self.authorizationSession = authorizationSession
        self.scheduler = scheduler
        self.candidateProvider = candidateProvider
        self.preferences = preferences
        let isEnabled = preferences.bool(forKey: Self.enabledKey)
        settings = LowFrequencyTrendReminderSettings(isEnabled: isEnabled)
        statusMessage = isEnabled
            ? "正在确认是否有值得提醒的新趋势…"
            : "默认关闭；开启后只提醒质量合格的持续变化。"
    }

    func setEnabled(
        _ isEnabled: Bool,
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        guard settings.isEnabled != isEnabled else { return }
        if isEnabled && !authorizationSession.authorizationStatus.isEnabled {
            errorMessage = "请先允许知衡发送通知，再开启低频趋势提醒。"
            return
        }
        settings.isEnabled = isEnabled
        preferences.set(isEnabled, forKey: Self.enabledKey)
        await synchronize(
            snapshot: snapshot,
            loadedInterval: loadedInterval,
            access: access,
            dataMode: dataMode,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
    }

    func synchronize(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async {
        updateRevision += 1
        let revision = updateRevision
        isUpdating = true
        errorMessage = nil

        let authorizationStatus = authorizationSession.authorizationStatus
        var result = LowFrequencyTrendCandidateResult.unavailable
        var candidate: LowFrequencyTrendCandidate?
        var remindersDisabled: Bool?
        var preferenceReadFailed = false

        if settings.isEnabled && authorizationStatus.isEnabled && dataMode == .live {
            result = candidateProvider.candidate(
                snapshot: snapshot,
                loadedInterval: loadedInterval,
                access: access,
                dataMode: dataMode,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
            if case .candidate(let value) = result {
                candidate = value
                do {
                    remindersDisabled = try interactionStore.state(
                        for: value.interactionIdentity
                    ).areRemindersDisabled
                } catch {
                    remindersDisabled = nil
                    preferenceReadFailed = true
                }
            }
        }

        let handledKeys = Set(
            preferences.stringArray(forKey: Self.handledSemanticKeysKey) ?? []
        )
        let pendingSemanticKey = preferences.string(forKey: Self.pendingSemanticKeyKey)
        let pendingFireDate = preferences.object(forKey: Self.pendingFireDateKey) as? Date
        let request = LowFrequencyTrendReminderPolicy.request(
            settings: settings,
            authorizationStatus: authorizationStatus,
            isLiveMode: dataMode == .live,
            candidate: candidate,
            remindersDisabled: remindersDisabled,
            handledSemanticKeys: handledKeys,
            pendingSemanticKey: pendingSemanticKey,
            pendingFireDate: pendingFireDate,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        do {
            let scheduled = try await scheduler.replacePendingTrendReminders(
                with: request.map { [$0] } ?? [],
                timeZone: timeZone
            )
            guard revision == updateRevision else { return }
            nextReminderDate = scheduled.first?.fireDate
            if let scheduledRequest = scheduled.first,
               !handledKeys.contains(scheduledRequest.semanticKey) {
                let updatedKeys = (handledKeys.union([scheduledRequest.semanticKey])).sorted()
                preferences.set(updatedKeys, forKey: Self.handledSemanticKeysKey)
                preferences.set(
                    scheduledRequest.semanticKey,
                    forKey: Self.pendingSemanticKeyKey
                )
                preferences.set(
                    scheduledRequest.fireDate,
                    forKey: Self.pendingFireDateKey
                )
            }
            statusMessage = statusText(
                authorizationStatus: authorizationStatus,
                dataMode: dataMode,
                result: result,
                candidate: candidate,
                remindersDisabled: remindersDisabled,
                preferenceReadFailed: preferenceReadFailed,
                wasAlreadyHandled: candidate.map {
                    handledKeys.contains($0.semanticKey)
                } ?? false,
                hadRequest: request != nil,
                nextDate: scheduled.first?.fireDate,
                timeZone: timeZone
            )
        } catch {
            guard revision == updateRevision else { return }
            nextReminderDate = nil
            errorMessage = settings.isEnabled
                ? "暂时无法安排低频趋势提醒，请稍后重试。"
                : "暂时无法确认低频趋势提醒已关闭，请稍后重试。"
            statusMessage = "没有把本次操作显示为已成功。"
        }
        if revision == updateRevision { isUpdating = false }
    }

    private func statusText(
        authorizationStatus: NotificationAuthorizationStatus,
        dataMode: HealthDataMode,
        result: LowFrequencyTrendCandidateResult,
        candidate: LowFrequencyTrendCandidate?,
        remindersDisabled: Bool?,
        preferenceReadFailed: Bool,
        wasAlreadyHandled: Bool,
        hadRequest: Bool,
        nextDate: Date?,
        timeZone: TimeZone
    ) -> String {
        guard settings.isEnabled else {
            return "已关闭，不会发送低频趋势提醒。"
        }
        guard authorizationStatus.isEnabled else {
            return "提醒偏好已保留，但系统当前不允许发送通知。"
        }
        guard dataMode == .live else {
            return "演示模式不会安排你的真实趋势提醒。"
        }
        guard !preferenceReadFailed else {
            return "暂时无法读取同类提醒偏好，因此没有安排提醒。"
        }
        guard remindersDisabled != true else {
            return "这类趋势提醒已由你关闭；洞悉页内容仍可查看。"
        }
        switch result {
        case .unavailable:
            return "健康数据或质量状态暂时不足，因此没有安排提醒。"
        case .noQualifiedTrend:
            return "目前没有质量合格的持续变化需要提醒。"
        case .candidate:
            break
        }
        if wasAlreadyHandled && nextDate == nil {
            return "同一持续变化已经处理，不会重复提醒。"
        }
        guard let nextDate else {
            return candidate != nil && hadRequest
                ? "受安静时间、提醒频率或更高优先级提醒影响，暂未安排趋势提醒。"
                : "目前没有可安排的趋势提醒。"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return "下一次提醒：\(formatter.string(from: nextDate))。同一持续变化不会重复提醒。"
    }
}
