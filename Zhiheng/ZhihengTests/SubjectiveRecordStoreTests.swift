import SwiftData
import XCTest
@testable import Zhiheng

final class SubjectiveRecordStoreTests: XCTestCase {
    @MainActor
    func testVersionedSchemaAndMigrationPlanAreAttachedToContainer() throws {
        let container = try makeContainer()

        XCTAssertEqual(
            container.schema.version,
            SubjectiveRecordsSchemaV1.versionIdentifier
        )
        XCTAssertTrue(
            container.migrationPlan == SubjectiveRecordsMigrationPlan.self
        )
        XCTAssertEqual(SubjectiveRecordsMigrationPlan.schemas.count, 1)
        XCTAssertTrue(SubjectiveRecordsMigrationPlan.stages.isEmpty)
    }

    @MainActor
    func testDailyCheckInRoundTripsWithLocalDayAndPrivateNote() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SubjectiveRecords-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "records.store")
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let day = try SubjectiveLocalDay(
            year: 2027,
            month: 1,
            day: 15,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let checkIn = try DailyCheckIn(
            localDay: day,
            energy: .two,
            stress: .four,
            bodyFeeling: .three,
            note: "  今天有些疲劳  ",
            recordedAt: recordedAt
        )

        let saved: DailyCheckIn
        do {
            let writer = SwiftDataSubjectiveRecordStore(
                modelContainer: try makeContainer(storeURL: storeURL)
            )
            saved = try writer.save(checkIn)
        }
        let reader = SwiftDataSubjectiveRecordStore(
            modelContainer: try makeContainer(storeURL: storeURL)
        )
        let restored = try XCTUnwrap(reader.checkIn(on: day))

        XCTAssertEqual(saved, restored)
        XCTAssertEqual(restored.note, "今天有些疲劳")
        XCTAssertEqual(restored.localDay.storageKey, "2027-01-15")
        XCTAssertEqual(restored.localDay.timeZoneIdentifier, "Asia/Shanghai")
    }

    @MainActor
    func testSavingSameLocalDayUpdatesSingleRecord() throws {
        let container = try makeContainer()
        let store = SwiftDataSubjectiveRecordStore(modelContainer: container)
        let day = try SubjectiveLocalDay(
            year: 2027,
            month: 2,
            day: 1,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let first = try DailyCheckIn(
            localDay: day,
            energy: .two,
            stress: .four,
            bodyFeeling: .two
        )
        let replacement = try DailyCheckIn(
            localDay: day,
            energy: .four,
            stress: .two,
            bodyFeeling: .four
        )

        let savedFirst = try store.save(first)
        let savedReplacement = try store.save(replacement)
        let count = try container.mainContext.fetchCount(
            FetchDescriptor<DailyCheckInEntity>()
        )

        XCTAssertEqual(count, 1)
        XCTAssertEqual(savedReplacement.id, savedFirst.id)
        XCTAssertEqual(savedReplacement.energy, .four)
        XCTAssertEqual(savedReplacement.stress, .two)
    }

    @MainActor
    func testContextEventRoundTripsAndFiltersByOverlap() throws {
        let store = SwiftDataSubjectiveRecordStore(
            modelContainer: try makeContainer()
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = try ContextEvent(
            kind: .custom,
            customLabel: "项目答辩",
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            intensity: .high,
            note: "需要长时间准备"
        )
        try store.save(event)

        let matching = try store.contextEvents(overlapping: DateInterval(
            start: start.addingTimeInterval(1_800),
            duration: 3_600
        ))
        let nonmatching = try store.contextEvents(overlapping: DateInterval(
            start: start.addingTimeInterval(7_200),
            duration: 3_600
        ))

        XCTAssertEqual(matching, [event])
        XCTAssertTrue(nonmatching.isEmpty)
    }

    @MainActor
    func testCheckInAndContextEventCanBeDeletedIndependently() throws {
        let store = SwiftDataSubjectiveRecordStore(
            modelContainer: try makeContainer()
        )
        let day = try SubjectiveLocalDay(
            year: 2027,
            month: 3,
            day: 2,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let checkIn = try DailyCheckIn(
            localDay: day,
            energy: .three,
            stress: .three,
            bodyFeeling: .three
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = try ContextEvent(kind: .overtime, startedAt: start)
        try store.save(checkIn)
        try store.save(event)

        try store.deleteCheckIn(on: day)
        XCTAssertNil(try store.checkIn(on: day))
        XCTAssertEqual(
            try store.contextEvents(overlapping: DateInterval(
                start: start.addingTimeInterval(-60),
                duration: 120
            )),
            [event]
        )

        try store.deleteContextEvent(id: event.id)
        XCTAssertTrue(
            try store.contextEvents(overlapping: DateInterval(
                start: start.addingTimeInterval(-60),
                duration: 120
            )).isEmpty
        )
    }

    func testInvalidEventAndOversizedPrivateTextAreRejected() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertThrowsError(try ContextEvent(
            kind: .overtime,
            startedAt: start,
            endedAt: start.addingTimeInterval(-1)
        )) { error in
            XCTAssertEqual(
                error as? SubjectiveRecordValidationError,
                .invalidEventInterval
            )
        }
        XCTAssertThrowsError(try ContextEvent(
            kind: .custom,
            startedAt: start
        )) { error in
            XCTAssertEqual(
                error as? SubjectiveRecordValidationError,
                .missingCustomLabel
            )
        }
        XCTAssertThrowsError(try DailyCheckIn(
            localDay: SubjectiveLocalDay(
                date: start,
                timeZone: TimeZone(identifier: "Asia/Shanghai")!
            ),
            energy: .three,
            stress: .three,
            bodyFeeling: .three,
            note: String(repeating: "感", count: 161)
        )) { error in
            XCTAssertEqual(
                error as? SubjectiveRecordValidationError,
                .textTooLong(maximumLength: 160)
            )
        }
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let configuration = ModelConfiguration(
            "SubjectiveRecordsTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: SubjectiveRecordsMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let configuration = ModelConfiguration(
            "SubjectiveRecordsDiskTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: SubjectiveRecordsMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

extension SubjectiveRecordStoreTests {
    @MainActor
    func testThreeSelectionsDoNotReadOrWriteUntilExplicitSave() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.load(for: date)

        session.energy = .four
        session.stress = .two
        session.bodyFeeling = .three

        XCTAssertTrue(session.canSave)
        XCTAssertEqual(store.readCount, 1)
        XCTAssertTrue(store.savedCheckIns.isEmpty)
        XCTAssertTrue(session.save(for: date))
        XCTAssertEqual(store.savedCheckIns.count, 1)
    }

    @MainActor
    func testCheckInDiskSavePerformance() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CheckInPerformance-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SwiftDataSubjectiveRecordStore(
            modelContainer: try makeContainer(
                storeURL: directory.appending(path: "records.store")
            )
        )
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.load(for: date)

        // Measures local persistence, not human reading time or UI response time.
        measure {
            session.energy = session.energy == .four ? .three : .four
            session.stress = .two
            session.bodyFeeling = .three
            XCTAssertTrue(session.save(for: date, recordedAt: date))
        }

        let restored = try XCTUnwrap(store.checkIn(on: SubjectiveLocalDay(date: date)))
        XCTAssertEqual(restored, session.savedCheckIn)
    }

    @MainActor
    func testCheckInSessionLoadsExistingRatingsForToday() throws {
        let store = TestSubjectiveRecordStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let existing = try DailyCheckIn(
            localDay: SubjectiveLocalDay(date: date, timeZone: timeZone),
            energy: .two,
            stress: .four,
            bodyFeeling: .three,
            recordedAt: date
        )
        store.checkIns[existing.localDay.storageKey] = existing
        let session = SubjectiveCheckInSession(store: store)

        session.load(for: date, timeZone: timeZone)

        XCTAssertEqual(session.savedCheckIn, existing)
        XCTAssertEqual(session.energy, .two)
        XCTAssertEqual(session.stress, .four)
        XCTAssertEqual(session.bodyFeeling, .three)
        XCTAssertTrue(session.canSave)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testCheckInSessionRequiresAllThreeRatingsBeforeSaving() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        session.load(for: date, timeZone: timeZone)
        session.energy = .three
        session.stress = .two

        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(for: date, timeZone: timeZone))
        XCTAssertEqual(store.savedCheckIns.count, 0)
        XCTAssertNotNil(session.errorMessage)
    }

    @MainActor
    func testCheckInSessionSavesSelectedRatingsForLocalDay() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let savedAt = date.addingTimeInterval(120)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        session.load(for: date, timeZone: timeZone)
        session.energy = .four
        session.stress = .two
        session.bodyFeeling = .five

        XCTAssertTrue(session.save(
            for: date,
            timeZone: timeZone,
            recordedAt: savedAt
        ))
        let saved = try XCTUnwrap(store.savedCheckIns.last)
        XCTAssertEqual(saved.localDay.storageKey, "2027-01-15")
        XCTAssertEqual(saved.energy, .four)
        XCTAssertEqual(saved.stress, .two)
        XCTAssertEqual(saved.bodyFeeling, .five)
        XCTAssertEqual(saved.updatedAt, savedAt)
        XCTAssertEqual(session.savedCheckIn, saved)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testCheckInSessionPreservesDraftWhenPersistenceFails() throws {
        let store = TestSubjectiveRecordStore()
        store.failsWrites = true
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        session.load(for: date, timeZone: timeZone)
        session.energy = .one
        session.stress = .five
        session.bodyFeeling = .two

        XCTAssertFalse(session.save(for: date, timeZone: timeZone))
        XCTAssertEqual(session.energy, .one)
        XCTAssertEqual(session.stress, .five)
        XCTAssertEqual(session.bodyFeeling, .two)
        XCTAssertNil(session.savedCheckIn)
        XCTAssertNotNil(session.errorMessage)
    }

    @MainActor
    func testCheckInSessionDoesNotReadOrWriteInDemoMode() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        session.load(
            for: date,
            timeZone: timeZone,
            isRecordingEnabled: false
        )
        session.energy = .three
        session.stress = .three
        session.bodyFeeling = .three

        XCTAssertEqual(store.readCount, 0)
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(for: date, timeZone: timeZone))
        XCTAssertTrue(store.savedCheckIns.isEmpty)
        XCTAssertEqual(
            session.errorMessage,
            "演示模式下不会保存你的主观记录。"
        )
    }
}

