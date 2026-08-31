@preconcurrency import HealthKit
import XCTest
@testable import Zhiheng

final class HealthKitAuthorizationServiceTests: XCTestCase {
    func testUnavailableDeviceDoesNotClaimHealthAccess() async {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: false,
            status: .unnecessary
        )
        let service = HealthKitAuthorizationService(client: client)

        let state = await service.accessState()

        XCTAssertEqual(state, .unavailable)
    }

    func testShouldRequestRemainsNotRequested() async {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: true,
            status: .shouldRequest
        )
        let service = HealthKitAuthorizationService(client: client)

        let state = await service.accessState()

        XCTAssertEqual(state, .notRequested)
    }

    func testUnnecessaryMeansOnlyThatSelectionWasCompleted() async {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: true,
            status: .unnecessary
        )
        let service = HealthKitAuthorizationService(client: client)

        let state = await service.accessState()

        XCTAssertEqual(state, .requestCompleted)
    }

    func testRequestsExactlyTheDashboardReadTypes() async throws {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: true,
            status: .shouldRequest
        )
        let service = HealthKitAuthorizationService(client: client)

        try await service.requestReadAccess(
            for: Set(HealthMetricType.allCases)
        )

        let identifiers = await client.requestedTypeIdentifiers()
        XCTAssertEqual(
            identifiers,
            Set([
                HKQuantityTypeIdentifier.stepCount.rawValue,
                HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
                HKQuantityTypeIdentifier.restingHeartRate.rawValue,
                HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
                HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
                HKCategoryTypeIdentifier.appleStandHour.rawValue,
                HKQuantityTypeIdentifier.heartRate.rawValue,
                HKQuantityTypeIdentifier.respiratoryRate.rawValue,
                HKQuantityTypeIdentifier.oxygenSaturation.rawValue,
                HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue,
                HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                HKQuantityTypeIdentifier.flightsClimbed.rawValue,
                HKQuantityTypeIdentifier.walkingSpeed.rawValue,
                HKQuantityTypeIdentifier.walkingStepLength.rawValue,
                HKQuantityTypeIdentifier.vo2Max.rawValue
            ])
        )
    }

    func testEmptyMetricSetDoesNotOpenAuthorization() async throws {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: true,
            status: .shouldRequest
        )
        let service = HealthKitAuthorizationService(client: client)

        try await service.requestReadAccess(for: [])

        let requestCount = await client.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testSystemFailureBecomesStableAuthorizationError() async {
        let client = HealthStoreClientSpy(
            isHealthDataAvailable: true,
            status: .shouldRequest,
            requestError: HealthStoreClientSpy.TestError.failed
        )
        let service = HealthKitAuthorizationService(client: client)

        do {
            try await service.requestReadAccess(for: [.stepCount])
            XCTFail("Expected authorization request failure")
        } catch let error as HealthDataServiceError {
            XCTAssertEqual(error, .authorizationRequestFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor HealthStoreClientSpy: HealthStoreClient {
    enum TestError: Error {
        case failed
    }

    nonisolated let isHealthDataAvailable: Bool
    private let status: HKAuthorizationRequestStatus
    private let requestError: Error?
    private var requestedIdentifiers = Set<String>()
    private var requests = 0

    init(
        isHealthDataAvailable: Bool,
        status: HKAuthorizationRequestStatus,
        requestError: Error? = nil
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.status = status
        self.requestError = requestError
    }

    func authorizationRequestStatus(
        for readTypes: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        status
    }

    func requestAuthorization(for readTypes: Set<HKObjectType>) async throws {
        requests += 1
        if let requestError {
            throw requestError
        }
        requestedIdentifiers = Set(readTypes.map(\.identifier))
    }

    func requestedTypeIdentifiers() -> Set<String> {
        requestedIdentifiers
    }

    func requestCount() -> Int {
        requests
    }
}
