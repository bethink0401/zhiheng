import Foundation
import XCTest
@testable import Zhiheng

final class HealthDataQualityTests: XCTestCase {
    func testCountsDistinctDaysCoverageLatestDateAndTrailingGap() throws {
        let context = try makeContext(dayCount: 7)
        let samples = try [0, 1, 2, 2].map { dayOffset in
            try makeSample(
                day: context.days[dayOffset],
                sourceName: "来源 A"
            )
        }

        let report = try HealthDataQualityCalculator.evaluate(
            metric: .stepCount,
            samples: samples,
            interval: context.interval,
            calendar: context.calendar
        )

        XCTAssertEqual(report.expectedDayCount, 7)
        XCTAssertEqual(report.validDayCount, 3)
        XCTAssertEqual(report.coverageRatio, 3.0 / 7.0, accuracy: 0.000_001)
        XCTAssertEqual(report.longestMissingDayStreak, 4)
        XCTAssertEqual(report.latestSampleDate, samples.map(\.endDate).max())
        XCTAssertFalse(report.hasSourceChange)
    }

    func testEmptyWindowRemainsMissingRatherThanZeroMeasurements() throws {
        let context = try makeContext(dayCount: 7)

        let report = try HealthDataQualityCalculator.evaluate(
            metric: .heartRateVariability,
            samples: [],
            interval: context.interval,
            calendar: context.calendar
        )

        XCTAssertEqual(report.validDayCount, 0)
        XCTAssertEqual(report.coverageRatio, 0)
        XCTAssertEqual(report.longestMissingDayStreak, 7)
        XCTAssertNil(report.latestSampleDate)
    }

    func testDetectsSourceChangeWithoutChangingValidDayCount() throws {
        let context = try makeContext(dayCount: 2)
        let samples = try [
            makeSample(day: context.days[0], sourceName: "来源 A"),
            makeSample(day: context.days[1], sourceName: "来源 B")
        ]

        let report = try HealthDataQualityCalculator.evaluate(
            metric: .stepCount,
            samples: samples,
            interval: context.interval,
            calendar: context.calendar
        )

        XCTAssertEqual(report.validDayCount, 2)
        XCTAssertTrue(report.hasSourceChange)
        XCTAssertEqual(report.sourceNames, ["来源 A", "来源 B"])
    }

    func testLongestGapResetsWhenDataReturns() throws {
        let context = try makeContext(dayCount: 7)
        let samples = try [0, 3, 6].map { dayOffset in
            try makeSample(
                day: context.days[dayOffset],
                sourceName: "来源 A"
            )
        }

        let report = try HealthDataQualityCalculator.evaluate(
            metric: .stepCount,
            samples: samples,
            interval: context.interval,
            calendar: context.calendar
        )

        XCTAssertEqual(report.validDayCount, 3)
        XCTAssertEqual(report.longestMissingDayStreak, 2)
    }

    func testNinetyDayInventoryCountsDistinctEffectiveDays() throws {
        let context = try makeContext(dayCount: 90)
        let samples = try [0, 1, 1, 45, 89].map { dayOffset in
            try makeSample(
                day: context.days[dayOffset],
                sourceName: "来源 A"
            )
        }

        let report = try HealthDataQualityCalculator.evaluate(
            metric: .stepCount,
            samples: samples,
            interval: context.interval,
            calendar: context.calendar
        )

        XCTAssertEqual(report.expectedDayCount, 90)
        XCTAssertEqual(report.validDayCount, 4)
        XCTAssertEqual(report.coverageRatio, 4.0 / 90.0, accuracy: 0.000_001)
    }

    func testTodayStepsSumOnlySameDayAndSameSource() throws {
        let context = try makeContext(dayCount: 2)
        let samples = try [
            makeSample(day: context.days[0], sourceName: "来源 A", value: 9_000),
            makeSample(day: context.days[1], sourceName: "来源 A", value: 2_000),
            makeSample(day: context.days[1], sourceName: "来源 A", value: 3_000)
        ]

        let result = HealthMetricSummaryCalculator.summarize(
            metric: .stepCount,
            samples: samples,
            referenceDate: context.days[1],
            calendar: context.calendar
        )

        guard case let .value(summary) = result else {
            return XCTFail("Expected a step summary")
        }
        XCTAssertEqual(summary.value, 5_000)
    }

    func testTodayStepsPreferAppleWatchOverIPhone() throws {
        let context = try makeContext(dayCount: 1)
        let samples = try [
            makeSample(
                day: context.days[0],
                sourceName: "iPhone",
                value: 2_000,
                productType: "iPhone17,1"
            ),
            makeSample(
                day: context.days[0],
                sourceName: "Apple Watch",
                value: 4_000,
                productType: "Watch7,3"
            )
        ]

        let result = HealthMetricSummaryCalculator.summarize(
            metric: .stepCount,
            samples: samples,
            referenceDate: context.days[0],
            calendar: context.calendar
        )

        guard case let .value(summary) = result else {
            return XCTFail("Expected Apple Watch steps")
        }
        XCTAssertEqual(summary.value, 4_000)
        XCTAssertEqual(summary.sourceName, "Apple Watch")
    }