@MainActor
private final class TestSubjectiveRecordStore: SubjectiveRecordStore {
    var checkIns = [String: DailyCheckIn]()
    var savedCheckIns = [DailyCheckIn]()
    var readCount = 0
    var failsWrites = false
    var failsReads = false
    var events = [UUID: ContextEvent]()
    var eventReadCount = 0
    var eventWriteAttempts = [ContextEvent]()
    var eventDeleteAttempts = [UUID]()

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        guard !failsWrites else {
            throw SubjectiveRecordStoreError.persistenceFailed
        }
        checkIns[record.localDay.storageKey] = record
        savedCheckIns.append(record)
        return record
    }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        readCount += 1
        if failsReads { throw SubjectiveRecordStoreError.persistenceFailed }
        return checkIns[day.storageKey]
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        checkIns[day.storageKey] = nil
    }

    func save(_ event: ContextEvent) throws {
        eventWriteAttempts.append(event)
        if failsWrites { throw SubjectiveRecordStoreError.persistenceFailed }
        events[event.id] = event
    }

    func contextEvents(
        overlapping interval: DateInterval
    ) throws -> [ContextEvent] {
        eventReadCount += 1
        if failsReads { throw SubjectiveRecordStoreError.persistenceFailed }
        return events.values.filter {
            $0.startedAt < interval.end && ($0.endedAt ?? $0.startedAt) >= interval.start
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func deleteContextEvent(id: UUID) throws {
        eventDeleteAttempts.append(id)
        if failsWrites { throw SubjectiveRecordStoreError.persistenceFailed }
        events[id] = nil
    }
}

extension SubjectiveRecordStoreTests {
    func testDefaultContextEventCatalogHasElevenStableLabelsWithoutCustom() {
        XCTAssertEqual(ContextEventKind.defaultKinds.count, 11)
        XCTAssertEqual(Set(ContextEventKind.defaultKinds).count, 11)
        XCTAssertFalse(ContextEventKind.defaultKinds.contains(.custom))
        XCTAssertEqual(ContextEventKind.defaultKinds.map(\.title), [
            "加班", "考试或截止日期", "旅行", "夜班", "咖啡", "饮酒", "生病",
            "高强度运动", "午睡", "照护家人", "未佩戴设备"
        ])
    }

    @MainActor
    func testEventSelectionRequiresExplicitSaveAndDoesNotChangeFeelings() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertFalse(session.save(at: date))
        session.select(.custom)
        XCTAssertEqual(session.selectedKind, .custom)
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(at: date))
        session.select(.caffeine)
        session.select(.caffeine)
        XCTAssertNil(session.selectedKind)
        session.select(.nap)
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
        XCTAssertTrue(session.save(at: date))
        XCTAssertEqual(session.events.first?.kind, .nap)
        XCTAssertEqual(session.events.first?.startedAt, date)
        XCTAssertNil(session.events.first?.endedAt)
        XCTAssertFalse(session.save(at: date))
        XCTAssertEqual(store.eventWriteAttempts.count, 1)
        XCTAssertTrue(store.savedCheckIns.isEmpty)
    }

    @MainActor
    func testEventSaveFailurePreservesSelectionAndRetriesSameID() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.overtime)
        store.failsWrites = true
        XCTAssertFalse(session.save(at: date))
        XCTAssertEqual(session.selectedKind, .overtime)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertNotNil(session.errorMessage)
        store.failsWrites = false
        XCTAssertTrue(session.save(at: date.addingTimeInterval(60)))
        XCTAssertEqual(store.eventWriteAttempts[0].id, store.eventWriteAttempts[1].id)
        XCTAssertEqual(session.events.first?.startedAt, date)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testEventReadFailureBlocksSaveUntilExplicitRetry() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.failsReads = true
        session.prepare(at: date, dataMode: .live)
        session.select(.travel)
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(at: date))
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
        store.failsReads = false
        session.open(at: date)
        XCTAssertEqual(session.selectedKind, .travel)
        XCTAssertTrue(session.canSave)
        XCTAssertTrue(session.save(at: date))
    }

    @MainActor
    func testEventDemoModeDoesNotReadWriteOrExposeRealRecords() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .demo)
        session.open(at: date)
        session.select(.caffeine)
        XCTAssertFalse(session.save(at: date))
        XCTAssertFalse(session.delete(id: UUID(), at: date))
        XCTAssertEqual(store.eventReadCount, 0)
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
        XCTAssertTrue(store.eventDeleteAttempts.isEmpty)
        session.prepare(at: date, dataMode: .live)
        session.select(.caffeine)
        XCTAssertTrue(session.save(at: date))
        session.open(at: date)
        let reads = store.eventReadCount
        session.prepare(at: date, dataMode: .demo)
        XCTAssertFalse(session.isPresented)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertNil(session.selectedKind)
        XCTAssertEqual(store.eventReadCount, reads)
        session.prepare(at: date, dataMode: .live)
        XCTAssertEqual(session.events.count, 1)
    }

    @MainActor
    func testEventForegroundDoesNotReloadOrResetUnsubmittedSelection() {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.nightShift)
        session.prepare(at: date.addingTimeInterval(60), dataMode: .live)
        XCTAssertEqual(session.selectedKind, .nightShift)
        XCTAssertEqual(store.eventReadCount, 1)
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
    }

    @MainActor
    func testEventMidnightRejectsOldSelectionAndCannotDeleteYesterday() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-15T23:59:00Z"))
        session.prepare(at: date, dataMode: .live, timeZone: .gmt)
        session.select(.overtime)
        XCTAssertTrue(session.save(at: date, timeZone: .gmt))
        let id = try XCTUnwrap(session.events.first?.id)
        session.select(.nap)
        let tomorrow = date.addingTimeInterval(120)
        XCTAssertFalse(session.save(at: tomorrow, timeZone: .gmt))
        XCTAssertNil(session.selectedKind)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertNotNil(session.notice)
        XCTAssertFalse(session.delete(id: id, at: tomorrow, timeZone: .gmt))
        XCTAssertEqual(store.events.count, 1)
    }

    @MainActor
    func testEventDeleteFailureKeepsRecordsAndSuccessOnlyRemovesTarget() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        for kind in [ContextEventKind.caffeine, .nap] {
            session.select(kind)
            XCTAssertTrue(session.save(at: date))
        }
        let target = try XCTUnwrap(session.events.first?.id)
        store.failsWrites = true
        XCTAssertFalse(session.delete(id: target, at: date))
        XCTAssertEqual(session.events.count, 2)
        store.failsWrites = false
        XCTAssertTrue(session.delete(id: target, at: date))
        XCTAssertEqual(session.events.count, 1)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(session.events.first?.kind, .caffeine)
    }

    @MainActor
    func testEventTimezoneChangeReloadsLocalDayAndClearsDraft() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2027-01-15T20:00:00Z"))
        session.prepare(at: date, dataMode: .live, timeZone: .gmt)
        session.select(.travel)
        XCTAssertFalse(session.save(at: date, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))))
        XCTAssertNil(session.selectedKind)
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
        XCTAssertEqual(store.eventReadCount, 2)
    }

    @MainActor
    func testEventLocalDayQueryHandlesDSTAndExcludesNextMidnight() throws {
        let store = TestSubjectiveRecordStore()
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2027-03-14T08:00:00Z"))
        let nextDay = start.addingTimeInterval(23 * 3600)
        let included = try ContextEvent(kind: .nap, startedAt: nextDay.addingTimeInterval(-1))
        let excluded = try ContextEvent(kind: .caffeine, startedAt: nextDay)
        store.events = [included.id: included, excluded.id: excluded]
        let session = ContextEventSession(store: store)
        session.prepare(at: start, dataMode: .live, timeZone: zone)
        XCTAssertEqual(session.events, [included])
    }

    @MainActor
    func testDefaultEventDiskRestartRestoresAndDeletionPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ContextEventTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "events.store")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var ids = [UUID]()
        do {
            let session = ContextEventSession(store: SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url)))
            session.prepare(at: date, dataMode: .live)
            for kind in ContextEventKind.defaultKinds {
                session.select(kind)
                XCTAssertTrue(session.save(at: date))
            }
            ids = session.events.map(\.id)
        }
        do {
            let session = ContextEventSession(store: SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url)))
            session.prepare(at: date, dataMode: .live)
            XCTAssertEqual(Set(session.events.map(\.id)), Set(ids))
            XCTAssertTrue(session.delete(id: ids[0], at: date))
        }
        let session = ContextEventSession(store: SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url)))
        session.prepare(at: date, dataMode: .live)
        XCTAssertEqual(session.events.count, 10)
        XCTAssertFalse(session.events.contains { $0.id == ids[0] })
    }

    @MainActor
    func testReadOnlyEventStoreRollsBackFailedInsertAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReadOnlyEventTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "events.store")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = try ContextEvent(kind: .nap, startedAt: date)
        do {
            let store = SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url))
            try store.save(original)
        }
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let configuration = ModelConfiguration("ReadOnlyEvents", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: SubjectiveRecordsMigrationPlan.self, configurations: [configuration])
        let store = SwiftDataSubjectiveRecordStore(modelContainer: container)
        let interval = DateInterval(start: date.addingTimeInterval(-60), duration: 120)
        let rejected = try ContextEvent(kind: .travel, startedAt: date)
        XCTAssertThrowsError(try store.save(rejected))
        XCTAssertEqual(try store.contextEvents(overlapping: interval), [original])
        XCTAssertThrowsError(try store.deleteContextEvent(id: original.id))
        XCTAssertEqual(try store.contextEvents(overlapping: interval), [original])
    }
}

