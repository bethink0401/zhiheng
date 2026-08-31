import Foundation
import XCTest
@testable import Zhiheng

final class InsightsDashboardPresentationTests: XCTestCase {
    func testHRVUsesLatestValueAndPriorPersonalBaseline() throws {
        let context = try makeContext()
        var samples = [HealthMetricSample]()
        for offset in -28 ... -1 {
            samples.append(try sample(
                metric: .heartRateVariability,
                value: 50,
                dayOffset: offset,
                hour: 8,
                context: context
            ))
        }
        samples.append(try sample(
            metric: .heartRateVariability,
            value: 51,
            dayOffset: 0,
            hour: 8,
            context: context
        ))

        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([.heartRateVariability: samples]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(current, baseline, level, position, points) = dashboard.hrv else {
            return XCTFail("Expected an available HRV presentation")
        }
        XCTAssertEqual(current.value, 51)
        XCTAssertEqual(baseline.medianValue, 50)
        XCTAssertEqual(level, .nearPersonalRange)
        XCTAssertEqual(position, 0.5333, accuracy: 0.001)
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(dashboard.hrvIntradayChart.points.count, 1)
        XCTAssertEqual(dashboard.hrvIntradayChart.points.first?.value, 51)
        XCTAssertEqual(dashboard.hrv.title, "状态正常")
        XCTAssertEqual(dashboard.hrv.visualState, .nearPersonalRange)
    }

    func testHRVIntradayChartUsesOnlyReferenceDaySamplesInTimeOrder() throws {
        let context = try makeContext()
        let samples = [
            try sample(metric: .heartRateVariability, value: 47, dayOffset: -1, hour: 23, context: context),
            try sample(metric: .heartRateVariability, value: 52, dayOffset: 0, hour: 9, context: context),
            try sample(metric: .heartRateVariability, value: 49, dayOffset: 0, hour: 6, context: context)
        ]

        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([.heartRateVariability: samples]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        XCTAssertEqual(dashboard.hrvIntradayChart.points.map(\.value), [49, 52])
        XCTAssertEqual(
            dashboard.hrvIntradayChart.interval.start,
            context.calendar.startOfDay(for: context.referenceDate)
        )
    }

    func testHRVWaitsForFourteenPriorValidDays() throws {
        let context = try makeContext()
        var samples = [HealthMetricSample]()
        for offset in -13 ... -1 {
            samples.append(try sample(
                metric: .heartRateVariability,
                value: 48,
                dayOffset: offset,
                hour: 8,
                context: context
            ))
        }
        samples.append(try sample(
            metric: .heartRateVariability,
            value: 49,
            dayOffset: 0,
            hour: 8,
            context: context
        ))

        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([.heartRateVariability: samples]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .learning(current, validDays, requiredDays, _) = dashboard.hrv else {
            return XCTFail("Expected learning state")
        }
        XCTAssertEqual(current?.value, 49)
        XCTAssertEqual(validDays, 13)
        XCTAssertEqual(requiredDays, 14)
        XCTAssertEqual(dashboard.hrv.title, "正在了解你的状态")
        XCTAssertFalse(dashboard.hrv.explanation.contains("正常"))
        XCTAssertEqual(dashboard.hrv.visualState, .learning)
    }

    func testHRVVisualStateChangesWithPersonalRangePosition() throws {
        let context = try makeContext()
        let baseline = HealthMetricBaseline(
            metric: .heartRateVariability,
            interval: DateInterval(
                start: context.referenceDate.addingTimeInterval(-28 * 86_400),
                end: context.referenceDate
            ),
            expectedDayCount: 28,
            validDayCount: 28,
            coverageRatio: 1,
            medianValue: 50,
            medianAbsoluteDeviation: 2,
            unit: .milliseconds
        )
        let current = HealthMetricSummary(
            metric: .heartRateVariability,
            value: 50,
            unit: .milliseconds,
            date: context.referenceDate,
            sourceName: "Apple Watch"
        )

        XCTAssertEqual(
            InsightsHRVPresentation.available(
                current: current,
                baseline: baseline,
                level: .belowPersonalRange,
                gaugePosition: 0.1,
                points: []
            ).visualState,
            .belowPersonalRange
        )
        XCTAssertEqual(
            InsightsHRVPresentation.available(
                current: current,
                baseline: baseline,
                level: .abovePersonalRange,
                gaugePosition: 0.9,
                points: []
            ).visualState,
            .abovePersonalRange
        )
        XCTAssertEqual(InsightsHRVPresentation.unavailable.visualState, .unavailable)
    }

    func testHRVStateEvaluationsAreDistinctAndAvoidTechnicalRangeCopy() throws {
        let context = try makeContext()
        let baseline = HealthMetricBaseline(
            metric: .heartRateVariability,
            interval: DateInterval(
                start: context.referenceDate.addingTimeInterval(-28 * 86_400),
                end: context.referenceDate
            ),
            expectedDayCount: 28,
            validDayCount: 28,
            coverageRatio: 1,
            medianValue: 50,
            medianAbsoluteDeviation: 2,
            unit: .milliseconds
        )
        let current = HealthMetricSummary(
            metric: .heartRateVariability,
            value: 50,
            unit: .milliseconds,
            date: context.referenceDate,
            sourceName: "Apple Watch"
        )
        let evaluations = [
            InsightsHRVPresentation.unavailable.explanation,
            InsightsHRVPresentation.learning(
                current: current,
                validDayCount: 8,
                requiredDayCount: 14,
                points: []
            ).explanation,
            InsightsHRVPresentation.available(
                current: current,
                baseline: baseline,
                level: .belowPersonalRange,
                gaugePosition: 0.1,
                points: []
            ).explanation,
            InsightsHRVPresentation.available(
                current: current,
                baseline: baseline,
                level: .nearPersonalRange,
                gaugePosition: 0.5,
                points: []
            ).explanation,
            InsightsHRVPresentation.available(
                current: current,
                baseline: baseline,
                level: .abovePersonalRange,
                gaugePosition: 0.9,
                points: []
            ).explanation
        ]

        XCTAssertEqual(Set(evaluations).count, 5)
        XCTAssertTrue(evaluations[2].contains("放慢一点"))
        XCTAssertTrue(evaluations[3].contains("状态平稳"))
        XCTAssertTrue(evaluations[4].contains("太棒了"))
        XCTAssertFalse(evaluations.joined().contains("高于你的个人近期参考范围"))
        XCTAssertFalse(evaluations.joined().contains("单次升高不代表"))
        XCTAssertFalse(evaluations.joined().contains("身心状态优秀"))
    }

    func testMissingBodyMetricRemainsUnavailable() throws {
        let context = try makeContext()
        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([:]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        let oxygen = try XCTUnwrap(
            dashboard.bodyMetrics.first { $0.kind == .oxygenSaturation }
        )
        XCTAssertNil(oxygen.currentValue)
        XCTAssertTrue(oxygen.points.isEmpty)
        XCTAssertEqual(oxygen.referenceState, .unavailable)
    }

    func testBodyMetricsCoverExpandedMobilityAndCardioFitnessSet() throws {
        let context = try makeContext()
        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([:]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        XCTAssertEqual(
            Set(dashboard.bodyMetrics.map(\.kind)),
            Set(InsightsBodyMetricKind.allCases)
        )
        XCTAssertTrue(dashboard.bodyMetrics.contains { $0.kind == .walkingRunningDistance })
        XCTAssertTrue(dashboard.bodyMetrics.contains { $0.kind == .flightsClimbed })
        XCTAssertTrue(dashboard.bodyMetrics.contains { $0.kind == .walkingSpeed })
        XCTAssertTrue(dashboard.bodyMetrics.contains { $0.kind == .walkingStepLength })
        XCTAssertTrue(dashboard.bodyMetrics.contains { $0.kind == .vo2Max })
    }

    func testBodyMetricStateDirectlyReportsPersonalDirection() throws {
        let context = try makeContext()
        var samples = [HealthMetricSample]()
        for offset in -28 ... -1 {
            samples.append(try sample(
                metric: .restingHeartRate,
                value: 60,
                dayOffset: offset,
                hour: 8,
                context: context
            ))
        }
        samples.append(try sample(
            metric: .restingHeartRate,
            value: 75,
            dayOffset: 0,
            hour: 8,
            context: context
        ))

        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([.restingHeartRate: samples]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )
        let restingHeartRate = try XCTUnwrap(
            dashboard.bodyMetrics.first { $0.kind == .restingHeartRate }
        )

        XCTAssertEqual(restingHeartRate.referenceState, .abovePersonalRange)
        XCTAssertEqual(restingHeartRate.referenceState.title, "状态偏高")
    }

    func testSleepingHeartRateUsesOnlySamplesInsideSleepWindow() throws {
        let context = try makeContext()
        let wake = try XCTUnwrap(context.calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: context.referenceDate
        ))
        let sleep = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: wake.addingTimeInterval(-7 * 60 * 60),
            endDate: wake,
            value: 7,
            unit: .hours,
            source: source,
            sleepStage: .core
        )
        let heartSamples = [
            try sample(metric: .heartRate, value: 50, dayOffset: 0, hour: 1, context: context),
            try sample(metric: .heartRate, value: 60, dayOffset: 0, hour: 5, context: context),
            try sample(metric: .heartRate, value: 120, dayOffset: 0, hour: 12, context: context)
        ]

        let dashboard = InsightsDashboardPresentationFactory.make(
            snapshot: snapshot([
                .sleepDuration: [sleep],
                .heartRate: heartSamples
            ]),
            referenceDate: context.referenceDate,
            calendar: context.calendar
        )

        let sleepingHeart = try XCTUnwrap(
            dashboard.bodyMetrics.first { $0.kind == .sleepingHeartRate }
        )
        XCTAssertEqual(sleepingHeart.currentValue, 55)
        XCTAssertEqual(sleepingHeart.points.count, 1)
        XCTAssertEqual(sleepingHeart.referenceState, .learning)
    }

    func testLayoutCanHideAndReorderMetrics() {
        var layout = InsightsDashboardLayout.standard
        layout.setVisible(false, metric: .oxygenSaturation)
        XCTAssertFalse(layout.visibleMetrics.contains(.oxygenSaturation))

        var metrics = layout.visibleMetrics
        let wrist = metrics.remove(at: metrics.firstIndex(of: .wristTemperature)!)
        metrics.insert(wrist, at: 0)
        layout = InsightsDashboardLayout(visibleMetrics: metrics)
        XCTAssertEqual(layout.visibleMetrics.first, .wristTemperature)
        XCTAssertFalse(layout.visibleMetrics.contains(.oxygenSaturation))
    }

    private struct Context {
        let referenceDate: Date
        let calendar: Calendar
    }

    private let source = HealthMetricSource(
        sourceName: "Apple Watch",
        bundleIdentifier: nil,
        deviceName: "Apple Watch"
    )

    private func makeContext() throws -> Context {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let reference = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 18)
        ))
        return Context(referenceDate: reference, calendar: calendar)
    }

    private func sample(
        metric: HealthMetricType,
        value: Double,
        dayOffset: Int,
        hour: Int,
        context: Context
    ) throws -> HealthMetricSample {
        let day = try XCTUnwrap(context.calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: context.calendar.startOfDay(for: context.referenceDate)
        ))
        let end = try XCTUnwrap(context.calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: day
        ))
        return try HealthMetricSample(
            id: UUID(),
            metricType: metric,
            startDate: end.addingTimeInterval(-60),
            endDate: end,
            value: value,
            unit: metric.expectedUnit,
            source: source
        )
    }

    private func snapshot(
        _ samples: [HealthMetricType: [HealthMetricSample]]
    ) -> HealthDataSnapshot {
        HealthDataSnapshot(states: Dictionary(
            uniqueKeysWithValues: HealthMetricType.allCases.map { metric in
                if let values = samples[metric] {
                    return (metric, .available(values))
                }
                return (metric, .noVisibleData)
            }
        ))
    }
}
