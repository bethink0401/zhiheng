import Foundation

enum HealthDataQualityThresholds {
    static let shortTermExpectedDays = 7
    static let shortTermMinimumValidDays = 4
    static let baselineExpectedDays = 28
    static let baselineMinimumValidDays = 14
    static let inventoryExpectedDays = 90
}

struct HealthDataQualityReport: Equatable, Sendable {
    let metric: HealthMetricType
    let expectedDayCount: Int
    let validDayCount: Int
    let coverageRatio: Double
    let latestSampleDate: Date?
    let longestMissingDayStreak: Int
    let sourceNames: Set<String>

    var hasSourceChange: Bool {
        sourceNames.count > 1
    }

    var supportsShortTermObservation: Bool {
        expectedDayCount == HealthDataQualityThresholds.shortTermExpectedDays
            && validDayCount >= HealthDataQualityThresholds.shortTermMinimumValidDays
    }
}

enum HealthDataQualityCalculator {
    static func evaluate(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        interval: DateInterval,
        calendar: Calendar = .current
    ) throws -> HealthDataQualityReport {
        guard interval.end > interval.start else {
            throw HealthDataServiceError.invalidInterval
        }
        guard samples.allSatisfy({ $0.metricType == metric }) else {
            throw HealthDataServiceError.queryFailed
        }

        let firstDay = calendar.startOfDay(for: interval.start)
        let lastDay = calendar.startOfDay(for: interval.end)
        var days = [Date]()
        var cursor = firstDay
        while cursor <= lastDay {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                throw HealthDataServiceError.queryFailed
            }
            cursor = next
        }

        let visibleSamples = samples.filter { sample in
            sample.endDate >= interval.start && sample.startDate <= interval.end
        }
        let validDays = Set(visibleSamples.map {
            calendar.startOfDay(for: $0.endDate)
        })
        var longestGap = 0
        var currentGap = 0
        for day in days {
            if validDays.contains(day) {
                currentGap = 0
            } else {
                currentGap += 1
                longestGap = max(longestGap, currentGap)
            }
        }
        let validDayCount = days.filter(validDays.contains).count
        let expectedDayCount = days.count

        return HealthDataQualityReport(
            metric: metric,
            expectedDayCount: expectedDayCount,
            validDayCount: validDayCount,
            coverageRatio: expectedDayCount == 0
                ? 0
                : Double(validDayCount) / Double(expectedDayCount),
            latestSampleDate: visibleSamples.map(\.endDate).max(),
            longestMissingDayStreak: longestGap,
            sourceNames: Set(visibleSamples.map(\.source.sourceName))
        )
    }
}

struct HealthMetricSummary: Equatable, Sendable {
    let metric: HealthMetricType
    let value: Double
    let unit: HealthMetricUnit
    let date: Date
    let sourceName: String
}

enum HealthMetricSummaryResult: Equatable, Sendable {
    case value(HealthMetricSummary)
    case noData
    case multipleSources
}

enum HealthMetricSummaryCalculator {
    static func summarize(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> HealthMetricSummaryResult {
        let matching = samples.filter { $0.metricType == metric }
        guard !matching.isEmpty else { return .noData }

        switch metric {
        case .stepCount, .walkingRunningDistance, .flightsClimbed:
            return aggregate(
                metric: metric,
                samples: matching.filter {
                    calendar.isDate($0.endDate, inSameDayAs: referenceDate)
                },
                prefersAppleDevices: true
            )
        case .sleepDuration:
            return aggregate(
                metric: metric,
                samples: matching.filter {
                    calendar.isDate($0.endDate, inSameDayAs: referenceDate)
                },
                prefersAppleDevices: true
            )
        case .restingHeartRate, .heartRateVariability, .heartRate,
             .respiratoryRate, .oxygenSaturation, .wristTemperature,
             .walkingSpeed, .walkingStepLength, .vo2Max:
            guard let latest = matching.max(by: { $0.endDate < $1.endDate }) else {
                return .noData
            }
            return .value(HealthMetricSummary(
                metric: metric,
                value: latest.value,
                unit: latest.unit,
                date: latest.endDate,
                sourceName: latest.source.sourceName
            ))
        case .activeEnergy, .exerciseDuration, .standHours:
            return aggregate(
                metric: metric,
                samples: matching.filter {
                    calendar.isDate($0.endDate, inSameDayAs: referenceDate)
                },
                prefersAppleDevices: true
            )
        }
    }

    private static func aggregate(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        prefersAppleDevices: Bool = false
    ) -> HealthMetricSummaryResult {
        guard !samples.isEmpty else { return .noData }
        let selectedSamples: [HealthMetricSample]
        if prefersAppleDevices {
            guard let preferred = PreferredHealthMetricSourceSelector.samples(
                from: samples
            ) else {
                return .multipleSources
            }
            selectedSamples = preferred
        } else {
            guard Set(samples.map(\.source)).count == 1 else {
                return .multipleSources
            }
            selectedSamples = samples
        }
        guard let source = selectedSamples.first?.source else {
            return .multipleSources
        }
        return .value(HealthMetricSummary(
            metric: metric,
            value: selectedSamples.reduce(0) { $0 + $1.value },
            unit: metric.expectedUnit,
            date: selectedSamples.map(\.endDate).max() ?? selectedSamples[0].endDate,
            sourceName: source.displayName
        ))
    }
}

enum PreferredHealthMetricSourceSelector {
    static func samples(
        from samples: [HealthMetricSample]
    ) -> [HealthMetricSample]? {
        guard !samples.isEmpty else { return nil }
        let groups = Dictionary(grouping: samples, by: \.source)
        guard let bestCategory = groups.keys.map(\.category).min(by: {
            $0.rawValue < $1.rawValue
        }) else {
            return nil
        }
        let preferredGroups = groups.filter { source, _ in
            source.category == bestCategory
        }
        if bestCategory == .other, preferredGroups.count > 1 {
            return nil
        }
        return preferredGroups.max { first, second in
            let firstLatest = first.value.map(\.endDate).max() ?? .distantPast
            let secondLatest = second.value.map(\.endDate).max() ?? .distantPast
            if firstLatest != secondLatest {
                return firstLatest < secondLatest
            }
            return first.value.count < second.value.count
        }?.value
    }
}

enum HealthTrendWindow: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case twentyEightDays = 28

