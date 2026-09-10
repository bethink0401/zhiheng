import Foundation

enum StateComparisonRules {
    static let version = "s08-state-comparison-v1"
    static let lowRatingMaximum = 2
    static let highRatingMinimum = 4
}

enum SubjectiveFeelingState: Equatable {
    case comfortable
    case needsCare
    case mixed

    static func classify(_ record: DailyCheckIn) -> Self {
        if record.energy.rawValue <= StateComparisonRules.lowRatingMaximum
            || record.bodyFeeling.rawValue <= StateComparisonRules.lowRatingMaximum
            || record.stress.rawValue >= StateComparisonRules.highRatingMinimum {
            return .needsCare
        }
        if record.energy.rawValue >= StateComparisonRules.highRatingMinimum
            && record.bodyFeeling.rawValue >= StateComparisonRules.highRatingMinimum
            && record.stress.rawValue <= StateComparisonRules.lowRatingMaximum {
            return .comfortable
        }
        return .mixed
    }
}

enum StateComparisonKind: CaseIterable, Equatable {
    case steadyComfortable, steadyNeedsCare, changedComfortable, changedNeedsCare
    case mixedFeelings, insufficientData, missingFeelings, feelingReadFailed, dateMismatch, demo

    var title: String {
        switch self {
        case .steadyComfortable: "感受舒适，近期未见明确变化"
        case .steadyNeedsCare: "数据未见明确变化，感受仍需照顾"
        case .changedComfortable: "感受舒适，数据变化可继续观察"
        case .changedNeedsCare: "感受需要照顾，近期也有变化"
        case .mixedFeelings: "感受各有不同，先分别看待"
        case .insufficientData: "数据暂不足以完成对照"
        case .missingFeelings: "记录今日感受后再对照"
        case .feelingReadFailed: "今日感受暂时读取失败"
        case .dateMismatch: "日期或时区不同，暂不合并判断"
        case .demo: "演示模式不对照真实感受"
        }
    }

    var message: String {
        switch self {
        case .steadyComfortable:
            "你记录的感受较舒适，四项近期趋势未见明确变化。保持适合自己的日常节奏，不必额外打卡。"
        case .steadyNeedsCare:
            "设备数据不能否定你的疲劳或压力。先按自己的感受安排节奏；最近有什么生活情境让你感觉不太好？"
        case .changedComfortable:
            "数据相对个人基线有持续变化，但变化不等于变差。尊重目前的舒适感受，继续观察即可。"
        case .changedNeedsCare:
            "先照顾当下感受，给自己留出休息空间。感受与数据同时变化并不说明两者存在因果关系。"
        case .mixedFeelings:
            "一般或混合感受不强行归为好或差，也不合成总分；可以继续分别记录精力、压力和身体感受。"
        case .insufficientData:
            "尚未满足完整对照条件，请查看下面的逐项原因。即使数据不足，你的感受仍值得重视。"
        case .missingFeelings:
            "只使用已保存的今日记录，不用昨天的感受或未提交的选择代替。你也可以选择暂不记录。"
        case .feelingReadFailed:
            "暂时无法确认已保存记录。可从今日感受卡重新打开重试，不会把读取失败当成未记录。"
        case .dateMismatch:
            "不把其他日期或时区的记录直接当作今日依据。可在历史中查看原日期与时区。"
        case .demo:
            "不会将演示健康数据与真实的感受记录混在一起，也不会读取或保存你的真实记录。"
        }
    }

    var isQuadrant: Bool {
        switch self {
        case .steadyComfortable, .steadyNeedsCare, .changedComfortable, .changedNeedsCare: true
        default: false
        }
    }
}

enum StateComparisonMetricStatus: Equatable {
    case ready(HealthMetricTrendLevel)
    case notRequested, unavailable, failed, noData, notLoaded, outsideWindow
    case currentInsufficient, baselineInsufficient, sourceChanged, sourceConflict
    case recentGap, isolatedOutlier

    var text: String {
        switch self {
        case .ready(.noClearChange): "未见明确变化"
        case .ready(.sustainedChange): "存在持续变化"
        case .ready(.worthObserving): "仍需继续观察"
        case .notRequested: "尚未申请读取"
        case .unavailable: "健康数据不可用"
        case .failed: "读取失败"
        case .noData: "没有可见数据"
        case .notLoaded: "健康数据尚未读取"
        case .outsideWindow: "本次读取范围不足或尚未更新"
        case .currentInsufficient: "近期有效日不足"
        case .baselineInsufficient: "个人基线有效日不足"
        case .sourceChanged: "数据来源有变化，暂不合并判断"
        case .sourceConflict: "同日来源有冲突，暂不合并判断"
        case .recentGap: "昨日没有有效日，暂不合并判断"
        case .isolatedOutlier: "存在孤立日期保护，暂不合并判断"
        }
    }
}

struct StateComparisonMetricEvidence: Identifiable, Equatable {
    var id: HealthMetricType { metric }
    let metric: HealthMetricType
    let status: StateComparisonMetricStatus
    let trend: HealthMetricTrendEvidence?
    let sources: [String]
}

struct StateComparisonResult: Equatable {
    let kind: StateComparisonKind
    let feeling: SubjectiveFeelingState?
    let currentInterval: DateInterval?
    let baselineInterval: DateInterval?
    let evidence: [StateComparisonMetricEvidence]
}

