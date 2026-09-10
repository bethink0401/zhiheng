import Foundation

struct HealthMetricRecentWindow: Equatable, Sendable {
    let metric: HealthMetricType
    /// Half-open calendar-day range: `start` is the first included day and
    /// `end` is the start of the day immediately after the reference day.
    let interval: DateInterval
    let expectedDayCount: Int
    let requiredDayCount: Int
    let validDayCount: Int
    let coverageRatio: Double
    let medianValue: Double
    let unit: HealthMetricUnit
    let points: [HealthMetricDailyPoint]
}

enum HealthMetricRecentWindowResult: Equatable, Sendable {
    case available(HealthMetricRecentWindow)
    case insufficientData(
        metric: HealthMetricType,
        interval: DateInterval,
        validDayCount: Int,
        requiredDayCount: Int,
        expectedDayCount: Int,
        coverageRatio: Double,
        unit: HealthMetricUnit,
        points: [HealthMetricDailyPoint]
    )
    case calendarUnavailable
}

enum HealthMetricRecentWindowEngine {
    static func calculate(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        endingAt referenceDate: Date,
        calendar: Calendar = .current
    ) -> HealthMetricRecentWindowResult {
        let expectedDays = HealthDataQualityThresholds.shortTermExpectedDays
        let requiredDays = HealthDataQualityThresholds.shortTermMinimumValidDays
        let finalDay = calendar.startOfDay(for: referenceDate)
        guard
            let firstDay = calendar.date(
                byAdding: .day,
                value: -(expectedDays - 1),
                to: finalDay
            ),
            let endExclusive = calendar.date(
                byAdding: .day,
                value: 1,
                to: finalDay
            )
        else {
            return .calendarUnavailable
        }

        let interval = DateInterval(start: firstDay, end: endExclusive)
        let points = HealthMetricDailySeriesCalculator.points(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            window: .sevenDays,
            calendar: calendar
        )
        guard points.count >= requiredDays else {
            return .insufficientData(
                metric: metric,
                interval: interval,
                validDayCount: points.count,
                requiredDayCount: requiredDays,
                expectedDayCount: expectedDays,
                coverageRatio: Double(points.count) / Double(expectedDays),
                unit: metric.expectedUnit,
                points: points
            )
        }

        return .available(HealthMetricRecentWindow(
            metric: metric,
            interval: interval,
            expectedDayCount: expectedDays,
            requiredDayCount: requiredDays,
            validDayCount: points.count,
            coverageRatio: Double(points.count) / Double(expectedDays),
            medianValue: median(points.map(\.value).sorted()),
            unit: metric.expectedUnit,
            points: points
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

enum HealthMetricRelativeChange: Equatable, Sendable {
    case available(ratio: Double)
    case unavailableZeroBaseline

    var percentage: Double? {
        guard case let .available(ratio) = self else { return nil }
        return ratio * 100
    }
}

struct HealthMetricChangeMagnitude: Equatable, Sendable {
    let metric: HealthMetricType
    let unit: HealthMetricUnit
    let baselineInterval: DateInterval
    let currentInterval: DateInterval
    let baselineValue: Double
    let currentValue: Double
    let absoluteChange: Double
    let relativeChange: HealthMetricRelativeChange
    let baselineValidDayCount: Int
    let baselineExpectedDayCount: Int
    let baselineCoverageRatio: Double
    let currentValidDayCount: Int
    let currentExpectedDayCount: Int
    let currentCoverageRatio: Double
}

enum HealthMetricChangeCalculationError: Error, Equatable {
    case mismatchedMetric
    case mismatchedUnit
    case overlappingOrReversedWindows
}

enum HealthMetricChangeMagnitudeCalculator {
    static func calculate(
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow
    ) throws -> HealthMetricChangeMagnitude {
        try calculate(
            baseline: baseline,
            current: current,
            analyzedCurrentValue: current.medianValue
        )
    }

    fileprivate static func calculate(
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow,
        analyzedCurrentValue: Double
    ) throws -> HealthMetricChangeMagnitude {
        guard baseline.metric == current.metric else {
            throw HealthMetricChangeCalculationError.mismatchedMetric
        }
        guard baseline.unit == current.unit else {
            throw HealthMetricChangeCalculationError.mismatchedUnit
        }
        guard baseline.interval.end <= current.interval.start else {
            throw HealthMetricChangeCalculationError.overlappingOrReversedWindows
        }

        let absoluteChange = analyzedCurrentValue - baseline.medianValue
        let relativeChange: HealthMetricRelativeChange = if baseline.medianValue == 0 {
            .unavailableZeroBaseline
        } else {
            .available(ratio: absoluteChange / baseline.medianValue)
        }
        return HealthMetricChangeMagnitude(
            metric: current.metric,
            unit: current.unit,
            baselineInterval: baseline.interval,
            currentInterval: current.interval,
            baselineValue: baseline.medianValue,
            currentValue: analyzedCurrentValue,
            absoluteChange: absoluteChange,
            relativeChange: relativeChange,
            baselineValidDayCount: baseline.validDayCount,
            baselineExpectedDayCount: baseline.expectedDayCount,
            baselineCoverageRatio: baseline.coverageRatio,
            currentValidDayCount: current.validDayCount,
            currentExpectedDayCount: current.expectedDayCount,
            currentCoverageRatio: current.coverageRatio
        )
    }
}

struct HealthMetricSingleDayOutlierAssessment: Equatable, Sendable {
    let metric: HealthMetricType
    let unit: HealthMetricUnit
    let currentInterval: DateInterval
    let evaluatedDayCount: Int
    let currentMedianValue: Double
    let currentMedianAbsoluteDeviation: Double
    let baselineMedianAbsoluteDeviation: Double
    let madMultiplier: Double
    let deviationThreshold: Double
    let exceedingDayCount: Int
    let isolatedOutlier: HealthMetricDailyPoint?
    let analysisPoints: [HealthMetricDailyPoint]
    let protectedMagnitude: HealthMetricChangeMagnitude
    let thresholdVersion: String

    var hasIsolatedSingleDayOutlier: Bool {
        isolatedOutlier != nil
    }
}

enum HealthMetricSingleDayOutlierGuard {
    static func evaluate(
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow
    ) throws -> HealthMetricSingleDayOutlierAssessment {
        let magnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: baseline,
            current: current
        )
        let deviations = current.points.map {
            abs($0.value - magnitude.currentValue)
        }.sorted()
        let currentMAD = median(deviations)
        let multiplier = HealthDataQualityThresholds.singleDayOutlierMADMultiplier
        let threshold = max(
            baseline.medianAbsoluteDeviation,
            currentMAD
        ) * multiplier
        let numericalTolerance = max(abs(magnitude.currentValue), 1) * 1e-12
        let exceedingPoints = current.points
            .filter {
                abs($0.value - magnitude.currentValue)
                    > threshold + numericalTolerance
            }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.value < $1.value
            }
        let isolatedOutlier = exceedingPoints.count == 1
            ? exceedingPoints[0]
            : nil
        let analysisPoints = current.points
            .filter { point in
                guard let isolatedOutlier else { return true }
                return point != isolatedOutlier
            }
            .sorted { $0.date < $1.date }
        let protectedMedian = median(analysisPoints.map(\.value).sorted())
        let protectedMagnitude = try HealthMetricChangeMagnitudeCalculator.calculate(
            baseline: baseline,
            current: current,
            analyzedCurrentValue: protectedMedian
        )

        return HealthMetricSingleDayOutlierAssessment(
            metric: magnitude.metric,
            unit: magnitude.unit,
            currentInterval: magnitude.currentInterval,
            evaluatedDayCount: current.points.count,
            currentMedianValue: magnitude.currentValue,
            currentMedianAbsoluteDeviation: currentMAD,
            baselineMedianAbsoluteDeviation: baseline.medianAbsoluteDeviation,
            madMultiplier: multiplier,
            deviationThreshold: threshold,
            exceedingDayCount: exceedingPoints.count,
            isolatedOutlier: isolatedOutlier,
            analysisPoints: analysisPoints,
            protectedMagnitude: protectedMagnitude,
            thresholdVersion: HealthDataQualityThresholds.singleDayOutlierThresholdVersion
        )
    }

    private static func median(_ sortedValues: [Double]) -> Double {
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}

enum HealthMetricTrendLevel: String, Equatable, Sendable {
    case noClearChange
    case worthObserving
    case sustainedChange
}

enum HealthMetricTrendDirection: String, Equatable, Sendable {
    case higher
    case lower
}

struct HealthMetricTrendConfiguration: Equatable, Sendable {
    let minimumRelativeChange: Double
    let thresholdVersion: String

    init(
        minimumRelativeChange: Double,
        thresholdVersion: String = HealthDataQualityThresholds.trendThresholdVersion
    ) {
        self.minimumRelativeChange = minimumRelativeChange
        self.thresholdVersion = thresholdVersion
    }
}

struct HealthMetricTrendThreshold: Equatable, Sendable {
    let metric: HealthMetricType
    let minimumRelativeChange: Double
    let version: String

    var detectorConfiguration: HealthMetricTrendConfiguration {
        HealthMetricTrendConfiguration(
            minimumRelativeChange: minimumRelativeChange,
            thresholdVersion: version
        )
    }
}

enum HealthMetricTrendThresholdCatalog {
    static let version = "s07-metric-thresholds-v1"

    static let coreMetrics: [HealthMetricType] = [
        .sleepDuration,
        .heartRateVariability,
        .restingHeartRate,
        .stepCount
    ]

    static let todayCandidateMetrics: [HealthMetricType] = coreMetrics + [
        .activeEnergy,
        .exerciseDuration
    ]

    static func threshold(
        for metric: HealthMetricType
    ) -> HealthMetricTrendThreshold? {
        let minimumRelativeChange: Double
        switch metric {
        case .sleepDuration:
            minimumRelativeChange = 0.08
        case .heartRateVariability:
            minimumRelativeChange = 0.15
        case .restingHeartRate:
            minimumRelativeChange = 0.08
        case .stepCount:
            minimumRelativeChange = 0.15
        case .activeEnergy:
            minimumRelativeChange = 0.18
        case .exerciseDuration:
            minimumRelativeChange = 0.25
        default:
            return nil
        }
        return HealthMetricTrendThreshold(
            metric: metric,
            minimumRelativeChange: minimumRelativeChange,
            version: version
        )
    }
}

struct HealthMetricTrendResult: Equatable, Sendable {
    let level: HealthMetricTrendLevel
    let direction: HealthMetricTrendDirection?
    let magnitude: HealthMetricChangeMagnitude
    let analysisPoints: [HealthMetricDailyPoint]
    let isolatedOutlier: HealthMetricDailyPoint?
    let sourceIsStable: Bool
    let minimumRelativeChange: Double
    let robustRelativeThreshold: Double?
    let effectiveRelativeThreshold: Double?
    let alignedDayCount: Int
    let requiredAlignedDayCount: Int
    let outlierThresholdVersion: String
    let thresholdVersion: String
}

enum HealthMetricTrendDetectionError: Error, Equatable {
    case invalidConfiguration
}

enum HealthMetricTrendDetector {
    static func detect(
        baseline: HealthMetricBaseline,
        current: HealthMetricRecentWindow,
        sourceIsStable: Bool,
        configuration: HealthMetricTrendConfiguration
    ) throws -> HealthMetricTrendResult {
        guard configuration.minimumRelativeChange.isFinite,
              configuration.minimumRelativeChange > 0,
              !configuration.thresholdVersion.isEmpty
        else {
            throw HealthMetricTrendDetectionError.invalidConfiguration
        }

        let outlierAssessment = try HealthMetricSingleDayOutlierGuard.evaluate(
            baseline: baseline,
            current: current
        )
        let magnitude = outlierAssessment.protectedMagnitude
        let analysisPoints = outlierAssessment.analysisPoints
        let requiredAlignedDays = max(
            HealthDataQualityThresholds.trendMinimumAlignedDays,
            Int(ceil(
                Double(analysisPoints.count)
                    * HealthDataQualityThresholds.trendMinimumAlignedFraction
            ))
        )

        guard case let .available(relativeChange) = magnitude.relativeChange else {
            return result(
                level: .worthObserving,
                direction: nil,
                magnitude: magnitude,
                assessment: outlierAssessment,
                sourceIsStable: sourceIsStable,
                configuration: configuration,
                robustRelativeThreshold: nil,
                effectiveRelativeThreshold: nil,
                alignedDayCount: 0,
                requiredAlignedDayCount: requiredAlignedDays
            )
        }

        let robustRelativeThreshold = baseline.medianAbsoluteDeviation
            * HealthDataQualityThresholds.trendMagnitudeMADMultiplier
            / abs(baseline.medianValue)
        let effectiveRelativeThreshold = max(
            configuration.minimumRelativeChange,
            robustRelativeThreshold
        )
        let direction: HealthMetricTrendDirection? = if relativeChange > 0 {
            .higher
        } else if relativeChange < 0 {
            .lower
        } else {
            nil
        }
        let directionSign = relativeChange >= 0 ? 1.0 : -1.0
        let alignedThreshold = abs(baseline.medianValue)
            * configuration.minimumRelativeChange
            * HealthDataQualityThresholds.trendAlignmentThresholdFraction
        let alignedDayCount = direction == nil ? 0 : analysisPoints.filter {
            (($0.value - baseline.medianValue) * directionSign) >= alignedThreshold
        }.count

        let level: HealthMetricTrendLevel
        if !sourceIsStable
            || analysisPoints.count < HealthDataQualityThresholds.shortTermMinimumValidDays
        {
            level = .worthObserving
        } else if abs(relativeChange) < effectiveRelativeThreshold {
            level = .noClearChange
        } else if alignedDayCount >= requiredAlignedDays {
            level = .sustainedChange
        } else {
            level = .worthObserving
        }

        return result(
            level: level,
            direction: direction,
            magnitude: magnitude,
            assessment: outlierAssessment,
            sourceIsStable: sourceIsStable,
            configuration: configuration,
            robustRelativeThreshold: robustRelativeThreshold,
            effectiveRelativeThreshold: effectiveRelativeThreshold,
            alignedDayCount: alignedDayCount,
            requiredAlignedDayCount: requiredAlignedDays
        )
    }

    private static func result(
        level: HealthMetricTrendLevel,
        direction: HealthMetricTrendDirection?,
        magnitude: HealthMetricChangeMagnitude,
        assessment: HealthMetricSingleDayOutlierAssessment,
        sourceIsStable: Bool,
        configuration: HealthMetricTrendConfiguration,
        robustRelativeThreshold: Double?,
        effectiveRelativeThreshold: Double?,
        alignedDayCount: Int,
        requiredAlignedDayCount: Int
    ) -> HealthMetricTrendResult {
        HealthMetricTrendResult(
            level: level,
            direction: direction,
            magnitude: magnitude,
            analysisPoints: assessment.analysisPoints,
            isolatedOutlier: assessment.isolatedOutlier,
            sourceIsStable: sourceIsStable,
            minimumRelativeChange: configuration.minimumRelativeChange,
            robustRelativeThreshold: robustRelativeThreshold,
            effectiveRelativeThreshold: effectiveRelativeThreshold,
            alignedDayCount: alignedDayCount,
            requiredAlignedDayCount: requiredAlignedDayCount,
            outlierThresholdVersion: assessment.thresholdVersion,
            thresholdVersion: configuration.thresholdVersion
        )
    }
}

enum HealthMetricTrendEvidenceState: Equatable, Sendable {
    case currentWindowInsufficient
    case baselineInsufficient
    case sourceChanged
    case trend(HealthMetricTrendLevel)
}

struct HealthMetricTrendEvidence: Equatable, Sendable {
    let metric: HealthMetricType
    let unit: HealthMetricUnit
    let state: HealthMetricTrendEvidenceState
    let currentInterval: DateInterval
    let currentValidDayCount: Int
    let currentExpectedDayCount: Int
    let baselineInterval: DateInterval
    let baselineValidDayCount: Int
    let baselineExpectedDayCount: Int
    let currentMedianValue: Double?
    let baselineMedianValue: Double?
    let relativeChange: Double?
    let configuredMinimumRelativeChange: Double
    let effectiveRelativeThreshold: Double?
    let alignedDayCount: Int?
    let analysisDayCount: Int?
    let requiredAlignedDayCount: Int?
    let isolatedOutlierExcluded: Bool
    let sourceIsStable: Bool
    let thresholdVersion: String
}

enum HealthMetricTrendSourceStabilityEvaluator {
    static func isStable(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        endingAt referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let endDay = calendar.startOfDay(for: referenceDate)
        guard let firstDay = calendar.date(byAdding: .day, value: -34, to: endDay) else {
            return false
        }
        let grouped = Dictionary(grouping: samples.filter {
            let day = calendar.startOfDay(for: $0.endDate)
            return day >= firstDay && day <= endDay
        }) { calendar.startOfDay(for: $0.endDate) }

        let sourceSignatures = grouped.values.compactMap { daySamples -> String? in
            let selected: [HealthMetricSample]
            switch metric {
            case .stepCount, .sleepDuration, .activeEnergy, .exerciseDuration:
                guard let preferred = PreferredHealthMetricSourceSelector.samples(
                    from: daySamples
                ) else { return nil }
                selected = preferred
            default:
                selected = daySamples
            }
            let identifiers = Set(selected.map {
                $0.source.bundleIdentifier ?? $0.source.displayName
            })
            guard identifiers.count == 1 else { return nil }
            return identifiers.first
        }
        return !sourceSignatures.isEmpty && Set(sourceSignatures).count == 1
    }
}

enum HealthMetricTrendEvidenceBuilder {
    static func make(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        endingAt referenceDate: Date,
        calendar: Calendar = .current
    ) -> HealthMetricTrendEvidence? {
        guard let threshold = HealthMetricTrendThresholdCatalog.threshold(for: metric) else {
            return nil
        }

        let currentResult = HealthMetricRecentWindowEngine.calculate(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            calendar: calendar
        )
        let currentInterval: DateInterval
        let currentValidDayCount: Int
        let currentExpectedDayCount: Int
        let current: HealthMetricRecentWindow?
        switch currentResult {
        case let .available(value):
            currentInterval = value.interval
            currentValidDayCount = value.validDayCount
            currentExpectedDayCount = value.expectedDayCount
            current = value
        case let .insufficientData(
            _, interval, validDayCount, _, expectedDayCount, _, _, _
        ):
            currentInterval = interval
            currentValidDayCount = validDayCount
            currentExpectedDayCount = expectedDayCount
            current = nil
        case .calendarUnavailable:
            return nil
        }

        guard let baselineStart = calendar.date(
            byAdding: .day,
            value: -HealthDataQualityThresholds.baselineExpectedDays,
            to: currentInterval.start
        ) else {
            return nil
        }
        let baselineInterval = DateInterval(
            start: baselineStart,
            end: currentInterval.start
        )
        let baselineReference = currentInterval.start.addingTimeInterval(-1)
        let baselineResult = HealthMetricBaselineEngine.calculate(
            metric: metric,
            samples: samples,
            endingAt: baselineReference,
            calendar: calendar
        )
        let baselineValidDayCount: Int
        let baselineExpectedDayCount: Int
        let baseline: HealthMetricBaseline?
        switch baselineResult {
        case let .available(value):
            baselineValidDayCount = value.validDayCount
            baselineExpectedDayCount = value.expectedDayCount
            baseline = value
        case let .insufficientData(validDayCount, _, expectedDayCount):
            baselineValidDayCount = validDayCount
            baselineExpectedDayCount = expectedDayCount
            baseline = nil
        }

        let sourceIsStable = HealthMetricTrendSourceStabilityEvaluator.isStable(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            calendar: calendar
        )
        let trend: HealthMetricTrendResult? = if let baseline, let current {
            try? HealthMetricTrendDetector.detect(
                baseline: baseline,
                current: current,
                sourceIsStable: sourceIsStable,
                configuration: threshold.detectorConfiguration
            )
        } else {
            nil
        }

        let state: HealthMetricTrendEvidenceState
        if current == nil {
            state = .currentWindowInsufficient
        } else if baseline == nil {
            state = .baselineInsufficient
        } else if !sourceIsStable {
            state = .sourceChanged
        } else if let trend {
            state = .trend(trend.level)
        } else {
            return nil
        }

        let relativeChange: Double? = if let trend,
            case let .available(value) = trend.magnitude.relativeChange
        {
            value
        } else {
            nil
        }

        return HealthMetricTrendEvidence(
            metric: metric,
            unit: metric.expectedUnit,
            state: state,
            currentInterval: currentInterval,
            currentValidDayCount: currentValidDayCount,
            currentExpectedDayCount: currentExpectedDayCount,
            baselineInterval: baselineInterval,
            baselineValidDayCount: baselineValidDayCount,
            baselineExpectedDayCount: baselineExpectedDayCount,
            currentMedianValue: trend?.magnitude.currentValue ?? current?.medianValue,
            baselineMedianValue: baseline?.medianValue,
            relativeChange: relativeChange,
            configuredMinimumRelativeChange: threshold.minimumRelativeChange,
            effectiveRelativeThreshold: trend?.effectiveRelativeThreshold,
            alignedDayCount: trend?.alignedDayCount,
            analysisDayCount: trend?.analysisPoints.count,
            requiredAlignedDayCount: trend?.requiredAlignedDayCount,
            isolatedOutlierExcluded: trend?.isolatedOutlier != nil,
            sourceIsStable: sourceIsStable,
            thresholdVersion: threshold.version
        )
    }
}
