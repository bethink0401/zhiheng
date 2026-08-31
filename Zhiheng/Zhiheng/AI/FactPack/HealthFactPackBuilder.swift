import Foundation

enum HealthFactPackBuilder {
    static let includedMetrics: [HealthMetricType] = HealthMetricType.allCases

    static func build(
        snapshot: HealthDataSnapshot,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> HealthFactPack {
        let historyStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.inventoryExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        let shortTermStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.shortTermExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        let shortTermInterval = DateInterval(
            start: shortTermStart,
            end: referenceDate
        )

        var facts = [HealthFactMetric]()
        var unavailable = [HealthFactUnavailableMetric]()

        for metric in includedMetrics {
            switch snapshot[metric] {
            case let .available(samples):
                let quality = try? HealthDataQualityCalculator.evaluate(
                    metric: metric,
                    samples: samples,
                    interval: shortTermInterval,
                    calendar: calendar
                )
                let baselineResult = HealthMetricBaselineEngine.calculate(
                    metric: metric,
                    samples: samples,
                    endingAt: referenceDate,
                    calendar: calendar
                )
                facts.append(HealthFactMetric(
                    metric: metric,
                    current: currentValue(
                        metric: metric,
                        samples: samples,
                        referenceDate: referenceDate,
                        calendar: calendar
                    ),
                    shortTermQuality: HealthFactDataQuality(
                        expectedDayCount: quality?.expectedDayCount
                            ?? HealthDataQualityThresholds.shortTermExpectedDays,
                        validDayCount: quality?.validDayCount ?? 0,
                        coverageRatio: quality?.coverageRatio ?? 0,
                        longestMissingDayStreak: quality?.longestMissingDayStreak
                            ?? HealthDataQualityThresholds.shortTermExpectedDays,
                        supportsObservation: quality?.supportsShortTermObservation
                            ?? false
                    ),
                    baseline: baseline(from: baselineResult)
                ))
            case .accessNotRequested:
                unavailable.append(.init(
                    metric: metric,
                    reason: .accessNotRequested
                ))
            case .healthDataUnavailable:
                unavailable.append(.init(
                    metric: metric,
                    reason: .healthDataUnavailable
                ))
            case .noVisibleData, .none:
                unavailable.append(.init(
                    metric: metric,
                    reason: .noVisibleData
                ))
            case .failed:
                unavailable.append(.init(
                    metric: metric,
                    reason: .queryFailed
                ))
            }
        }

        return HealthFactPack(
            generatedAt: referenceDate,
            rangeStart: historyStart,
            rangeEnd: referenceDate,
            dataMode: dataMode,
            metrics: facts,
            unavailableMetrics: unavailable
        )
    }

    static func empty(
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> HealthFactPack {
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.inventoryExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        return HealthFactPack(
            generatedAt: referenceDate,
            rangeStart: rangeStart,
            rangeEnd: referenceDate,
            dataMode: dataMode,
            metrics: [],
            unavailableMetrics: includedMetrics.map {
                HealthFactUnavailableMetric(metric: $0, reason: .noVisibleData)
            }
        )
    }

    private static func currentValue(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        referenceDate: Date,
        calendar: Calendar
    ) -> HealthFactCurrentValue? {
        guard case let .value(summary) = HealthMetricSummaryCalculator.summarize(
            metric: metric,
            samples: samples,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            return nil
        }
        return HealthFactCurrentValue(
            value: summary.value,
            unit: summary.unit,
            recordedAt: summary.date
        )
    }

    private static func baseline(
        from result: HealthMetricBaselineResult
    ) -> HealthFactBaseline? {
        guard case let .available(value) = result else { return nil }
        return HealthFactBaseline(
            medianValue: value.medianValue,
            medianAbsoluteDeviation: value.medianAbsoluteDeviation,
            unit: value.unit,
            validDayCount: value.validDayCount,
            expectedDayCount: value.expectedDayCount
        )
    }
}
