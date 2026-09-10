import Foundation

struct TodayDashboardMetricValue: Equatable, Sendable {
    let metric: HealthMetricType
    let value: Double
    let unit: HealthMetricUnit
    let date: Date
    let sourceName: String
}

struct TodayDashboardDateStatus: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let goalPercentage: Int?
    let activityRings: TodayActivityRingProgress
}

struct TodayActivityRingProgress: Equatable, Sendable {
    let activeEnergy: Double?
    let exercise: Double?
    let stand: Double?

    static let unavailable = TodayActivityRingProgress(
        activeEnergy: nil,
        exercise: nil,
        stand: nil
    )
}

struct TodayHourlyBar: Identifiable, Equatable, Sendable {
    var id: Int { hour }
    let hour: Int
    let value: Double
}

struct TodaySleepSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let stage: HealthSleepStage
}

enum TodayLoadReference: Equatable, Sendable {
    case insufficient(currentHRV: TodayDashboardMetricValue?)
    case available(
        currentHRV: TodayDashboardMetricValue,
        baseline: HealthMetricBaseline,
        relativeDifference: Double,
        level: Level
    )

    enum Level: String, Equatable, Sendable {
        case belowPersonalRange
        case nearPersonalRange
        case abovePersonalRange
    }

    var visualState: HRVVisualState {
        switch self {
        case let .insufficient(currentHRV):
            currentHRV == nil ? .unavailable : .learning
        case let .available(_, _, _, level):
            switch level {
            case .belowPersonalRange: .belowPersonalRange
            case .nearPersonalRange: .nearPersonalRange
            case .abovePersonalRange: .abovePersonalRange
            }
        }
    }
}

struct TodayRecoveryComponent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let score: Double
}

enum TodayTrainingReadiness: Equatable, Sendable {
    case insufficient(availableComponentCount: Int, requiredComponentCount: Int)
    case available(score: Int, components: [TodayRecoveryComponent], advice: String)
}

struct TodayNightVital: Identifiable, Equatable, Sendable {
    var id: HealthMetricType { metric }
    let metric: HealthMetricType
    let value: Double?
    let unit: HealthMetricUnit
}

struct TodayNightSummary: Equatable, Sendable {
    let title: String
    let detail: String
    let availableVitalCount: Int
}

struct TodayImportantChange: Equatable, Sendable {
    let metric: HealthMetricType
    let currentMedian: Double
    let whatChanged: String
    let actionText: String
    let relativeDifference: Double

    var metricTitle: String {
        switch metric {
        case .sleepDuration: "睡眠时长"
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "静息心率"
        case .stepCount: "步数"
        case .activeEnergy: "活动能量"
        case .exerciseDuration: "锻炼时长"
        default: metric.rawValue
        }
    }
}

struct TodayDashboardPresentation: Equatable, Sendable {
    let selectedDate: Date
    let dateStatuses: [TodayDashboardDateStatus]
    let goalProgress: TodayGoalProgressResult
    let encouragement: TodayActivityEncouragement
    let values: [HealthMetricType: TodayDashboardMetricValue]
    let stepHourlyBars: [TodayHourlyBar]
    let energyHourlyBars: [TodayHourlyBar]
    let sleepSegments: [TodaySleepSegment]
    let importantChange: TodayImportantChange?
    let loadReference: TodayLoadReference
    let trainingReadiness: TodayTrainingReadiness
    let nightVitals: [TodayNightVital]
    let nightSummary: TodayNightSummary
}