    var id: Int { rawValue }
    var title: String { "\(rawValue) 天" }
}

struct HealthMetricDailyPoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let value: Double
    let unit: HealthMetricUnit
}

enum HealthTrendChartCoverage: Equatable, Sendable {
    case noData
    case partial(validDayCount: Int, expectedDayCount: Int)
    case complete(dayCount: Int)
}

struct HealthTrendChartPresentation: Equatable, Sendable {
    let points: [HealthMetricDailyPoint]
    let expectedDayCount: Int

    var coverage: HealthTrendChartCoverage {
        guard !points.isEmpty else { return .noData }
        if points.count >= expectedDayCount {
            return .complete(dayCount: expectedDayCount)
        }
        return .partial(
            validDayCount: points.count,
            expectedDayCount: expectedDayCount
        )
    }

    var yDomain: ClosedRange<Double> {
        guard
            let minimum = points.map(\.value).min(),
            let maximum = points.map(\.value).max()
        else {
            return 0...1
        }
        let span = maximum - minimum
        let padding = span > 0 ? span * 0.08 : max(abs(maximum) * 0.1, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    var hasWideValueRange: Bool {
        guard points.count >= 3 else { return false }
        let values = points.map(\.value).sorted()
        let medianValue = median(values)
        let deviations = values.map { abs($0 - medianValue) }.sorted()
        let medianAbsoluteDeviation = median(deviations)
        let minimumReference = max(abs(medianValue) * 0.05, 0.000_1)
        let robustReference = max(medianAbsoluteDeviation, minimumReference)
        let largestDeviation = deviations.last ?? 0
        return largestDeviation > robustReference * 6
    }

    var contextText: String {
        let rangeContext = hasWideValueRange
            ? " 数值跨度较大，图表已完整保留；这本身不代表健康异常。"
            : ""
        switch coverage {
        case .noData:
            return "当前范围没有可安全绘制的每日记录，缺失值不会补成 0。"
        case let .partial(validDayCount, expectedDayCount):
            return "仅有 \(validDayCount)/\(expectedDayCount) 个有效日；空缺日期未补零，点位连线不代表其间每天都有记录。\(rangeContext)"
        case let .complete(dayCount):
            return "已显示 \(dayCount)/\(dayCount) 个有效日。\(rangeContext)"
        }
    }

    private func median(_ sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}

enum HealthMetricDailySeriesCalculator {
    static func points(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        endingAt endDate: Date,
        window: HealthTrendWindow,
        calendar: Calendar = .current
    ) -> [HealthMetricDailyPoint] {
        let finalDay = calendar.startOfDay(for: endDate)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(window.rawValue - 1),
            to: finalDay
        ) else {
            return []
        }
        let matching = samples.filter { sample in
            guard sample.metricType == metric else { return false }
            let day = calendar.startOfDay(for: sample.endDate)
            return day >= firstDay && day <= finalDay
        }
        let grouped = Dictionary(grouping: matching) {
            calendar.startOfDay(for: $0.endDate)
        }

        return grouped.compactMap { day, daySamples in
            let selectedSamples: [HealthMetricSample]
            if metric == .stepCount || metric == .sleepDuration || metric == .activeEnergy
                || metric == .exerciseDuration || metric == .standHours
                || metric == .walkingRunningDistance || metric == .flightsClimbed {
                guard let preferred = PreferredHealthMetricSourceSelector.samples(
                    from: daySamples
                ) else {
                    return nil
                }
                selectedSamples = preferred
            } else {
                guard Set(daySamples.map(\.source)).count == 1 else {
                    return nil
                }
                selectedSamples = daySamples
            }
            let value: Double
            switch metric {
            case .stepCount, .sleepDuration, .activeEnergy, .exerciseDuration,
                 .standHours, .walkingRunningDistance, .flightsClimbed:
                value = selectedSamples.reduce(0) { $0 + $1.value }
            case .restingHeartRate, .heartRateVariability, .heartRate,
                 .respiratoryRate, .oxygenSaturation, .wristTemperature,
                 .walkingSpeed, .walkingStepLength, .vo2Max:
                guard let latest = selectedSamples.max(by: { $0.endDate < $1.endDate }) else {
                    return nil
                }
                value = latest.value
            }
            return HealthMetricDailyPoint(
                date: day,
                value: value,
                unit: metric.expectedUnit
            )
        }
        .sorted { $0.date < $1.date }
    }
}
