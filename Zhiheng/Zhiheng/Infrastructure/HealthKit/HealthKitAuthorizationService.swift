@preconcurrency import HealthKit

protocol HealthStoreClient: Sendable {
    var isHealthDataAvailable: Bool { get }

    func authorizationRequestStatus(
        for readTypes: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus

    func requestAuthorization(for readTypes: Set<HKObjectType>) async throws
}

struct SystemHealthStoreClient: HealthStoreClient, @unchecked Sendable {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationRequestStatus(
        for readTypes: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        try await store.statusForAuthorizationRequest(
            toShare: [],
            read: readTypes
        )
    }

    func requestAuthorization(for readTypes: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
}

enum HealthKitMetricTypeMapper {
    static func objectType(for metric: HealthMetricType) -> HKObjectType? {
        switch metric {
        case .stepCount:
            HKObjectType.quantityType(forIdentifier: .stepCount)
        case .sleepDuration:
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .restingHeartRate:
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .heartRateVariability:
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .activeEnergy:
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exerciseDuration:
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .standHours:
            HKObjectType.categoryType(forIdentifier: .appleStandHour)
        case .heartRate:
            HKObjectType.quantityType(forIdentifier: .heartRate)
        case .respiratoryRate:
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .oxygenSaturation:
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .wristTemperature:
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)
        case .walkingRunningDistance:
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .flightsClimbed:
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)
        case .walkingSpeed:
            HKObjectType.quantityType(forIdentifier: .walkingSpeed)
        case .walkingStepLength:
            HKObjectType.quantityType(forIdentifier: .walkingStepLength)
        case .vo2Max:
            HKObjectType.quantityType(forIdentifier: .vo2Max)
        }
    }

    static func objectTypes(
        for metrics: Set<HealthMetricType>
    ) throws -> Set<HKObjectType> {
        var result = Set<HKObjectType>()
        for metric in metrics {
            guard let objectType = objectType(for: metric) else {
                throw HealthDataServiceError.authorizationRequestFailed
            }
            result.insert(objectType)
        }
        return result
    }
}

actor HealthKitAuthorizationService: HealthAccessService {
    private let client: any HealthStoreClient
    private let requestedMetrics: Set<HealthMetricType>

    init(
        client: any HealthStoreClient = SystemHealthStoreClient(),
        requestedMetrics: Set<HealthMetricType> = HealthMetricType.initialConnectionMetrics
    ) {
        self.client = client
        self.requestedMetrics = requestedMetrics
    }

    func accessState() async -> HealthAccessState {
        guard client.isHealthDataAvailable else {
            return .unavailable
        }

        do {
            let readTypes = try HealthKitMetricTypeMapper.objectTypes(
                for: requestedMetrics
            )
            let status = try await client.authorizationRequestStatus(
                for: readTypes
            )

            switch status {
            case .unnecessary:
                return .requestCompleted
            case .shouldRequest, .unknown:
                return .notRequested
            @unknown default:
                return .notRequested
            }
        } catch {
            return .notRequested
        }
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {
        guard client.isHealthDataAvailable else {
            throw HealthDataServiceError.healthDataUnavailable
        }
        guard !metrics.isEmpty else {
            return
        }

        do {
            let readTypes = try HealthKitMetricTypeMapper.objectTypes(for: metrics)
            try await client.requestAuthorization(for: readTypes)
        } catch let error as HealthDataServiceError {
            throw error
        } catch {
            throw HealthDataServiceError.authorizationRequestFailed
        }
    }
}