enum TodayDashboardPresentationFactory {
    static func make(
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        today: Date,
        dateWindowEnd: Date? = nil,
        goals: TodayDashboardGoals,
        calendar: Calendar = .current
    ) -> TodayDashboardPresentation {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let values = Dictionary(uniqueKeysWithValues: HealthMetricType.allCases.compactMap { metric in
            metricValue(
                metric: metric,
                snapshot: snapshot,
                date: selectedDay,
                calendar: calendar
            ).map { (metric, $0) }
        })
        let selectedGoalProgress = goalProgress(
            values: values,
            goals: goals
        )
        let dates = TodayDashboardDateWindow.sevenDays(
            endingAt: dateWindowEnd ?? today,
            calendar: calendar
        )
        let dateStatuses = dates.map { date in
            let dateValues = Dictionary(uniqueKeysWithValues: HealthMetricType.allCases.compactMap { metric in
                metricValue(
                    metric: metric,
                    snapshot: snapshot,
                    date: date,
                    calendar: calendar
                ).map { (metric, $0) }
            })
            let percentage: Int?
            if case let .available(progress) = goalProgress(values: dateValues, goals: goals) {
                percentage = progress.percentage
            } else {
                percentage = nil
            }
            return TodayDashboardDateStatus(
                date: date,
                goalPercentage: percentage,
                activityRings: activityRings(values: dateValues, goals: goals)
            )
        }
        let night = nightContext(
            snapshot: snapshot,
            date: selectedDay,
            calendar: calendar
        )
        let nightVitals = makeNightVitals(
            snapshot: snapshot,
            nightInterval: night.interval,
            sleepHours: night.sleepHours
        )
        let loadReference = makeLoadReference(
            snapshot: snapshot,
            current: values[.heartRateVariability],
            selectedDate: selectedDay,
            calendar: calendar
        )
        let readiness = makeTrainingReadiness(
            snapshot: snapshot,
            values: values,
            nightVitals: nightVitals,
            goals: goals,
            selectedDate: selectedDay,
            calendar: calendar
        )

        return TodayDashboardPresentation(
            selectedDate: selectedDay,
            dateStatuses: dateStatuses,
            goalProgress: selectedGoalProgress,
            encouragement: TodayActivityEncouragementFactory.make(
                from: selectedGoalProgress,
                isToday: calendar.isDate(selectedDay, inSameDayAs: today)
            ),
            values: values,
            stepHourlyBars: hourlyBars(
                metric: .stepCount,
                snapshot: snapshot,
                date: selectedDay,
                calendar: calendar
            ),
            energyHourlyBars: hourlyBars(
                metric: .activeEnergy,
                snapshot: snapshot,
                date: selectedDay,
                calendar: calendar
            ),
            sleepSegments: night.segments,
            importantChange: TodayImportantChangeSelector.select(
                snapshot: snapshot,
                selectedDate: selectedDay,
                calendar: calendar
            ),
            loadReference: loadReference,
            trainingReadiness: readiness,
            nightVitals: nightVitals,
            nightSummary: makeNightSummary(
                vitals: nightVitals,
                readiness: readiness
            )
        )
    }

    private static func metricValue(
        metric: HealthMetricType,
        snapshot: HealthDataSnapshot,
        date: Date,
        calendar: Calendar
    ) -> TodayDashboardMetricValue? {
        guard case let .available(samples) = snapshot[metric] else { return nil }
        guard case let .value(summary) = HealthMetricSummaryCalculator.summarize(
            metric: metric,
            samples: samples,
            referenceDate: date,
            calendar: calendar
        ) else { return nil }
        return TodayDashboardMetricValue(
            metric: metric,
            value: summary.value,
            unit: summary.unit,
            date: summary.date,
            sourceName: summary.sourceName
        )
    }

    private static func goalProgress(
        values: [HealthMetricType: TodayDashboardMetricValue],
        goals: TodayDashboardGoals
    ) -> TodayGoalProgressResult {
        TodayGoalProgressCalculator.calculate(
            goals: goals,
            actuals: TodayGoalActuals(values: [
                .steps: values[.stepCount]?.value,
                .sleep: values[.sleepDuration]?.value,
                .activeEnergy: values[.activeEnergy]?.value,
                .exercise: values[.exerciseDuration]?.value,
                .stand: values[.standHours]?.value
            ].compactMapValues { $0 })
        )
    }

