import Foundation

/// Transient, read-only alignment. No causal interpretation or persisted health copy.
struct HealthContextTimelineDay: Identifiable, Equatable {
    var id: Date { interval.start }
    let interval: DateInterval
    let localDay: SubjectiveLocalDay
    let checkIn: DailyCheckIn?
    let events: [ContextEvent]
}

enum TimelineMetricState: Equatable {
    case value(Double, source: String)
    case noData
    case sourceConflict
    case notRequested
    case unavailable
    case failed
    case notLoaded
    case outsideWindow

    var message: String {
        switch self {
        case .value: ""
        case .noData: "无可见数据"
        case .sourceConflict: "来源冲突，未合并"
        case .notRequested: "尚未申请读取"
        case .unavailable: "健康数据不可用"
        case .failed: "读取失败，请重试"
        case .notLoaded: "健康数据尚未读取"
        case .outsideWindow: "超出本次读取范围"
        }
    }
}

enum HealthContextTimeline {
    static let metrics: [HealthMetricType] = [
        .stepCount, .sleepDuration, .restingHeartRate, .heartRateVariability
    ]

    static func intervals(endingAt date: Date, timeZone: TimeZone) -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let lastDay = calendar.startOfDay(for: date)
        return (0..<7).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: lastDay),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    static func overlapping(_ events: [ContextEvent], interval: DateInterval) -> [ContextEvent] {
        events.filter {
            $0.startedAt < interval.end && ($0.endedAt ?? $0.startedAt) >= interval.start
        }.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func metricState(
        _ metric: HealthMetricType,
        day: DateInterval,
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        timeZone: TimeZone
    ) -> TimelineMetricState {
        guard let snapshot else {
            switch access {
            case .notRequested: return .notRequested
            case .unavailable: return .unavailable
            case .requestCompleted: return .notLoaded
            }
        }
        guard let loadedInterval else { return .notLoaded }
        // Require a complete start of day; never label a partial first day as a daily total.
        guard day.start >= loadedInterval.start, day.start <= loadedInterval.end else {
            return .outsideWindow
        }
        guard let state = snapshot[metric] else { return .notLoaded }
        switch state {
        case .accessNotRequested: return .notRequested
        case .healthDataUnavailable: return .unavailable
        case .noVisibleData: return .noData
        case .failed: return .failed
        case .available(let samples):
            let matching = samples.filter {
                $0.metricType == metric && $0.endDate >= day.start
                    && $0.endDate < day.end && $0.endDate <= loadedInterval.end
            }
            guard !matching.isEmpty else { return .noData }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let point = HealthMetricDailySeriesCalculator.points(
                metric: metric, samples: matching, endingAt: day.start,
                window: .sevenDays, calendar: calendar
            ).first(where: { $0.date == day.start }) else { return .sourceConflict }
            let selected: [HealthMetricSample]
            switch metric {
            case .stepCount, .sleepDuration:
                selected = PreferredHealthMetricSourceSelector.samples(from: matching) ?? []
            default:
                selected = matching
            }
            return .value(point.value, source: selected.first?.source.displayName ?? "未知来源")
        }
    }

    static func title(for metric: HealthMetricType) -> String {
        switch metric {
        case .stepCount: "步数"
        case .sleepDuration: "睡眠"
        case .restingHeartRate: "静息心率"
        case .heartRateVariability: "HRV"
        default: metric.rawValue
        }
    }

    static func valueText(_ value: Double, metric: HealthMetricType) -> String {
        switch metric {
        case .stepCount: String(format: "%.0f 步", value)
        case .sleepDuration: String(format: "%.1f 小时", value)
        case .restingHeartRate: String(format: "%.0f 次/分", value)
        case .heartRateVariability: String(format: "%.0f 毫秒", value)
        default: String(format: "%.1f", value)
        }
    }
}
