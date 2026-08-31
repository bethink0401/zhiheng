import Foundation

enum InsightsHRVLevel: Equatable, Sendable {
    case belowPersonalRange
    case nearPersonalRange
    case abovePersonalRange
}

enum InsightsHRVPresentation: Equatable, Sendable {
    case unavailable
    case learning(
        current: HealthMetricSummary?,
        validDayCount: Int,
        requiredDayCount: Int,
        points: [HealthMetricDailyPoint]
    )
    case available(
        current: HealthMetricSummary,
        baseline: HealthMetricBaseline,
        level: InsightsHRVLevel,
        gaugePosition: Double,
        points: [HealthMetricDailyPoint]
    )

    var current: HealthMetricSummary? {
        switch self {
        case .unavailable:
            nil
        case let .learning(current, _, _, _):
            current
        case let .available(current, _, _, _, _):
            current
        }
    }

    var points: [HealthMetricDailyPoint] {
        switch self {
        case .unavailable:
            []
        case let .learning(_, _, _, points),
             let .available(_, _, _, _, points):
            points
        }
    }

    var title: String {
        switch self {
        case .unavailable:
            "暂无 HRV 记录"
        case .learning:
            "正在了解你的状态"
        case let .available(_, _, level, _, _):
            switch level {
            case .belowPersonalRange: "状态偏低"
            case .nearPersonalRange: "状态正常"
            case .abovePersonalRange: "状态较好"
            }
        }
    }

    var explanation: String {
        switch self {
        case .unavailable:
            "今天还没有 HRV 记录。先听听自己的感受，按舒服的节奏安排此刻。"
        case .learning:
            "正在慢慢认识你的日常节奏。今天先以自己的感受为主，安心积累更多记录。"
        case let .available(_, _, level, _, _):
            switch level {
            case .belowPersonalRange:
                "此刻的 HRV 状态稍显紧绷。先把节奏放慢一点，照顾好休息，活动时以身体感受为准。"
            case .nearPersonalRange:
                "此刻的 HRV 状态平稳，身体节奏与平时相近。按自己的感受，安心继续今天的安排吧。"
            case .abovePersonalRange:
                "太棒了，此刻的 HRV 状态显得格外舒展。带着这份轻松感开启今天，也记得继续听从身体感受。"
            }
        }
    }

    var gaugePosition: Double? {
        guard case let .available(_, _, _, gaugePosition, _) = self else {
            return nil
        }
        return gaugePosition
    }

    var baselineRange: ClosedRange<Double>? {
        guard case let .available(_, baseline, _, _, _) = self else {
            return nil
        }
        return (baseline.medianValue * 0.85)...(baseline.medianValue * 1.15)
    }

    var visualState: HRVVisualState {
        switch self {
        case .unavailable:
            .unavailable
        case .learning:
            .learning
        case let .available(_, _, level, _, _):
            switch level {
            case .belowPersonalRange: .belowPersonalRange
            case .nearPersonalRange: .nearPersonalRange
            case .abovePersonalRange: .abovePersonalRange
            }
        }
    }
}

enum InsightsBodyMetricKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case restingHeartRate
    case sleepingHeartRate
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case walkingRunningDistance
    case flightsClimbed
    case walkingSpeed
    case walkingStepLength
    case vo2Max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: "静息心率"
        case .sleepingHeartRate: "睡眠时心率"
        case .respiratoryRate: "呼吸频率"
        case .oxygenSaturation: "血氧"
        case .wristTemperature: "睡眠腕温"
        case .walkingRunningDistance: "步行与跑步距离"
        case .flightsClimbed: "爬楼层数"
        case .walkingSpeed: "步行速度"
        case .walkingStepLength: "步长"
        case .vo2Max: "心肺适能"
        }
    }

    var metric: HealthMetricType {
        switch self {
        case .restingHeartRate: .restingHeartRate
        case .sleepingHeartRate: .heartRate
        case .respiratoryRate: .respiratoryRate
        case .oxygenSaturation: .oxygenSaturation
        case .wristTemperature: .wristTemperature
        case .walkingRunningDistance: .walkingRunningDistance
        case .flightsClimbed: .flightsClimbed
        case .walkingSpeed: .walkingSpeed
        case .walkingStepLength: .walkingStepLength
        case .vo2Max: .vo2Max
        }
    }
}

