import Foundation

struct HealthMetricBaseline: Equatable, Sendable {
    let metric: HealthMetricType
    let interval: DateInterval
    let expectedDayCount: Int
    let validDayCount: Int
    let coverageRatio: Double
    let medianValue: Double
    let medianAbsoluteDeviation: Double
    let unit: HealthMetricUnit
}

enum HealthMetricBaselineResult: Equatable, Sendable {
    case available(HealthMetricBaseline)
    case insufficientData(
        validDayCount: Int,
        requiredDayCount: Int,
        expectedDayCount: Int
    )
}

enum HealthMetricBaselineEngine {
    static func calculate(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        endingAt referenceDate: Date,
        calendar: Calendar = .current
    ) -> HealthMetricBaselineResult {
        let expectedDays = HealthDataQualityThresholds.baselineExpectedDays
        let requiredDays = HealthDataQualityThresholds.baselineMinimumValidDays
        let points = HealthMetricDailySeriesCalculator.points(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            window: .twentyEightDays,
            calendar: calendar
        )

        guard points.count >= requiredDays else {
            return .insufficientData(
                validDayCount: points.count,
                requiredDayCount: requiredDays,
                expectedDayCount: expectedDays
            )
        }
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(expectedDays - 1),
            to: referenceDate
        ) else {
            return .insufficientData(
                validDayCount: points.count,
                requiredDayCount: requiredDays,
                expectedDayCount: expectedDays
            )
        }

        let values = points.map(\.value).sorted()
        let medianValue = median(values)
        let deviations = values.map { abs($0 - medianValue) }.sorted()
        let interval = DateInterval(
            start: calendar.startOfDay(for: firstDay),
            end: referenceDate
        )
        return .available(HealthMetricBaseline(
            metric: metric,
            interval: interval,
            expectedDayCount: expectedDays,
            validDayCount: points.count,
            coverageRatio: Double(points.count) / Double(expectedDays),
            medianValue: medianValue,
            medianAbsoluteDeviation: median(deviations),
            unit: metric.expectedUnit
        ))
    }

    private static func median(_ sortedValues: [Double]) -> Double {
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}