    private static func hourlyBars(
        metric: HealthMetricType,
        snapshot: HealthDataSnapshot,
        date: Date,
        calendar: Calendar
    ) -> [TodayHourlyBar] {
        guard case let .available(samples) = snapshot[metric] else { return [] }
        let daySamples = samples.filter {
            calendar.isDate($0.endDate, inSameDayAs: date)
        }
        guard let selected = PreferredHealthMetricSourceSelector.samples(from: daySamples) else {
            return []
        }
        var values = Array(repeating: 0.0, count: 24)
        for sample in selected {
            let hour = min(max(calendar.component(.hour, from: sample.endDate), 0), 23)
            values[hour] += sample.value
        }
        return values.enumerated().map { TodayHourlyBar(hour: $0.offset, value: $0.element) }
    }

    private static func nightContext(
        snapshot: HealthDataSnapshot,
        date: Date,
        calendar: Calendar
    ) -> (interval: DateInterval?, sleepHours: Double?, segments: [TodaySleepSegment]) {
        guard case let .available(samples) = snapshot[.sleepDuration] else {
            return (nil, nil, [])
        }
        let matchingNightSamples = samples.filter {
            calendar.isDate($0.endDate, inSameDayAs: date)
        }
        guard let nightSamples = PreferredHealthMetricSourceSelector.samples(
            from: matchingNightSamples
        ) else {
            return (nil, nil, [])
        }
        guard
            !nightSamples.isEmpty,
            let start = nightSamples.map(\.startDate).min(),
            let end = nightSamples.map(\.endDate).max()
        else {
            return (nil, nil, [])
        }
        return (
            DateInterval(start: start, end: end),
            nightSamples.reduce(0) { $0 + $1.value },
            nightSamples.map {
                TodaySleepSegment(
                    id: $0.id,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    stage: $0.sleepStage ?? .asleepUnspecified
                )
            }.sorted { $0.startDate < $1.startDate }
        )
    }

    private static func activityRings(
        values: [HealthMetricType: TodayDashboardMetricValue],
        goals: TodayDashboardGoals
    ) -> TodayActivityRingProgress {
        func ratio(_ value: Double?, _ goal: Double) -> Double? {
            guard let value, goal > 0 else { return nil }
            return min(max(value / goal, 0), 1)
        }
        return TodayActivityRingProgress(
            activeEnergy: ratio(values[.activeEnergy]?.value, goals.activeEnergyKilocalories),
            exercise: ratio(values[.exerciseDuration]?.value, goals.exerciseMinutes),
            stand: ratio(values[.standHours]?.value, goals.standHours)
        )
    }

    private static func makeNightVitals(
        snapshot: HealthDataSnapshot,
        nightInterval: DateInterval?,
        sleepHours: Double?
    ) -> [TodayNightVital] {
        var result = [TodayNightVital(
            metric: .sleepDuration,
            value: sleepHours,
            unit: .hours
        )]
        for metric in [
            HealthMetricType.heartRate,
            .wristTemperature,
            .respiratoryRate,
            .oxygenSaturation
        ] {
            let value: Double?
            if
                let nightInterval,
                case let .available(samples) = snapshot[metric]
            {
                let matching = samples.filter {
                    $0.endDate >= nightInterval.start && $0.startDate <= nightInterval.end
                }
                if let selected = PreferredHealthMetricSourceSelector.samples(from: matching),
                   !selected.isEmpty {
                    value = selected.map(\.value).reduce(0, +) / Double(selected.count)
                } else {
                    value = nil
                }
            } else {
                value = nil
            }
            result.append(TodayNightVital(
                metric: metric,
                value: value,
                unit: metric.expectedUnit
            ))
        }
        return result
    }

    private static func makeLoadReference(
        snapshot: HealthDataSnapshot,
        current: TodayDashboardMetricValue?,
        selectedDate: Date,
        calendar: Calendar
    ) -> TodayLoadReference {
        guard
            let current,
            case let .available(samples) = snapshot[.heartRateVariability],
            let baselineEnd = calendar.date(byAdding: .second, value: -1, to: selectedDate),
            case let .available(baseline) = HealthMetricBaselineEngine.calculate(
                metric: .heartRateVariability,
                samples: samples,
                endingAt: baselineEnd,
                calendar: calendar
            ),
            baseline.medianValue > 0
        else {
            return .insufficient(currentHRV: current)
        }
        let difference = (current.value - baseline.medianValue) / baseline.medianValue
        let level: TodayLoadReference.Level
        if difference < -0.15 {
            level = .belowPersonalRange
        } else if difference > 0.15 {
            level = .abovePersonalRange
        } else {
            level = .nearPersonalRange
        }
        return .available(
            currentHRV: current,
            baseline: baseline,
            relativeDifference: difference,
            level: level
        )
    }

