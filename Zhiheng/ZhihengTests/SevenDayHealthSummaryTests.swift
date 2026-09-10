import XCTest
@testable import Zhiheng

final class SevenDayHealthSummaryTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private var reference: Date {
        ISO8601DateFormatter().date(from: "2026-09-04T04:00:00Z")!
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = zone
        return value
    }
    private var end: Date { calendar.startOfDay(for: reference) }
    private var loadedInterval: DateInterval {
        DateInterval(start: day(-90), end: reference)
    }
    private let watch = HealthMetricSource(
        sourceName: "Apple Watch",
        bundleIdentifier: "test.synthetic.watch",
        deviceName: "合成手表",
        productType: "Watch-Test"
    )

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: end)!
    }

    private func baseValue(_ metric: HealthMetricType) -> Double {
        switch metric {
        case .sleepDuration: 8
        case .heartRateVariability: 50
        case .restingHeartRate: 60
        case .stepCount: 6_000
        default: 1
        }
    }

    private func samples(
        for metric: HealthMetricType,
        offsets: [Int] = Array(-35 ... -1),
        currentMultiplier: Double = 1
    ) throws -> [HealthMetricSample] {
        try offsets.map { offset in
            let date = day(offset).addingTimeInterval(12 * 3_600)
            return try HealthMetricSample(
                id: UUID(),
                metricType: metric,
                startDate: date,
                endDate: date,
                value: baseValue(metric) * (offset >= -7 ? currentMultiplier : 1),
                unit: metric.expectedUnit,
                source: watch
            )
        }
    }

    private func factSet(
        mode: HealthDataMode = .live,
        stateOverrides: [HealthMetricType: HealthMetricReadState] = [:],
        sampleOffsets: [HealthMetricType: [Int]] = [:]
    ) throws -> InsightFactSet {
        var states: [HealthMetricType: HealthMetricReadState] = [:]
        for metric in SevenDayHealthSummaryFactory.objectiveMetrics {
            states[metric] = try stateOverrides[metric] ?? .available(samples(
                for: metric,
                offsets: sampleOffsets[metric] ?? Array(-35 ... -1)
            ))
        }
        return try InsightFactGenerator.generate(
            snapshot: HealthDataSnapshot(states: states),
            loadedInterval: loadedInterval,
            access: .requestCompleted,
            dataMode: mode,
            referenceDate: reference,
            timeZone: zone,
            metrics: SevenDayHealthSummaryFactory.objectiveMetrics
        )
    }

    private func checkIn(
        offset: Int,
        energy: SubjectiveRating,
        stress: SubjectiveRating,
        body: SubjectiveRating,
        note: String? = nil
    ) throws -> DailyCheckIn {
        let date = day(offset).addingTimeInterval(12 * 3_600)
        return try DailyCheckIn(
            localDay: SubjectiveLocalDay(date: date, timeZone: zone),
            energy: energy,
            stress: stress,
            bodyFeeling: body,
            note: note,
            recordedAt: date
        )
    }

    private func context(
        for facts: InsightFactSet,
        checkIns: [DailyCheckIn] = [],
        events: [ContextEvent] = []
    ) throws -> InsightContextMatch {
        try InsightContextMatcher.match(
            factSet: facts,
            checkIns: checkIns,
            contextEvents: events
        )
    }

    func testUsesSevenCompleteLocalDaysAndPreviousNonOverlappingBaseline() throws {
        let facts = try factSet()
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts)),
            generatedAt: reference
        )

        XCTAssertEqual(result.version, "s13-seven-day-health-summary-v1")
        XCTAssertEqual(result.interval, DateInterval(start: day(-7), end: end))
        XCTAssertEqual(result.baselineInterval, DateInterval(start: day(-35), end: day(-7)))
        XCTAssertFalse(result.interval.contains(reference))
        XCTAssertEqual(result.timeZoneIdentifier, zone.identifier)
        XCTAssertEqual(result.objectiveFacts.map(\.metric), [
            .sleepDuration, .heartRateVariability, .restingHeartRate, .stepCount
        ])
    }

    func testObjectiveFactsReuseTrendMediansCoverageAndReadableSource() throws {
        let facts = try factSet()
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts)),
            generatedAt: reference
        )

        for fact in result.objectiveFacts {
            XCTAssertEqual(fact.currentMedianValue, baseValue(fact.metric))
            XCTAssertEqual(fact.baselineMedianValue, baseValue(fact.metric))
            XCTAssertEqual(fact.relativeChange, 0)
            XCTAssertEqual(fact.currentValidDayCount, 7)
            XCTAssertEqual(fact.baselineValidDayCount, 28)
            XCTAssertEqual(fact.trendState, .trend(.noClearChange))
            XCTAssertEqual(fact.sourceNames, ["Apple Watch"])
            XCTAssertNil(fact.unavailableReason)
        }
    }

    func testInsufficientCurrentWindowStaysInsufficientWithoutInventingValue() throws {
        let facts = try factSet(sampleOffsets: [
            .sleepDuration: Array(-35 ... -8) + Array(-3 ... -1)
        ])
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts)),
            generatedAt: reference
        )
        let sleep = try XCTUnwrap(result.objectiveFacts.first {
            $0.metric == .sleepDuration
        })

        XCTAssertEqual(sleep.trendState, .currentWindowInsufficient)
        XCTAssertEqual(sleep.currentValidDayCount, 3)
        XCTAssertNil(sleep.currentMedianValue)
        XCTAssertNil(sleep.relativeChange)
    }

    func testUnavailableMetricStaysUnavailableWithoutZeroOrSource() throws {
        let facts = try factSet(stateOverrides: [.stepCount: .noVisibleData])
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts)),
            generatedAt: reference
        )
        let steps = try XCTUnwrap(result.objectiveFacts.first { $0.metric == .stepCount })

        XCTAssertEqual(steps.unavailableReason, .noVisibleData)
        XCTAssertNil(steps.currentMedianValue)
        XCTAssertNil(steps.currentValidDayCount)
        XCTAssertTrue(steps.sourceNames.isEmpty)
    }

    func testSubjectiveRatingsAreSeparatedAndUseRecordedDayMedian() throws {
        let facts = try factSet()
        let checkIns = try [
            checkIn(offset: -3, energy: .one, stress: .five, body: .two, note: "不进入摘要"),
            checkIn(offset: -2, energy: .three, stress: .three, body: .four),
            checkIn(offset: -1, energy: .five, stress: .one, body: .five)
        ]
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts, checkIns: checkIns)),
            generatedAt: reference
        )
        guard case let .available(values) = result.subjectiveState else {
            return XCTFail("Expected subjective values")
        }

        XCTAssertEqual(values.recordedDayCount, 3)
        XCTAssertEqual(values.expectedDayCount, 7)
        XCTAssertEqual(values.energyMedian, 3)
        XCTAssertEqual(values.stressMedian, 3)
        XCTAssertEqual(values.bodyFeelingMedian, 4)
    }

    func testNoSubjectiveRecordsAndNoEventsRemainExplicitlyNotRecorded() throws {
        let facts = try factSet()
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts)),
            generatedAt: reference
        )

        XCTAssertEqual(result.subjectiveState, .notRecorded)
        XCTAssertEqual(result.contextState, .notRecorded)
    }

    func testContextEventsAreGroupedByStructuredKindOnly() throws {
        let facts = try factSet()
        let events = try [
            ContextEvent(
                kind: .overtime,
                startedAt: day(-3).addingTimeInterval(3_600),
                note: "自由文本不进入摘要"
            ),
            ContextEvent(
                kind: .overtime,
                startedAt: day(-2).addingTimeInterval(3_600)
            ),
            ContextEvent(
                kind: .custom,
                customLabel: "私密自定义名称",
                startedAt: day(-1).addingTimeInterval(3_600),
                note: "私密备注"
            )
        ]
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(try context(for: facts, events: events)),
            generatedAt: reference
        )
        guard case let .available(counts) = result.contextState else {
            return XCTFail("Expected context counts")
        }

        XCTAssertEqual(counts, [
            .init(kind: .overtime, count: 2),
            .init(kind: .custom, count: 1)
        ])
    }

    func testContextReadFailureKeepsObjectiveFactsButPublishesNoPartialSubjectiveData() throws {
        let facts = try factSet()
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .failed(.readFailed),
            generatedAt: reference
        )

        XCTAssertEqual(result.objectiveFacts.count, 4)
        XCTAssertEqual(result.subjectiveState, .unavailable)
        XCTAssertEqual(result.contextState, .unavailable)
        XCTAssertTrue(result.recommendation.sourceText.contains("主观记录暂时无法读取"))
    }

    func testDemoSummaryNeverRelabelsLiveSubjectiveRecords() throws {
        let facts = try factSet(mode: .demo)
        let result = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .demoMode,
            generatedAt: reference
        )

        XCTAssertEqual(result.dataMode, .demo)
        XCTAssertEqual(result.subjectiveState, .demoMode)
        XCTAssertEqual(result.contextState, .demoMode)
        XCTAssertTrue(result.recommendation.sourceText.contains("未读取真实感受"))
    }

    func testRecommendationIsLocalTraceableAndNeverStartsAPlan() throws {
        let facts = try factSet()
        let state = InsightContextLoadState.available(try context(for: facts))
        let first = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: state,
            generatedAt: reference
        )
        let second = try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: state,
            generatedAt: reference
        )

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.recommendation.usesAI)
        XCTAssertFalse(first.recommendation.automaticallyCreatesPlan)
        XCTAssertTrue(first.recommendation.sourceText.contains("本地 7/28 天趋势"))
        XCTAssertTrue(first.recommendation.sourceText.contains("未使用 AI"))
    }

    func testMismatchedContextWindowIsRejectedInsteadOfSplicingRecords() throws {
        let facts = try factSet()
        let valid = try context(for: facts)
        let mismatched = InsightContextMatch(
            matcherVersion: valid.matcherVersion,
            window: InsightContextWindow(
                interval: DateInterval(
                    start: valid.window.interval.start.addingTimeInterval(1),
                    end: valid.window.interval.end
                ),
                localDays: valid.window.localDays,
                timeZoneIdentifier: valid.window.timeZoneIdentifier
            ),
            dataMode: valid.dataMode,
            checkIns: valid.checkIns,
            contextEvents: valid.contextEvents
        )

        XCTAssertThrowsError(try SevenDayHealthSummaryFactory.make(
            factSet: facts,
            contextState: .available(mismatched),
            generatedAt: reference
        )) { error in
            XCTAssertEqual(error as? SevenDayHealthSummaryError, .invalidContextState)
        }
    }
}
