import Foundation

struct HealthFactPack: Codable, Equatable, Sendable {
    let generatedAt: Date
    let rangeStart: Date
    let rangeEnd: Date
    let dataMode: HealthDataMode
    let metrics: [HealthFactMetric]
    let unavailableMetrics: [HealthFactUnavailableMetric]

    var availableMetricTypes: Set<HealthMetricType> {
        Set(metrics.map(\.metric))
    }
}

struct HealthFactMetric: Codable, Equatable, Sendable {
    let metric: HealthMetricType
    let current: HealthFactCurrentValue?
    let shortTermQuality: HealthFactDataQuality
    let baseline: HealthFactBaseline?
}

struct HealthFactCurrentValue: Codable, Equatable, Sendable {
    let value: Double
    let unit: HealthMetricUnit
    let recordedAt: Date
}

struct HealthFactDataQuality: Codable, Equatable, Sendable {
    let expectedDayCount: Int
    let validDayCount: Int
    let coverageRatio: Double
    let longestMissingDayStreak: Int
    let supportsObservation: Bool
}

struct HealthFactBaseline: Codable, Equatable, Sendable {
    let medianValue: Double
    let medianAbsoluteDeviation: Double
    let unit: HealthMetricUnit
    let validDayCount: Int
    let expectedDayCount: Int
}

enum HealthFactUnavailableReason: String, Codable, Sendable {
    case accessNotRequested
    case healthDataUnavailable
    case noVisibleData
    case queryFailed
}

struct HealthFactUnavailableMetric: Codable, Equatable, Sendable {
    let metric: HealthMetricType
    let reason: HealthFactUnavailableReason
}

struct HealthAIConversationTurn: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct HealthAIRequest: Codable, Equatable, Sendable {
    let question: String
    let factPack: HealthFactPack
    let recentConversation: [HealthAIConversationTurn]
}

enum HealthAISafetyLevel: String, Codable, Sendable {
    case normal
    case caution
    case urgent
}

enum MicroPlanTemplateID: String, Codable, CaseIterable, Sendable {
    case afternoonCaffeineCutoff
    case earlierBedtime
    case afternoonWalk
    case movementBreak
    case reducedTrainingLoad
    case bedtimeBreathing
    case morningDaylight
    case afterMealWalk
    case consistentWakeTime
    case gentleMobility

    var title: String {
        switch self {
        case .afternoonCaffeineCutoff: "下午咖啡截止"
        case .earlierBedtime: "提前上床"
        case .afternoonWalk: "午后步行"
        case .movementBreak: "工作间歇活动"
        case .reducedTrainingLoad: "短期降低运动负荷"
        case .bedtimeBreathing: "睡前呼吸"
        case .morningDaylight: "晨间日光"
        case .afterMealWalk: "饭后散步"
        case .consistentWakeTime: "固定起床时间"
        case .gentleMobility: "轻柔活动"
        }
    }
}

struct HealthAISuggestedAction: Codable, Equatable, Sendable {
    let templateID: MicroPlanTemplateID
    let rationale: String
}

struct HealthAIResponse: Codable, Equatable, Sendable {
    let summary: String
    let observedFacts: [String]
    let possibleFactors: [String]
    let uncertainty: String
    let followUpQuestion: String?
    let suggestedAction: HealthAISuggestedAction?
    let safetyLevel: HealthAISafetyLevel
    let usedMetrics: [HealthMetricType]
    /// Optional for compatibility with conversations saved before S12-15.
    let supportiveClosing: String?

    init(
        summary: String,
        observedFacts: [String],
        possibleFactors: [String],
        uncertainty: String,
        followUpQuestion: String?,
        suggestedAction: HealthAISuggestedAction?,
        safetyLevel: HealthAISafetyLevel,
        usedMetrics: [HealthMetricType],
        supportiveClosing: String? = nil
    ) {
        self.summary = summary
        self.observedFacts = observedFacts
        self.possibleFactors = possibleFactors
        self.uncertainty = uncertainty
        self.followUpQuestion = followUpQuestion
        self.suggestedAction = suggestedAction
        self.safetyLevel = safetyLevel
        self.usedMetrics = usedMetrics
        self.supportiveClosing = supportiveClosing
    }
}

enum HealthAIServiceError: Error, Equatable, Sendable {
    case notConfigured
    case networkUnavailable
    case timedOut
    case cancelled
    case invalidRequest
    case invalidResponse
    case serviceRejected(statusCode: Int)
}

extension HealthMetricType {
    var assistantDisplayName: String {
        switch self {
        case .stepCount: "步数"
        case .sleepDuration: "睡眠"
        case .restingHeartRate: "静息心率"
        case .heartRateVariability: "HRV"
        case .activeEnergy: "活动能量"
        case .exerciseDuration: "运动分钟"
        case .standHours: "站立小时"
        case .heartRate: "心率"
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
}

extension HealthMetricUnit {
    var assistantDisplayName: String {
        switch self {
        case .count: "步"
        case .hours: "小时"
        case .beatsPerMinute: "次/分"
        case .milliseconds: "毫秒"
        case .kilocalories: "千卡"
        case .minutes: "分钟"
        case .breathsPerMinute: "次/分"
        case .percentage: "%"
        case .degreesCelsius: "°C"
        case .kilometers: "公里"
        case .floors: "层"
        case .metersPerSecond: "米/秒"
        case .meters: "米"
        case .millilitersPerKilogramPerMinute: "毫升/千克/分钟"
        }
    }
}