    private static func makeTrainingReadiness(
        snapshot: HealthDataSnapshot,
        values: [HealthMetricType: TodayDashboardMetricValue],
        nightVitals: [TodayNightVital],
        goals: TodayDashboardGoals,
        selectedDate: Date,
        calendar: Calendar
    ) -> TodayTrainingReadiness {
        var components = [TodayRecoveryComponent]()
        if let sleep = values[.sleepDuration] {
            components.append(TodayRecoveryComponent(
                id: "sleep",
                title: "睡眠目标",
                score: min(max(sleep.value / goals.sleepHours, 0), 1) * 100
            ))
        }
        appendBaselineRatioComponent(
            id: "hrv",
            title: "HRV",
            metric: .heartRateVariability,
            current: values[.heartRateVariability],
            higherIsBetter: true,
            snapshot: snapshot,
            selectedDate: selectedDate,
            calendar: calendar,
            into: &components
        )
        appendBaselineRatioComponent(
            id: "restingHeartRate",
            title: "静息心率",
            metric: .restingHeartRate,
            current: values[.restingHeartRate],
            higherIsBetter: false,
            snapshot: snapshot,
            selectedDate: selectedDate,
            calendar: calendar,
            into: &components
        )
        for (metric, title) in [
            (HealthMetricType.respiratoryRate, "呼吸频率"),
            (.oxygenSaturation, "血氧"),
            (.wristTemperature, "睡眠腕温")
        ] {
            guard let currentValue = nightVitals.first(where: { $0.metric == metric })?.value else {
                continue
            }
            appendClosenessComponent(
                id: metric.rawValue,
                title: title,
                metric: metric,
                currentValue: currentValue,
                snapshot: snapshot,
                selectedDate: selectedDate,
                calendar: calendar,
                into: &components
            )
        }
        let activityRatios = [
            values[.activeEnergy].map { $0.value / goals.activeEnergyKilocalories },
            values[.exerciseDuration].map { $0.value / goals.exerciseMinutes }
        ].compactMap { $0 }
        if !activityRatios.isEmpty {
            let intensity = activityRatios.reduce(0, +) / Double(activityRatios.count)
            let score = max(0, 100 - abs(intensity - 0.75) * 55)
            components.append(TodayRecoveryComponent(
                id: "activityIntensity",
                title: "活动强度",
                score: min(score, 100)
            ))
        }

        let requiredCount = 4
        guard components.count >= requiredCount else {
            return .insufficient(
                availableComponentCount: components.count,
                requiredComponentCount: requiredCount
            )
        }
        let score = Int((components.map(\.score).reduce(0, +) / Double(components.count)).rounded())
        let advice: String
        switch score {
        case 80...:
            advice = "数据支持按原计划活动；先热身，并以主观感受为准。"
        case 60..<80:
            advice = "更适合轻到中等强度活动，过程中留意疲劳感。"
        default:
            advice = "可优先恢复或选择低强度活动；这不是医学判断。"
        }
        return .available(score: score, components: components, advice: advice)
    }

    private static func appendBaselineRatioComponent(
        id: String,
        title: String,
        metric: HealthMetricType,
        current: TodayDashboardMetricValue?,
        higherIsBetter: Bool,
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        calendar: Calendar,
        into components: inout [TodayRecoveryComponent]
    ) {
        guard
            let current,
            let baseline = baseline(
                metric: metric,
                snapshot: snapshot,
                selectedDate: selectedDate,
                calendar: calendar
            ),
            current.value > 0,
            baseline.medianValue > 0
        else { return }
        let ratio = higherIsBetter
            ? current.value / baseline.medianValue
            : baseline.medianValue / current.value
        components.append(TodayRecoveryComponent(
            id: id,
            title: title,
            score: min(max(ratio, 0.4), 1) * 100
        ))
    }