enum InsightsMetricReferenceState: Equatable, Sendable {
    case belowPersonalRange
    case nearPersonalRange
    case abovePersonalRange
    case learning
    case unavailable

    var title: String {
        switch self {
        case .belowPersonalRange: "状态偏低"
        case .nearPersonalRange: "状态正常"
        case .abovePersonalRange: "状态偏高"
        case .learning: "建立基线中"
        case .unavailable: "暂无记录"
        }
    }
}

struct InsightsBodyMetricPresentation: Identifiable, Equatable, Sendable {
    var id: InsightsBodyMetricKind { kind }
    let kind: InsightsBodyMetricKind
    let currentValue: Double?
    let unit: HealthMetricUnit
    let date: Date?
    let points: [HealthMetricDailyPoint]
    let changeFromPrevious: Double?
    let referenceState: InsightsMetricReferenceState
}

struct InsightsHRVChartPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
}

struct InsightsHRVIntradayChartPresentation: Equatable, Sendable {
    let interval: DateInterval
    let points: [InsightsHRVChartPoint]
}

struct InsightsDashboardPresentation: Equatable, Sendable {
    let hrv: InsightsHRVPresentation
    let hrvIntradayChart: InsightsHRVIntradayChartPresentation
    let bodyMetrics: [InsightsBodyMetricPresentation]
}

struct InsightsDashboardLayout: Codable, Equatable, Sendable {
    private(set) var visibleMetrics: [InsightsBodyMetricKind]

    static let standard = InsightsDashboardLayout(
        visibleMetrics: InsightsBodyMetricKind.allCases
    )

    init(visibleMetrics: [InsightsBodyMetricKind]) {
        var seen = Set<InsightsBodyMetricKind>()
        self.visibleMetrics = visibleMetrics.filter { seen.insert($0).inserted }
    }

    mutating func setVisible(_ visible: Bool, metric: InsightsBodyMetricKind) {
        if visible {
            guard !visibleMetrics.contains(metric) else { return }
            visibleMetrics.append(metric)
        } else {
            visibleMetrics.removeAll { $0 == metric }
        }
    }

}

