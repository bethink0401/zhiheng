import Foundation

enum HealthMetricType: String, CaseIterable, Codable, Sendable {
    case stepCount
    case sleepDuration
    case restingHeartRate
    case heartRateVariability
    case activeEnergy
    case exerciseDuration
    case standHours
    case heartRate
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case walkingRunningDistance
    case flightsClimbed
    case walkingSpeed
    case walkingStepLength
    case vo2Max

    static let initialConnectionMetrics: Set<HealthMetricType> = [
        .stepCount,
        .sleepDuration,
        .restingHeartRate,
        .heartRateVariability,
        .activeEnergy,
        .exerciseDuration
    ]

    var expectedUnit: HealthMetricUnit {
        switch self {
        case .stepCount:
            .count
        case .sleepDuration:
            .hours
        case .restingHeartRate, .heartRate:
            .beatsPerMinute
        case .heartRateVariability:
            .milliseconds
        case .activeEnergy:
            .kilocalories
        case .exerciseDuration:
            .minutes
        case .standHours:
            .hours
        case .respiratoryRate:
            .breathsPerMinute
        case .oxygenSaturation:
            .percentage
        case .wristTemperature:
            .degreesCelsius
        case .walkingRunningDistance:
            .kilometers
        case .flightsClimbed:
            .floors
        case .walkingSpeed:
            .metersPerSecond
        case .walkingStepLength:
            .meters
        case .vo2Max:
            .millilitersPerKilogramPerMinute
        }
    }
}

enum HealthMetricUnit: String, Codable, Sendable {
    case count
    case hours
    case beatsPerMinute
    case milliseconds
    case kilocalories
    case minutes
    case breathsPerMinute
    case percentage
    case degreesCelsius
    case kilometers
    case floors
    case metersPerSecond
    case meters
    case millilitersPerKilogramPerMinute
}

enum HealthSleepStage: String, Codable, CaseIterable, Sendable {
    case deep
    case core
    case rem
    case awake
    case asleepUnspecified

    static let displayedStages: [HealthSleepStage] = [.awake, .rem, .core, .deep]

    var title: String {
        switch self {
        case .deep: "深睡"
        case .core: "核心"
        case .rem: "REM"
        case .awake: "清醒"
        case .asleepUnspecified: "睡眠"
        }
    }
}

enum HealthMetricSourceCategory: Int, Codable, Sendable {
    case appleWatch = 0
    case iPhone = 1
    case other = 2
}

struct HealthMetricSource: Hashable, Codable, Sendable {
    let sourceName: String
    let bundleIdentifier: String?
    let deviceName: String?
    let productType: String?

    init(
        sourceName: String,
        bundleIdentifier: String?,
        deviceName: String?,
        productType: String? = nil
    ) {
        self.sourceName = sourceName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.productType = productType
    }

    var category: HealthMetricSourceCategory {
        let identity = [sourceName, deviceName, productType]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if identity.contains("watch") || identity.contains("手表") {
            return .appleWatch
        }
        if identity.contains("iphone") || identity.contains("苹果手机") {
            return .iPhone
        }
        return .other
    }

    var displayName: String {
        switch category {
        case .appleWatch:
            "Apple Watch"
        case .iPhone:
            "iPhone"
        case .other:
            sourceName
        }
    }
}

enum HealthMetricSampleValidationError: Error, Equatable {
    case invalidInterval
    case nonFiniteValue
    case negativeValue
    case invalidUnit
}

struct HealthMetricSample: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let metricType: HealthMetricType
    let startDate: Date
    let endDate: Date
    let value: Double
    let unit: HealthMetricUnit
    let source: HealthMetricSource
    let sleepStage: HealthSleepStage?

    init(
        id: UUID,
        metricType: HealthMetricType,
        startDate: Date,
        endDate: Date,
        value: Double,
        unit: HealthMetricUnit,
        source: HealthMetricSource,
        sleepStage: HealthSleepStage? = nil
    ) throws {
        guard endDate >= startDate else {
            throw HealthMetricSampleValidationError.invalidInterval
        }
        guard value.isFinite else {
            throw HealthMetricSampleValidationError.nonFiniteValue
        }
        guard value >= 0 else {
            throw HealthMetricSampleValidationError.negativeValue
        }
        guard unit == metricType.expectedUnit else {
            throw HealthMetricSampleValidationError.invalidUnit
        }

        self.id = id
        self.metricType = metricType
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unit = unit
        self.source = source
        self.sleepStage = sleepStage
    }
}
