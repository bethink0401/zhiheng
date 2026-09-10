import Foundation
import XCTest
@testable import Zhiheng

final class HealthBaselineTests: XCTestCase {
    func testRecentWindowUsesFourNonConsecutiveDaysWithoutFillingMissingDays() throws {
        let context = try makeContext()
        let selected = [21, 23, 25, 27]
        let values = [6.0, 7.0, 8.0, 9.0]
        let samples = try zip(selected, values).map { index, value in
            try makeSample(day: context.days[index], value: value)
        }

        let result = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(window) = result else {
            return XCTFail("Expected an available recent window")
        }
        XCTAssertEqual(window.expectedDayCount, 7)
        XCTAssertEqual(window.requiredDayCount, 4)
        XCTAssertEqual(window.validDayCount, 4)
        XCTAssertEqual(window.coverageRatio, 4.0 / 7.0, accuracy: 0.000_001)
        XCTAssertEqual(window.medianValue, 7.5)
        XCTAssertEqual(window.unit, .hours)
        XCTAssertEqual(window.points.map(\.value), values)
        XCTAssertEqual(
            window.points.map(\.date),
            selected.map { context.days[$0] }
        )
    }

    func testRecentWindowReturnsTraceableInsufficientDataAtThreeDays() throws {
        let context = try makeContext()
        let selected = [22, 24, 27]
        let samples = try selected.map { index in
            try makeSample(day: context.days[index], value: 7)
        }

        let result = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .insufficientData(
            metric,
            interval,
            validDayCount,
            requiredDayCount,
            expectedDayCount,
            coverageRatio,
            unit,
            points
        ) = result else {
            return XCTFail("Expected explicit insufficient data")
        }
        XCTAssertEqual(metric, .sleepDuration)
        XCTAssertEqual(validDayCount, 3)
        XCTAssertEqual(requiredDayCount, 4)
        XCTAssertEqual(expectedDayCount, 7)
        XCTAssertEqual(coverageRatio, 3.0 / 7.0, accuracy: 0.000_001)
        XCTAssertEqual(unit, .hours)
        XCTAssertEqual(points.count, 3)
        XCTAssertFalse(points.contains { $0.value == 0 })
        XCTAssertEqual(interval.start, context.days[21])
        XCTAssertEqual(
            interval.end,
            try XCTUnwrap(context.calendar.date(
                byAdding: .day,
                value: 1,
                to: context.days[27]
            ))
        )
    }

    func testRecentWindowExcludesDaysBeforeAndAfterItsCalendarBoundary() throws {
        let context = try makeContext()
        let futureDay = try XCTUnwrap(context.calendar.date(
            byAdding: .day,
            value: 1,
            to: context.days[27]
        ))
        let samples = try ([20] + Array(21...27)).map { index in
            try makeSample(day: context.days[index], value: Double(index))
        } + [makeSample(day: futureDay, value: 100)]

        let result = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        guard case let .available(window) = result else {
            return XCTFail("Expected an available recent window")
        }
        XCTAssertEqual(window.points.map(\.value), (21...27).map(Double.init))
        XCTAssertEqual(window.interval.start, context.days[21])
        XCTAssertEqual(window.interval.end, futureDay)
    }

    func testRecentWindowUsesCalendarDaysAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 4
        )))
        let days = try (0..<7).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        let referenceDate = try XCTUnwrap(calendar.date(
            byAdding: .hour,
            value: 12,
            to: days[6]
        ))
        let samples = try [0, 2, 4, 6].map { index in
            try makeSample(day: days[index], value: 7)
        }

        let result = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: referenceDate,
            calendar: calendar
        )

        guard case let .available(window) = result else {
            return XCTFail("Expected an available recent window")
        }
        XCTAssertEqual(window.interval.start, days[0])
        XCTAssertEqual(
            calendar.dateComponents(
                [.day],
                from: window.interval.start,
                to: window.interval.end
            ).day,
            7
        )
        XCTAssertEqual(window.interval.duration, 167 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(window.validDayCount, 4)
    }

    func testRecentWindowSourceTieBreakIsStableForReorderedInput() throws {
        let context = try makeContext()
        let sourceA = HealthMetricSource(
            sourceName: "Apple Watch A",
            bundleIdentifier: "test.watch.a",
            deviceName: "Apple Watch"
        )
        let sourceB = HealthMetricSource(
            sourceName: "Apple Watch B",
            bundleIdentifier: "test.watch.b",
            deviceName: "Apple Watch"
        )
        let samples = try (24...27).flatMap { index in
            [
                try makeSample(day: context.days[index], value: 6, source: sourceA),
                try makeSample(day: context.days[index], value: 9, source: sourceB)
            ]
        }

        let forward = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )
        let reversed = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: Array(samples.reversed()),
            endingAt: context.referenceDate,
            calendar: context.calendar
        )

        XCTAssertEqual(forward, reversed)
        guard case let .available(window) = forward else {
            return XCTFail("Expected an available recent window")
        }
        XCTAssertEqual(window.points.map(\.value), [6, 6, 6, 6])
        XCTAssertEqual(window.medianValue, 6)
    }

    func testChangeMagnitudeIncludesDecreaseAndBothWindowCoverages() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValue: 6
        )

        let magnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertEqual(magnitude.metric, .sleepDuration)
        XCTAssertEqual(magnitude.unit, .hours)
        XCTAssertEqual(magnitude.baselineValue, 8)
        XCTAssertEqual(magnitude.currentValue, 6)
        XCTAssertEqual(magnitude.absoluteChange, -2)
        XCTAssertEqual(magnitude.relativeChange, .available(ratio: -0.25))
        XCTAssertEqual(magnitude.relativeChange.percentage, -25)
        XCTAssertEqual(magnitude.baselineValidDayCount, 28)
        XCTAssertEqual(magnitude.baselineExpectedDayCount, 28)
        XCTAssertEqual(magnitude.baselineCoverageRatio, 1)
        XCTAssertEqual(magnitude.currentValidDayCount, 4)
        XCTAssertEqual(magnitude.currentExpectedDayCount, 7)
        XCTAssertEqual(magnitude.currentCoverageRatio, 4.0 / 7.0, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(magnitude.baselineInterval.end, magnitude.currentInterval.start)
    }

    func testChangeMagnitudePreservesIncreaseDirection() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValue: 10
        )

        let magnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertEqual(magnitude.absoluteChange, 2)
        XCTAssertEqual(magnitude.relativeChange, .available(ratio: 0.25))
        XCTAssertEqual(magnitude.relativeChange.percentage, 25)
    }

    func testChangeMagnitudePreservesNoChange() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValue: 8
        )

        let magnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertEqual(magnitude.absoluteChange, 0)
        XCTAssertEqual(magnitude.relativeChange, .available(ratio: 0))
        XCTAssertEqual(magnitude.relativeChange.percentage, 0)
    }

    func testChangeMagnitudeKeepsAbsoluteChangeWhenZeroBaselineHasNoPercentage() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 0,
            currentValue: 2
        )

        let magnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertEqual(magnitude.absoluteChange, 2)
        XCTAssertEqual(magnitude.relativeChange, .unavailableZeroBaseline)
        XCTAssertNil(magnitude.relativeChange.percentage)
    }

    func testChangeMagnitudeRejectsMismatchedOrOverlappingWindows() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValue: 6
        )
        func currentCopy(
            metric: HealthMetricType = .sleepDuration,
            unit: HealthMetricUnit = .hours,
            interval: DateInterval? = nil
        ) -> HealthMetricRecentWindow {
            HealthMetricRecentWindow(
                metric: metric,
                interval: interval ?? inputs.current.interval,
                expectedDayCount: inputs.current.expectedDayCount,
                requiredDayCount: inputs.current.requiredDayCount,
                validDayCount: inputs.current.validDayCount,
                coverageRatio: inputs.current.coverageRatio,
                medianValue: inputs.current.medianValue,
                unit: unit,
                points: inputs.current.points
            )
        }

        XCTAssertThrowsError(try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: currentCopy(metric: .stepCount, unit: .count)
        )) { error in
            XCTAssertEqual(error as? HealthMetricChangeCalculationError, .mismatchedMetric)
        }
        XCTAssertThrowsError(try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: currentCopy(unit: .count)
        )) { error in
            XCTAssertEqual(error as? HealthMetricChangeCalculationError, .mismatchedUnit)
        }
        XCTAssertThrowsError(try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: inputs.baseline,
            current: currentCopy(interval: DateInterval(
                start: inputs.baseline.interval.end.addingTimeInterval(-60),
                end: inputs.current.interval.end
            ))
        )) { error in
            XCTAssertEqual(
                error as? HealthMetricChangeCalculationError,
                .overlappingOrReversedWindows
            )
        }
    }

    func testSingleDayOutlierGuardDetectsOneIsolatedExtremeDay() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [8, 8, 8, 2]
        )

        let assessment = try HealthMetricSingleDayOutlierGuard.evaluate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertTrue(assessment.hasIsolatedSingleDayOutlier)
        XCTAssertEqual(assessment.isolatedOutlier?.value, 2)
        XCTAssertEqual(assessment.evaluatedDayCount, 4)
        XCTAssertEqual(assessment.currentMedianValue, 8)
        XCTAssertEqual(assessment.currentMedianAbsoluteDeviation, 0)
        XCTAssertEqual(assessment.baselineMedianAbsoluteDeviation, 0)
        XCTAssertEqual(assessment.madMultiplier, 3.5)
        XCTAssertEqual(assessment.deviationThreshold, 0)
        XCTAssertEqual(assessment.exceedingDayCount, 1)
        XCTAssertEqual(assessment.analysisPoints.map(\.value), [8, 8, 8])
        XCTAssertEqual(assessment.protectedMagnitude.currentValue, 8)
        XCTAssertEqual(assessment.protectedMagnitude.relativeChange, .available(ratio: 0))
        XCTAssertEqual(assessment.thresholdVersion, "s07-outlier-v1")
    }

    func testSingleDayOutlierGuardDoesNotRejectSustainedShift() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 6]
        )

        let assessment = try HealthMetricSingleDayOutlierGuard.evaluate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertFalse(assessment.hasIsolatedSingleDayOutlier)
        XCTAssertNil(assessment.isolatedOutlier)
        XCTAssertEqual(assessment.exceedingDayCount, 0)
        XCTAssertEqual(assessment.analysisPoints.count, 4)
        XCTAssertEqual(assessment.protectedMagnitude.currentValue, 6)
    }

    func testSingleDayOutlierGuardDoesNotCallMultiDayDispersionASingleOutlier() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [2, 2, 8, 8]
        )

        let assessment = try HealthMetricSingleDayOutlierGuard.evaluate(
            baseline: inputs.baseline,
            current: inputs.current
        )

        XCTAssertFalse(assessment.hasIsolatedSingleDayOutlier)
        XCTAssertNil(assessment.isolatedOutlier)
    }

    func testSingleDayOutlierGuardIsStableWhenCurrentPointsAreReordered() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [8, 2, 8, 8]
        )
        let reordered = HealthMetricRecentWindow(
            metric: inputs.current.metric,
            interval: inputs.current.interval,
            expectedDayCount: inputs.current.expectedDayCount,
            requiredDayCount: inputs.current.requiredDayCount,
            validDayCount: inputs.current.validDayCount,
            coverageRatio: inputs.current.coverageRatio,
            medianValue: inputs.current.medianValue,
            unit: inputs.current.unit,
            points: Array(inputs.current.points.reversed())
        )

        XCTAssertEqual(
            try HealthMetricSingleDayOutlierGuard.evaluate(
                baseline: inputs.baseline,
                current: inputs.current
            ),
            try HealthMetricSingleDayOutlierGuard.evaluate(
                baseline: inputs.baseline,
                current: reordered
            )
        )
    }

    func testTrendDetectorReturnsNoClearChangeBelowEffectiveThreshold() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [7.6, 7.6, 7.6, 7.6]
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)
        )

        XCTAssertEqual(trend.level, .noClearChange)
        XCTAssertEqual(trend.direction, .lower)
        XCTAssertEqual(
            try XCTUnwrap(trend.magnitude.relativeChange.percentage),
            -5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(trend.minimumRelativeChange, 0.08)
        XCTAssertEqual(trend.robustRelativeThreshold, 0)
        XCTAssertEqual(trend.effectiveRelativeThreshold, 0.08)
        XCTAssertEqual(trend.outlierThresholdVersion, "s07-outlier-v1")
        XCTAssertEqual(trend.thresholdVersion, "s07-trend-v1")
        XCTAssertEqual(trend.magnitude.baselineValidDayCount, 28)
        XCTAssertEqual(trend.magnitude.currentValidDayCount, 4)
    }

    func testTrendDetectorReturnsWorthObservingWithoutEnoughAlignedDays() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 8, 8]
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)
        )

        XCTAssertEqual(trend.level, .worthObserving)
        XCTAssertEqual(trend.direction, .lower)
        XCTAssertEqual(trend.alignedDayCount, 2)
        XCTAssertEqual(trend.requiredAlignedDayCount, 3)
    }

    func testTrendDetectorReturnsSustainedChangeWithEnoughAlignedDays() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 6]
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)
        )

        XCTAssertEqual(trend.level, .sustainedChange)
        XCTAssertEqual(trend.direction, .lower)
        XCTAssertEqual(trend.alignedDayCount, 4)
        XCTAssertEqual(trend.requiredAlignedDayCount, 3)
    }

    func testTrendDetectorReturnsWorthObservingWhenQualityIsLimited() throws {
        let sourceChangeInputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 6]
        )
        let outlierInputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 2]
        )
        let configuration = HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)

        let sourceChange = try HealthMetricTrendDetector.detect(
            baseline: sourceChangeInputs.baseline,
            current: sourceChangeInputs.current,
            sourceIsStable: false,
            configuration: configuration
        )
        let tooFewAfterProtection = try HealthMetricTrendDetector.detect(
            baseline: outlierInputs.baseline,
            current: outlierInputs.current,
            sourceIsStable: true,
            configuration: configuration
        )

        XCTAssertEqual(sourceChange.level, .worthObserving)
        XCTAssertFalse(sourceChange.sourceIsStable)
        XCTAssertEqual(tooFewAfterProtection.level, .worthObserving)
        XCTAssertEqual(tooFewAfterProtection.analysisPoints.count, 3)
        XCTAssertEqual(tooFewAfterProtection.isolatedOutlier?.value, 2)
    }

    func testTrendDetectorReturnsWorthObservingWhenZeroBaselineHasNoRelativeChange() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 0,
            currentValues: [2, 2, 2, 2]
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)
        )

        XCTAssertEqual(trend.level, .worthObserving)
        XCTAssertNil(trend.direction)
        XCTAssertNil(trend.robustRelativeThreshold)
        XCTAssertNil(trend.effectiveRelativeThreshold)
        XCTAssertEqual(trend.magnitude.relativeChange, .unavailableZeroBaseline)
    }

    func testTrendDetectorUsesRobustThresholdWhenBaselineDispersionIsLarger() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 6]
        )
        let variableBaseline = HealthMetricBaseline(
            metric: inputs.baseline.metric,
            interval: inputs.baseline.interval,
            expectedDayCount: inputs.baseline.expectedDayCount,
            validDayCount: inputs.baseline.validDayCount,
            coverageRatio: inputs.baseline.coverageRatio,
            medianValue: inputs.baseline.medianValue,
            medianAbsoluteDeviation: 1,
            unit: inputs.baseline.unit
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: variableBaseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0.08)
        )

        XCTAssertEqual(trend.level, .noClearChange)
        XCTAssertEqual(trend.robustRelativeThreshold, 0.3125)
        XCTAssertEqual(trend.effectiveRelativeThreshold, 0.3125)
        XCTAssertEqual(trend.alignedDayCount, 4)
    }

    func testTrendDetectorRejectsInvalidConfiguration() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValue: 6
        )

        XCTAssertThrowsError(try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: HealthMetricTrendConfiguration(minimumRelativeChange: 0)
        )) { error in
            XCTAssertEqual(error as? HealthMetricTrendDetectionError, .invalidConfiguration)
        }
    }

    func testTrendThresholdCatalogDefinesFourVersionedCoreMetrics() throws {
        XCTAssertEqual(
            HealthMetricTrendThresholdCatalog.coreMetrics,
            [.sleepDuration, .heartRateVariability, .restingHeartRate, .stepCount]
        )
        XCTAssertEqual(Set(HealthMetricTrendThresholdCatalog.coreMetrics).count, 4)

        let expected: [HealthMetricType: Double] = [
            .sleepDuration: 0.08,
            .heartRateVariability: 0.15,
            .restingHeartRate: 0.08,
            .stepCount: 0.15
        ]
        for metric in HealthMetricTrendThresholdCatalog.coreMetrics {
            let threshold = try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: metric)
            )
            XCTAssertEqual(threshold.metric, metric)
            XCTAssertEqual(
                threshold.minimumRelativeChange,
                try XCTUnwrap(expected[metric])
            )
            XCTAssertEqual(threshold.version, "s07-metric-thresholds-v1")
        }
    }

    func testTrendThresholdCatalogPreservesTodayExtensionsOnly() throws {
        XCTAssertEqual(
            HealthMetricTrendThresholdCatalog.todayCandidateMetrics,
            [
                .sleepDuration,
                .heartRateVariability,
                .restingHeartRate,
                .stepCount,
                .activeEnergy,
                .exerciseDuration
            ]
        )
        XCTAssertEqual(
            try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: .activeEnergy)
            ).minimumRelativeChange,
            0.18
        )
        XCTAssertEqual(
            try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: .exerciseDuration)
            ).minimumRelativeChange,
            0.25
        )
        XCTAssertNil(HealthMetricTrendThresholdCatalog.threshold(for: .heartRate))
    }

    func testCatalogConfigurationCarriesMetricVersionIntoTrendResult() throws {
        let inputs = try makeComparisonInputs(
            baselineValue: 8,
            currentValues: [6, 6, 6, 6]
        )
        let threshold = try XCTUnwrap(
            HealthMetricTrendThresholdCatalog.threshold(for: .sleepDuration)
        )

        let trend = try HealthMetricTrendDetector.detect(
            baseline: inputs.baseline,
            current: inputs.current,
            sourceIsStable: true,
            configuration: threshold.detectorConfiguration
        )

        XCTAssertEqual(trend.level, .sustainedChange)
        XCTAssertEqual(trend.minimumRelativeChange, 0.08)
        XCTAssertEqual(trend.thresholdVersion, "s07-metric-thresholds-v1")
    }

    func testCoreMetricsRemainStableAtPersonalBaseline() throws {
        for scenario in coreTrendScenarios {
            let inputs = try makeCoreScenarioInputs(
                metric: scenario.metric,
                baselineValue: scenario.baselineValue,
                currentValues: Array(repeating: scenario.baselineValue, count: 7)
            )
            let threshold = try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: scenario.metric)
            )

            let trend = try HealthMetricTrendDetector.detect(
                baseline: inputs.baseline,
                current: inputs.current,
                sourceIsStable: true,
                configuration: threshold.detectorConfiguration
            )

            XCTAssertEqual(trend.level, .noClearChange, scenario.metric.rawValue)
            XCTAssertNil(trend.direction, scenario.metric.rawValue)
            XCTAssertEqual(trend.magnitude.relativeChange, .available(ratio: 0))
            XCTAssertEqual(trend.thresholdVersion, HealthMetricTrendThresholdCatalog.version)
        }
    }

    func testCoreMetricsDetectSustainedIncrease() throws {
        for scenario in coreTrendScenarios {
            let threshold = try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: scenario.metric)
            )
            let currentValue = scenario.baselineValue
                * (1 + threshold.minimumRelativeChange + 0.05)
            let inputs = try makeCoreScenarioInputs(
                metric: scenario.metric,
                baselineValue: scenario.baselineValue,
                currentValues: Array(repeating: currentValue, count: 7)
            )

            let trend = try HealthMetricTrendDetector.detect(
                baseline: inputs.baseline,
                current: inputs.current,
                sourceIsStable: true,
                configuration: threshold.detectorConfiguration
            )

            XCTAssertEqual(trend.level, .sustainedChange, scenario.metric.rawValue)
            XCTAssertEqual(trend.direction, .higher, scenario.metric.rawValue)
            XCTAssertEqual(trend.alignedDayCount, 7, scenario.metric.rawValue)
            XCTAssertEqual(trend.requiredAlignedDayCount, 4, scenario.metric.rawValue)
        }
    }

    func testCoreMetricsDetectSustainedDecrease() throws {
        for scenario in coreTrendScenarios {
            let threshold = try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: scenario.metric)
            )
            let currentValue = scenario.baselineValue
                * (1 - threshold.minimumRelativeChange - 0.05)
            let inputs = try makeCoreScenarioInputs(
                metric: scenario.metric,
                baselineValue: scenario.baselineValue,
                currentValues: Array(repeating: currentValue, count: 7)
            )

            let trend = try HealthMetricTrendDetector.detect(
                baseline: inputs.baseline,
                current: inputs.current,
                sourceIsStable: true,
                configuration: threshold.detectorConfiguration
            )

            XCTAssertEqual(trend.level, .sustainedChange, scenario.metric.rawValue)
            XCTAssertEqual(trend.direction, .lower, scenario.metric.rawValue)
            XCTAssertEqual(trend.alignedDayCount, 7, scenario.metric.rawValue)
            XCTAssertEqual(trend.requiredAlignedDayCount, 4, scenario.metric.rawValue)
        }
    }

    func testCoreMetricsExposeCurrentAndBaselineInsufficientDataWithoutFillingZero() throws {
        let context = try makeContext(dayCount: 35)
        let baselineReference = try XCTUnwrap(context.calendar.date(
            byAdding: .hour,
            value: 12,
            to: context.days[27]
        ))

        for scenario in coreTrendScenarios {
            let currentSamples = try [32, 33, 34].map { index in
                try makeCoreSample(
                    metric: scenario.metric,
                    day: context.days[index],
                    value: scenario.baselineValue
                )
            }
            let currentResult = HealthMetricRecentWindowEngine.calculate(
                metric: scenario.metric,
                samples: currentSamples,
                endingAt: context.referenceDate,
                calendar: context.calendar
            )
            guard case let .insufficientData(
                metric,
                _,
                validDayCount,
                requiredDayCount,
                expectedDayCount,
                coverageRatio,
                unit,
                points
            ) = currentResult else {
                XCTFail("Expected current-window insufficient data for \(scenario.metric.rawValue)")
                continue
            }
            XCTAssertEqual(metric, scenario.metric)
            XCTAssertEqual(validDayCount, 3)
            XCTAssertEqual(requiredDayCount, 4)
            XCTAssertEqual(expectedDayCount, 7)
            XCTAssertEqual(coverageRatio, 3.0 / 7.0, accuracy: 0.000_001)
            XCTAssertEqual(unit, scenario.metric.expectedUnit)
            XCTAssertEqual(points.count, 3)
            XCTAssertFalse(points.contains { $0.value == 0 })

            let baselineSamples = try context.days.prefix(13).map { day in
                try makeCoreSample(
                    metric: scenario.metric,
                    day: day,
                    value: scenario.baselineValue
                )
            }
            XCTAssertEqual(
                HealthMetricBaselineEngine.calculate(
                    metric: scenario.metric,
                    samples: baselineSamples,
                    endingAt: baselineReference,
                    calendar: context.calendar
                ),
                .insufficientData(
                    validDayCount: 13,
                    requiredDayCount: 14,
                    expectedDayCount: 28
                ),
                scenario.metric.rawValue
            )
        }
    }

    func testCoreMetricsKeepNonConsecutiveDaysAndStillDetectSustainedChange() throws {
        let currentIndices = [28, 30, 32, 34]
        for scenario in coreTrendScenarios {
            let threshold = try XCTUnwrap(
                HealthMetricTrendThresholdCatalog.threshold(for: scenario.metric)
            )
            let currentValue = scenario.baselineValue
                * (1 - threshold.minimumRelativeChange - 0.05)
            let inputs = try makeCoreScenarioInputs(
                metric: scenario.metric,
                baselineValue: scenario.baselineValue,
                currentValues: Array(repeating: currentValue, count: currentIndices.count),
                currentIndices: currentIndices
            )

            XCTAssertEqual(inputs.current.validDayCount, 4, scenario.metric.rawValue)
            XCTAssertEqual(inputs.current.coverageRatio, 4.0 / 7.0, accuracy: 0.000_001)
            XCTAssertFalse(inputs.current.points.contains { $0.value == 0 })

            let trend = try HealthMetricTrendDetector.detect(
                baseline: inputs.baseline,
                current: inputs.current,
                sourceIsStable: true,
                configuration: threshold.detectorConfiguration
            )
            XCTAssertEqual(trend.level, .sustainedChange, scenario.metric.rawValue)
            XCTAssertEqual(trend.direction, .lower, scenario.metric.rawValue)
            XCTAssertEqual(trend.alignedDayCount, 4, scenario.metric.rawValue)
            XCTAssertEqual(trend.requiredAlignedDayCount, 3, scenario.metric.rawValue)
        }
    }

    func testTrendEvidenceExposesWindowsSamplesAndDecisionBasis() throws {
        let context = try makeContext(dayCount: 35)
        let samples = try context.days.enumerated().map { index, day in
            try makeCoreSample(
                metric: .sleepDuration,
                day: day,
                value: index < 28 ? 8 : 6
            )
        }

        let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ))

        XCTAssertEqual(evidence.state, .trend(.sustainedChange))
        XCTAssertEqual(evidence.currentValidDayCount, 7)
        XCTAssertEqual(evidence.currentExpectedDayCount, 7)
        XCTAssertEqual(evidence.baselineValidDayCount, 28)
        XCTAssertEqual(evidence.baselineExpectedDayCount, 28)
        XCTAssertEqual(evidence.currentMedianValue, 6)
        XCTAssertEqual(evidence.baselineMedianValue, 8)
        XCTAssertEqual(evidence.relativeChange, -0.25)
        XCTAssertEqual(evidence.configuredMinimumRelativeChange, 0.08)
        XCTAssertEqual(evidence.effectiveRelativeThreshold, 0.08)
        XCTAssertEqual(evidence.alignedDayCount, 7)
        XCTAssertEqual(evidence.analysisDayCount, 7)
        XCTAssertEqual(evidence.requiredAlignedDayCount, 4)
        XCTAssertFalse(evidence.isolatedOutlierExcluded)
        XCTAssertTrue(evidence.sourceIsStable)
        XCTAssertEqual(evidence.thresholdVersion, "s07-metric-thresholds-v1")
        XCTAssertEqual(evidence.baselineInterval.end, evidence.currentInterval.start)
    }

    func testTrendEvidenceExplainsCurrentWindowInsufficientData() throws {
        let context = try makeContext(dayCount: 35)
        let baseline = try context.days.prefix(28).map { day in
            try makeCoreSample(metric: .stepCount, day: day, value: 8_000)
        }
        let recent = try [32, 33, 34].map { index in
            try makeCoreSample(
                metric: .stepCount,
                day: context.days[index],
                value: 4_000
            )
        }

        let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(
            metric: .stepCount,
            samples: baseline + recent,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ))

        XCTAssertEqual(evidence.state, .currentWindowInsufficient)
        XCTAssertEqual(evidence.currentValidDayCount, 3)
        XCTAssertEqual(evidence.currentExpectedDayCount, 7)
        XCTAssertEqual(evidence.baselineValidDayCount, 28)
        XCTAssertNil(evidence.currentMedianValue)
        XCTAssertEqual(evidence.baselineMedianValue, 8_000)
        XCTAssertNil(evidence.relativeChange)
        XCTAssertEqual(evidence.configuredMinimumRelativeChange, 0.15)
    }

    func testTrendEvidenceExplainsBaselineInsufficientData() throws {
        let context = try makeContext(dayCount: 35)
        let baseline = try context.days.prefix(13).map { day in
            try makeCoreSample(
                metric: .heartRateVariability,
                day: day,
                value: 50
            )
        }
        let recent = try context.days.suffix(7).map { day in
            try makeCoreSample(
                metric: .heartRateVariability,
                day: day,
                value: 40
            )
        }

        let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(
            metric: .heartRateVariability,
            samples: baseline + recent,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ))

        XCTAssertEqual(evidence.state, .baselineInsufficient)
        XCTAssertEqual(evidence.currentValidDayCount, 7)
        XCTAssertEqual(evidence.baselineValidDayCount, 13)
        XCTAssertEqual(evidence.currentMedianValue, 40)
        XCTAssertNil(evidence.baselineMedianValue)
        XCTAssertNil(evidence.relativeChange)
    }

    func testTrendEvidenceSurfacesSourceChangeInsteadOfSustainedConclusion() throws {
        let context = try makeContext(dayCount: 35)
        let changedSource = HealthMetricSource(
            sourceName: "新测试来源",
            bundleIdentifier: "test.changed.source",
            deviceName: nil
        )
        let baseline = try context.days.prefix(28).map { day in
            try makeCoreSample(
                metric: .restingHeartRate,
                day: day,
                value: 60
            )
        }
        let recent = try context.days.suffix(7).map { day in
            try makeCoreSample(
                metric: .restingHeartRate,
                day: day,
                value: 72,
                source: changedSource
            )
        }

        let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(
            metric: .restingHeartRate,
            samples: baseline + recent,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ))

        XCTAssertEqual(evidence.state, .sourceChanged)
        XCTAssertFalse(evidence.sourceIsStable)
        XCTAssertEqual(evidence.currentValidDayCount, 7)
        XCTAssertEqual(evidence.baselineValidDayCount, 28)
        XCTAssertEqual(
            try XCTUnwrap(evidence.relativeChange),
            0.2,
            accuracy: 0.000_001
        )
    }

    func testTrendEvidenceDoesNotGuessThresholdForUnsupportedMetric() throws {
        let context = try makeContext(dayCount: 35)
        let samples = try context.days.map { day in
            try makeCoreSample(metric: .heartRate, day: day, value: 70)
        }

        XCTAssertNil(HealthMetricTrendEvidenceBuilder.make(
            metric: .heartRate,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ))
    }

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

    private var coreTrendScenarios: [(metric: HealthMetricType, baselineValue: Double)] {
        [
            (.sleepDuration, 8),
            (.heartRateVariability, 50),
            (.restingHeartRate, 60),
            (.stepCount, 8_000)
        ]
    }

    private func makeCoreScenarioInputs(
        metric: HealthMetricType,
        baselineValue: Double,
        currentValues: [Double],
        currentIndices: [Int] = Array(28...34)
    ) throws -> (
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow
    ) {
        let context = try makeContext(dayCount: 35)
        XCTAssertEqual(currentValues.count, currentIndices.count)
        let baselineSamples = try context.days.prefix(28).map { day in
            try makeCoreSample(metric: metric, day: day, value: baselineValue)
        }
        let currentSamples = try zip(currentIndices, currentValues).map { index, value in
            try makeCoreSample(metric: metric, day: context.days[index], value: value)
        }
        let samples = baselineSamples + currentSamples
        let baselineReference = try XCTUnwrap(context.calendar.date(
            byAdding: .hour,
            value: 12,
            to: context.days[27]
        ))

        guard case let .available(baseline) = HealthMetricBaselineEngine.calculate(
            metric: metric,
            samples: samples,
            endingAt: baselineReference,
            calendar: context.calendar
        ) else {
            throw HealthDataServiceError.queryFailed
        }
        guard case let .available(current) = HealthMetricRecentWindowEngine.calculate(
            metric: metric,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        ) else {
            throw HealthDataServiceError.queryFailed
        }
        return (baseline, current)
    }

    private func makeComparisonInputs(
        baselineValue: Double,
        currentValue: Double
    ) throws -> (
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow
    ) {
        let context = try makeContext(dayCount: 35)
        let baselineSamples = try context.days.prefix(28).map { day in
            try makeSample(day: day, value: baselineValue)
        }
        let currentSamples = try [28, 30, 32, 34].map { index in
            try makeSample(day: context.days[index], value: currentValue)
        }
        let samples = baselineSamples + currentSamples
        let baselineReference = try XCTUnwrap(context.calendar.date(
            byAdding: .hour,
            value: 12,
            to: context.days[27]
        ))
        let baselineResult = HealthMetricBaselineEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: baselineReference,
            calendar: context.calendar
        )
        let maybeBaseline: HealthMetricBaseline? = {
            guard case let .available(value) = baselineResult else { return nil }
            return value
        }()
        let baseline = try XCTUnwrap(maybeBaseline)
        let currentResult = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )
        let maybeCurrent: HealthMetricRecentWindow? = {
            guard case let .available(value) = currentResult else { return nil }
            return value
        }()
        let current = try XCTUnwrap(maybeCurrent)
        return (baseline, current)
    }

    private func makeComparisonInputs(
        baselineValue: Double,
        currentValues: [Double]
    ) throws -> (
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow
    ) {
        let context = try makeContext(dayCount: 35)
        let baselineSamples = try context.days.prefix(28).map { day in
            try makeSample(day: day, value: baselineValue)
        }
        let currentIndices = [28, 30, 32, 34]
        XCTAssertEqual(currentValues.count, currentIndices.count)
        let currentSamples = try zip(currentIndices, currentValues).map { index, value in
            try makeSample(day: context.days[index], value: value)
        }
        let samples = baselineSamples + currentSamples
        let baselineReference = try XCTUnwrap(context.calendar.date(
            byAdding: .hour,
            value: 12,
            to: context.days[27]
        ))
        let baselineResult = HealthMetricBaselineEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: baselineReference,
            calendar: context.calendar
        )
        guard case let .available(baseline) = baselineResult else {
            throw HealthDataServiceError.queryFailed
        }
        let currentResult = HealthMetricRecentWindowEngine.calculate(
            metric: .sleepDuration,
            samples: samples,
            endingAt: context.referenceDate,
            calendar: context.calendar
        )
        guard case let .available(current) = currentResult else {
            throw HealthDataServiceError.queryFailed
        }
        return (baseline, current)
    }

    private func makeContext(dayCount: Int = 28) throws -> (
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
        let days = try (0..<dayCount).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }
        let referenceDate = try XCTUnwrap(calendar.date(
            byAdding: .hour,
            value: 12,
            to: try XCTUnwrap(days.last)
        ))
        return (calendar, days, referenceDate)
    }

    private func makeCoreSample(
        metric: HealthMetricType,
        day: Date,
        value: Double,
        source: HealthMetricSource = HealthMetricSource(
            sourceName: "合成测试来源",
            bundleIdentifier: nil,
            deviceName: nil
        )
    ) throws -> HealthMetricSample {
        let endDate = day.addingTimeInterval(7 * 60 * 60)
        let startDate = metric == .sleepDuration
            ? endDate.addingTimeInterval(-value * 60 * 60)
            : endDate.addingTimeInterval(-60)
        return try HealthMetricSample(
            id: UUID(),
            metricType: metric,
            startDate: startDate,
            endDate: endDate,
            value: value,
            unit: metric.expectedUnit,
            source: source
        )
    }

    private func makeSample(
        day: Date,
        value: Double,
        source: HealthMetricSource = HealthMetricSource(
            sourceName: "合成测试来源",
            bundleIdentifier: nil,
            deviceName: nil
        )
    ) throws -> HealthMetricSample {
        let endDate = day.addingTimeInterval(7 * 60 * 60)
        return try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: endDate.addingTimeInterval(-value * 60 * 60),
            endDate: endDate,
            value: value,
            unit: .hours,
            source: source
        )
    }
}