enum InsightsDashboardPresentationFactory {
    static func make(
        snapshot: HealthDataSnapshot,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> InsightsDashboardPresentation {
        InsightsDashboardPresentation(
            hrv: makeHRV(
                snapshot: snapshot,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            hrvIntradayChart: makeHRVIntradayChart(
                snapshot: snapshot,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            bodyMetrics: InsightsBodyMetricKind.allCases.map {
                makeMetric(
                    kind: $0,
                    snapshot: snapshot,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        )
    }

    private static func makeHRVIntradayChart(
        snapshot: HealthDataSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> InsightsHRVIntradayChartPresentation {
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? referenceDate.addingTimeInterval(24 * 60 * 60)
        guard case let .available(samples) = snapshot[.heartRateVariability] else {
            return InsightsHRVIntradayChartPresentation(
                interval: DateInterval(start: start, end: end),
                points: []
            )
        }
        let points = samples
            .filter {
                $0.metricType == .heartRateVariability
                    && $0.endDate >= start
                    && $0.endDate < end
                    && $0.endDate <= referenceDate
            }
            .sorted { $0.endDate < $1.endDate }
            .map {
                InsightsHRVChartPoint(
                    id: $0.id,
                    date: $0.endDate,
                    value: $0.value
                )
            }
        return InsightsHRVIntradayChartPresentation(
            interval: DateInterval(start: start, end: end),
            points: points
        )
    }

    private static func makeHRV(
        snapshot: HealthDataSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> InsightsHRVPresentation {
        guard case let .available(samples) = snapshot[.heartRateVariability] else {
            return .unavailable
        }
        let current: HealthMetricSummary?
        if case let .value(summary) = HealthMetricSummaryCalculator.summarize(
            metric: .heartRateVariability,
            samples: samples,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            current = summary
        } else {
            current = nil
        }
        let points = HealthMetricDailySeriesCalculator.points(
            metric: .heartRateVariability,
            samples: samples,
            endingAt: referenceDate,
            window: .sevenDays,
            calendar: calendar
        )
        guard let baselineEnd = priorDayEnd(referenceDate, calendar: calendar) else {
            return .learning(
                current: current,
                validDayCount: 0,
                requiredDayCount: HealthDataQualityThresholds.baselineMinimumValidDays,
                points: points
            )
        }
        switch HealthMetricBaselineEngine.calculate(
            metric: .heartRateVariability,
            samples: samples,
            endingAt: baselineEnd,
            calendar: calendar
        ) {
        case let .insufficientData(validDayCount, requiredDayCount, _):
            return .learning(
                current: current,
                validDayCount: validDayCount,
                requiredDayCount: requiredDayCount,
                points: points
            )
        case let .available(baseline):
            guard let current, baseline.medianValue > 0 else {
                return .learning(
                    current: current,
                    validDayCount: baseline.validDayCount,
                    requiredDayCount: HealthDataQualityThresholds.baselineMinimumValidDays,
                    points: points
                )
            }
            let relativeDifference = (current.value - baseline.medianValue)
                / baseline.medianValue
            let level: InsightsHRVLevel
            if relativeDifference < -0.15 {
                level = .belowPersonalRange
            } else if relativeDifference > 0.15 {
                level = .abovePersonalRange
            } else {
                level = .nearPersonalRange
            }
            return .available(
                current: current,
                baseline: baseline,
                level: level,
                gaugePosition: min(max((relativeDifference + 0.30) / 0.60, 0), 1),
                points: points
            )
        }
    }

    private static func makeMetric(
        kind: InsightsBodyMetricKind,
        snapshot: HealthDataSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> InsightsBodyMetricPresentation {
        if kind == .sleepingHeartRate {
            return makeSleepingHeartRate(
                snapshot: snapshot,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        let metric = kind.metric
        guard case let .available(samples) = snapshot[metric] else {
            return InsightsBodyMetricPresentation(
                kind: kind,
                currentValue: nil,
                unit: metric.expectedUnit,
                date: nil,
                points: [],
                changeFromPrevious: nil,
                referenceState: .unavailable
            )
        }
        let points = HealthMetricDailySeriesCalculator.points(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            window: .sevenDays,
            calendar: calendar
        )
        let summary: HealthMetricSummary?
        if case let .value(value) = HealthMetricSummaryCalculator.summarize(
            metric: metric,
            samples: samples,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            summary = value
        } else {
            summary = nil
        }
        let baseline = personalBaseline(
            metric: metric,
            samples: samples,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return InsightsBodyMetricPresentation(
            kind: kind,
            currentValue: summary?.value,
            unit: metric.expectedUnit,
            date: summary?.date,
            points: points,
            changeFromPrevious: previousChange(points),
            referenceState: referenceState(
                current: summary?.value,
                baseline: baseline
            )
        )
    }

    private static func makeSleepingHeartRate(
        snapshot: HealthDataSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) -> InsightsBodyMetricPresentation {
        guard
            case let .available(sleepSamples) = snapshot[.sleepDuration],
            case let .available(heartSamples) = snapshot[.heartRate]
        else {
            return InsightsBodyMetricPresentation(
                kind: .sleepingHeartRate,
                currentValue: nil,
                unit: .beatsPerMinute,
                date: nil,
                points: [],
                changeFromPrevious: nil,
                referenceState: .unavailable
            )
        }
        let allPoints = nightlyHeartRatePoints(
            sleepSamples: sleepSamples,
            heartSamples: heartSamples,
            referenceDate: referenceDate,
            dayCount: HealthDataQualityThresholds.baselineExpectedDays,
            calendar: calendar
        )
        let sevenDayStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.shortTermExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? .distantPast
        let recentPoints = allPoints.filter { $0.date >= sevenDayStart }
        let current = recentPoints.last
        let baselinePoints = allPoints.filter {
            $0.date < calendar.startOfDay(for: referenceDate)
        }
        let baseline = personalReference(values: baselinePoints.map(\.value))
        return InsightsBodyMetricPresentation(
            kind: .sleepingHeartRate,
            currentValue: current?.value,
            unit: .beatsPerMinute,
            date: current?.date,
            points: recentPoints,
            changeFromPrevious: previousChange(recentPoints),
            referenceState: referenceState(
                current: current?.value,
                reference: baseline
            )
        )
    }

    private static func nightlyHeartRatePoints(
        sleepSamples: [HealthMetricSample],
        heartSamples: [HealthMetricSample],
        referenceDate: Date,
        dayCount: Int,
        calendar: Calendar
    ) -> [HealthMetricDailyPoint] {
        let finalDay = calendar.startOfDay(for: referenceDate)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: finalDay
        ) else { return [] }
        let groupedSleep = Dictionary(grouping: sleepSamples.filter {
            let day = calendar.startOfDay(for: $0.endDate)
            return day >= firstDay && day <= finalDay
        }) {
            calendar.startOfDay(for: $0.endDate)
        }
        return groupedSleep.compactMap { day, samples in
            guard
                let selectedSleep = PreferredHealthMetricSourceSelector.samples(from: samples),
                let start = selectedSleep.map(\.startDate).min(),
                let end = selectedSleep.map(\.endDate).max()
            else { return nil }
            let matchingHeart = heartSamples.filter {
                $0.endDate >= start && $0.startDate <= end
            }
            guard
                let selectedHeart = PreferredHealthMetricSourceSelector.samples(
                    from: matchingHeart
                ),
                !selectedHeart.isEmpty
            else { return nil }
            return HealthMetricDailyPoint(
                date: day,
                value: selectedHeart.map(\.value).reduce(0, +)
                    / Double(selectedHeart.count),
                unit: .beatsPerMinute
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func personalBaseline(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        referenceDate: Date,
        calendar: Calendar
    ) -> HealthMetricBaseline? {
        guard
            let baselineEnd = priorDayEnd(referenceDate, calendar: calendar),
            case let .available(baseline) = HealthMetricBaselineEngine.calculate(
                metric: metric,
                samples: samples,
                endingAt: baselineEnd,
                calendar: calendar
            )
        else { return nil }
        return baseline
    }

    private static func priorDayEnd(
        _ referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            byAdding: .second,
            value: -1,
            to: calendar.startOfDay(for: referenceDate)
        )
    }

    private static func previousChange(_ points: [HealthMetricDailyPoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        return points[points.count - 1].value - points[points.count - 2].value
    }

    private static func referenceState(
        current: Double?,
        baseline: HealthMetricBaseline?
    ) -> InsightsMetricReferenceState {
        guard let current else { return .unavailable }
        guard let baseline, baseline.medianValue > 0 else { return .learning }
        let difference = (current - baseline.medianValue) / baseline.medianValue
        if difference < -0.15 { return .belowPersonalRange }
        if difference > 0.15 { return .abovePersonalRange }
        return .nearPersonalRange
    }

    private static func referenceState(
        current: Double?,
        reference: Double?
    ) -> InsightsMetricReferenceState {
        guard let current else { return .unavailable }
        guard let reference, reference > 0 else { return .learning }
        let difference = (current - reference) / reference
        if difference < -0.15 { return .belowPersonalRange }
        if difference > 0.15 { return .abovePersonalRange }
        return .nearPersonalRange
    }

    private static func personalReference(values: [Double]) -> Double? {
        guard values.count >= HealthDataQualityThresholds.baselineMinimumValidDays else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
