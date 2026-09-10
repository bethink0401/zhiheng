import XCTest
@testable import Zhiheng

@MainActor
final class DailyCheckInReminderTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testSettingsUseSafeDefaultsAndRepairInvalidStoredTime() {
        XCTAssertEqual(
            DailyCheckInReminderSettings(),
            DailyCheckInReminderSettings(isEnabled: false, hour: 20, minute: 0)
        )
        XCTAssertEqual(
            DailyCheckInReminderSettings(isEnabled: true, hour: 25, minute: -1),
            DailyCheckInReminderSettings(isEnabled: true, hour: 20, minute: 0)
        )
    }

    func testPolicyRequiresEnabledAuthorizedLiveAndReadableCheckInState() {
        let now = date(2026, 9, 6, 10, 0)
        let enabled = DailyCheckInReminderSettings(isEnabled: true)

        XCTAssertTrue(requests(settings: .init(), status: .authorized, live: true, checkIn: false, now: now).isEmpty)
        XCTAssertTrue(requests(settings: enabled, status: .denied, live: true, checkIn: false, now: now).isEmpty)
        XCTAssertTrue(requests(settings: enabled, status: .unknown, live: true, checkIn: false, now: now).isEmpty)
        XCTAssertTrue(requests(settings: enabled, status: .authorized, live: false, checkIn: false, now: now).isEmpty)
        XCTAssertTrue(requests(settings: enabled, status: .authorized, live: true, checkIn: nil, now: now).isEmpty)
    }

    func testUncheckedDayBeforeSelectedTimeStartsTodayWithoutDuplicateDates() {
        let now = date(2026, 9, 6, 10, 0)
        let result = requests(
            settings: .init(isEnabled: true, hour: 20, minute: 15),
            status: .authorized,
            live: true,
            checkIn: false,
            now: now
        )

        XCTAssertEqual(result.count, DailyCheckInReminderPolicy.rollingDayCount)
        XCTAssertEqual(result.first?.fireDate, date(2026, 9, 6, 20, 15))
        XCTAssertEqual(Set(result.map(\.identifier)).count, result.count)
        XCTAssertTrue(result.allSatisfy {
            $0.identifier.hasPrefix(DailyCheckInReminderPolicy.identifierPrefix)
        })
    }

    func testPastTimeOrExistingCheckInStartsTomorrow() {
        let settings = DailyCheckInReminderSettings(isEnabled: true, hour: 20, minute: 0)
        let afterTime = requests(
            settings: settings,
            status: .authorized,
            live: true,
            checkIn: false,
            now: date(2026, 9, 6, 21, 0)
        )
        let alreadyRecorded = requests(
            settings: settings,
            status: .authorized,
            live: true,
            checkIn: true,
            now: date(2026, 9, 6, 10, 0)
        )

        XCTAssertEqual(afterTime.first?.fireDate, date(2026, 9, 7, 20, 0))
        XCTAssertEqual(alreadyRecorded.first?.fireDate, date(2026, 9, 7, 20, 0))
    }

    func testNotificationCopyIsNeutralAndContainsNoHealthDetail() {
        let content = ReminderLockScreenPrivacyPolicy.publicContent(
            for: .dailyCheckIn
        )
        let visibleCopy = [content.title, content.body].joined(separator: " ")
        for forbidden in [
            "感受", "精力", "压力", "症状", "心率", "睡眠", "评分", "异常"
        ] {
            XCTAssertFalse(visibleCopy.contains(forbidden), "通知不应包含：\(forbidden)")
        }
        XCTAssertEqual(visibleCopy, "知衡提醒 打开知衡查看。")
    }

    func testSessionDefaultsOffAndDoesNotReadSubjectiveStore() async throws {
        let store = DailyReminderSubjectiveStore()
        let scheduler = DailyReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
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
        XCTAssertEqual(store.checkInReadCount, 0)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
    }

    func testExplicitEnablePersistsAndSchedulesToday() async throws {
        let preferenceStore = try preferences()
        let store = DailyReminderSubjectiveStore()
        let scheduler = DailyReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: preferenceStore
        )
        let now = date(2026, 9, 6, 10, 0)

        await session.setEnabled(
            true,
            isLiveMode: true,
            referenceDate: now,
            timeZone: utc
        )

        XCTAssertTrue(session.settings.isEnabled)
        XCTAssertTrue(preferenceStore.bool(forKey: DailyCheckInReminderSession.enabledKey))
        XCTAssertEqual(session.nextReminderDate, date(2026, 9, 6, 20, 0))
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch.count, DailyCheckInReminderPolicy.rollingDayCount)
        XCTAssertNil(session.errorMessage)

        let restored = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: preferenceStore
        )
        XCTAssertTrue(restored.settings.isEnabled)
        XCTAssertEqual(restored.settings.hour, 20)
    }

    func testExistingCheckInAndTimeChangeRescheduleFromTomorrow() async throws {
        let store = DailyReminderSubjectiveStore()
        let now = date(2026, 9, 6, 10, 0)
        store.records[SubjectiveLocalDay(date: now, timeZone: utc).storageKey] = try DailyCheckIn(
            localDay: SubjectiveLocalDay(date: now, timeZone: utc),
            energy: .three,
            stress: .three,
            bodyFeeling: .three,
            recordedAt: now
        )
        let scheduler = DailyReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: try preferences()
        )
        await session.setEnabled(true, isLiveMode: true, referenceDate: now, timeZone: utc)

        await session.updateTime(
            from: date(2026, 9, 6, 19, 30),
            isLiveMode: true,
            referenceDate: now,
            timeZone: utc
        )

        XCTAssertEqual(session.settings.hour, 19)
        XCTAssertEqual(session.settings.minute, 30)
        XCTAssertEqual(session.nextReminderDate, date(2026, 9, 7, 19, 30))
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch.first?.fireDate, date(2026, 9, 7, 19, 30))
    }

    func testReadFailureCancelsPendingRequestsAndNeverPretendsScheduled() async throws {
        let store = DailyReminderSubjectiveStore()
        store.failsReads = true
        let scheduler = DailyReminderSchedulerSpy()
        let authorization = await authorizationSession(status: .authorized)
        let session = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: try preferences()
        )

        await session.setEnabled(
            true,
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertTrue(session.settings.isEnabled)
        XCTAssertNil(session.nextReminderDate)
        let batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
        XCTAssertTrue(session.statusMessage.contains("没有安排"))
    }

    func testDisableAndPermissionRevocationBothRemovePendingRequests() async throws {
        let store = DailyReminderSubjectiveStore()
        let scheduler = DailyReminderSchedulerSpy()
        let authorizationClient = DailyReminderAuthorizationClient(status: .authorized)
        let authorization = NotificationAuthorizationSession(client: authorizationClient)
        await authorization.refresh()
        let session = DailyCheckInReminderSession(
            store: store,
            authorizationSession: authorization,
            scheduler: scheduler,
            preferences: try preferences()
        )
        let now = date(2026, 9, 6, 10, 0)
        await session.setEnabled(true, isLiveMode: true, referenceDate: now, timeZone: utc)
        await session.setEnabled(false, isLiveMode: true, referenceDate: now, timeZone: utc)

        XCTAssertFalse(session.settings.isEnabled)
        var batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])

        await session.setEnabled(true, isLiveMode: true, referenceDate: now, timeZone: utc)
        await authorizationClient.setStatus(.denied)
        await authorization.refresh()
        await session.synchronize(isLiveMode: true, referenceDate: now, timeZone: utc)
        XCTAssertTrue(session.settings.isEnabled)
        batch = await scheduler.lastBatch()
        XCTAssertEqual(batch, [])
        XCTAssertTrue(session.statusMessage.contains("系统当前不允许"))
    }

    func testSchedulingFailureDoesNotPublishFalseNextReminder() async throws {
        let scheduler = DailyReminderSchedulerSpy()
        await scheduler.setFailure(true)
        let session = DailyCheckInReminderSession(
            store: DailyReminderSubjectiveStore(),
            authorizationSession: await authorizationSession(status: .authorized),
            scheduler: scheduler,
            preferences: try preferences()
        )

        await session.setEnabled(
            true,
            isLiveMode: true,
            referenceDate: date(2026, 9, 6, 10, 0),
            timeZone: utc
        )

        XCTAssertNil(session.nextReminderDate)
        XCTAssertEqual(session.errorMessage, "暂时无法安排每日感受提醒，请稍后重试。")
        XCTAssertTrue(session.statusMessage.contains("没有把本次操作显示为已成功"))
    }

    func testCoordinatorSignalsSuccessfulSaveAndCurrentDayHistoryChange() throws {
        let store = DailyReminderSubjectiveStore()
        let now = date(2026, 9, 6, 10, 0)
        let coordinator = DailyCheckInCoordinator(
            store: store,
            preferences: try preferences(),
            referenceDate: now
        )
        var changeCount = 0
        coordinator.onCurrentCheckInChanged = { changeCount += 1 }
        coordinator.enterApp(at: now, dataMode: .live, timeZone: utc)
        coordinator.session.energy = .three
        coordinator.session.stress = .three
        coordinator.session.bodyFeeling = .three

        XCTAssertTrue(coordinator.save(at: now, timeZone: utc))
        XCTAssertEqual(changeCount, 1)
        let record = try XCTUnwrap(coordinator.session.savedCheckIn)
        try store.deleteCheckIn(on: record.localDay)
        coordinator.refreshAfterHistoryChange(.checkIn(record), at: now, timeZone: utc)
        XCTAssertEqual(changeCount, 2)
        XCTAssertNil(coordinator.session.savedCheckIn)
    }

    private func requests(
        settings: DailyCheckInReminderSettings,
        status: NotificationAuthorizationStatus,
        live: Bool,
        checkIn: Bool?,
        now: Date
    ) -> [DailyCheckInReminderRequest] {
        DailyCheckInReminderPolicy.requests(
            settings: settings,
            authorizationStatus: status,
            isLiveMode: live,
            hasCheckInToday: checkIn,
            referenceDate: now,
            timeZone: utc
        )
    }

    private func authorizationSession(
        status: NotificationAuthorizationStatus
    ) async -> NotificationAuthorizationSession {
        let session = NotificationAuthorizationSession(
            client: DailyReminderAuthorizationClient(status: status)
        )
        await session.refresh()
        return session
    }

    private func preferences() throws -> UserDefaults {
        let name = "DailyCheckInReminderTests-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
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

private enum DailyReminderTestError: Error {
    case failed
}

private actor DailyReminderAuthorizationClient: NotificationAuthorizationClient {
    private var status: NotificationAuthorizationStatus

    init(status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> NotificationAuthorizationStatus { status }
    func requestAuthorization() -> NotificationAuthorizationStatus { status }
    func setStatus(_ status: NotificationAuthorizationStatus) { self.status = status }
}

private actor DailyReminderSchedulerSpy: DailyCheckInReminderScheduling {
    private var batches: [[DailyCheckInReminderRequest]] = []
    private var shouldFail = false

    func replacePendingReminders(
        with requests: [DailyCheckInReminderRequest],
        timeZone: TimeZone
    ) throws -> [DailyCheckInReminderRequest] {
        batches.append(requests)
        if shouldFail { throw DailyReminderTestError.failed }
        return requests
    }

    func lastBatch() -> [DailyCheckInReminderRequest] { batches.last ?? [] }
    func setFailure(_ shouldFail: Bool) { self.shouldFail = shouldFail }
}

@MainActor
private final class DailyReminderSubjectiveStore: SubjectiveRecordStore {
    var records: [String: DailyCheckIn] = [:]
    var failsReads = false
    private(set) var checkInReadCount = 0

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        records[record.localDay.storageKey] = record
        return record
    }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        checkInReadCount += 1
        if failsReads { throw SubjectiveRecordStoreError.persistenceFailed }
        return records[day.storageKey]
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        records[day.storageKey] = nil
    }

    func save(_ event: ContextEvent) throws {}
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] { [] }
    func deleteContextEvent(id: UUID) throws {}
}
