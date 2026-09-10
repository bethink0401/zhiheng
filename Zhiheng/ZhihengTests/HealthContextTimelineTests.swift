import XCTest
import SwiftData
@testable import Zhiheng

@MainActor
final class HealthContextTimelineTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private let watch = HealthMetricSource(sourceName: "Apple Watch", bundleIdentifier: nil, deviceName: nil)
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")! }
    private var day: DateInterval { HealthContextTimeline.intervals(endingAt: now, timeZone: zone)[0] }
    private var loaded: DateInterval { DateInterval(start: day.start.addingTimeInterval(-90 * 86400), end: now) }

    private func sample(_ metric: HealthMetricType = .stepCount, value: Double = 100,
                        end: Date? = nil, start: Date? = nil,
                        source: HealthMetricSource? = nil) throws -> HealthMetricSample {
        try HealthMetricSample(id: UUID(), metricType: metric, startDate: start ?? end ?? now,
            endDate: end ?? now, value: value, unit: metric.expectedUnit, source: source ?? watch)
    }

    private func state(_ samples: [HealthMetricSample], metric: HealthMetricType = .stepCount,
                       interval: DateInterval? = nil) -> TimelineMetricState {
        HealthContextTimeline.metricState(metric, day: interval ?? day,
            snapshot: HealthDataSnapshot(states: [metric: .available(samples)]),
            loadedInterval: loaded, access: .requestCompleted, timeZone: zone)
    }

    private func session(_ store: TimelineTestStore) -> SubjectiveHistorySession {
        let result = SubjectiveHistorySession(store: store)
        result.setDataMode(.live)
        result.open(at: now, timeZone: zone)
        return result
    }

    func testSevenDatesAreContiguousNewestFirstWithHalfOpenBoundaries() {
        let days = HealthContextTimeline.intervals(endingAt: now, timeZone: zone)
        XCTAssertEqual(days.count, 7)
        for index in 1..<days.count { XCTAssertEqual(days[index].end, days[index - 1].start) }
        XCTAssertEqual(SubjectiveLocalDay(date: days[0].start, timeZone: zone).storageKey, "2026-09-03")
        XCTAssertEqual(SubjectiveLocalDay(date: days[6].start, timeZone: zone).storageKey, "2026-08-28")
    }

    func testDSTDaysUseCalendarNotFixedSeconds() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = ISO8601DateFormatter().date(from: "2026-03-08T20:00:00Z")!
        let fall = ISO8601DateFormatter().date(from: "2026-11-01T20:00:00Z")!
        XCTAssertEqual(HealthContextTimeline.intervals(endingAt: spring, timeZone: zone)[0].duration, 23 * 3600)
        XCTAssertEqual(HealthContextTimeline.intervals(endingAt: fall, timeZone: zone)[0].duration, 25 * 3600)
    }

    func testSleepBelongsToEndDayAndIsNotSplitAtMidnight() throws {
        let sample = try sample(.sleepDuration, value: 8, end: day.start.addingTimeInterval(7 * 3600),
            start: day.start.addingTimeInterval(-3600))
        XCTAssertEqual(state([sample], metric: .sleepDuration), .value(8, source: "Apple Watch"))
        let yesterday = HealthContextTimeline.intervals(endingAt: now, timeZone: zone)[1]
        XCTAssertEqual(state([sample], metric: .sleepDuration, interval: yesterday), .noData)
    }

    func testZeroIsRealValueButEmptyAndOtherDayNeverBecomeZero() throws {
        XCTAssertEqual(state([try sample(value: 0)]), .value(0, source: "Apple Watch"))
        XCTAssertEqual(state([]), .noData)
        XCTAssertEqual(state([try sample(end: day.start.addingTimeInterval(-1))]), .noData)
    }

    func testSourcePriorityMatchesExistingChartAndDoesNotDoubleCount() throws {
        let phone = HealthMetricSource(sourceName: "iPhone", bundleIdentifier: nil, deviceName: nil)
        XCTAssertEqual(state([try sample(value: 30), try sample(value: 40),
                              try sample(value: 300, source: phone)]), .value(70, source: "Apple Watch"))
    }

    func testDifferentDaySourcesStayAttachedToTheirOwnDailyValues() throws {
        let phone = HealthMetricSource(sourceName: "iPhone", bundleIdentifier: nil, deviceName: nil)
        let yesterday = HealthContextTimeline.intervals(endingAt: now, timeZone: zone)[1]
        let samples = [try sample(value: 100), try sample(value: 50, end: yesterday.start, source: phone)]
        XCTAssertEqual(state(samples), .value(100, source: "Apple Watch"))
        XCTAssertEqual(state(samples, interval: yesterday), .value(50, source: "iPhone"))
    }

    func testAmbiguousSourcesAreNotPresentedAsMissingOrSummed() throws {
        let a = HealthMetricSource(sourceName: "合成 A", bundleIdentifier: nil, deviceName: nil)
        let b = HealthMetricSource(sourceName: "合成 B", bundleIdentifier: nil, deviceName: nil)
        XCTAssertEqual(state([try sample(source: a), try sample(source: b)]), .sourceConflict)
        XCTAssertEqual(state([try sample(.restingHeartRate), try sample(.restingHeartRate, source: b)],
            metric: .restingHeartRate), .sourceConflict)
    }

    func testHeartMetricsUseLatestSameDayNotAverageOrPreviousDay() throws {
        for metric in [HealthMetricType.restingHeartRate, .heartRateVariability] {
            let samples = [try sample(metric, value: 60, end: now.addingTimeInterval(-60)),
                           try sample(metric, value: 80),
                           try sample(metric, value: 99, end: day.start.addingTimeInterval(-1))]
            XCTAssertEqual(state(samples, metric: metric), .value(80, source: "Apple Watch"))
        }
    }

    func testFutureSamplesBeyondSnapshotEndAndWrongMetricsAreExcluded() throws {
        XCTAssertEqual(state([try sample(end: now.addingTimeInterval(1)),
                              try sample(.sleepDuration)]), .noData)
    }

    func testAllReadFailuresAndPermissionStatesStayDistinct() {
        let pairs: [(HealthMetricReadState, TimelineMetricState)] = [
            (.accessNotRequested, .notRequested), (.healthDataUnavailable, .unavailable),
            (.noVisibleData, .noData), (.failed(.queryFailed), .failed)
        ]
        for (input, expected) in pairs {
            XCTAssertEqual(HealthContextTimeline.metricState(.stepCount, day: day,
                snapshot: HealthDataSnapshot(states: [.stepCount: input]), loadedInterval: loaded,
                access: .requestCompleted, timeZone: zone), expected)
        }
    }

    func testUnloadedSnapshotDoesNotClaimPermissionDenialOrNoRecords() {
        let pairs: [(HealthAccessState, TimelineMetricState)] = [
            (.notRequested, .notRequested), (.unavailable, .unavailable), (.requestCompleted, .notLoaded)
        ]
        for (access, expected) in pairs {
            XCTAssertEqual(HealthContextTimeline.metricState(.stepCount, day: day, snapshot: nil,
                loadedInterval: nil, access: access, timeZone: zone), expected)
        }
    }

    func testOutOfWindowAndPartialFirstDayNeverClaimDailyTotal() {
        let snapshot = HealthDataSnapshot(states: [.stepCount: .noVisibleData])
        for interval in [DateInterval(start: day.start.addingTimeInterval(1), end: now),
                         DateInterval(start: loaded.start, end: day.start.addingTimeInterval(-1))] {
            XCTAssertEqual(HealthContextTimeline.metricState(.stepCount, day: day, snapshot: snapshot,
                loadedInterval: interval, access: .requestCompleted, timeZone: zone), .outsideWindow)
        }
        XCTAssertEqual(HealthContextTimeline.metricState(.stepCount, day: day, snapshot: snapshot,
            loadedInterval: nil, access: .requestCompleted, timeZone: zone), .notLoaded)
    }

    func testOvernightEventsAppearOnBothDaysAndStartAtNextMidnightIsExcluded() throws {
        let overnight = try ContextEvent(kind: .travel, startedAt: day.start.addingTimeInterval(-3600),
            endedAt: day.start.addingTimeInterval(3600))
        let next = try ContextEvent(kind: .caffeine, startedAt: day.end)
        let yesterday = HealthContextTimeline.intervals(endingAt: now, timeZone: zone)[1]
        XCTAssertEqual(HealthContextTimeline.overlapping([next, overnight], interval: day), [overnight])
        XCTAssertEqual(HealthContextTimeline.overlapping([overnight], interval: yesterday), [overnight])
    }

    func testPointEventsAndInclusiveEndMatchExistingStoreSemantics() throws {
        let point = try ContextEvent(kind: .caffeine, startedAt: day.start)
        let ending = try ContextEvent(kind: .travel, startedAt: day.start.addingTimeInterval(-1), endedAt: day.start)
        XCTAssertEqual(HealthContextTimeline.overlapping([point, ending], interval: day), [ending, point])
    }

    func testSameDateAlignmentIncludesFeelingsNotesAndEventsWithoutWriting() throws {
        let store = TimelineTestStore()
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: now, timeZone: zone),
            energy: .four, stress: .two, bodyFeeling: .five, note: "合成备注", recordedAt: now)
        let event = try ContextEvent(kind: .caffeine, startedAt: now)
        store.records[record.localDay.storageKey] = record
        store.events = [event]
        let history = session(store)
        store.reads = 0
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays.count, 7)
        XCTAssertEqual(history.timelineDays[0].checkIn, record)
        XCTAssertEqual(history.timelineDays[0].events, [event])
        XCTAssertTrue(history.timelineDays.dropFirst().allSatisfy { $0.checkIn == nil && $0.events.isEmpty })
        XCTAssertEqual(store.reads, 8)
        XCTAssertEqual(store.writes, 0)
    }

    func testFeelingsRetainOriginalLocalDateAndTimezoneWhileEventsUseBrowsingZone() throws {
        let store = TimelineTestStore()
        let originalZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = ISO8601DateFormatter().date(from: "2026-09-03T00:30:00Z")!
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: instant, timeZone: originalZone),
            energy: .four, stress: .two, bodyFeeling: .five, recordedAt: instant)
        store.records[record.localDay.storageKey] = record
        store.events = [try ContextEvent(kind: .travel, startedAt: instant)]
        let history = session(store)
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertNil(history.timelineDays[0].checkIn)
        XCTAssertEqual(history.timelineDays[0].events.count, 1)
        XCTAssertEqual(history.timelineDays[1].checkIn?.localDay.timeZoneIdentifier, originalZone.identifier)
        XCTAssertEqual(history.timelineDays[1].checkIn?.localDay.storageKey, "2026-09-02")
    }

    func testLateReadFailureClearsOldRowsAndNeverPublishesPartialWeekThenRetryWorks() {
        let store = TimelineTestStore()
        let history = session(store)
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays.count, 7)
        store.reads = 0
        store.failAtRead = 5
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertTrue(history.timelineDays.isEmpty)
        XCTAssertNotNil(history.timelineError)
        store.failAtRead = nil
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays.count, 7)
        XCTAssertNil(history.timelineError)
    }

    func testEventReadFailureIsNotAnEmptyEventList() {
        let store = TimelineTestStore()
        let history = session(store)
        store.reads = 0
        store.failAtRead = 1
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertTrue(history.timelineDays.isEmpty)
        XCTAssertNotNil(history.timelineError)
    }

    func testDemoClearsRowsAndBlocksAllStoreReads() {
        let store = TimelineTestStore()
        let history = session(store)
        history.loadTimeline(endingAt: now, now: now)
        history.setDataMode(.demo)
        store.reads = 0
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertTrue(history.timelineDays.isEmpty)
        XCTAssertNil(history.timelineError)
        XCTAssertEqual(store.reads, 0)
        history.setDataMode(.live)
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays.count, 7)
    }

    func testFutureDatesAreRejectedWithoutReading() {
        let store = TimelineTestStore()
        let history = session(store)
        store.reads = 0
        history.loadTimeline(endingAt: day.end, now: now)
        XCTAssertEqual(store.reads, 0)
        XCTAssertTrue(history.timelineDays.isEmpty)
        XCTAssertNotNil(history.timelineError)
    }

    func testReloadReflectsEditsAndDeletionsWithoutRetainingCachedCopies() throws {
        let store = TimelineTestStore()
        let history = session(store)
        let event = try ContextEvent(kind: .caffeine, startedAt: now)
        store.events = [event]
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays[0].events, [event])
        store.events = []
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertTrue(history.timelineDays[0].events.isEmpty)
    }

    func testTimelineReadsSameSwiftDataStoreAndReflectsHistoryMutation() throws {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let container = try ModelContainer(for: schema, migrationPlan: SubjectiveRecordsMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = SwiftDataSubjectiveRecordStore(modelContainer: container)
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: now, timeZone: zone),
            energy: .four, stress: .two, bodyFeeling: .five, recordedAt: now)
        let event = try ContextEvent(kind: .travel, startedAt: day.start.addingTimeInterval(-3600),
            endedAt: day.start.addingTimeInterval(3600))
        try store.save(record)
        try store.save(event)
        let history = SubjectiveHistorySession(store: store)
        history.setDataMode(.live)
        history.open(at: now, timeZone: zone)
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays[0].checkIn, record)
        XCTAssertEqual(history.timelineDays[0].events, [event])
        XCTAssertEqual(history.timelineDays[1].events, [event])
        history.beginEditing(.checkIn(record))
        var draft = SubjectiveHistoryDraft(record: .checkIn(record))
        draft.energy = .one
        XCTAssertTrue(history.save(draft, at: now))
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertEqual(history.timelineDays[0].checkIn?.energy, .one)
        history.requestDeletion(.event(event))
        XCTAssertTrue(history.confirmDeletion())
        history.loadTimeline(endingAt: now, now: now)
        XCTAssertTrue(history.timelineDays.allSatisfy { $0.events.isEmpty })
        XCTAssertNotNil(history.timelineDays[0].checkIn)
    }
}

@MainActor
private final class TimelineTestStore: SubjectiveRecordStore {
    var records: [String: DailyCheckIn] = [:]
    var events: [ContextEvent] = []
    var reads = 0
    var writes = 0
    var failAtRead: Int?
    private func read() throws {
        reads += 1
        if reads == failAtRead { throw SubjectiveRecordStoreError.corruptData }
    }
    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        try read()
        return records[day.storageKey]
    }
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] {
        try read()
        return HealthContextTimeline.overlapping(events, interval: interval)
    }
    func save(_ record: DailyCheckIn) throws -> DailyCheckIn { writes += 1; return record }
    func save(_ event: ContextEvent) throws { writes += 1 }
    func deleteCheckIn(on day: SubjectiveLocalDay) throws { writes += 1 }
    func deleteContextEvent(id: UUID) throws { writes += 1 }
}
