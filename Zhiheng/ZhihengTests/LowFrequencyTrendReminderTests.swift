import XCTest
@testable import Zhiheng

@MainActor
final class LowFrequencyTrendReminderTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testCandidateRuleRequiresSustainedQualityQualifiedStableTrend() {
        let qualified = factSet(level: .sustainedChange)
        guard case .candidate(let candidate) = LowFrequencyTrendCandidateRule.decide(
            factSet: qualified
        ) else { return XCTFail("应选择持续变化") }
        XCTAssertEqual(candidate.metric, .stepCount)
        XCTAssertEqual(candidate.direction, .higher)
        XCTAssertEqual(candidate.interactionIdentity.topic, .metricChange(.stepCount))
        XCTAssertEqual(candidate.semanticKey.count, 64)
        XCTAssertFalse(candidate.semanticKey.contains(HealthMetricType.stepCount.rawValue))

        for input in [
            factSet(level: .worthObserving),
            factSet(level: .noClearChange),
            factSet(level: .sustainedChange, stable: false),
            factSet(level: .sustainedChange, outlier: true),
            factSet(level: .sustainedChange, currentCount: 3),
            factSet(level: .sustainedChange, baselineCount: 13)
        ] {
            XCTAssertNotEqual(
                LowFrequencyTrendCandidateRule.decide(factSet: input),
                .candidate(candidate)
            )
        }
    }

    func testCandidateDirectionChangesSemanticIdentityWithoutUsingValues() {
        guard case .candidate(let higher) = LowFrequencyTrendCandidateRule.decide(
            factSet: factSet(level: .sustainedChange, relativeChange: 0.4)
        ), case .candidate(let lower) = LowFrequencyTrendCandidateRule.decide(
            factSet: factSet(level: .sustainedChange, relativeChange: -0.4)
        ) else { return XCTFail("应生成两个方向候选") }

        XCTAssertNotEqual(higher.semanticKey, lower.semanticKey)
        XCTAssertNotEqual(higher.interactionIdentity.insightID, lower.interactionIdentity.insightID)
        XCTAssertEqual(lower.direction, .lower)
    }

    func testPolicyRequiresAllGatesAndUsesNextDaytimeSlot() {
        let now = date(2026, 9, 6, 11, 0)
        let value = candidate()
        let enabled = LowFrequencyTrendReminderSettings(isEnabled: true)

        XCTAssertNil(request(settings: .init(), status: .authorized, live: true, candidate: value, disabled: false, now: now))
        XCTAssertNil(request(settings: enabled, status: .denied, live: true, candidate: value, disabled: false, now: now))
        XCTAssertNil(request(settings: enabled, status: .authorized, live: false, candidate: value, disabled: false, now: now))
        XCTAssertNil(request(settings: enabled, status: .authorized, live: true, candidate: nil, disabled: false, now: now))
        XCTAssertNil(request(settings: enabled, status: .authorized, live: true, candidate: value, disabled: nil, now: now))
        XCTAssertNil(request(settings: enabled, status: .authorized, live: true, candidate: value, disabled: true, now: now))

        let result = request(
            settings: enabled,
            status: .authorized,
            live: true,
            candidate: value,
            disabled: false,
            now: now
        )
        XCTAssertEqual(result?.fireDate, date(2026, 9, 7, 10, 0))
        XCTAssertEqual(result?.identifier, "zhiheng.low-frequency-trend.2026-09-07")
    }

    func testHandledTrendOnlyPreservesItsExistingFutureRequest() {
        let value = candidate()
        let now = date(2026, 9, 6, 11, 0)
        let future = date(2026, 9, 7, 10, 0)
        let preserved = LowFrequencyTrendReminderPolicy.request(
            settings: .init(isEnabled: true),
            authorizationStatus: .authorized,
            isLiveMode: true,
            candidate: value,
            remindersDisabled: false,
            handledSemanticKeys: [value.semanticKey],
            pendingSemanticKey: value.semanticKey,
            pendingFireDate: future,
            referenceDate: now,
            timeZone: utc
        )
        XCTAssertEqual(preserved?.fireDate, future)

        XCTAssertNil(LowFrequencyTrendReminderPolicy.request(
            settings: .init(isEnabled: true),
            authorizationStatus: .authorized,
            isLiveMode: true,
            candidate: value,
            remindersDisabled: false,
            handledSemanticKeys: [value.semanticKey],
            pendingSemanticKey: value.semanticKey,
            pendingFireDate: future,
            referenceDate: future,
            timeZone: utc
        ))
    }

    func testDailyBudgetUsesPlanThenTrendThenCheckInPriority() {
        let day = "2026-09-07"
        let trend = LowFrequencyTrendReminderRequest(
            identifier: LowFrequencyTrendReminderPolicy.identifierPrefix + day,
            localDayKey: day,
            fireDate: date(2026, 9, 7, 10, 0),
            semanticKey: "trend"
        )
        let daily = DailyCheckInReminderRequest(
            identifier: DailyCheckInReminderPolicy.identifierPrefix + day,
            fireDate: date(2026, 9, 7, 20, 0)
        )

        XCTAssertTrue(NotificationDailyBudget.trendRequests(
            [trend],
            reservingMicroPlanIdentifiers: [MicroPlanReminderPolicy.identifierPrefix + day]
        ).isEmpty)
        XCTAssertTrue(NotificationDailyBudget.dailyCheckInRequests(
            [daily],
            reservingMicroPlanIdentifiers: [trend.identifier]
        ).isEmpty)
        XCTAssertEqual(NotificationDailyBudget.trendRequests(
            [trend],
            reservingMicroPlanIdentifiers: [daily.identifier]
        ), [trend])
    }

    func testNotificationCopyIsNeutralAndContainsNoTrendDetail() {
        let content = ReminderLockScreenPrivacyPolicy.publicContent(
            for: .lowFrequencyTrend
        )
        let copy = [content.title, content.body].joined(separator: " ")
        for forbidden in [
            "趋势", "观察", "睡眠", "心率", "步数", "压力", "症状", "异常", "%", "上升", "下降"
        ] {
            XCTAssertFalse(copy.contains(forbidden), "通知不应包含：\(forbidden)")
        }
        XCTAssertEqual(copy, "知衡提醒 打开知衡查看。")
    }

    func testSessionDefaultsOffWithoutReadingFactsOrTopicPreference() async throws {
        let provider = TrendCandidateProviderSpy(result: .candidate(candidate()))
        let store = TrendInteractionStoreSpy()
        let scheduler = TrendReminderSchedulerSpy()
        let session = LowFrequencyTrendReminderSession(
            interactionStore: store,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: try preferences()
        )

        await synchronize(session)

        XCTAssertFalse(session.settings.isEnabled)
        XCTAssertEqual(provider.readCount, 0)
        XCTAssertEqual(store.readCount, 0)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
        XCTAssertNil(session.nextReminderDate)
    }

    func testExplicitEnablePersistsSchedulesOnceAndRestoresPendingDate() async throws {
        let preferenceStore = try preferences()
        let value = candidate()
        let provider = TrendCandidateProviderSpy(result: .candidate(value))
        let scheduler = TrendReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = LowFrequencyTrendReminderSession(
            interactionStore: TrendInteractionStoreSpy(),
            authorizationSession: authorization,
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: preferenceStore
        )
        let now = date(2026, 9, 6, 11, 0)

        await session.setEnabled(
            true,
            snapshot: nil,
            loadedInterval: nil,
            access: .requestCompleted,
            dataMode: .live,
            referenceDate: now,
            timeZone: utc
        )
        XCTAssertTrue(preferenceStore.bool(forKey: LowFrequencyTrendReminderSession.enabledKey))
        XCTAssertEqual(session.nextReminderDate, date(2026, 9, 7, 10, 0))
        XCTAssertEqual(
            preferenceStore.stringArray(
                forKey: LowFrequencyTrendReminderSession.handledSemanticKeysKey
            ),
            [value.semanticKey]
        )

        await synchronize(session, now: date(2026, 9, 6, 12, 0))
        XCTAssertEqual(session.nextReminderDate, date(2026, 9, 7, 10, 0))
        let repeatedBatch = await scheduler.lastBatch()
        XCTAssertEqual(repeatedBatch.first?.fireDate, date(2026, 9, 7, 10, 0))

        let restored = LowFrequencyTrendReminderSession(
            interactionStore: TrendInteractionStoreSpy(),
            authorizationSession: authorization,
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: preferenceStore
        )
        XCTAssertTrue(restored.settings.isEnabled)
    }

    func testTopicPreferenceAndPreferenceReadFailureBothClearRequests() async throws {
        let provider = TrendCandidateProviderSpy(result: .candidate(candidate()))
        let scheduler = TrendReminderSchedulerSpy()
        let disabledStore = TrendInteractionStoreSpy(remindersDisabled: true)
        let disabled = LowFrequencyTrendReminderSession(
            interactionStore: disabledStore,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: try enabledPreferences()
        )
        await synchronize(disabled)
        XCTAssertTrue(disabled.statusMessage.contains("已由你关闭"))
        let disabledBatch = await scheduler.lastBatch()
        XCTAssertEqual(disabledBatch, [])

        let failedStore = TrendInteractionStoreSpy(failsReads: true)
        let failed = LowFrequencyTrendReminderSession(
            interactionStore: failedStore,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: try enabledPreferences()
        )
        await synchronize(failed)
        XCTAssertTrue(failed.statusMessage.contains("无法读取同类提醒偏好"))
        XCTAssertNil(failed.nextReminderDate)
        let failedBatch = await scheduler.lastBatch()
        XCTAssertEqual(failedBatch, [])
    }

    func testDemoUnavailableAndSchedulingFailureNeverPretendSuccess() async throws {
        let provider = TrendCandidateProviderSpy(result: .unavailable)
        let scheduler = TrendReminderSchedulerSpy()
        let session = LowFrequencyTrendReminderSession(
            interactionStore: TrendInteractionStoreSpy(),
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            candidateProvider: provider,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            snapshot: nil,
            loadedInterval: nil,
            access: .requestCompleted,
            dataMode: .demo,
            referenceDate: date(2026, 9, 6, 11, 0),
            timeZone: utc
        )
        XCTAssertEqual(provider.readCount, 0)
        XCTAssertTrue(session.statusMessage.contains("演示模式"))

        provider.result = .candidate(candidate())
        await scheduler.setFailure(true)
        await synchronize(session)
        XCTAssertNil(session.nextReminderDate)
        XCTAssertEqual(session.errorMessage, "暂时无法安排低频趋势提醒，请稍后重试。")
        XCTAssertTrue(session.statusMessage.contains("没有把本次操作显示为已成功"))
    }

    private func synchronize(
        _ session: LowFrequencyTrendReminderSession,
        now: Date? = nil
    ) async {
        await session.synchronize(
            snapshot: nil,
            loadedInterval: nil,
            access: .requestCompleted,
            dataMode: .live,
            referenceDate: now ?? date(2026, 9, 6, 11, 0),
            timeZone: utc
        )
    }

    private func request(
        settings: LowFrequencyTrendReminderSettings,
        status: NotificationAuthorizationStatus,
        live: Bool,
        candidate: LowFrequencyTrendCandidate?,
        disabled: Bool?,
        now: Date
    ) -> LowFrequencyTrendReminderRequest? {
        LowFrequencyTrendReminderPolicy.request(
            settings: settings,
            authorizationStatus: status,
            isLiveMode: live,
            candidate: candidate,
            remindersDisabled: disabled,
            handledSemanticKeys: [],
            pendingSemanticKey: nil,
            pendingFireDate: nil,
            referenceDate: now,
            timeZone: utc
        )
    }

    private func candidate() -> LowFrequencyTrendCandidate {
        LowFrequencyTrendCandidate(
            metric: .stepCount,
            direction: .higher,
            semanticKey: "synthetic-trend-key",
            interactionIdentity: InsightInteractionIdentity(
                insightID: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                topic: .metricChange(.stepCount),
                dataMode: .live
            )
        )
    }

    private func factSet(
        level: HealthMetricTrendLevel,
        stable: Bool = true,
        outlier: Bool = false,
        currentCount: Int = 7,
        baselineCount: Int = 28,
        relativeChange: Double = 0.4
    ) -> InsightFactSet {
        let end = date(2026, 9, 6, 0, 0)
        let currentStart = end.addingTimeInterval(-7 * 86_400)
        let baselineStart = currentStart.addingTimeInterval(-28 * 86_400)
        let evidence = HealthMetricTrendEvidence(
            metric: .stepCount,
            unit: .count,
            state: .trend(level),
            currentInterval: DateInterval(start: currentStart, end: end),
            currentValidDayCount: currentCount,
            currentExpectedDayCount: 7,
            baselineInterval: DateInterval(start: baselineStart, end: currentStart),
            baselineValidDayCount: baselineCount,
            baselineExpectedDayCount: 28,
            currentMedianValue: 7_000,
            baselineMedianValue: 5_000,
            relativeChange: relativeChange,
            configuredMinimumRelativeChange: 0.15,
            effectiveRelativeThreshold: 0.15,
            alignedDayCount: 7,
            analysisDayCount: 7,
            requiredAlignedDayCount: 4,
            isolatedOutlierExcluded: outlier,
            sourceIsStable: stable,
            thresholdVersion: "synthetic-v1"
        )
        let source = HealthMetricSource(
            sourceName: "合成设备",
            bundleIdentifier: "test.trend-reminder",
            deviceName: nil
        )
        return InsightFactSet(
            generatorVersion: InsightFactGenerator.version,
            analysisInterval: DateInterval(start: baselineStart, end: end),
            timeZoneIdentifier: utc.identifier,
            dataMode: .live,
            facts: [InsightFact(
                id: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!,
                metric: .stepCount,
                evidence: .evaluated(evidence, sources: [source])
            )]
        )
    }

    private func authorizationSession(
        status: NotificationAuthorizationStatus
    ) async -> NotificationAuthorizationSession {
        let session = NotificationAuthorizationSession(
            client: TrendAuthorizationClient(status: status)
        )
        await session.refresh()
        return session
    }

    private func preferences() throws -> UserDefaults {
        let name = "LowFrequencyTrendReminderTests-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return store
    }

    private func enabledPreferences() throws -> UserDefaults {
        let store = try preferences()
        store.set(true, forKey: LowFrequencyTrendReminderSession.enabledKey)
        return store
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

private actor TrendAuthorizationClient: NotificationAuthorizationClient {
    let status: NotificationAuthorizationStatus

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> NotificationAuthorizationStatus { status }
    func requestAuthorization() -> NotificationAuthorizationStatus { status }
}

private final class TrendCandidateProviderSpy: LowFrequencyTrendCandidateProviding, @unchecked Sendable {
    var result: LowFrequencyTrendCandidateResult
    private(set) var readCount = 0

    init(result: LowFrequencyTrendCandidateResult) {
        self.result = result
    }

    func candidate(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> LowFrequencyTrendCandidateResult {
        readCount += 1
        return result
    }
}

private enum TrendReminderTestError: Error {
    case failed
}

private actor TrendReminderSchedulerSpy: LowFrequencyTrendReminderScheduling {
    private var batches = [[LowFrequencyTrendReminderRequest]]()
    private var shouldFail = false

    func replacePendingTrendReminders(
        with requests: [LowFrequencyTrendReminderRequest],
        timeZone: TimeZone
    ) throws -> [LowFrequencyTrendReminderRequest] {
        batches.append(requests)
        if shouldFail { throw TrendReminderTestError.failed }
        return requests
    }

    func lastBatch() -> [LowFrequencyTrendReminderRequest] { batches.last ?? [] }
    func setFailure(_ value: Bool) { shouldFail = value }
}

@MainActor
private final class TrendInteractionStoreSpy: InsightInteractionStore {
    private let remindersDisabled: Bool
    private let failsReads: Bool
    private(set) var readCount = 0

    init(remindersDisabled: Bool = false, failsReads: Bool = false) {
        self.remindersDisabled = remindersDisabled
        self.failsReads = failsReads
    }

    func state(for identity: InsightInteractionIdentity) throws -> InsightInteractionState {
        readCount += 1
        if failsReads { throw InsightInteractionStoreError.persistenceFailed }
        return InsightInteractionState(
            identity: identity,
            readAt: nil,
            ignoredAt: nil,
            remindersDisabledAt: remindersDisabled ? Date() : nil
        )
    }

    func setRead(
        _ isRead: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        try state(for: identity)
    }

    func setIgnored(
        _ isIgnored: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        try state(for: identity)
    }

    func setRemindersDisabled(
        _ isDisabled: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        try state(for: identity)
    }
}