    private static func appendClosenessComponent(
        id: String,
        title: String,
        metric: HealthMetricType,
        currentValue: Double,
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        calendar: Calendar,
        into components: inout [TodayRecoveryComponent]
    ) {
        guard let baseline = baseline(
            metric: metric,
            snapshot: snapshot,
            selectedDate: selectedDate,
            calendar: calendar
        ) else { return }
        let scale = max(
            baseline.medianAbsoluteDeviation * 1.4826,
            max(abs(baseline.medianValue) * 0.03, 0.1)
        )
        let robustDistance = abs(currentValue - baseline.medianValue) / scale
        components.append(TodayRecoveryComponent(
            id: id,
            title: title,
            score: max(0, 100 - robustDistance * 18)
        ))
    }

    private static func baseline(
        metric: HealthMetricType,
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        calendar: Calendar
    ) -> HealthMetricBaseline? {
        guard
            case let .available(samples) = snapshot[metric],
            let end = calendar.date(byAdding: .second, value: -1, to: selectedDate),
            case let .available(baseline) = HealthMetricBaselineEngine.calculate(
                metric: metric,
                samples: samples,
                endingAt: end,
                calendar: calendar
            )
        else { return nil }
        return baseline
    }

    private static func makeNightSummary(
        vitals: [TodayNightVital],
        readiness: TodayTrainingReadiness
    ) -> TodayNightSummary {
        let availableCount = vitals.compactMap(\.value).count
        guard availableCount >= 3 else {
            return TodayNightSummary(
                title: "记录不足，暂时无法判断睡得怎么样",
                detail: "至少需要三项可见记录，缺失数据不会补成正常。",
                availableVitalCount: availableCount
            )
        }
        switch readiness {
        case let .available(score, _, _) where score >= 70:
            return TodayNightSummary(
                title: "指标正常，睡得不错",
                detail: "根据昨晚记录与个人近期参考生成，不代表医学诊断。",
                availableVitalCount: availableCount
            )
        case .available:
            return TodayNightSummary(
                title: "部分指标有变化，昨晚睡眠一般",
                detail: "这是与个人近期参考的对照，建议结合今天的主观感受。",
                availableVitalCount: availableCount
            )
        case .insufficient:
            return TodayNightSummary(
                title: "记录已读取，暂时无法判断睡得怎么样",
                detail: "个人基线仍不足，继续积累数据后再评价。",
                availableVitalCount: availableCount
            )
        }
    }
}

enum TodayImportantChangeSelector {
    private struct Configuration {
        let metric: HealthMetricType
        let priority: Int
    }

    private struct Candidate {
        let change: TodayImportantChange
        let score: Double
        let priority: Int
    }

    private static let configurations = [
        Configuration(metric: .sleepDuration, priority: 0),
        Configuration(metric: .heartRateVariability, priority: 1),
        Configuration(metric: .restingHeartRate, priority: 2),
        Configuration(metric: .stepCount, priority: 3),
        Configuration(metric: .activeEnergy, priority: 4),
        Configuration(metric: .exerciseDuration, priority: 5)
    ]