    func testTodayStepsPreferIPhoneOverUnknownSource() throws {
        let context = try makeContext(dayCount: 1)
        let samples = try [
            makeSample(day: context.days[0], sourceName: "第三方", value: 8_000),
            makeSample(
                day: context.days[0],
                sourceName: "iPhone",
                value: 3_000,
                productType: "iPhone17,1"
            )
        ]

        let result = HealthMetricSummaryCalculator.summarize(
            metric: .stepCount,
            samples: samples,
            referenceDate: context.days[0],
            calendar: context.calendar
        )

        guard case let .value(summary) = result else {
            return XCTFail("Expected iPhone steps")
        }
        XCTAssertEqual(summary.value, 3_000)
        XCTAssertEqual(summary.sourceName, "iPhone")
    }

    func testTodayStepsStillRefuseTwoUnknownSources() throws {
        let context = try makeContext(dayCount: 1)
        let samples = try [
            makeSample(day: context.days[0], sourceName: "来源 A"),
            makeSample(day: context.days[0], sourceName: "来源 B")
        ]

        XCTAssertEqual(
            HealthMetricSummaryCalculator.summarize(
                metric: .stepCount,
                samples: samples,
                referenceDate: context.days[0],
                calendar: context.calendar
            ),
            .multipleSources
        )
    }

    func testLatestHeartMetricUsesLatestMeasurementWithoutSumming() throws {
        let context = try makeContext(dayCount: 2)
        let earlier = try makeHeartSample(day: context.days[0], value: 42)
        let latest = try makeHeartSample(day: context.days[1], value: 48)

        let result = HealthMetricSummaryCalculator.summarize(
            metric: .heartRateVariability,
            samples: [latest, earlier],
            referenceDate: context.days[1],
            calendar: context.calendar
        )

        guard case let .value(summary) = result else {
            return XCTFail("Expected an HRV summary")
        }
        XCTAssertEqual(summary.value, 48)
        XCTAssertEqual(summary.date, latest.endDate)
    }

    func testLatestNightSleepSumsOnlyLatestWakeDaySegments() throws {
        let context = try makeContext(dayCount: 2)
        let previousNight = try makeSleepSample(
            wakeDay: context.days[0],
            hours: 8
        )
        let coreSleep = try makeSleepSample(
            wakeDay: context.days[1],
            hours: 4
        )
        let deepSleep = try makeSleepSample(
            wakeDay: context.days[1],
            hours: 3,
            endOffset: 3 * 60 * 60
        )

        let result = HealthMetricSummaryCalculator.summarize(
            metric: .sleepDuration,
            samples: [coreSleep, previousNight, deepSleep],
            referenceDate: context.days[1],
            calendar: context.calendar
        )

        guard case let .value(summary) = result else {
            return XCTFail("Expected a sleep summary")
        }
        XCTAssertEqual(summary.value, 7)
        XCTAssertEqual(summary.unit, .hours)
    }

    func testDailyStepSeriesUsesAppleWatchAndOmitsUnknownMultipleSourceDay() throws {
        let context = try makeContext(dayCount: 7)
        let samples = try [
            makeSample(
                day: context.days[5],
                sourceName: "Apple Watch",
                value: 2_000,
                productType: "Watch7,3"
            ),
            makeSample(
                day: context.days[5],
                sourceName: "Apple Watch",
                value: 3_000,
                productType: "Watch7,3"
            ),
            makeSample(
                day: context.days[5],
                sourceName: "iPhone",
                value: 4_000,
                productType: "iPhone17,1"
            ),
            makeSample(day: context.days[6], sourceName: "来源 A", value: 4_000),
            makeSample(day: context.days[6], sourceName: "来源 B", value: 1_000)
        ]

        let points = HealthMetricDailySeriesCalculator.points(
            metric: .stepCount,
            samples: samples,
            endingAt: context.days[6],
            window: .sevenDays,
            calendar: context.calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.date, context.days[5])
        XCTAssertEqual(points.first?.value, 5_000)
    }

    func testDailyHeartSeriesUsesLatestMeasurementPerDay() throws {
        let context = try makeContext(dayCount: 7)
        let earlier = try makeHeartSample(day: context.days[6], value: 40)
        let latest = try HealthMetricSample(
            id: UUID(),
            metricType: .heartRateVariability,
            startDate: earlier.startDate.addingTimeInterval(120),
            endDate: earlier.endDate.addingTimeInterval(120),
            value: 46,
            unit: .milliseconds,
            source: earlier.source
        )

        let points = HealthMetricDailySeriesCalculator.points(
            metric: .heartRateVariability,
            samples: [latest, earlier],
            endingAt: context.days[6],
            window: .sevenDays,
            calendar: context.calendar
        )

        XCTAssertEqual(points.map(\.value), [46])
    }

