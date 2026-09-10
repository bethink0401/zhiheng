import XCTest
@testable import Zhiheng

final class InsightContextMatchingTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!

    private func calendar(_ timeZone: TimeZone? = nil) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone ?? zone
        return value
    }

    private func localDate(
        year: Int = 2026,
        month: Int = 9,
        day: Int = 4,
        hour: Int = 0,
        timeZone: TimeZone? = nil
    ) -> Date {
        calendar(timeZone).date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func factSet(
        mode: HealthDataMode = .live,
        timeZone: TimeZone? = nil,
        end: Date? = nil
    ) -> InsightFactSet {
        let resolvedZone = timeZone ?? zone
        let resolvedEnd = end ?? localDate(timeZone: resolvedZone)
        let start = calendar(resolvedZone).date(byAdding: .day, value: -35, to: resolvedEnd)!
        return InsightFactSet(
            generatorVersion: InsightFactGenerator.version,
            analysisInterval: DateInterval(start: start, end: resolvedEnd),
            timeZoneIdentifier: resolvedZone.identifier,
            dataMode: mode,
            facts: [InsightFact(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                metric: .stepCount,
                evidence: .unavailable(.noVisibleData)
            )]
        )
    }

    private func day(_ offset: Int, factSet: InsightFactSet? = nil) throws -> SubjectiveLocalDay {
        let window = try InsightContextMatcher.window(for: factSet ?? self.factSet())
        return window.localDays[offset]
    }

    private func checkIn(
        id: UUID = UUID(),
        dayOffset: Int,
        note: String? = nil,
        updatedAt: Date? = nil,
        factSet: InsightFactSet? = nil
    ) throws -> DailyCheckIn {
        let recordDate = localDate(day: 1 + dayOffset, hour: 12)
        return try DailyCheckIn(
            id: id,
            localDay: day(dayOffset, factSet: factSet),
            energy: .four,
            stress: .two,
            bodyFeeling: .three,
            note: note,
            recordedAt: recordDate,
            updatedAt: updatedAt ?? recordDate
        )
    }

    func testWindowUsesOnlyCurrentSevenCompleteLocalDays() throws {
        let result = try InsightContextMatcher.window(for: factSet())

        XCTAssertEqual(result.interval.start, localDate(month: 8, day: 28))
        XCTAssertEqual(result.interval.end, localDate(day: 4))
        XCTAssertEqual(result.localDays.count, 7)
        XCTAssertEqual(result.localDays.first?.storageKey, "2026-08-28")
        XCTAssertEqual(result.localDays.last?.storageKey, "2026-09-03")
        XCTAssertEqual(result.timeZoneIdentifier, zone.identifier)
    }

    func testWindowKeepsSevenCalendarDaysAcrossDaylightSavingChange() throws {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let end = localDate(year: 2026, month: 11, day: 5, timeZone: losAngeles)
        let result = try InsightContextMatcher.window(for: factSet(
            timeZone: losAngeles,
            end: end
        ))

        XCTAssertEqual(result.localDays.count, 7)
        XCTAssertEqual(result.localDays.first?.storageKey, "2026-10-29")
        XCTAssertEqual(result.localDays.last?.storageKey, "2026-11-04")
        XCTAssertEqual(result.interval.end, end)
    }

    func testMatchKeepsStructuredValuesAndReferencesButNoPrivateText() throws {
        let facts = factSet()
        let checkInID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let eventID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let privateNote = "仅保留在主观记录中的合成备注"
        let privateLabel = "仅保留在事件记录中的合成名称"
        let subjective = try checkIn(
            id: checkInID,
            dayOffset: 5,
            note: privateNote
        )
        let event = try ContextEvent(
            id: eventID,
            kind: .custom,
            customLabel: privateLabel,
            startedAt: localDate(day: 2, hour: 9),
            endedAt: localDate(day: 2, hour: 11),
            intensity: .high,
            note: privateNote,
            createdAt: localDate(day: 2, hour: 9)
        )

        let result = try InsightContextMatcher.match(
            factSet: facts,
            checkIns: [subjective],
            contextEvents: [event]
        )

        XCTAssertEqual(result.matcherVersion, "s09-context-matcher-v1")
        XCTAssertEqual(result.checkIns.first?.energy, .four)
        XCTAssertEqual(result.checkIns.first?.stress, .two)
        XCTAssertEqual(result.contextEvents.first?.kind, .custom)
        XCTAssertEqual(result.contextEvents.first?.intensity, .high)
        XCTAssertEqual(result.references.map(\.recordID), [checkInID, eventID])
        XCTAssertTrue(result.references.allSatisfy { $0.dataMode == .live })
        let description = String(reflecting: result)
        XCTAssertFalse(description.contains(privateNote))
        XCTAssertFalse(description.contains(privateLabel))
    }

    func testEventsUseHalfOpenWindowAndExistingOverlapSemantics() throws {
        let facts = factSet()
        let window = try InsightContextMatcher.window(for: facts).interval
        func event(_ id: String, start: Date, end: Date? = nil) throws -> ContextEvent {
            try ContextEvent(
                id: UUID(uuidString: id)!,
                kind: .travel,
                startedAt: start,
                endedAt: end,
                createdAt: start
            )
        }
        let endingAtStart = try event(
            "30000000-0000-0000-0000-000000000001",
            start: window.start.addingTimeInterval(-3_600),
            end: window.start
        )
        let pointAtStart = try event(
            "30000000-0000-0000-0000-000000000002",
            start: window.start
        )
        let pointAtEnd = try event(
            "30000000-0000-0000-0000-000000000003",
            start: window.end
        )
        let prior = try event(
            "30000000-0000-0000-0000-000000000004",
            start: window.start.addingTimeInterval(-7_200)
        )

        let result = try InsightContextMatcher.match(
            factSet: facts,
            checkIns: [],
            contextEvents: [pointAtEnd, prior, pointAtStart, endingAtStart]
        )

        XCTAssertEqual(result.contextEvents.map(\.reference.recordID), [
            endingAtStart.id, pointAtStart.id
        ])
    }

    func testOrderingAndExactDuplicateRemovalAreDeterministic() throws {
        let laterID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        let earlierID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let later = try checkIn(id: laterID, dayOffset: 6)
        let earlier = try checkIn(id: earlierID, dayOffset: 0)
        let event = try ContextEvent(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
            kind: .nap,
            startedAt: localDate(day: 1, hour: 14),
            createdAt: localDate(day: 1, hour: 14)
        )

        let result = try InsightContextMatcher.match(
            factSet: factSet(),
            checkIns: [later, earlier, earlier],
            contextEvents: [event, event]
        )

        XCTAssertEqual(result.checkIns.map(\.reference.recordID), [earlierID, laterID])
        XCTAssertEqual(result.contextEvents.count, 1)
    }

    func testConflictingDuplicateRecordAndDuplicateLocalDayAreRejected() throws {
        let sharedID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let original = try checkIn(id: sharedID, dayOffset: 2)
        let conflicting = try DailyCheckIn(
            id: sharedID,
            localDay: original.localDay,
            energy: .one,
            stress: original.stress,
            bodyFeeling: original.bodyFeeling,
            recordedAt: original.recordedAt,
            updatedAt: original.updatedAt
        )
        XCTAssertThrowsError(try InsightContextMatcher.match(
            factSet: factSet(), checkIns: [original, conflicting], contextEvents: []
        )) { XCTAssertEqual($0 as? InsightContextMatchingError, .duplicateRecord) }

        let secondID = try checkIn(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            dayOffset: 2
        )
        XCTAssertThrowsError(try InsightContextMatcher.match(
            factSet: factSet(), checkIns: [original, secondID], contextEvents: []
        )) { XCTAssertEqual($0 as? InsightContextMatchingError, .duplicateLocalDay) }
    }

    func testSameUUIDAcrossDifferentRecordKindsRemainsUnambiguous() throws {
        let sharedID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let subjective = try checkIn(id: sharedID, dayOffset: 1)
        let event = try ContextEvent(
            id: sharedID,
            kind: .overtime,
            startedAt: localDate(day: 1, hour: 20),
            createdAt: localDate(day: 1, hour: 20)
        )
        let result = try InsightContextMatcher.match(
            factSet: factSet(), checkIns: [subjective], contextEvents: [event]
        )

        XCTAssertEqual(result.references.map(\.kind), [.dailyCheckIn, .contextEvent])
        XCTAssertEqual(result.references.map(\.recordID), [sharedID, sharedID])
    }

    func testInvalidOrNonCanonicalFactWindowIsRejected() throws {
        let valid = factSet()
        let invalid = InsightFactSet(
            generatorVersion: valid.generatorVersion,
            analysisInterval: DateInterval(
                start: valid.analysisInterval.start.addingTimeInterval(3_600),
                end: valid.analysisInterval.end
            ),
            timeZoneIdentifier: valid.timeZoneIdentifier,
            dataMode: valid.dataMode,
            facts: valid.facts
        )

        XCTAssertThrowsError(try InsightContextMatcher.window(for: invalid)) {
            XCTAssertEqual($0 as? InsightContextMatchingError, .invalidFactWindow)
        }
    }

    @MainActor
    func testLoaderReadsSevenDaysAndOneEventRangeAsOneAvailableSnapshot() throws {
        let facts = factSet()
        let subjective = try checkIn(dayOffset: 3)
        let event = try ContextEvent(
            kind: .deadline,
            startedAt: localDate(day: 2, hour: 10),
            createdAt: localDate(day: 2, hour: 10)
        )
        let store = InsightContextStoreSpy(checkIns: [subjective], events: [event])

        let state = InsightContextLoader(store: store).load(for: facts)

        guard case let .available(result) = state else {
            return XCTFail("Expected available context")
        }
        XCTAssertEqual(result.checkIns.count, 1)
        XCTAssertEqual(result.contextEvents.count, 1)
        XCTAssertEqual(store.checkInReadCount, 7)
        XCTAssertEqual(store.eventReadCount, 1)
        XCTAssertEqual(store.lastEventInterval, result.window.interval)
    }

    @MainActor
    func testEmptyLiveStoreIsAvailableRatherThanAReadFailure() {
        let store = InsightContextStoreSpy()
        let state = InsightContextLoader(store: store).load(for: factSet())

        guard case let .available(result) = state else {
            return XCTFail("Expected an empty available snapshot")
        }
        XCTAssertTrue(result.checkIns.isEmpty)
        XCTAssertTrue(result.contextEvents.isEmpty)
    }

    @MainActor
    func testDemoModeNeverReadsOrRelabelsLiveSubjectiveRecords() throws {
        let record = try checkIn(dayOffset: 0)
        let store = InsightContextStoreSpy(checkIns: [record])
        let demoFacts = factSet(mode: .demo)

        XCTAssertEqual(
            InsightContextLoader(store: store).load(for: demoFacts),
            .demoMode
        )
        XCTAssertEqual(store.checkInReadCount, 0)
        XCTAssertEqual(store.eventReadCount, 0)
        XCTAssertThrowsError(try InsightContextMatcher.match(
            factSet: demoFacts,
            checkIns: [record],
            contextEvents: []
        )) {
            XCTAssertEqual($0 as? InsightContextMatchingError, .unsupportedDataMode)
        }
    }

    @MainActor
    func testTimeZoneMismatchFailsWithoutReturningPartialContext() throws {
        let requested = try day(0)
        let mismatchedDay = try SubjectiveLocalDay(
            year: requested.year,
            month: requested.month,
            day: requested.day,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let record = try DailyCheckIn(
            localDay: mismatchedDay,
            energy: .three,
            stress: .three,
            bodyFeeling: .three,
            recordedAt: localDate(day: 28, hour: 12)
        )
        let store = InsightContextStoreSpy(checkIns: [record])

        XCTAssertEqual(
            InsightContextLoader(store: store).load(for: factSet()),
            .failed(.dateOrTimeZoneMismatch)
        )
        XCTAssertEqual(store.eventReadCount, 0)
    }

    @MainActor
    func testAnyStoreReadFailureReturnsNoPartialSnapshot() throws {
        let checkInStore = InsightContextStoreSpy(checkIns: [try checkIn(dayOffset: 0)])
        checkInStore.failCheckInReadNumber = 4
        XCTAssertEqual(
            InsightContextLoader(store: checkInStore).load(for: factSet()),
            .failed(.readFailed)
        )
        XCTAssertEqual(checkInStore.eventReadCount, 0)

        let eventStore = InsightContextStoreSpy(checkIns: [try checkIn(dayOffset: 0)])
        eventStore.failEventRead = true
        XCTAssertEqual(
            InsightContextLoader(store: eventStore).load(for: factSet()),
            .failed(.readFailed)
        )
        XCTAssertEqual(eventStore.checkInReadCount, 7)
    }

    @MainActor
    func testRevalidationDetectsAdditionEditDeletionAndMoveOutOfWindow() throws {
        let facts = factSet()
        let original = try checkIn(dayOffset: 2)
        let event = try ContextEvent(
            kind: .travel,
            startedAt: localDate(day: 1, hour: 8),
            createdAt: localDate(day: 1, hour: 8)
        )
        let store = InsightContextStoreSpy(checkIns: [original], events: [event])
        let loader = InsightContextLoader(store: store)
        guard case let .available(snapshot) = loader.load(for: facts) else {
            return XCTFail("Expected initial snapshot")
        }
        XCTAssertEqual(loader.validate(snapshot, for: facts), .current)

        store.checkIns = [try checkIn(
            id: original.id,
            dayOffset: 2,
            updatedAt: original.updatedAt.addingTimeInterval(1)
        )]
        XCTAssertEqual(loader.validate(snapshot, for: facts), .stale)

        store.checkIns = [original, try checkIn(dayOffset: 4)]
        XCTAssertEqual(loader.validate(snapshot, for: facts), .stale)

        store.checkIns = []
        store.events = []
        XCTAssertEqual(loader.validate(snapshot, for: facts), .stale)

        store.checkIns = [original]
        store.events = [try ContextEvent(
            id: event.id,
            kind: event.kind,
            startedAt: localDate(day: 4, hour: 8),
            createdAt: event.createdAt,
            updatedAt: event.updatedAt.addingTimeInterval(1)
        )]
        XCTAssertEqual(loader.validate(snapshot, for: facts), .stale)
    }

    @MainActor
    func testUnavailableObjectiveFactDoesNotEraseConcurrentUserContext() throws {
        let facts = factSet()
        XCTAssertEqual(facts.facts.first?.evidence, .unavailable(.noVisibleData))
        let store = InsightContextStoreSpy(checkIns: [try checkIn(dayOffset: 6)])

        guard case let .available(result) = InsightContextLoader(store: store).load(for: facts) else {
            return XCTFail("Expected context independent of objective availability")
        }
        XCTAssertEqual(result.checkIns.count, 1)
        XCTAssertTrue(result.contextEvents.isEmpty)
    }
}

@MainActor
private final class InsightContextStoreSpy: SubjectiveRecordStore {
    enum Failure: Error { case requested }

    var checkIns: [DailyCheckIn]
    var events: [ContextEvent]
    var failCheckInReadNumber: Int?
    var failEventRead = false
    private(set) var checkInReadCount = 0
    private(set) var eventReadCount = 0
    private(set) var lastEventInterval: DateInterval?

    init(checkIns: [DailyCheckIn] = [], events: [ContextEvent] = []) {
        self.checkIns = checkIns
        self.events = events
    }

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn { record }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        checkInReadCount += 1
        if checkInReadCount == failCheckInReadNumber { throw Failure.requested }
        return checkIns.first { $0.localDay.storageKey == day.storageKey }
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {}

    func save(_ event: ContextEvent) throws {}

    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] {
        eventReadCount += 1
        lastEventInterval = interval
        if failEventRead { throw Failure.requested }
        return events.filter {
            $0.startedAt < interval.end && ($0.endedAt ?? $0.startedAt) >= interval.start
        }
    }

    func deleteContextEvent(id: UUID) throws {}
}