    static func select(
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> TodayImportantChange? {
        configurations.compactMap { configuration in
            candidate(
                configuration: configuration,
                snapshot: snapshot,
                selectedDate: selectedDate,
                calendar: calendar
            )
        }
        .sorted {
            if abs($0.score - $1.score) > 0.000_001 {
                return $0.score > $1.score
            }
            return $0.priority < $1.priority
        }
        .first?.change
    }

    private static func candidate(
        configuration: Configuration,
        snapshot: HealthDataSnapshot,
        selectedDate: Date,
        calendar: Calendar
    ) -> Candidate? {
        guard case let .available(samples) = snapshot[configuration.metric] else {
            return nil
        }
        guard let threshold = HealthMetricTrendThresholdCatalog.threshold(
            for: configuration.metric
        ),
              case let .available(currentWindow) = HealthMetricRecentWindowEngine.calculate(
            metric: configuration.metric,
            samples: samples,
            endingAt: selectedDate,
            calendar: calendar
        ),
              let baselineEnd = calendar.date(
                  byAdding: .second,
                  value: -1,
                  to: currentWindow.interval.start
              ),
              case let .available(baseline) = HealthMetricBaselineEngine.calculate(
                  metric: configuration.metric,
                  samples: samples,
                  endingAt: baselineEnd,
                  calendar: calendar
              ),
              let trend = try? HealthMetricTrendDetector.detect(
                  baseline: baseline,
                  current: currentWindow,
                  sourceIsStable: HealthMetricTrendSourceStabilityEvaluator.isStable(
                      metric: configuration.metric,
                      samples: samples,
                      endingAt: selectedDate,
                      calendar: calendar
                  ),
                  configuration: threshold.detectorConfiguration
              ),
              trend.level == .sustainedChange,
              case let .available(relativeDifference) =
                  trend.magnitude.relativeChange,
              let effectiveThreshold = trend.effectiveRelativeThreshold
        else {
            return nil
        }

        let currentMedian = trend.magnitude.currentValue

        let change = TodayImportantChange(
            metric: configuration.metric,
            currentMedian: currentMedian,
            whatChanged: whatChangedText(
                metric: configuration.metric,
                currentMedian: currentMedian,
                baselineMedian: baseline.medianValue,
                relativeDifference: relativeDifference
            ),
            actionText: actionText(
                metric: configuration.metric,
                relativeDifference: relativeDifference
            ),
            relativeDifference: relativeDifference
        )
        return Candidate(
            change: change,
            score: abs(relativeDifference) / effectiveThreshold,
            priority: configuration.priority
        )
    }

    private static func whatChangedText(
        metric: HealthMetricType,
        currentMedian: Double,
        baselineMedian: Double,
        relativeDifference: Double
    ) -> String {
        let direction = relativeDifference > 0 ? "增加" : "减少"
        let percentage = Int((abs(relativeDifference) * 100).rounded())
        return "近 7 天\(title(for: metric))中位数为 \(valueText(currentMedian, unit: metric.expectedUnit))，比前期个人基线 \(valueText(baselineMedian, unit: metric.expectedUnit))\(direction) \(percentage)%。"
    }

    private static func title(for metric: HealthMetricType) -> String {
        switch metric {
        case .sleepDuration: "睡眠时长"
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "静息心率"
        case .stepCount: "步数"
        case .activeEnergy: "活动能量"
        case .exerciseDuration: "锻炼时长"
        default: metric.rawValue
        }
    }

    private static func valueText(_ value: Double, unit: HealthMetricUnit) -> String {
        switch unit {
        case .count: "\(Int(value.rounded())) 步"
        case .hours: "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .beatsPerMinute: "\(Int(value.rounded())) 次/分"
        case .milliseconds: "\(Int(value.rounded())) ms"
        case .kilocalories: "\(Int(value.rounded())) 千卡"
        case .minutes: "\(Int(value.rounded())) 分钟"
        default: value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private static func actionText(
        metric: HealthMetricType,
        relativeDifference: Double
    ) -> String {
        switch (metric, relativeDifference > 0) {
        case (.sleepDuration, false):
            "今晚可先保持固定上床时间，并继续观察接下来几天。"
        case (.sleepDuration, true):
            "可先保持当前作息，继续观察这一变化是否稳定。"
        case (.heartRateVariability, false):
            "今天可优先休息或轻松活动，并结合自己的感受继续观察。"
        case (.heartRateVariability, true):
            "先保持当前节奏；单项 HRV 变化不代表整体健康结论。"
        case (.restingHeartRate, true):
            "今天可选择较轻松的活动，并结合疲劳或不适感继续观察。"
        case (.restingHeartRate, false):
            "先保持当前节奏；单项静息心率变化不代表整体健康结论。"
        case (.stepCount, false), (.activeEnergy, false), (.exerciseDuration, false):
            "如果身体感觉允许，可安排一次 10～15 分钟的轻松活动。"
        case (.stepCount, true), (.activeEnergy, true), (.exerciseDuration, true):
            "可保持当前活动节奏，同时留意自己的疲劳感。"
        default:
            "继续观察接下来几天，并以自己的感受为准。"
        }
    }
}
