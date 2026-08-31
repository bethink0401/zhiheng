import Foundation

enum TodayInformationSection: String, Equatable, Sendable {
    case demoNotice
    case keyMetrics
    case trendChart
    case nextAction
    case productExplanation
    case privacy
}

enum TodayInformationHierarchy {
    static func sections(
        dataMode: HealthDataMode,
        canQueryHealthData: Bool
    ) -> [TodayInformationSection] {
        var result = [TodayInformationSection]()
        if dataMode == .demo {
            result.append(.demoNotice)
        }
        if canQueryHealthData {
            result.append(.keyMetrics)
        }
        result.append(.productExplanation)
        result.append(.privacy)
        return result
    }
}

struct HealthDataQualityPresentation: Equatable, Sendable {
    let report: HealthDataQualityReport

    var title: String {
        report.supportsShortTermObservation
            ? "数据覆盖可用于短期观察"
            : "数据还不够连续，先继续记录"
    }

    var systemImage: String {
        report.supportsShortTermObservation
            ? "checkmark.circle"
            : "clock.badge.questionmark"
    }

    var detail: String {
        let percentage = Int((report.coverageRatio * 100).rounded())
        var parts = [
            "近 7 天有效 \(report.validDayCount) 天（\(percentage)%）"
        ]
        if report.longestMissingDayStreak > 0 {
            parts.append("最长断档 \(report.longestMissingDayStreak) 天")
        }
        if report.hasSourceChange {
            parts.append("数据来源有变化")
        }
        return parts.joined(separator: " · ")
    }
}

struct HealthDataCoveragePresentation: Equatable, Sendable {
    let report: HealthDataQualityReport

    var detail: String {
        let percentage = Int((report.coverageRatio * 100).rounded())
        return "近 \(report.expectedDayCount) 天有效 \(report.validDayCount) 天（\(percentage)%）"
    }
}

enum AppContentState: CaseIterable, Equatable, Sendable {
    case loading
    case healthAccessNotRequested
    case noData
    case failed

    var title: String {
        switch self {
        case .loading:
            "正在读取"
        case .healthAccessNotRequested:
            "尚未连接 Apple Health"
        case .noData:
            "暂无健康数据"
        case .failed:
            "暂时无法读取"
        }
    }

    var message: String {
        switch self {
        case .loading:
            "正在准备数据，请稍候。"
        case .healthAccessNotRequested:
            "只有在你主动授权后，知衡才会读取你选择分享的数据。"
        case .noData:
            "当前时间范围内没有可用记录。你可以稍后重试或调整时间范围。"
        case .failed:
            "健康数据读取失败，但这不表示数值为零。你可以稍后重试。"
        }
    }

    var systemImage: String {
        switch self {
        case .loading:
            "hourglass"
        case .healthAccessNotRequested:
            "heart.slash"
        case .noData:
            "chart.bar.xaxis"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var actionTitle: String? {
        switch self {
        case .loading:
            nil
        case .healthAccessNotRequested:
            "了解并连接"
        case .noData:
            "重新检查"
        case .failed:
            "重试"
        }
    }
}

struct HealthMetricStatusPresentation: Equatable, Sendable {
    let metric: HealthMetricType
    let state: HealthMetricReadState

    var title: String {
        switch metric {
        case .stepCount:
            "步数"
        case .sleepDuration:
            "睡眠"
        case .restingHeartRate:
            "静息心率"
        case .heartRateVariability:
            "HRV（SDNN）"
        case .activeEnergy:
            "活动能量"
        case .exerciseDuration:
            "运动分钟"
        case .standHours:
            "站立小时"
        case .heartRate:
            "心率"
        case .respiratoryRate:
            "呼吸频率"
        case .oxygenSaturation:
            "血氧"
        case .wristTemperature:
            "睡眠腕温"
        case .walkingRunningDistance:
            "步行与跑步距离"
        case .flightsClimbed:
            "爬楼层数"
        case .walkingSpeed:
            "步行速度"
        case .walkingStepLength:
            "步长"
        case .vo2Max:
            "心肺适能（VO₂ max）"
        }
    }

    var statusText: String {
        switch state {
        case .accessNotRequested:
            "等待你选择健康数据权限"
        case .healthDataUnavailable:
            "此设备暂不支持 Apple Health"
        case .noVisibleData:
            "最近 90 天没有可见数据"
        case let .available(samples):
            "已发现 \(samples.count) 条记录"
        case .failed:
            "暂时无法读取，可稍后重试"
        }
    }

    var latestSample: HealthMetricSample? {
        guard case let .available(samples) = state else {
            return nil
        }
        return samples.max { first, second in
            first.endDate < second.endDate
        }
    }

    var fallbackDetail: String? {
        switch state {
        case .noVisibleData:
            "可能是该时段没有记录，或你未允许读取此项。"
        case .failed:
            "读取失败不表示数值为零。"
        default:
            nil
        }
    }
}