extension SubjectiveRecordStoreTests {
    @MainActor
    func testCustomEventValidatesBlankAndUnicodeLengthsWithoutTruncating() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.custom)
        session.customLabel = " \n "
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(at: date))
        session.customLabel = String(repeating: "🌿", count: 31)
        XCTAssertFalse(session.canSave)
        XCTAssertEqual(session.customLabel.count, 31)
        session.customLabel = "  " + String(repeating: "🌿", count: 30) + "  "
        session.note = String(repeating: "记", count: 161)
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(at: date))
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
        session.note = " \n" + String(repeating: "记", count: 160) + " \n"
        XCTAssertTrue(session.canSave)
        XCTAssertTrue(session.save(at: date))
        XCTAssertEqual(session.events.first?.customLabel?.count, 30)
        XCTAssertEqual(session.events.first?.note?.count, 160)
        XCTAssertEqual(session.customLabel, "")
        XCTAssertEqual(session.note, "")
    }

    @MainActor
    func testDefaultEventKeepsOptionalNoteButNeverHiddenCustomLabel() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.custom)
        session.customLabel = "园艺"
        session.note = "  合成生活背景  "
        session.select(.nap)
        XCTAssertTrue(session.save(at: date))
        XCTAssertEqual(session.events.first?.kind, .nap)
        XCTAssertNil(session.events.first?.customLabel)
        XCTAssertEqual(session.events.first?.note, "合成生活背景")
        session.select(.nap)
        session.note = " \n "
        XCTAssertTrue(session.save(at: date))
        XCTAssertNil(session.events.first?.note)
    }

    @MainActor
    func testEditedCustomEventRetryUsesLatestTextAndOriginalIdentity() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.custom)
        session.customLabel = "初始标签"
        session.note = "初始合成备注"
        store.failsWrites = true
        XCTAssertFalse(session.save(at: date))
        XCTAssertEqual(session.customLabel, "初始标签")
        XCTAssertEqual(session.note, "初始合成备注")
        session.customLabel = "修改标签"
        session.note = "修改后的合成备注"
        store.failsWrites = false
        XCTAssertTrue(session.save(at: date.addingTimeInterval(60)))
        XCTAssertEqual(store.eventWriteAttempts[0].id, store.eventWriteAttempts[1].id)
        XCTAssertEqual(session.events.first?.startedAt, date)
        XCTAssertEqual(session.events.first?.customLabel, "修改标签")
        XCTAssertEqual(session.events.first?.note, "修改后的合成备注")
        XCTAssertEqual(store.events.count, 1)
        XCTAssertFalse(session.save(at: date))
    }

    @MainActor
    func testCustomEventDraftSurvivesReopenButClearsOnDayAndModeChange() throws {
        let store = TestSubjectiveRecordStore()
        let session = ContextEventSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.prepare(at: date, dataMode: .live)
        session.select(.custom)
        session.customLabel = "合成标签"
        session.note = "合成草稿"
        store.failsReads = true
        session.open(at: date)
        XCTAssertFalse(session.canSave)
        XCTAssertEqual(session.note, "合成草稿")
        store.failsReads = false
        session.open(at: date)
        XCTAssertTrue(session.canSave)
        XCTAssertEqual(session.customLabel, "合成标签")
        XCTAssertFalse(session.save(at: date.addingTimeInterval(86_400)))
        XCTAssertEqual(session.customLabel, "")
        XCTAssertEqual(session.note, "")
        session.select(.custom)
        session.customLabel = "另一个标签"
        session.note = "另一个草稿"
        let reads = store.eventReadCount
        session.prepare(at: date.addingTimeInterval(86_400), dataMode: .demo)
        XCTAssertEqual(session.note, "")
        XCTAssertEqual(session.customLabel, "")
        XCTAssertEqual(store.eventReadCount, reads)
        XCTAssertFalse(session.save(at: date.addingTimeInterval(86_400)))
        XCTAssertTrue(store.eventWriteAttempts.isEmpty)
    }

    @MainActor
    func testCustomEventsAndCheckInNotesSurviveDiskSessionRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SubjectiveTextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "records.store")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let store = SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url))
            let event = ContextEventSession(store: store)
            event.prepare(at: date, dataMode: .live)
            event.select(.custom)
            event.customLabel = "园艺"
            event.note = "合成事件备注"
            XCTAssertTrue(event.save(at: date))
            let feeling = SubjectiveCheckInSession(store: store)
            feeling.load(for: date)
            feeling.energy = .three
            feeling.stress = .three
            feeling.bodyFeeling = .three
            feeling.note = "合成感受备注"
            XCTAssertTrue(feeling.save(for: date))
        }
        let store = SwiftDataSubjectiveRecordStore(modelContainer: try makeContainer(storeURL: url))
        let event = ContextEventSession(store: store)
        event.prepare(at: date, dataMode: .live)
        XCTAssertEqual(event.events.first?.customLabel, "园艺")
        XCTAssertEqual(event.events.first?.note, "合成事件备注")
        let feeling = SubjectiveCheckInSession(store: store)
        feeling.load(for: date)
        XCTAssertEqual(feeling.note, "合成感受备注")
    }

    @MainActor
    func testFeelingNoteCanUpdateAndClearWithoutDuplicatingTheDay() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.load(for: date)
        session.energy = .four
        session.stress = .two
        session.bodyFeeling = .four
        session.note = "  合成备注  "
        XCTAssertTrue(session.save(for: date))
        let id = try XCTUnwrap(session.savedCheckIn?.id)
        XCTAssertEqual(session.note, "合成备注")
        session.note = "更新后的备注"
        XCTAssertTrue(session.save(for: date))
        XCTAssertEqual(session.savedCheckIn?.id, id)
        session.note = " \n "
        XCTAssertTrue(session.save(for: date))
        XCTAssertNil(session.savedCheckIn?.note)
        XCTAssertEqual(session.note, "")
        XCTAssertEqual(store.checkIns.count, 1)
    }

    @MainActor
    func testFeelingNoteLimitAndWriteFailureKeepTheDraft() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.load(for: date)
        session.energy = .three
        session.stress = .three
        session.bodyFeeling = .three
        session.note = String(repeating: "🌿", count: 161)
        XCTAssertFalse(session.canSave)
        XCTAssertFalse(session.save(for: date))
        XCTAssertEqual(session.note.count, 161)
        XCTAssertTrue(store.savedCheckIns.isEmpty)
        session.note = String(repeating: "🌿", count: 160)
        store.failsWrites = true
        XCTAssertTrue(session.canSave)
        XCTAssertFalse(session.save(for: date))
        XCTAssertEqual(session.note.count, 160)
        store.failsWrites = false
        XCTAssertTrue(session.save(for: date))
        XCTAssertEqual(session.savedCheckIn?.note?.count, 160)
    }

    @MainActor
    func testFeelingNoteIsClearedByReadFailureDemoAndCrossDaySave() throws {
        let store = TestSubjectiveRecordStore()
        let session = SubjectiveCheckInSession(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        session.load(for: date)
        session.note = "合成草稿"
        store.failsReads = true
        session.load(for: date)
        XCTAssertEqual(session.note, "")
        XCTAssertFalse(session.canSave)
        store.failsReads = false
        session.load(for: date)
        session.energy = .three
        session.stress = .three
        session.bodyFeeling = .three
        session.note = "旧日合成草稿"
        XCTAssertFalse(session.save(for: date.addingTimeInterval(86_400)))
        XCTAssertEqual(session.note, "")
        XCTAssertTrue(store.savedCheckIns.isEmpty)
        session.note = "另一个草稿"
        session.load(for: date, isRecordingEnabled: false)
        XCTAssertEqual(session.note, "")
        XCTAssertFalse(session.save(for: date))
    }

    @MainActor
    private func promptPreferences() throws -> UserDefaults {
        let name = "DailyCheckInPromptTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return preferences
    }

    @MainActor
    func testAppEntryNeverPresentsFeelingSheetEvenAfterCoordinatorRecreation() throws {
        let store = TestSubjectiveRecordStore()
        let preferences = try promptPreferences()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = DailyCheckInCoordinator(store: store, preferences: preferences)
        first.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(first.isPresented)
        XCTAssertNil(preferences.string(forKey: DailyCheckInCoordinator.promptedDayKey))
        first.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(first.isPresented)
        let restarted = DailyCheckInCoordinator(store: store, preferences: preferences)
        restarted.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(restarted.isPresented)
        restarted.openManually(at: date)
        XCTAssertTrue(restarted.isPresented)
        XCTAssertTrue(store.savedCheckIns.isEmpty)
    }

    @MainActor
    func testAlreadyRecordedDayDoesNotShowAutomaticPrompt() throws {
        let store = TestSubjectiveRecordStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: date), energy: .two, stress: .three, bodyFeeling: .four)
        store.checkIns[record.localDay.storageKey] = record
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        coordinator.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.session.savedCheckIn, record)
    }

    @MainActor
    func testManualReopenRetainsDraftAndSaveClosesSheet() throws {
        let store = TestSubjectiveRecordStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        coordinator.enterApp(at: date, dataMode: .live)
        coordinator.markPresented()
        coordinator.session.energy = .four
        coordinator.dismiss()
        coordinator.openManually(at: date)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.session.energy, .four)
        coordinator.session.stress = .two
        coordinator.session.bodyFeeling = .three
        XCTAssertTrue(coordinator.save(at: date))
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(store.savedCheckIns.count, 1)
        XCTAssertEqual(coordinator.session.savedCheckIn, store.savedCheckIns.last)
    }

    @MainActor
    func testNextLocalDayRefreshesEmptyRatingsWithoutPresentingSheet() throws {
        let coordinator = DailyCheckInCoordinator(store: TestSubjectiveRecordStore(), preferences: try promptPreferences())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.enterApp(at: date, dataMode: .live)
        coordinator.markPresented()
        coordinator.session.energy = .four
        coordinator.dismiss()
        coordinator.enterApp(at: date.addingTimeInterval(86_400), dataMode: .live)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.session.energy)
        XCTAssertNil(coordinator.session.savedCheckIn)
    }

    @MainActor
    func testSavingAfterMidnightDoesNotCarryYesterdayDraftForward() throws {
        let store = TestSubjectiveRecordStore()
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.openManually(at: date)
        coordinator.session.energy = .four
        coordinator.session.stress = .two
        coordinator.session.bodyFeeling = .three
        XCTAssertFalse(coordinator.save(at: date.addingTimeInterval(86_400)))
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertNotNil(coordinator.notice)
        XCTAssertNil(coordinator.session.energy)
        XCTAssertTrue(store.savedCheckIns.isEmpty)
    }

    @MainActor
    func testDemoModeDoesNotReadOrConsumeDailyPrompt() throws {
        let store = TestSubjectiveRecordStore()
        let preferences = try promptPreferences()
        let coordinator = DailyCheckInCoordinator(store: store, preferences: preferences)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.enterApp(at: date, dataMode: .demo)
        coordinator.openManually(at: date)
        coordinator.markPresented()
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertFalse(coordinator.save(at: date))
        XCTAssertEqual(store.readCount, 0)
        XCTAssertNil(preferences.string(forKey: DailyCheckInCoordinator.promptedDayKey))
        coordinator.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(coordinator.isPresented)
        coordinator.openManually(at: date)
        XCTAssertTrue(coordinator.isPresented)
        coordinator.session.energy = .four
        coordinator.enterApp(at: date, dataMode: .demo)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.session.energy)
    }

    @MainActor
    func testDemoCoordinatorAllowsSessionOnlyFeelingAndEventEdits() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DemoSubjectiveRecordStore(endingAt: date)
        let coordinator = DailyCheckInCoordinator(
            store: store,
            preferences: try promptPreferences(),
            referenceDate: date,
            allowsDemoRecords: true
        )

        coordinator.enterApp(at: date, dataMode: .demo)
        XCTAssertTrue(coordinator.session.isRecordingEnabled)
        coordinator.openManually(at: date)
        XCTAssertTrue(coordinator.isPresented)
        coordinator.session.energy = .five
        coordinator.session.stress = .one
        coordinator.session.bodyFeeling = .four
        coordinator.session.note = "演示中修改后的感受"
        XCTAssertTrue(coordinator.save(at: date))
        XCTAssertEqual(
            try store.checkIn(on: SubjectiveLocalDay(date: date))?.note,
            "演示中修改后的感受"
        )

        let eventSession = coordinator.contextEvents
        eventSession.open(at: date)
        XCTAssertTrue(eventSession.isPresented)
        eventSession.select(.travel)
        eventSession.note = "演示中新增的生活事件"
        XCTAssertTrue(eventSession.save(at: date))
        let savedEvent = try XCTUnwrap(eventSession.events.first {
            $0.note == "演示中新增的生活事件"
        })
        XCTAssertTrue(eventSession.delete(id: savedEvent.id, at: date))
        XCTAssertFalse(eventSession.events.contains { $0.id == savedEvent.id })
    }

    @MainActor
    func testPromptSaveFailureKeepsWindowAndDraftForRetry() throws {
        let store = TestSubjectiveRecordStore()
        store.failsWrites = true
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.openManually(at: date)
        coordinator.session.energy = .four
        coordinator.session.stress = .two
        coordinator.session.bodyFeeling = .three
        XCTAssertFalse(coordinator.save(at: date))
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.session.energy, .four)
        XCTAssertNotNil(coordinator.session.errorMessage)
        store.failsWrites = false
        XCTAssertTrue(coordinator.save(at: date))
        XCTAssertFalse(coordinator.isPresented)
    }

    @MainActor
    func testReadFailureDoesNotAutomaticallyInterruptUser() throws {
        let store = TestSubjectiveRecordStore()
        store.failsReads = true
        let preferences = try promptPreferences()
        let coordinator = DailyCheckInCoordinator(store: store, preferences: preferences)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.enterApp(at: date, dataMode: .live)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.session.errorMessage, "暂时无法读取今日记录，请关闭窗口后重新打开重试。")
        XCTAssertNil(preferences.string(forKey: DailyCheckInCoordinator.promptedDayKey))
        coordinator.openManually(at: date)
        XCTAssertTrue(coordinator.isPresented)
    }

    @MainActor
    func testRepeatedForegroundEventsDoNotReloadAnOpenDraft() throws {
        let store = TestSubjectiveRecordStore()
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.openManually(at: date)
        coordinator.session.energy = .four
        coordinator.enterApp(at: date.addingTimeInterval(60), dataMode: .live)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.session.energy, .four)
        XCTAssertEqual(store.readCount, 1)
    }

    @MainActor
    func testReadFailureCannotOverwriteUnknownRecordAndManualReopenRetries() throws {
        let store = TestSubjectiveRecordStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: date), energy: .two, stress: .three, bodyFeeling: .four, note: "合成测试备注")
        store.checkIns[record.localDay.storageKey] = record
        store.failsReads = true
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try promptPreferences())
        coordinator.enterApp(at: date, dataMode: .live)
        coordinator.openManually(at: date)
        coordinator.session.energy = .four
        coordinator.session.stress = .two
        coordinator.session.bodyFeeling = .three
        XCTAssertFalse(coordinator.session.canSave)
        XCTAssertFalse(coordinator.save(at: date))
        XCTAssertTrue(store.savedCheckIns.isEmpty)
        coordinator.dismiss()
        store.failsReads = false
        coordinator.openManually(at: date)
        XCTAssertEqual(coordinator.session.savedCheckIn, record)
        XCTAssertTrue(coordinator.save(at: date))
        XCTAssertEqual(store.savedCheckIns.last?.note, record.note)
    }
}
