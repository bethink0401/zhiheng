import Foundation
import XCTest
@testable import Zhiheng

final class HealthBaselineTests: XCTestCase {
    func testStableTwentyEightDaysProducesTraceableBaseline() throws {
        let context = try makeContext()
        let samples = try context.days.map { day in
            try makeSample(day: day, value: 7)
        }

        let result = HealthMetricBaselineEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(baseline) = result else {
            return XCTFail("Expected an available baseline")
        }
        XCTAssertEqual(baseline.expectedDayCount, 28)
        XCTAssertEqual(baseline.validDayCount, 28)
        XCTAssertEqual(baseline.coverageRatio, 1)
        XCTAssertEqual(baseline.medianValue, 7)
        XCTAssertEqual(baseline.medianAbsoluteDeviation, 0)
        XCTAssertEqual(baseline.unit, .hours)
        XCTAssertEqual(
            context.calendar.dateComponents(
                [.day],
                from: baseline.interval.start,
                to: context.calendar.startOfDay(for: context.referenceDate)
            ).day,
            27
        )
    }

    func testSingleExtremeDayDoesNotMoveMedianBaseline() throws {
        let context = try makeContext()
        let samples = try context.days.enumerated().map { index, day in
            try makeSample(day: day, value: index == 27 ? 20 : 7)
        }

        let result = HealthMetricBaselineEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(baseline) = result else {
            return XCTFail("Expected an available baseline")
        }
        XCTAssertEqual(baseline.medianValue, 7)
        XCTAssertEqual(baseline.medianAbsoluteDeviation, 0)
    }

    func testFourteenNonConsecutiveDaysMeetMinimumWithHalfCoverage() throws {
        let context = try makeContext()
        let samples = try context.days.enumerated().compactMap { index, day in
            index.isMultiple(of: 2) ? try makeSample(day: day, value: 6.5) : nil
        }

        let result = HealthMetricBaselineEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(baseline) = result else {
            return XCTFail("Expected the minimum valid baseline")
        }
        XCTAssertEqual(baseline.validDayCount, 14)
        XCTAssertEqual(baseline.coverageRatio, 0.5)
    }

    func testThirteenDaysRemainInsufficient() throws {
        let context = try makeContext()
        let samples = try context.days.prefix(13).map { day in
            try makeSample(day: day, value: 7)
        }

        XCTAssertEqual(
            HealthMetricBaselineEngine.calculate(
                metric: .sleepDuration,
                samples: samples,
                endingAt: context.referenceDate,
                calendar: context.calendar
            ),
            .insufficientData(
                validDayCount: 13,
                requiredDayCount: 14,
                expectedDayCount: 28
            )
        )
    }

    func testDuplicateSamplesOnOneDayStillCountAsOneValidDay() throws {
        let context = try makeContext()
        let repeated = try (0..<20).map { _ in
            try makeSample(day: context.days[0], value: 0.35)
        }

        XCTAssertEqual(
            HealthMetricBaselineEngine.calculate(
                metric: .sleepDuration,
                samples: repeated,
                endingAt: context.referenceDate,
                calendar: context.calendar
            ),
            .insufficientData(
                validDayCount: 1,
                requiredDayCount: 14,
                expectedDayCount: 28
            )
        )
    }

    private func makeContext() throws -> (
        calendar: Calendar,
        days: [Date],
        referenceDate: Date
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 25
        )))
        let days = try (0..<28).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        let referenceDate = try XCTUnwrap(calendar.date(
            byAdding: .hour,
            value: 12,
            to: days[27]
        ))
        return (calendar, days, referenceDate)
    }

    private func makeSample(
        day: Date,
        value: Double
    ) throws -> HealthMetricSample {
        let endDate = day.addingTimeInterval(7 * 60 * 60)
        return try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: endDate.addingTimeInterval(-value * 60 * 60),
            endDate: endDate,
            value: value,
            unit: .hours,
            source: HealthMetricSource(
                sourceName: "合成测试来源",
                bundleIdentifier: nil,
                deviceName: nil
            )
        )
    }
}
