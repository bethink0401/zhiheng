import Foundation

enum HRVVisualState: Equatable, Sendable {
    case unavailable
    case learning
    case belowPersonalRange
    case nearPersonalRange
    case abovePersonalRange
}

enum TodayGoalKind: String, CaseIterable, Codable, Sendable {
    case steps
    case sleep
    case activeEnergy
    case exercise
    case stand

    var title: String {
        switch self {
        case .steps: "步数"
        case .sleep: "睡眠"
        case .activeEnergy: "活动能量"
        case .exercise: "运动分钟"
        case .stand: "站立小时"
        }
    }

    var unit: HealthMetricUnit {
        switch self {
        case .steps: .count
        case .sleep, .stand: .hours
        case .activeEnergy: .kilocalories
        case .exercise: .minutes
        }
    }
}

struct TodayDashboardGoals: Codable, Equatable, Sendable {
    var steps: Double
    var sleepHours: Double
    var activeEnergyKilocalories: Double
    var exerciseMinutes: Double
    var standHours: Double

    static let standard = TodayDashboardGoals(
        steps: 8_000,
        sleepHours: 8,
        activeEnergyKilocalories: 500,
        exerciseMinutes: 30,
        standHours: 12
    )

    func value(for kind: TodayGoalKind) -> Double {
        switch kind {
        case .steps: steps
        case .sleep: sleepHours
        case .activeEnergy: activeEnergyKilocalories
        case .exercise: exerciseMinutes
        case .stand: standHours
        }
    }

    mutating func setValue(_ value: Double, for kind: TodayGoalKind) {
        guard value.isFinite, value > 0 else { return }
        switch kind {
        case .steps: steps = value
        case .sleep: sleepHours = value
        case .activeEnergy: activeEnergyKilocalories = value
        case .exercise: exerciseMinutes = value
        case .stand: standHours = value
        }
    }
}

struct TodayGoalActuals: Equatable, Sendable {
    private var values: [TodayGoalKind: Double]

    init(values: [TodayGoalKind: Double] = [:]) {
        self.values = values.filter { $0.value.isFinite && $0.value >= 0 }
    }

    subscript(kind: TodayGoalKind) -> Double? {
        values[kind]
    }
}

struct TodayGoalProgressItem: Identifiable, Equatable, Sendable {
    var id: TodayGoalKind { kind }
    let kind: TodayGoalKind
    let actual: Double
    let goal: Double

    var ratio: Double {
        guard goal > 0 else { return 0 }
        return actual / goal
    }

    var cappedRatio: Double {
        min(max(ratio, 0), 1)
    }
}

enum TodayGoalProgressResult: Equatable, Sendable {
    case unavailable
    case available(TodayGoalProgress)
}

struct TodayGoalProgress: Equatable, Sendable {
    let items: [TodayGoalProgressItem]
    let overallRatio: Double

    var percentage: Int {
        Int((overallRatio * 100).rounded())
    }

    var completedGoalCount: Int {
        items.filter { $0.ratio >= 1 }.count
    }
}

enum TodayGoalProgressCalculator {
    static func calculate(
        goals: TodayDashboardGoals,
        actuals: TodayGoalActuals
    ) -> TodayGoalProgressResult {
        let items = TodayGoalKind.allCases.compactMap { kind -> TodayGoalProgressItem? in
            guard let actual = actuals[kind] else { return nil }
            let goal = goals.value(for: kind)
            guard goal.isFinite, goal > 0 else { return nil }
            return TodayGoalProgressItem(kind: kind, actual: actual, goal: goal)
        }
        guard !items.isEmpty else { return .unavailable }
        let ratio = items.map(\.cappedRatio).reduce(0, +) / Double(items.count)
        return .available(TodayGoalProgress(items: items, overallRatio: ratio))
    }
}

struct TodayActivityEncouragement: Equatable, Sendable {
    let title: String
    let detail: String
    let level: Level

    enum Level: String, Equatable, Sendable {
        case gettingStarted
        case progressing
        case onTrack
        case completed
        case unavailable
    }
}

