@preconcurrency import HealthKit
import Foundation

enum HealthHistoryWindow {
    static func last90Days(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard let startDate = calendar.date(
            byAdding: .day,
            value: -90,
            to: endDate
        ) else {
            return nil
        }
        return DateInterval(start: startDate, end: endDate)
    }
}

protocol HealthSampleClient: Sendable {
    var isHealthDataAvailable: Bool { get }

    func quantitySamples(
        for type: HKQuantityType,
        interval: DateInterval
    ) async throws -> [HKQuantitySample]

    func categorySamples(
        for type: HKCategoryType,
        interval: DateInterval
    ) async throws -> [HKCategorySample]
}

struct SystemHealthSampleClient: HealthSampleClient, @unchecked Sendable {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func quantitySamples(
        for type: HKQuantityType,
        interval: DateInterval
    ) async throws -> [HKQuantitySample] {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: [.strictStartDate, .strictEndDate]
        )
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    func categorySamples(
        for type: HKCategoryType,
        interval: DateInterval
    ) async throws -> [HKCategorySample] {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let predicate = HKSamplePredicate.categorySample(
            type: type,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }
}

actor HealthKitDataService: HealthDataService {
    private let accessService: any HealthAccessService
    private let sampleClient: any HealthSampleClient

    init(
        accessService: any HealthAccessService = HealthKitAuthorizationService(),
        sampleClient: any HealthSampleClient = SystemHealthSampleClient()
    ) {
        self.accessService = accessService
        self.sampleClient = sampleClient
    }

    func accessState() async -> HealthAccessState {
        await accessService.accessState()
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {
        try await accessService.requestReadAccess(for: metrics)
    }

    func fetchSamples(
        for metric: HealthMetricType,
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        guard interval.end > interval.start else {
            throw HealthDataServiceError.invalidInterval
        }
        guard sampleClient.isHealthDataAvailable else {
            throw HealthDataServiceError.healthDataUnavailable
        }
        do {
            switch metric {
            case .stepCount:
                return try await fetchQuantitySamples(
                    metric: .stepCount,
                    identifier: .stepCount,
                    healthKitUnit: .count(),
                    domainUnit: .count,
                    interval: interval
                )
            case .sleepDuration:
                return try await fetchSleepSamples(interval: interval)
            case .restingHeartRate:
                return try await fetchQuantitySamples(
                    metric: .restingHeartRate,
                    identifier: .restingHeartRate,
                    healthKitUnit: HKUnit.count().unitDivided(by: .minute()),
                    domainUnit: .beatsPerMinute,
                    interval: interval
                )
            case .heartRateVariability:
                return try await fetchQuantitySamples(
                    metric: .heartRateVariability,
                    identifier: .heartRateVariabilitySDNN,
                    healthKitUnit: HKUnit.secondUnit(with: .milli),
                    domainUnit: .milliseconds,
                    interval: interval
                )
            case .activeEnergy:
                return try await fetchQuantitySamples(
                    metric: .activeEnergy,
                    identifier: .activeEnergyBurned,
                    healthKitUnit: .kilocalorie(),
                    domainUnit: .kilocalories,
                    interval: interval
                )
            case .exerciseDuration:
                return try await fetchQuantitySamples(
                    metric: .exerciseDuration,
                    identifier: .appleExerciseTime,
                    healthKitUnit: .minute(),
                    domainUnit: .minutes,
                    interval: interval
                )
            case .standHours:
                return try await fetchStandHourSamples(interval: interval)
            case .heartRate:
                return try await fetchQuantitySamples(
                    metric: .heartRate,
                    identifier: .heartRate,
                    healthKitUnit: HKUnit.count().unitDivided(by: .minute()),
                    domainUnit: .beatsPerMinute,
                    interval: interval
                )
            case .respiratoryRate:
                return try await fetchQuantitySamples(
                    metric: .respiratoryRate,
                    identifier: .respiratoryRate,
                    healthKitUnit: HKUnit.count().unitDivided(by: .minute()),
                    domainUnit: .breathsPerMinute,
                    interval: interval
                )
            case .oxygenSaturation:
                return try await fetchQuantitySamples(
                    metric: .oxygenSaturation,
                    identifier: .oxygenSaturation,
                    healthKitUnit: .percent(),
                    domainUnit: .percentage,
                    multiplier: 100,
                    interval: interval
                )
            case .wristTemperature:
                return try await fetchQuantitySamples(
                    metric: .wristTemperature,
                    identifier: .appleSleepingWristTemperature,
                    healthKitUnit: .degreeCelsius(),
                    domainUnit: .degreesCelsius,
                    interval: interval
                )
            case .walkingRunningDistance:
                return try await fetchQuantitySamples(
                    metric: .walkingRunningDistance,
                    identifier: .distanceWalkingRunning,
                    healthKitUnit: .meter(),
                    domainUnit: .kilometers,
                    multiplier: 0.001,
                    interval: interval
                )
            case .flightsClimbed:
                return try await fetchQuantitySamples(
                    metric: .flightsClimbed,
                    identifier: .flightsClimbed,
                    healthKitUnit: .count(),
                    domainUnit: .floors,
                    interval: interval
                )
            case .walkingSpeed:
                return try await fetchQuantitySamples(
                    metric: .walkingSpeed,
                    identifier: .walkingSpeed,
                    healthKitUnit: HKUnit.meter().unitDivided(by: .second()),
                    domainUnit: .metersPerSecond,
                    interval: interval
                )
            case .walkingStepLength:
                return try await fetchQuantitySamples(
                    metric: .walkingStepLength,
                    identifier: .walkingStepLength,
                    healthKitUnit: .meter(),
                    domainUnit: .meters,
                    interval: interval
                )
            case .vo2Max:
                return try await fetchQuantitySamples(
                    metric: .vo2Max,
                    identifier: .vo2Max,
                    healthKitUnit: HKUnit.literUnit(with: .milli)
                        .unitDivided(
                            by: HKUnit.gramUnit(with: .kilo)
                                .unitMultiplied(by: .minute())
                        ),
                    domainUnit: .millilitersPerKilogramPerMinute,
                    interval: interval
                )
            }
        } catch let error as HealthDataServiceError {
            throw error
        } catch {
            throw HealthDataServiceError.queryFailed
        }
    }

    private func fetchQuantitySamples(
        metric: HealthMetricType,
        identifier: HKQuantityTypeIdentifier,
        healthKitUnit: HKUnit,
        domainUnit: HealthMetricUnit,
        multiplier: Double = 1,
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthDataServiceError.queryFailed
        }
        let samples = try await sampleClient.quantitySamples(
            for: type,
            interval: interval
        )
        return try samples.map { sample in
            try HealthMetricSample(
                id: sample.uuid,
                metricType: metric,
                startDate: sample.startDate,
                endDate: sample.endDate,
                value: sample.quantity.doubleValue(for: healthKitUnit) * multiplier,
                unit: domainUnit,
                source: source(for: sample)
            )
        }
    }

    private func fetchSleepSamples(
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthDataServiceError.queryFailed
        }
        let samples = try await sampleClient.categorySamples(
            for: type,
            interval: interval
        )
        return try samples.compactMap { sample in
            guard let stage = sleepStage(for: sample.value) else { return nil }
            let clippedStart = max(sample.startDate, interval.start)
            let clippedEnd = min(sample.endDate, interval.end)
            guard clippedEnd > clippedStart else {
                return nil
            }

            return try HealthMetricSample(
                id: sample.uuid,
                metricType: .sleepDuration,
                startDate: clippedStart,
                endDate: clippedEnd,
                value: stage == .awake
                    ? 0
                    : clippedEnd.timeIntervalSince(clippedStart) / (60 * 60),
                unit: .hours,
                source: source(for: sample),
                sleepStage: stage
            )
        }
    }

    private func sleepStage(for rawValue: Int) -> HealthSleepStage? {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            .deep
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            .core
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            .rem
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            .asleepUnspecified
        default:
            nil
        }
    }

    private func fetchStandHourSamples(
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            throw HealthDataServiceError.queryFailed
        }
        let samples = try await sampleClient.categorySamples(
            for: type,
            interval: interval
        )
        return try samples.compactMap { sample in
            guard sample.value == HKCategoryValueAppleStandHour.stood.rawValue else {
                return nil
            }
            return try HealthMetricSample(
                id: sample.uuid,
                metricType: .standHours,
                startDate: sample.startDate,
                endDate: sample.endDate,
                value: 1,
                unit: .hours,
                source: source(for: sample)
            )
        }
    }

    private func source(for sample: HKSample) -> HealthMetricSource {
        HealthMetricSource(
            sourceName: sourceName(for: sample),
            bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            deviceName: sample.device?.name,
            productType: sample.sourceRevision.productType
        )
    }

    private func sourceName(for sample: HKSample) -> String {
        let name = sample.sourceRevision.source.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        let bundleIdentifier = sample.sourceRevision.source.bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundleIdentifier.isEmpty ? "未知来源" : bundleIdentifier
    }
}
