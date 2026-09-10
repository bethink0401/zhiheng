import XCTest
@testable import Zhiheng

final class InsightFactGeneratorTests: XCTestCase {
    private enum FixtureError: Error { case unexpectedEvidence }
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private var reference: Date { ISO8601DateFormatter().date(from: "2026-09-04T04:00:00Z")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = zone
        return value
    }
    private var end: Date { calendar.startOfDay(for: reference) }
    private var loaded: DateInterval { DateInterval(start: day(-90), end: reference) }
    private let watch = HealthMetricSource(
        sourceName: "Apple Watch", bundleIdentifier: "test.synthetic.watch",
        deviceName: "合成手表", productType: "Watch-Test"
    )

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: end)!
    }

    private func baseValue(_ metric: HealthMetricType) -> Double {
        switch metric {
        case .stepCount: 5_000
        case .sleepDuration: 8
        case .restingHeartRate: 60
        case .heartRateVariability: 50
        case .activeEnergy: 500
        case .exerciseDuration: 30
        default: 1
        }
    }

    private func sample(
        _ metric: HealthMetricType, offset: Int, value: Double? = nil,
        source: HealthMetricSource? = nil, id: UUID = UUID()
    ) throws -> HealthMetricSample {
        let date = day(offset).addingTimeInterval(12 * 3_600)
        return try HealthMetricSample(
            id: id, metricType: metric, startDate: date, endDate: date,
            value: value ?? baseValue(metric), unit: metric.expectedUnit,
            source: source ?? watch
        )
    }

    private func samples(
        _ metric: HealthMetricType = .stepCount,
        currentMultiplier: Double = 1,
        offsets: [Int] = Array(-35 ... -1),
        source: HealthMetricSource? = nil
    ) throws -> [HealthMetricSample] {
        try offsets.map { offset in
            try sample(
                metric,
                offset: offset,
                value: baseValue(metric) * (offset >= -7 ? currentMultiplier : 1),
                source: source
            )
        }
    }

    private func snapshot(
        _ metric: HealthMetricType = .stepCount,
        state: HealthMetricReadState? = nil,
        currentMultiplier: Double = 1,
        offsets: [Int] = Array(-35 ... -1)
    ) throws -> HealthDataSnapshot {
        let resolved: HealthMetricReadState
        if let state {
            resolved = state
        } else {
            resolved = .available(try samples(
                metric, currentMultiplier: currentMultiplier, offsets: offsets
            ))
        }
        return HealthDataSnapshot(states: [metric: resolved])
    }

    private func generate(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval? = nil,
        hasLoadedInterval: Bool = true,
        access: HealthAccessState = .requestCompleted,
        mode: HealthDataMode = .live,
        referenceDate: Date? = nil,
        timeZone: TimeZone? = nil,
        metrics: [HealthMetricType] = [.stepCount]
    ) throws -> InsightFactSet {
        try InsightFactGenerator.generate(
            snapshot: snapshot,
            loadedInterval: hasLoadedInterval ? (loadedInterval ?? loaded) : nil,
            access: access,
            dataMode: mode,
            referenceDate: referenceDate ?? reference,
            timeZone: timeZone ?? zone,
            metrics: metrics
        )
    }

    private func evidence(_ result: InsightFactSet) throws -> HealthMetricTrendEvidence {
        guard case let .evaluated(value, _) = try XCTUnwrap(result.facts.first).evidence else {
            XCTFail("Expected evaluated evidence")
            throw FixtureError.unexpectedEvidence
        }
        return value
    }

    private func unavailable(_ result: InsightFactSet) throws -> InsightDataUnavailableReason {
        guard case let .unavailable(reason) = try XCTUnwrap(result.facts.first).evidence else {
            XCTFail("Expected unavailable evidence")
            throw FixtureError.unexpectedEvidence
        }
        return reason
    }

    func testDefaultFactSetUsesEveryConfiguredMetricInCanonicalOrder() throws {
        let states = Dictionary(uniqueKeysWithValues:
            HealthMetricTrendThresholdCatalog.todayCandidateMetrics.map { ($0, HealthMetricReadState.noVisibleData) }
        )
        let result = try InsightFactGenerator.generate(
            snapshot: HealthDataSnapshot(states: states), loadedInterval: loaded,
            access: .requestCompleted, dataMode: .live, referenceDate: reference, timeZone: zone
        )
        XCTAssertEqual(result.generatorVersion, "s09-fact-generator-v1")
        XCTAssertEqual(result.facts.map(\.metric), [
            .stepCount, .sleepDuration, .restingHeartRate, .heartRateVariability,
            .activeEnergy, .exerciseDuration
        ])
        XCTAssertTrue(result.facts.allSatisfy { $0.evidence == .unavailable(.noVisibleData) })
        XCTAssertEqual(Set(result.facts.map(\.id)).count, 6)
    }

    func testAnalysisUsesPreviousThirtyFiveCompleteLocalCalendarDays() throws {
        let result = try generate(snapshot: try snapshot())
        XCTAssertEqual(result.analysisInterval.start, day(-35))
        XCTAssertEqual(result.analysisInterval.end, end)
        XCTAssertEqual(result.timeZoneIdentifier, zone.identifier)
        XCTAssertEqual(result.dataMode, .live)
        let value = try evidence(result)
        XCTAssertEqual(value.baselineInterval, DateInterval(start: day(-35), end: day(-7)))
        XCTAssertEqual(value.currentInterval, DateInterval(start: day(-7), end: end))
        XCTAssertEqual(value.currentValidDayCount, 7)
        XCTAssertEqual(value.baselineValidDayCount, 28)
    }

    func testStableRisingAndFallingInputsComeOnlyFromTrendEngine() throws {
        for (multiplier, expected, sign) in [
            (1.0, HealthMetricTrendLevel.noClearChange, 0),
            (1.3, .sustainedChange, 1),
            (0.7, .sustainedChange, -1)
        ] {
            let value = try evidence(generate(snapshot: try snapshot(currentMultiplier: multiplier)))
            XCTAssertEqual(value.state, .trend(expected))
            let relative = value.relativeChange ?? 0
            XCTAssertEqual(relative == 0 ? 0 : relative > 0 ? 1 : -1, sign)
            XCTAssertEqual(value.thresholdVersion, HealthMetricTrendThresholdCatalog.version)
        }
    }

    func testCurrentAndBaselineInsufficiencyRemainEvidenceInsteadOfZero() throws {
        let currentOffsets = Array(-35 ... -8) + [-7, -5, -1]
        let current = try evidence(generate(snapshot: try snapshot(offsets: currentOffsets)))
        XCTAssertEqual(current.state, .currentWindowInsufficient)
        XCTAssertEqual(current.currentValidDayCount, 3)
        XCTAssertNil(current.currentMedianValue)

        let baselineOffsets = Array(-17 ... -1)
        let baseline = try evidence(generate(snapshot: try snapshot(offsets: baselineOffsets)))
        XCTAssertEqual(baseline.state, .baselineInsufficient)
        XCTAssertEqual(baseline.baselineValidDayCount, 10)
        XCTAssertNil(baseline.baselineMedianValue)
    }

    func testIntermittentGapCanStillProduceEvidenceButLatestDayGapCannot() throws {
        let intermittent = Array(-35 ... -1).filter { ![-6, -4, -2].contains($0) }
        let value = try evidence(generate(snapshot: try snapshot(offsets: intermittent)))
        XCTAssertEqual(value.currentValidDayCount, 4)
        XCTAssertEqual(value.state, .trend(.noClearChange))

        let stale = Array(-35 ... -2)
        XCTAssertEqual(
            try unavailable(generate(snapshot: try snapshot(offsets: stale))),
            .recentDataGap
        )
    }

    func testIsolatedOutlierProtectionIsPreservedAndCannotBecomePlainValue() throws {
        var values = try samples(currentMultiplier: 1.4)
        let index = try XCTUnwrap(values.indices.last)
        values[index] = try sample(.stepCount, offset: -1, value: 30_000)
        let value = try evidence(generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(values)])))
        XCTAssertTrue(value.isolatedOutlierExcluded)
        XCTAssertEqual(value.state, .trend(.sustainedChange))
        XCTAssertEqual(value.currentMedianValue, 7_000)
    }

    func testAccessStateOverridesStaleSnapshotAndKeepsReasonsDistinct() throws {
        let stale = try snapshot()
        XCTAssertEqual(try unavailable(generate(snapshot: stale, access: .notRequested)), .accessNotRequested)
        XCTAssertEqual(try unavailable(generate(snapshot: stale, access: .unavailable)), .healthDataUnavailable)
        XCTAssertEqual(try unavailable(generate(snapshot: nil)), .notLoaded)
        XCTAssertEqual(try unavailable(generate(snapshot: stale, hasLoadedInterval: false)), .notLoaded)
    }

    func testSnapshotReadStatesMapWithoutInventingAuthorizationDenial() throws {
        let cases: [(HealthMetricReadState?, InsightDataUnavailableReason)] = [
            (.accessNotRequested, .accessNotRequested),
            (.healthDataUnavailable, .healthDataUnavailable),
            (.noVisibleData, .noVisibleData),
            (.failed(.healthDataUnavailable), .healthDataUnavailable),
            (.failed(.authorizationRequestFailed), .queryFailed),
            (.failed(.invalidInterval), .queryFailed),
            (.failed(.queryFailed), .queryFailed),
            (nil, .notLoaded)
        ]
        for (state, expected) in cases {
            let snapshot = HealthDataSnapshot(states: state.map { [.stepCount: $0] } ?? [:])
            XCTAssertEqual(try unavailable(generate(snapshot: snapshot)), expected)
        }
    }

    func testLoadedRangeMustCoverBothBaselineAndCurrentWindows() throws {
        let input = try snapshot()
        for interval in [
            DateInterval(start: day(-34), end: reference),
            DateInterval(start: day(-90), end: end.addingTimeInterval(-1))
        ] {
            XCTAssertEqual(
                try unavailable(generate(snapshot: input, loadedInterval: interval)),
                .queryWindowIncomplete
            )
        }
    }

    func testUnsupportedMetricIsExplicitEvenWhenSnapshotHasValues() throws {
        let input = try snapshot(.vo2Max, state: .available([try sample(.vo2Max, offset: -1)]))
        XCTAssertEqual(
            try unavailable(generate(snapshot: input, metrics: [.vo2Max])),
            .unsupportedMetric
        )
    }

    func testWrongMetricAndOutOfWindowSamplesAreNotReused() throws {
        let wrong = try sample(.sleepDuration, offset: -1)
        XCTAssertEqual(
            try unavailable(generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available([wrong])]))),
            .noVisibleData
        )
        var valid = try samples()
        valid.append(try sample(.stepCount, offset: 0, value: 99_999))
        let value = try evidence(generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(valid)])))
        XCTAssertEqual(value.currentMedianValue, 5_000)
    }

    func testSameDaySourceConflictIsSeparatedFromPreferredAppleDeviceSelection() throws {
        let phone = HealthMetricSource(
            sourceName: "iPhone", bundleIdentifier: "test.synthetic.phone",
            deviceName: "合成 iPhone", productType: "iPhone-Test"
        )
        var additive = try samples()
        additive.append(try sample(.stepCount, offset: -1, value: 1_000, source: phone))
        _ = try evidence(generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(additive)])))

        var pointSamples = try samples(.restingHeartRate)
        pointSamples.append(try sample(.restingHeartRate, offset: -1, value: 61, source: phone))
        XCTAssertEqual(
            try unavailable(generate(
                snapshot: HealthDataSnapshot(states: [.restingHeartRate: .available(pointSamples)]),
                metrics: [.restingHeartRate]
            )),
            .sourceConflict
        )
    }

    func testSourceChangeAcrossDaysCannotSupportAFalseStableFact() throws {
        let replacement = HealthMetricSource(
            sourceName: "Apple Watch", bundleIdentifier: watch.bundleIdentifier,
            deviceName: "另一块合成手表", productType: "Watch-New"
        )
        let values = try (-35 ... -1).map { offset in
            try sample(.stepCount, offset: offset, source: offset >= -7 ? replacement : watch)
        }
        XCTAssertEqual(
            try unavailable(generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(values)]))),
            .sourceChanged
        )
    }

    func testTrendEngineSourceChangeKeepsEvidenceAndSortedSources() throws {
        let replacement = HealthMetricSource(
            sourceName: "Apple Watch", bundleIdentifier: "test.synthetic.other-watch",
            deviceName: "另一来源", productType: "Watch-New"
        )
        let values = try (-35 ... -1).map { offset in
            try sample(.stepCount, offset: offset, source: offset >= -7 ? replacement : watch)
        }
        let result = try generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(values)]))
        guard case let .evaluated(value, sources) = try XCTUnwrap(result.facts.first).evidence else {
            return XCTFail("Expected source-change evidence")
        }
        XCTAssertEqual(value.state, .sourceChanged)
        XCTAssertFalse(value.sourceIsStable)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(Set(sources), Set([watch, replacement]))
    }

    func testFactIdentityIsStableAcrossSampleIDsOrderAndSnapshotDictionaryOrder() throws {
        let firstValues = try samples()
        let secondValues = try firstValues.reversed().map {
            try HealthMetricSample(
                id: UUID(), metricType: $0.metricType, startDate: $0.startDate,
                endDate: $0.endDate, value: $0.value, unit: $0.unit, source: $0.source
            )
        }
        let first = try generate(snapshot: HealthDataSnapshot(states: [.stepCount: .available(firstValues)]))
        let second = try generate(snapshot: HealthDataSnapshot(states: [
            .sleepDuration: .noVisibleData, .stepCount: .available(secondValues)
        ]))
        XCTAssertEqual(first.facts.first?.id, second.facts.first?.id)
        XCTAssertEqual(first.facts.first?.evidence, second.facts.first?.evidence)
    }

    func testFactIdentityChangesAcrossDayModeTimezoneAndGeneratorInputs() throws {
        let input = try snapshot()
        let base = try generate(snapshot: input)
        let nextDay = try generate(snapshot: input, referenceDate: day(1).addingTimeInterval(3_600))
        let demo = try generate(snapshot: input, mode: .demo)
        let utc = try generate(snapshot: input, timeZone: TimeZone(secondsFromGMT: 0)!)
        let ids = [base, nextDay, demo, utc].compactMap { $0.facts.first?.id }
        XCTAssertEqual(Set(ids).count, 4)
    }

    func testGeneratedFactsCanConstructANeutralInsightWithoutExplanationOrPlan() throws {
        let result = try generate(snapshot: try snapshot(currentMultiplier: 1.3))
        let insight = try Insight(
            id: UUID(), generatedAt: reference, analysisInterval: result.analysisInterval,
            timeZoneIdentifier: result.timeZoneIdentifier, dataMode: result.dataMode,
            facts: result.facts, uncertainty: "这是本地聚合观察，尚未匹配生活背景。"
        )
        XCTAssertTrue(insight.possibleExplanations.isEmpty)
        XCTAssertNil(insight.followUpQuestion)
        XCTAssertEqual(insight.recommendation, .continueObserving)
    }

    func testDSTWindowUsesCalendarDaysInsteadOfFixedHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        calendar.timeZone = losAngeles
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let result = try generate(
            snapshot: HealthDataSnapshot(states: [.stepCount: .noVisibleData]),
            loadedInterval: DateInterval(start: .distantPast, end: .distantFuture),
            referenceDate: date, timeZone: losAngeles
        )
        XCTAssertEqual(result.analysisInterval.duration, 35 * 86_400 - 3_600)
        XCTAssertEqual(calendar.dateComponents([.day], from: result.analysisInterval.start,
                                                to: result.analysisInterval.end).day, 35)
    }

    func testInvalidReferenceAndEmptyMetricRequestFailWithoutPartialFacts() {
        XCTAssertThrowsError(try generate(
            snapshot: nil,
            referenceDate: Date(timeIntervalSinceReferenceDate: .infinity)
        )) { XCTAssertEqual($0 as? InsightFactGenerationError, .invalidReferenceDate) }
        XCTAssertThrowsError(try generate(snapshot: nil, metrics: [])) {
            XCTAssertEqual($0 as? InsightFactGenerationError, .noMetrics)
        }
    }
}