    func testSevenAndTwentyEightDayWindowsExcludeOlderPoints() throws {
        let context = try makeContext(dayCount: 28)
        let samples = try context.days.enumerated().map { index, day in
            try makeSample(
                day: day,
                sourceName: "来源 A",
                value: Double(index + 1)
            )
        }

        let seven = HealthMetricDailySeriesCalculator.points(
            metric: .stepCount,
            samples: samples,
            endingAt: context.days[27],
            window: .sevenDays,
            calendar: context.calendar
        )
        let twentyEight = HealthMetricDailySeriesCalculator.points(
            metric: .stepCount,
            samples: samples,
            endingAt: context.days[27],
            window: .twentyEightDays,
            calendar: context.calendar
        )

        XCTAssertEqual(seven.count, 7)
        XCTAssertEqual(twentyEight.count, 28)
        XCTAssertEqual(seven.first?.value, 22)
    }

    func testEmptyTrendPresentationDoesNotInventZeroData() {
        let presentation = HealthTrendChartPresentation(
            points: [],
            expectedDayCount: 7
        )

        XCTAssertEqual(presentation.coverage, .noData)
        XCTAssertEqual(presentation.yDomain, 0...1)
        XCTAssertTrue(presentation.contextText.contains("不会补成 0"))
    }

    func testPartialTrendPresentationKeepsMissingDaysExplicit() throws {
        let context = try makeContext(dayCount: 7)
        let points = [0, 2, 6].map { offset in
            HealthMetricDailyPoint(
                date: context.days[offset],
                value: Double(offset + 1),
                unit: .hours
            )
        }
        let presentation = HealthTrendChartPresentation(
            points: points,
            expectedDayCount: 7
        )

        XCTAssertEqual(
            presentation.coverage,
            .partial(validDayCount: 3, expectedDayCount: 7)
        )
        XCTAssertTrue(presentation.contextText.contains("空缺日期未补零"))
    }

    func testWideValueRangeStaysInDomainWithoutBeingCalledAbnormal() throws {
        let context = try makeContext(dayCount: 5)
        let values = [6.0, 6.1, 5.9, 6.0, 30.0]
        let points = zip(context.days, values).map { day, value in
            HealthMetricDailyPoint(date: day, value: value, unit: .hours)
        }
        let presentation = HealthTrendChartPresentation(
            points: points,
            expectedDayCount: 7
        )

        XCTAssertTrue(presentation.hasWideValueRange)
        XCTAssertGreaterThan(presentation.yDomain.upperBound, 30)
        XCTAssertLessThanOrEqual(presentation.yDomain.lowerBound, 5.9)
        XCTAssertTrue(presentation.contextText.contains("完整保留"))
        XCTAssertTrue(presentation.contextText.contains("不代表健康异常"))
    }

    private func makeContext(dayCount: Int) throws -> (
        calendar: Calendar,
        days: [Date],
        interval: DateInterval
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1
        )))
        let days = try (0..<dayCount).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        let end = try XCTUnwrap(calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: days[dayCount - 1]
        ))
        return (calendar, days, DateInterval(start: firstDay, end: end))
    }

    private func makeSample(
        day: Date,
        sourceName: String,
        value: Double = 6_000,
        productType: String? = nil
    ) throws -> HealthMetricSample {
        try HealthMetricSample(
            id: UUID(),
            metricType: .stepCount,
            startDate: day.addingTimeInterval(10 * 60 * 60),
            endDate: day.addingTimeInterval(10 * 60 * 60 + 60),
            value: value,
            unit: .count,
            source: HealthMetricSource(
                sourceName: sourceName,
                bundleIdentifier: nil,
                deviceName: nil,
                productType: productType
            )
        )
    }

    private func makeHeartSample(day: Date, value: Double) throws -> HealthMetricSample {
        try HealthMetricSample(
            id: UUID(),
            metricType: .heartRateVariability,
            startDate: day.addingTimeInterval(8 * 60 * 60),
            endDate: day.addingTimeInterval(8 * 60 * 60 + 60),
            value: value,
            unit: .milliseconds,
            source: HealthMetricSource(
                sourceName: "来源 A",
                bundleIdentifier: nil,
                deviceName: nil
            )
        )
    }

    private func makeSleepSample(
        wakeDay: Date,
        hours: Double,
        endOffset: TimeInterval = 7 * 60 * 60
    ) throws -> HealthMetricSample {
        let endDate = wakeDay.addingTimeInterval(endOffset)
        return try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: endDate.addingTimeInterval(-hours * 60 * 60),
            endDate: endDate,
            value: hours,
            unit: .hours,
            source: HealthMetricSource(
                sourceName: "来源 A",
                bundleIdentifier: nil,
                deviceName: nil
            )
        )
    }
}
