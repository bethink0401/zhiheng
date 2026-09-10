import XCTest
import SwiftData
@testable import Zhiheng

@MainActor
final class StateComparisonTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = zone
        return value
    }
    private var today: Date { calendar.startOfDay(for: now) }
    private var loaded: DateInterval { DateInterval(start: day(-90), end: now) }
    private let source = HealthMetricSource(sourceName: "Apple Watch", bundleIdentifier: "test.synthetic.watch", deviceName: "合成设备")
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    private func feeling(_ energy: SubjectiveRating = .four, _ stress: SubjectiveRating = .two,
                         _ body: SubjectiveRating = .four, at date: Date? = nil, zone: TimeZone? = nil) throws -> DailyCheckIn {
        try DailyCheckIn(localDay: SubjectiveLocalDay(date: date ?? now, timeZone: zone ?? self.zone),
            energy: energy, stress: stress, bodyFeeling: body, recordedAt: date ?? now)
    }

    private func sample(_ metric: HealthMetricType, date: Date, value: Double,
                        source: HealthMetricSource? = nil) throws -> HealthMetricSample {
        try HealthMetricSample(id: UUID(), metricType: metric, startDate: date, endDate: date,
            value: value, unit: metric.expectedUnit, source: source ?? self.source)
    }

    private func fixture(changed metric: HealthMetricType? = nil, multiplier: Double = 1.3,
                         skip: Set<Int> = []) throws -> HealthDataSnapshot {
        var states: [HealthMetricType: HealthMetricReadState] = [:]
        for type in HealthMetricTrendThresholdCatalog.coreMetrics {
            let baseline: Double
            switch type {
            case .stepCount: baseline = 8000
            case .sleepDuration: baseline = 8
            case .restingHeartRate: baseline = 60
            default: baseline = 50
            }
            states[type] = .available(try (-35 ... -1).filter { !skip.contains($0) }.map { offset in
                try sample(type, date: day(offset).addingTimeInterval(12 * 3600),
                    value: baseline * (offset >= -7 && type == metric ? multiplier : 1))
            })
        }
        return HealthDataSnapshot(states: states)
    }

    private func replacing(_ snapshot: HealthDataSnapshot, metric: HealthMetricType,
                           transform: ([HealthMetricSample]) throws -> [HealthMetricSample]) rethrows -> HealthDataSnapshot {
        var states = snapshot.states
        if case .available(let values) = states[metric] { states[metric] = .available(try transform(values)) }
        return HealthDataSnapshot(states: states)
    }

    private func result(_ snapshot: HealthDataSnapshot?, checkIn: DailyCheckIn?, didLoad: Bool = true,
                        mode: HealthDataMode = .live, interval: DateInterval? = nil,
                        access: HealthAccessState = .requestCompleted) -> StateComparisonResult {
        StateComparisonEngine.make(snapshot: snapshot, loadedInterval: interval ?? loaded, access: access,
            mode: mode, checkIn: checkIn, didLoadCheckIn: didLoad, now: now, timeZone: zone)
    }

    func testAllFourCombinationsHaveDistinctNonDiagnosticResponses() throws {
        let stable = try fixture()
        let changed = try fixture(changed: .sleepDuration, multiplier: 0.7)
        let comfortable = try feeling()
        let care = try feeling(.one)
        XCTAssertEqual(result(stable, checkIn: comfortable).kind, .steadyComfortable)
        XCTAssertEqual(result(stable, checkIn: care).kind, .steadyNeedsCare)
        XCTAssertEqual(result(changed, checkIn: comfortable).kind, .changedComfortable)
        XCTAssertEqual(result(changed, checkIn: care).kind, .changedNeedsCare)
        XCTAssertTrue(StateComparisonKind.steadyNeedsCare.message.contains("不能否定"))
        XCTAssertTrue(StateComparisonKind.changedComfortable.message.contains("不等于变差"))
        XCTAssertTrue(StateComparisonKind.changedNeedsCare.message.contains("并不说明"))
    }

    func testEveryCoreMetricDetectsBothSustainedDirectionsWithoutCallingEitherBad() throws {
        for metric in HealthMetricTrendThresholdCatalog.coreMetrics {
            for multiplier in [0.7, 1.3] {
                let value = result(try fixture(changed: metric, multiplier: multiplier), checkIn: try feeling())
                XCTAssertEqual(value.kind, .changedComfortable)
                XCTAssertEqual(value.evidence.first(where: { $0.metric == metric })?.status, .ready(.sustainedChange))
            }
        }
    }

    func testAll125RatingCombinationsKeepAnyPoorDimensionInsteadOfAveraging() throws {
        for energy in SubjectiveRating.allCases {
            for stress in SubjectiveRating.allCases {
                for body in SubjectiveRating.allCases {
                    let value = SubjectiveFeelingState.classify(try feeling(energy, stress, body))
                    if energy.rawValue <= 2 || body.rawValue <= 2 || stress.rawValue >= 4 {
                        XCTAssertEqual(value, .needsCare)
                    } else if energy.rawValue >= 4 && body.rawValue >= 4 && stress.rawValue <= 2 {
                        XCTAssertEqual(value, .comfortable)
                    } else { XCTAssertEqual(value, .mixed) }
                }
            }
        }
    }

    func testPressureIsReversedAndOneConcernWinsOverTwoHighRatings() throws {
        XCTAssertEqual(SubjectiveFeelingState.classify(try feeling(.five, .five, .five)), .needsCare)
        XCTAssertEqual(SubjectiveFeelingState.classify(try feeling(.five, .one, .five)), .comfortable)
        XCTAssertEqual(SubjectiveFeelingState.classify(try feeling(.five, .one, .one)), .needsCare)
    }

    func testNeutralAndMixedFeelingsDoNotForceAQuadrant() throws {
        for record in [try feeling(.three, .three, .three), try feeling(.five, .three, .four)] {
            XCTAssertEqual(result(try fixture(), checkIn: record).kind, .mixedFeelings)
        }
    }

    func testMissingFailedAndDemoFeelingsDoNotExposeEvidence() throws {
        let snapshot = try fixture()
        let record = try feeling()
        let values = [result(snapshot, checkIn: nil), result(snapshot, checkIn: record, didLoad: false),
                      result(snapshot, checkIn: record, mode: .demo)]
        XCTAssertEqual(values.map(\.kind), [.missingFeelings, .feelingReadFailed, .demo])
        XCTAssertTrue(values.allSatisfy { $0.feeling == nil && $0.evidence.isEmpty })
    }

    func testYesterdayFutureAndDifferentTimezoneFeelingsAreNotUsedAsToday() throws {
        for record in [try feeling(at: day(-1)), try feeling(at: day(1)),
                       try feeling(zone: TimeZone(identifier: "Asia/Tokyo")!)] {
            let value = result(try fixture(), checkIn: record)
            XCTAssertEqual(value.kind, .dateMismatch)
            XCTAssertTrue(value.evidence.isEmpty)
        }
    }

    func testTodayPartialSamplesCannotCreateApparentDeclineOrRaise() throws {
        let snapshot = try replacing(fixture(), metric: .stepCount) { values in
            values + [try sample(.stepCount, date: now, value: 0),
                      try sample(.stepCount, date: day(1), value: 1_000_000)]
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .steadyComfortable)
        XCTAssertEqual(value.currentInterval, DateInterval(start: day(-7), end: today))
        XCTAssertEqual(value.baselineInterval, DateInterval(start: day(-35), end: day(-7)))
    }

    func testCurrentAndBaselineMinimumBoundaries() throws {
        // 14 baseline days and 4 non-contiguous recent days, including yesterday.
        let enough = Set((-35 ... -8).filter { $0.isMultiple(of: 2) } + [-6, -4, -2])
        XCTAssertEqual(result(try fixture(skip: enough), checkIn: try feeling()).kind, .steadyComfortable)
        let insufficientCurrent = result(try fixture(skip: [-7, -6, -5, -4]), checkIn: try feeling())
        XCTAssertEqual(insufficientCurrent.kind, .insufficientData)
        XCTAssertTrue(insufficientCurrent.evidence.allSatisfy { $0.status == .currentInsufficient })
        let insufficientBaseline = result(try fixture(skip: Set(-35 ... -21)), checkIn: try feeling())
        XCTAssertEqual(insufficientBaseline.kind, .insufficientData)
        XCTAssertTrue(insufficientBaseline.evidence.allSatisfy { $0.status == .baselineInsufficient })
    }

    func testTrailingGapCannotMasqueradeAsCurrentSteadinessEvenWithSixValidDays() throws {
        let value = result(try fixture(skip: [-1]), checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        XCTAssertTrue(value.evidence.allSatisfy { $0.status == .recentGap })
    }

    func testSingleIsolatedOutlierRemainsExplicitlyUncertain() throws {
        let snapshot = try replacing(fixture(), metric: .stepCount) { values in
            Array(values.dropLast()) + [try sample(.stepCount, date: day(-1).addingTimeInterval(3600), value: 100_000)]
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        let evidence = try XCTUnwrap(value.evidence.first { $0.metric == .stepCount })
        XCTAssertEqual(evidence.status, .isolatedOutlier)
        XCTAssertTrue(evidence.trend?.isolatedOutlierExcluded == true)
    }

    func testOneFailedOrMissingMetricPreventsPartialOverallConclusion() throws {
        for state in [HealthMetricReadState.failed(.queryFailed), .noVisibleData, .available([])] {
            var states = try fixture(changed: .sleepDuration).states
            states[.heartRateVariability] = state
            let value = result(HealthDataSnapshot(states: states), checkIn: try feeling())
            XCTAssertEqual(value.kind, .insufficientData)
            XCTAssertEqual(value.evidence.count, 4)
            XCTAssertEqual(value.evidence.first { $0.metric == .sleepDuration }?.status, .ready(.sustainedChange))
        }
    }

    func testPermissionUnavailableAndUnloadedStatesAreDistinct() throws {
        let pairs: [(HealthAccessState, StateComparisonMetricStatus)] = [
            (.notRequested, .notRequested), (.unavailable, .unavailable), (.requestCompleted, .notLoaded)
        ]
        for (access, expected) in pairs {
            let value = result(nil, checkIn: try feeling(), access: access)
            XCTAssertEqual(value.kind, .insufficientData)
            XCTAssertTrue(value.evidence.allSatisfy { $0.status == expected })
        }
    }

    func testPerMetricReadStatesRemainVisible() throws {
        let states: [HealthMetricType: HealthMetricReadState] = [
            .sleepDuration: .accessNotRequested, .heartRateVariability: .healthDataUnavailable,
            .restingHeartRate: .failed(.queryFailed)]
        let value = result(HealthDataSnapshot(states: states), checkIn: try feeling())
        XCTAssertEqual(value.evidence.map(\.status), [.notRequested, .unavailable, .failed, .notLoaded])
    }

    func testSnapshotMustCoverAll35DaysAndEndAfterYesterday() throws {
        for interval in [DateInterval(start: day(-35).addingTimeInterval(1), end: now),
                         DateInterval(start: day(-90), end: today.addingTimeInterval(-1))] {
            let value = result(try fixture(), checkIn: try feeling(), interval: interval)
            XCTAssertEqual(value.kind, .insufficientData)
            XCTAssertTrue(value.evidence.allSatisfy { $0.status == .outsideWindow })
        }
    }

    func testSnapshotWithoutIntervalDoesNotGuessCoverage() throws {
        let value = StateComparisonEngine.make(snapshot: try fixture(), loadedInterval: nil,
            access: .requestCompleted, mode: .live, checkIn: try feeling(), didLoadCheckIn: true,
            now: now, timeZone: zone)
        XCTAssertTrue(value.evidence.allSatisfy { $0.status == .notLoaded })
    }

    func testChangedDeviceWithSameBundleIdentifierIsStillGuarded() throws {
        let changed = HealthMetricSource(sourceName: "Apple Watch", bundleIdentifier: source.bundleIdentifier,
            deviceName: "另一合成设备")
        let snapshot = try replacing(fixture(), metric: .heartRateVariability) { values in
            try values.map { value in
                try sample(.heartRateVariability, date: value.endDate, value: value.value,
                    source: value.endDate >= day(-7) ? changed : source)
            }
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        XCTAssertEqual(value.evidence.first { $0.metric == .heartRateVariability }?.status, .sourceChanged)
    }

    func testAmbiguousSingleDayIsNotSilentlyDroppedFromCombinedDecision() throws {
        let other = HealthMetricSource(sourceName: "合成第三方", bundleIdentifier: "test.other", deviceName: nil)
        let snapshot = try replacing(fixture(), metric: .restingHeartRate) { values in
            values + [try sample(.restingHeartRate, date: day(-3), value: 90, source: other)]
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        XCTAssertEqual(value.evidence.first { $0.metric == .restingHeartRate }?.status, .sourceConflict)
    }

    func testWatchPriorityDoesNotTreatUnselectedPhoneAsSourceChange() throws {
        let phone = HealthMetricSource(sourceName: "iPhone", bundleIdentifier: "test.phone", deviceName: nil)
        let snapshot = try replacing(fixture(), metric: .stepCount) { values in
            values + [try sample(.stepCount, date: day(-2), value: 999_999, source: phone)]
        }
        XCTAssertEqual(result(snapshot, checkIn: try feeling()).kind, .steadyComfortable)
    }

    func testZeroBaselineKeepsUndefinedRelativeChangeOutOfQuadrants() throws {
        let snapshot = try replacing(fixture(), metric: .stepCount) { values in
            try values.map { try sample(.stepCount, date: $0.endDate, value: 0) }
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        XCTAssertEqual(value.evidence.first { $0.metric == .stepCount }?.status, .ready(.worthObserving))
    }

    func testMixedObjectiveDirectionsWithTooFewAlignedDaysRemainWorthObserving() throws {
        let snapshot = try replacing(fixture(), metric: .stepCount) { values in
            let baseline = values.filter { $0.endDate < day(-7) }
            let offsets = [-7, -5, -3, -1]
            let changes = [6400.0, 6400, 12800, 12800]
            return baseline + (try zip(offsets, changes).map { offset, value in
                try sample(.stepCount, date: day(offset).addingTimeInterval(3600), value: value)
            })
        }
        let value = result(snapshot, checkIn: try feeling())
        XCTAssertEqual(value.kind, .insufficientData)
        let evidence = try XCTUnwrap(value.evidence.first { $0.metric == .stepCount })
        XCTAssertEqual(evidence.status, .ready(.worthObserving))
        XCTAssertEqual(evidence.trend?.alignedDayCount, 2)
        XCTAssertEqual(evidence.trend?.requiredAlignedDayCount, 3)
    }

    func testEvidenceCarriesExactCountsMediansVersionAndSources() throws {
        let value = result(try fixture(changed: .sleepDuration, multiplier: 0.75), checkIn: try feeling())
        let evidence = try XCTUnwrap(value.evidence.first { $0.metric == .sleepDuration })
        XCTAssertEqual(evidence.sources, ["Apple Watch"])
        XCTAssertEqual(evidence.trend?.currentValidDayCount, 7)
        XCTAssertEqual(evidence.trend?.baselineValidDayCount, 28)
        XCTAssertEqual(evidence.trend?.currentMedianValue, 6)
        XCTAssertEqual(evidence.trend?.baselineMedianValue, 8)
        XCTAssertEqual(evidence.trend?.relativeChange, -0.25)
        XCTAssertEqual(evidence.trend?.thresholdVersion, HealthMetricTrendThresholdCatalog.version)
    }

    func testStableInputProducesIdenticalOutputIndependentOfSampleOrder() throws {
        let snapshot = try fixture()
        let reversed = HealthDataSnapshot(states: snapshot.states.mapValues { state in
            if case .available(let samples) = state { return .available(samples.reversed()) }
            return state
        })
        let record = try feeling()
        XCTAssertEqual(result(snapshot, checkIn: record), result(reversed, checkIn: record))
    }

    func testDSTWindowUsesLocalCalendarDaysWithoutOverlap() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let date = ISO8601DateFormatter().date(from: "2026-03-09T20:00:00Z")!
        let value = StateComparisonEngine.make(snapshot: nil, loadedInterval: nil, access: .notRequested,
            mode: .live, checkIn: try feeling(at: date, zone: zone), didLoadCheckIn: true, now: date, timeZone: zone)
        XCTAssertEqual(value.currentInterval?.duration, 7 * 86400 - 3600)
        XCTAssertEqual(value.baselineInterval?.end, value.currentInterval?.start)
    }

    func testStoredFeelingNotDraftDrivesComparisonAndDeletionClearsIt() throws {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = SwiftDataSubjectiveRecordStore(modelContainer: container)
        let record = try feeling()
        try store.save(record)
        let session = SubjectiveCheckInSession(store: store)
        session.load(for: now, timeZone: zone)
        session.energy = .one
        XCTAssertEqual(result(try fixture(), checkIn: session.savedCheckIn).kind, .steadyComfortable)
        XCTAssertTrue(session.save(for: now, timeZone: zone, recordedAt: now))
        XCTAssertEqual(result(try fixture(), checkIn: session.savedCheckIn).kind, .steadyNeedsCare)
        try store.deleteCheckIn(on: record.localDay)
        session.load(for: now, timeZone: zone)
        XCTAssertEqual(result(try fixture(), checkIn: session.savedCheckIn).kind, .missingFeelings)
    }

    func testNoResultTextMakesCausalMedicalOrGuaranteedHealthClaims() {
        for kind in StateComparisonKind.allCases {
            let text = kind.title + kind.message
            for banned in ["你很健康", "你不健康", "证明有效", "一定改善", "你患有", "无需就医"] {
                XCTAssertFalse(text.contains(banned))
            }
            XCTAssertLessThanOrEqual(text.filter { $0 == "？" }.count, 1)
        }
        XCTAssertEqual(StateComparisonKind.allCases.filter(\.isQuadrant).count, 4)
    }
}