enum TodayActivityEncouragementFactory {
    static func make(
        from result: TodayGoalProgressResult,
        isToday: Bool
    ) -> TodayActivityEncouragement {
        guard case let .available(progress) = result else {
            return TodayActivityEncouragement(
                title: "等待更多记录",
                detail: "当前数据还不足以计算目标完成度。",
                level: .unavailable
            )
        }

        let suffix = isToday ? "今天仍有时间，按自己的节奏继续。" : "这是所选日期的目标完成情况。"
        switch progress.overallRatio {
        case 1...:
            return TodayActivityEncouragement(
                title: "今日目标已完成",
                detail: "五项目标分别计算，超额完成不会掩盖其他项目。",
                level: .completed
            )
        case 0.7..<1:
            return TodayActivityEncouragement(
                title: "状态不错，继续保持",
                detail: suffix,
                level: .onTrack
            )
        case 0.35..<0.7:
            return TodayActivityEncouragement(
                title: "已经有了不错的开始",
                detail: suffix,
                level: .progressing
            )
        default:
            return TodayActivityEncouragement(
                title: "从一个轻松的小行动开始",
                detail: suffix,
                level: .gettingStarted
            )
        }
    }
}

enum TodayDashboardDateWindow {
    static func sevenDays(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let finalDay = calendar.startOfDay(for: endDate)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: finalDay)
        }
    }
}

enum TodayDashboardSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case body
    case daily
    case nightlyVitals

    var id: String { rawValue }
}

enum TodayDashboardModule: String, CaseIterable, Codable, Identifiable, Sendable {
    case loadReference
    case trainingReadiness
    case walking
    case sleep
    case activity
    case energy
    case sleepDuration
    case sleepingHeartRate
    case wristTemperature
    case respiratoryRate
    case oxygenSaturation

    var id: String { rawValue }

    var section: TodayDashboardSection {
        switch self {
        case .loadReference, .trainingReadiness:
            .body
        case .walking, .sleep, .activity, .energy:
            .daily
        case .sleepDuration, .sleepingHeartRate, .wristTemperature,
             .respiratoryRate, .oxygenSaturation:
            .nightlyVitals
        }
    }

    var title: String {
        switch self {
        case .loadReference: "负荷参考"
        case .trainingReadiness: "训练准备"
        case .walking: "走路"
        case .sleep: "睡眠"
        case .activity: "活动圆环"
        case .energy: "燃烧卡路里"
        case .sleepDuration: "睡眠时长"
        case .sleepingHeartRate: "睡眠时心率"
        case .wristTemperature: "睡眠腕温"
        case .respiratoryRate: "呼吸频率"
        case .oxygenSaturation: "血氧"
        }
    }
}

struct TodayDashboardLayout: Codable, Equatable, Sendable {
    private(set) var modulesBySection: [TodayDashboardSection: [TodayDashboardModule]]

    static let standard = TodayDashboardLayout(modulesBySection: [
        .body: [.loadReference, .trainingReadiness],
        .daily: [.walking, .sleep, .activity, .energy],
        .nightlyVitals: [
            .sleepDuration,
            .sleepingHeartRate,
            .wristTemperature,
            .respiratoryRate,
            .oxygenSaturation
        ]
    ])

    init(modulesBySection: [TodayDashboardSection: [TodayDashboardModule]]) {
        var sanitized = [TodayDashboardSection: [TodayDashboardModule]]()
        for section in TodayDashboardSection.allCases {
            var seen = Set<TodayDashboardModule>()
            sanitized[section] = modulesBySection[section, default: []].filter { module in
                module.section == section && seen.insert(module).inserted
            }
        }
        self.modulesBySection = sanitized
    }

    func modules(in section: TodayDashboardSection) -> [TodayDashboardModule] {
        modulesBySection[section, default: []]
    }

    mutating func setVisible(
        _ isVisible: Bool,
        module: TodayDashboardModule
    ) {
        var modules = modules(in: module.section)
        if isVisible {
            if !modules.contains(module) {
                modules.append(module)
            }
        } else {
            modules.removeAll { $0 == module }
        }
        modulesBySection[module.section] = modules
    }

    mutating func move(
        module: TodayDashboardModule,
        before destination: TodayDashboardModule
    ) {
        guard module.section == destination.section else { return }
        var modules = modules(in: module.section)
        guard
            let sourceIndex = modules.firstIndex(of: module),
            let destinationIndex = modules.firstIndex(of: destination),
            sourceIndex != destinationIndex
        else { return }
        modules.remove(at: sourceIndex)
        let updatedDestination = modules.firstIndex(of: destination) ?? modules.endIndex
        modules.insert(module, at: updatedDestination)
        modulesBySection[module.section] = modules
    }
}
