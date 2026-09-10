import XCTest
@testable import Zhiheng

@MainActor
final class MicroPlanReminderTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testPolicyRequiresEnabledAuthorizedLiveActivePlan() throws {
        let now = date(2026, 9, 6, 10, 0)
        let plan = try makePlan(status: .active)
        let days = [MicroPlanReminderDay(
            date: now,
            occurrenceIndex: 0,
            hasOutcome: false
        )]

        XCTAssertTrue(requests(settings: .init(), status: .authorized, live: true, plan: plan, days: days, now: now).isEmpty)
        XCTAssertTrue(requests(settings: .init(isEnabled: true), status: .denied, live: true, plan: plan, days: days, now: now).isEmpty)
        XCTAssertTrue(requests(settings: .init(isEnabled: true), status: .authorized, live: false, plan: plan, days: days, now: now).isEmpty)
        XCTAssertTrue(requests(settings: .init(isEnabled: true), status: .authorized, live: true, plan: nil, days: days, now: now).isEmpty)
        XCTAssertTrue(requests(settings: .init(isEnabled: true), status: .authorized, live: true, plan: try makePlan(status: .paused), days: days, now: now).isEmpty)
    }

    func testPolicySkipsRecordedAndPastOccurrencesWithStableDailyIDs() throws {
        let now = date(2026, 9, 6, 19, 0)
        let plan = try makePlan(status: .active)
        let days = [
            MicroPlanReminderDay(date: date(2026, 9, 6, 0, 0), occurrenceIndex: 0, hasOutcome: false),
            MicroPlanReminderDay(date: date(2026, 9, 7, 0, 0), occurrenceIndex: 1, hasOutcome: true),
            MicroPlanReminderDay(date: date(2026, 9, 8, 0, 0), occurrenceIndex: 2, hasOutcome: false),
            MicroPlanReminderDay(date: date(2026, 9, 8, 12, 0), occurrenceIndex: 2, hasOutcome: false)
        ]

        let result = requests(
            settings: .init(isEnabled: true),
            status: .authorized,
            live: true,
            plan: plan,
            days: days,
            now: now
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].fireDate, date(2026, 9, 8, 18, 0))
        XCTAssertEqual(result[0].identifier, "zhiheng.micro-plan.2026-09-08")
        XCTAssertEqual(result[0].localDayKey, "2026-09-08")
    }

    func testDailyBudgetReservesPlanDatesAndKeepsOtherDailyReminders() {
        let daily = [
            DailyCheckInReminderRequest(
                identifier: "zhiheng.daily-check-in.2026-09-06",
                fireDate: date(2026, 9, 6, 20, 0)
            ),
            DailyCheckInReminderRequest(
                identifier: "zhiheng.daily-check-in.2026-09-07",
                fireDate: date(2026, 9, 7, 20, 0)
            )
        ]

        let result = NotificationDailyBudget.dailyCheckInRequests(
            daily,
            reservingMicroPlanIdentifiers: [
                "unrelated.request",
                "zhiheng.micro-plan.2026-09-06"
            ]
        )

        XCTAssertEqual(result, [daily[1]])
    }

    func testNotificationCopyIsNeutralAndContainsNoPlanDetail() {
        let content = ReminderLockScreenPrivacyPolicy.publicContent(for: .microPlan)
        let visibleCopy = [content.title, content.body].joined(separator: " ")
        for forbidden in [
            "计划", "睡眠", "心率", "压力", "症状", "异常", "咖啡", "训练", "反馈", "完成率"
        ] {
            XCTAssertFalse(visibleCopy.contains(forbidden), "通知不应包含：\(forbidden)")
        }
        XCTAssertEqual(visibleCopy, "知衡提醒 打开知衡查看。")
    }

    func testSessionDefaultsOffWithoutReadingCareKit() async throws {
        let service = MicroPlanReminderServiceSpy()
        let scheduler = MicroPlanReminderSchedulerSpy()
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try preferences()
        )

        await session.synchronize(
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertFalse(session.settings.isEnabled)
        XCTAssertNil(session.nextReminderDate)
        let reads = await service.readCounts()
        XCTAssertEqual(reads.activePlan, 0)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
    }

    func testExplicitEnablePersistsAndUsesCareKitOutcomesAndSchedule() async throws {
        let preferenceStore = try preferences()
        let service = MicroPlanReminderServiceSpy(plan: try makePlan(status: .active))
        await service.setOccurrences([
            dayKey(date(2026, 9, 6, 0, 0)): 0,
            dayKey(date(2026, 9, 7, 0, 0)): 1,
            dayKey(date(2026, 9, 8, 0, 0)): 2
        ])
        await service.setRecords([
            PlanOutcomeRecord(
                occurrenceIndex: 0,
                state: .completed,
                recordedAt: date(2026, 9, 6, 12, 0),
                feedback: "本地反馈不会进入通知"
            )
        ])
        let scheduler = MicroPlanReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: preferenceStore
        )

        await session.setEnabled(
            true,
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertTrue(session.settings.isEnabled)
        XCTAssertTrue(preferenceStore.bool(forKey: MicroPlanReminderSession.enabledKey))
        XCTAssertEqual(session.nextReminderDate, date(2026, 9, 7, 18, 0))
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch.map(\.localDayKey), ["2026-09-07", "2026-09-08"])
        XCTAssertNil(session.errorMessage)

        let restored = MicroPlanReminderSession(
            service: service,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: preferenceStore
        )
        XCTAssertTrue(restored.settings.isEnabled)
    }

    func testPausedPlanClearsRequestsWithoutReadingOutcomes() async throws {
        let service = MicroPlanReminderServiceSpy(plan: try makePlan(status: .paused))
        let scheduler = MicroPlanReminderSchedulerSpy()
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertNil(session.nextReminderDate)
        XCTAssertTrue(session.statusMessage.contains("暂停期间"))
        let reads = await service.readCounts()
        XCTAssertEqual(reads.outcomes, 0)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
    }

    func testDemoAndCareKitReadFailureBothClearWithoutPretendingScheduled() async throws {
        let service = MicroPlanReminderServiceSpy(plan: try makePlan(status: .active))
        let scheduler = MicroPlanReminderSchedulerSpy()
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            isLiveMode: false,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )
        XCTAssertTrue(session.statusMessage.contains("演示模式"))
        let demoReads = await service.readCounts()
        let demoBatch = await scheduler.lastBatch()
        XCTAssertEqual(demoReads.activePlan, 0)
        XCTAssertEqual(demoBatch, [])

        await service.setReadFailure(true)
        await session.synchronize(
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )
        XCTAssertNil(session.nextReminderDate)
        XCTAssertTrue(session.statusMessage.contains("无法读取微计划状态"))
        let failedBatch = await scheduler.lastBatch()
        XCTAssertEqual(failedBatch, [])
    }

    func testSchedulingFailureDoesNotPublishFalseNextReminder() async throws {
        let service = MicroPlanReminderServiceSpy(plan: try makePlan(status: .active))
        await service.setOccurrences([dayKey(date(2026, 9, 6, 0, 0)): 0])
        let scheduler = MicroPlanReminderSchedulerSpy()
        await scheduler.setFailure(true)
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertNil(session.nextReminderDate)
        XCTAssertEqual(session.errorMessage, "暂时无法安排微计划提醒，请稍后重试。")
        XCTAssertTrue(session.statusMessage.contains("没有把本次操作显示为已成功"))
    }

    func testSessionPublishesSchedulerFilteredResultInsteadOfUnfilteredCandidate() async throws {
        let service = MicroPlanReminderServiceSpy(plan: try makePlan(status: .active))
        await service.setOccurrences([dayKey(date(2026, 9, 6, 0, 0)): 0])
        let scheduler = MicroPlanReminderSchedulerSpy()
        await scheduler.setScheduledRequests([])
        let session = MicroPlanReminderSession(
            service: service,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch.count, 1)
        XCTAssertNil(session.nextReminderDate)
        XCTAssertTrue(session.statusMessage.contains("安静时间或提醒频率"))
    }

    func testRealCareKitScheduleAndOutcomeDriveRemainingReminders() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startDate = calendar.startOfDay(for: Date())
        let referenceDate = try XCTUnwrap(calendar.date(
            bySettingHour: 10,
            minute: 0,
            second: 0,
            of: startDate
        ))
        let endDate = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 3,
            to: startDate
        ))
        let tomorrow = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 1,
            to: startDate
        ))
        let expectedNext = try XCTUnwrap(calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: tomorrow
        ))
        let store = CareKitPlanStore(
            inMemoryStoreNamed: "MicroPlanReminderIntegration-\(UUID().uuidString)"
        )
        let draft = MicroPlanDraft(
            id: CarePlanID(rawValue: "plan.integration.\(UUID().uuidString)"),
            title: "集成计划",
            taskID: CareTaskID(rawValue: "task.integration.\(UUID().uuidString)"),
            taskTitle: "不会进入通知",
            startDate: startDate,
            endDateExclusive: endDate,
            scheduledTime: try ScheduledLocalTime(hour: 18, minute: 0)
        )
        _ = try await store.createPlan(from: draft)
        let loadedTodayIndex = try await store.occurrenceIndex(
            for: draft.taskID,
            on: referenceDate
        )
        let todayIndex = try XCTUnwrap(loadedTodayIndex)
        try await store.recordOutcome(PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: todayIndex,
            state: .skipped,
            recordedAt: referenceDate,
            difficulty: nil,
            feedback: "不会进入通知"
        ))
        let scheduler = MicroPlanReminderSchedulerSpy()
        let session = MicroPlanReminderSession(
            service: store,
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try enabledPreferences()
        )

        await session.synchronize(
            isLiveMode: true,
            referenceDate: referenceDate,
            timeZone: .current
        )

        XCTAssertEqual(session.nextReminderDate, expectedNext)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch.count, 2)
        XCTAssertFalse(batch.contains { request in
            calendar.isDate(request.fireDate, inSameDayAs: referenceDate)
        })
    }

    private func requests(
        settings: MicroPlanReminderSettings,
        status: NotificationAuthorizationStatus,
        live: Bool,
        plan: MicroPlan?,
        days: [MicroPlanReminderDay],
        now: Date
    ) -> [MicroPlanReminderRequest] {
        MicroPlanReminderPolicy.requests(
            settings: settings,
            authorizationStatus: status,
            isLiveMode: live,
            plan: plan,
            days: days,
            referenceDate: now,
            timeZone: utc
        )
    }

    private func makePlan(status: MicroPlanStatus) throws -> MicroPlan {
        MicroPlan(
            draft: MicroPlanDraft(
                id: CarePlanID(rawValue: "plan.reminder"),
                title: "测试计划",
                taskID: CareTaskID(rawValue: "task.reminder"),
                taskTitle: "不应出现在锁屏",
                startDate: date(2026, 9, 6, 0, 0),
                endDateExclusive: date(2026, 9, 9, 0, 0),
                scheduledTime: try ScheduledLocalTime(hour: 18, minute: 0)
            ),
            status: status
        )
    }

    private func authorizationSession(
        status: NotificationAuthorizationStatus
    ) async -> NotificationAuthorizationSession {
        let session = NotificationAuthorizationSession(
            client: MicroPlanReminderAuthorizationClient(status: status)
        )
        await session.refresh()
        return session
    }

    private func preferences() throws -> UserDefaults {
        let name = "MicroPlanReminderTests-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return store
    }

    private func enabledPreferences() throws -> UserDefaults {
        let store = try preferences()
        store.set(true, forKey: MicroPlanReminderSession.enabledKey)
        return store
    }

    private func dayKey(_ date: Date) -> Int {
        Int(Calendar(identifier: .gregorian).startOfDay(for: date).timeIntervalSince1970)
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

private enum MicroPlanReminderTestError: Error {
    case failed
}

private actor MicroPlanReminderAuthorizationClient: NotificationAuthorizationClient {
    private let status: NotificationAuthorizationStatus

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> NotificationAuthorizationStatus { status }
    func requestAuthorization() -> NotificationAuthorizationStatus { status }
}

private actor MicroPlanReminderSchedulerSpy: MicroPlanReminderScheduling {
    private var batches = [[MicroPlanReminderRequest]]()
    private var shouldFail = false
    private var scheduledRequests: [MicroPlanReminderRequest]?

    func replacePendingPlanReminders(
        with requests: [MicroPlanReminderRequest],
        timeZone: TimeZone
    ) throws -> [MicroPlanReminderRequest] {
        batches.append(requests)
        if shouldFail { throw MicroPlanReminderTestError.failed }
        return scheduledRequests ?? requests
    }

    func lastBatch() -> [MicroPlanReminderRequest] { batches.last ?? [] }
    func setFailure(_ value: Bool) { shouldFail = value }
    func setScheduledRequests(_ requests: [MicroPlanReminderRequest]?) {
        scheduledRequests = requests
    }
}

private actor MicroPlanReminderServiceSpy: CarePlanService {
    private var plan: MicroPlan?
    private var records = [PlanOutcomeRecord]()
    private var occurrences = [Int: Int]()
    private var failsReads = false
    private var activePlanReadCount = 0
    private var outcomeReadCount = 0

    init(plan: MicroPlan? = nil) {
        self.plan = plan
    }

    func setRecords(_ records: [PlanOutcomeRecord]) { self.records = records }
    func setOccurrences(_ occurrences: [Int: Int]) { self.occurrences = occurrences }
    func setReadFailure(_ value: Bool) { failsReads = value }
    func readCounts() -> (activePlan: Int, outcomes: Int) {
        (activePlanReadCount, outcomeReadCount)
    }

    func createPlan(from draft: MicroPlanDraft) throws -> MicroPlan {
        throw CarePlanServiceError.persistenceFailed
    }

    func activePlan() throws -> MicroPlan? {
        activePlanReadCount += 1
        if failsReads { throw CarePlanServiceError.persistenceFailed }
        return plan
    }

    func mostRecentPlan() throws -> MicroPlan? { plan }
    func planHistory() throws -> [MicroPlan] { plan.map { [$0] } ?? [] }
    func recordOutcome(_ input: PlanOutcomeInput) throws {}

    func outcomeState(
        for taskID: CareTaskID,
        occurrenceIndex: Int
    ) throws -> PlanOutcomeState? {
        records.first { $0.occurrenceIndex == occurrenceIndex }?.state
    }

    func outcomeRecords(for taskID: CareTaskID) throws -> [PlanOutcomeRecord] {
        outcomeReadCount += 1
        if failsReads { throw CarePlanServiceError.persistenceFailed }
        return records
    }

    func occurrenceIndex(
        for taskID: CareTaskID,
        on date: Date
    ) throws -> Int? {
        if failsReads { throw CarePlanServiceError.persistenceFailed }
        return occurrences[Int(
            Calendar(identifier: .gregorian).startOfDay(for: date).timeIntervalSince1970
        )]
    }

    func progress(for planID: CarePlanID) throws -> MicroPlanProgress {
        try MicroPlanProgress(scheduledCount: 0, completedCount: 0, skippedCount: 0)
    }

    func pausePlan(_ planID: CarePlanID, at date: Date) throws {}
    func resumePlan(_ planID: CarePlanID, at date: Date) throws {}
    func endPlan(_ planID: CarePlanID, at date: Date) throws {}
    func deletePlan(_ planID: CarePlanID) throws {}
}