/// Product-level juxtaposition, not a medical score or a causal model.
enum StateComparisonEngine {
    static func make(
        snapshot: HealthDataSnapshot?, loadedInterval: DateInterval?, access: HealthAccessState,
        mode: HealthDataMode, checkIn: DailyCheckIn?, didLoadCheckIn: Bool,
        now: Date, timeZone: TimeZone
    ) -> StateComparisonResult {
        func empty(_ kind: StateComparisonKind) -> StateComparisonResult {
            StateComparisonResult(kind: kind, feeling: nil, currentInterval: nil, baselineInterval: nil, evidence: [])
        }
        guard mode == .live else { return empty(.demo) }
        guard didLoadCheckIn else { return empty(.feelingReadFailed) }
        guard let checkIn else { return empty(.missingFeelings) }
        let today = SubjectiveLocalDay(date: now, timeZone: timeZone)
        guard checkIn.localDay == today else { return empty(.dateMismatch) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: end),
              let start = calendar.date(byAdding: .day, value: -7, to: end),
              let baselineStart = calendar.date(byAdding: .day, value: -28, to: start) else {
            return empty(.insufficientData)
        }
        let evidence = HealthMetricTrendThresholdCatalog.coreMetrics.map { metric in
            metricEvidence(metric, snapshot: snapshot, loadedInterval: loadedInterval, access: access,
                baselineStart: baselineStart, end: end, yesterday: yesterday, calendar: calendar)
        }
        let feeling = SubjectiveFeelingState.classify(checkIn)
        let usable = evidence.allSatisfy {
            $0.status == .ready(.noClearChange) || $0.status == .ready(.sustainedChange)
        }
        let kind: StateComparisonKind
        if !usable { kind = .insufficientData }
        else if feeling == .mixed { kind = .mixedFeelings }
        else {
            let changed = evidence.contains { $0.status == .ready(.sustainedChange) }
            switch (changed, feeling == .needsCare) {
            case (false, false): kind = .steadyComfortable
            case (false, true): kind = .steadyNeedsCare
            case (true, false): kind = .changedComfortable
            case (true, true): kind = .changedNeedsCare
            }
        }
        return StateComparisonResult(kind: kind, feeling: feeling,
            currentInterval: DateInterval(start: start, end: end),
            baselineInterval: DateInterval(start: baselineStart, end: start), evidence: evidence)
    }

    private static func metricEvidence(
        _ metric: HealthMetricType, snapshot: HealthDataSnapshot?, loadedInterval: DateInterval?,
        access: HealthAccessState, baselineStart: Date, end: Date, yesterday: Date, calendar: Calendar
    ) -> StateComparisonMetricEvidence {
        func unavailable(_ status: StateComparisonMetricStatus) -> StateComparisonMetricEvidence {
            StateComparisonMetricEvidence(metric: metric, status: status, trend: nil, sources: [])
        }
        guard let snapshot else {
            switch access {
            case .notRequested: return unavailable(.notRequested)
            case .unavailable: return unavailable(.unavailable)
            case .requestCompleted: return unavailable(.notLoaded)
            }
        }
        guard let loadedInterval else { return unavailable(.notLoaded) }
        guard loadedInterval.start <= baselineStart, loadedInterval.end >= end else {
            return unavailable(.outsideWindow)
        }
        guard let state = snapshot[metric] else { return unavailable(.notLoaded) }
        let samples: [HealthMetricSample]
        switch state {
        case .accessNotRequested: return unavailable(.notRequested)
        case .healthDataUnavailable: return unavailable(.unavailable)
        case .failed: return unavailable(.failed)
        case .noVisibleData: return unavailable(.noData)
        case .available(let values):
            samples = values.filter { $0.metricType == metric && $0.endDate >= baselineStart && $0.endDate < end }
        }
        guard !samples.isEmpty else { return unavailable(.noData) }
        let trend = HealthMetricTrendEvidenceBuilder.make(metric: metric, samples: samples,
            endingAt: yesterday, calendar: calendar)
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        var sources = Set<HealthMetricSource>()
        var hasConflict = false
        for values in grouped.values {
            let selected: [HealthMetricSample]?
            switch metric {
            case .sleepDuration, .stepCount: selected = PreferredHealthMetricSourceSelector.samples(from: values)
            default: selected = Set(values.map(\.source)).count == 1 ? values : nil
            }
            if let selected { sources.formUnion(selected.map(\.source)) }
            else { hasConflict = true }
        }
        let status: StateComparisonMetricStatus
        if hasConflict { status = .sourceConflict }
        else if sources.count > 1 { status = .sourceChanged }
        else if let trend {
            switch trend.state {
            case .currentWindowInsufficient: status = .currentInsufficient
            case .baselineInsufficient: status = .baselineInsufficient
            case .sourceChanged: status = .sourceChanged
            case .trend(let level):
                if trend.isolatedOutlierExcluded { status = .isolatedOutlier }
                else if grouped[yesterday] == nil { status = .recentGap }
                else { status = .ready(level) }
            }
        } else { status = .notLoaded }
        return StateComparisonMetricEvidence(metric: metric, status: status, trend: trend,
            sources: Set(sources.map(\.displayName)).sorted())
    }
}
