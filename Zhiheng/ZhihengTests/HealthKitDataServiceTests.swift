@preconcurrency import HealthKit
import XCTest
@testable import Zhiheng

final class HealthKitDataServiceTests: XCTestCase {
    func testLast90DayWindowUsesCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 21,
                hour: 12
            ))
        )

        let interval = try XCTUnwrap(
            HealthHistoryWindow.last90Days(endingAt: end, calendar: calendar)
        )

        XCTAssertEqual(
            calendar.dateComponents([.day], from: interval.start, to: interval.end).day,
            90
        )
    }

    func testConvertsStepSamplesWithoutLosingTimeOrSource() async throws {
        let start = Date(timeIntervalSince1970: 1_770_000_000)
        let end = start.addingTimeInterval(5 * 60)
        let quantityType = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .stepCount)
        )
        let sample = HKQuantitySample(
            type: quantityType,
            quantity: HKQuantity(unit: .count(), doubleValue: 321),
            start: start,
            end: end
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )
        let interval = DateInterval(
            start: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60)
        )

        let result = try await service.fetchSamples(
            for: .stepCount,
            interval: interval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(converted.metricType, .stepCount)
        XCTAssertEqual(converted.value, 321)
        XCTAssertEqual(converted.unit, .count)
        XCTAssertEqual(converted.startDate, start)
        XCTAssertEqual(converted.endDate, end)
        XCTAssertFalse(converted.source.sourceName.isEmpty)
        let requestedIdentifier = await client.requestedIdentifier()
        let requestedInterval = await client.requestedInterval()
        XCTAssertEqual(requestedIdentifier, quantityType.identifier)
        XCTAssertEqual(requestedInterval, interval)
    }

    func testSuccessfulEmptyQueryRemainsEmptyInsteadOfZero() async throws {
        let client = HealthSampleClientSpy(samples: [])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .stepCount,
            interval: validInterval
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testRejectsEmptyIntervalBeforeQueryingHealthKit() async {
        let client = HealthSampleClientSpy(samples: [])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )
        let date = Date()

        do {
            _ = try await service.fetchSamples(
                for: .stepCount,
                interval: DateInterval(start: date, end: date)
            )
            XCTFail("Expected invalid interval")
        } catch let error as HealthDataServiceError {
            XCTAssertEqual(error, .invalidInterval)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQueryFailureDoesNotMasqueradeAsNoData() async {
        let client = HealthSampleClientSpy(
            samples: [],
            queryError: HealthSampleClientSpy.TestError.failed
        )
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        do {
            _ = try await service.fetchSamples(
                for: .stepCount,
                interval: validInterval
            )
            XCTFail("Expected query failure")
        } catch let error as HealthDataServiceError {
            XCTAssertEqual(error, .queryFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSleepKeepsStagesSeparateAndDoesNotCountAwakeAsSleep() async throws {
        let type = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        )
        let start = validInterval.start.addingTimeInterval(60 * 60)
        let samples = [
            HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: start,
                end: start.addingTimeInterval(4 * 60 * 60)
            ),
            HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: start,
                end: start.addingTimeInterval(2 * 60 * 60)
            ),
            HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.awake.rawValue,
                start: start.addingTimeInterval(2 * 60 * 60),
                end: start.addingTimeInterval(2.5 * 60 * 60)
            ),
            HKCategorySample(
                type: type,
                value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                start: start.addingTimeInterval(2.5 * 60 * 60),
                end: start.addingTimeInterval(3.5 * 60 * 60)
            )
        ]
        let client = HealthSampleClientSpy(
            quantitySamples: [],
            categorySamples: samples
        )
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .sleepDuration,
            interval: validInterval
        )

        XCTAssertEqual(result.map(\.value), [2, 0, 1])
        XCTAssertEqual(result.map(\.sleepStage), [.core, .awake, .deep])
        XCTAssertTrue(result.allSatisfy { $0.unit == .hours })
        XCTAssertTrue(result.allSatisfy { $0.metricType == .sleepDuration })
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testSleepSegmentIsClippedToRequestedWindow() async throws {
        let type = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        )
        let interval = validInterval
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            start: interval.start.addingTimeInterval(-60 * 60),
            end: interval.start.addingTimeInterval(60 * 60)
        )
        let client = HealthSampleClientSpy(
            quantitySamples: [],
            categorySamples: [sample]
        )
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .sleepDuration,
            interval: interval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(converted.startDate, interval.start)
        XCTAssertEqual(converted.endDate, sample.endDate)
        XCTAssertEqual(converted.value, 1)
        XCTAssertEqual(converted.sleepStage, .rem)
    }

    func testConvertsRestingHeartRateToBeatsPerMinute() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: 58),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .restingHeartRate,
            interval: validInterval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(converted.metricType, .restingHeartRate)
        XCTAssertEqual(converted.value, 58)
        XCTAssertEqual(converted.unit, .beatsPerMinute)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsHeartRateVariabilitySDNNToMilliseconds() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        )
        let unit = HKUnit.secondUnit(with: .milli)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: 42),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .heartRateVariability,
            interval: validInterval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(converted.metricType, .heartRateVariability)
        XCTAssertEqual(converted.value, 42)
        XCTAssertEqual(converted.unit, .milliseconds)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsActiveEnergyToKilocalories() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        )
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 186.5),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(30 * 60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .activeEnergy,
            interval: validInterval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(converted.metricType, .activeEnergy)
        XCTAssertEqual(converted.value, 186.5)
        XCTAssertEqual(converted.unit, .kilocalories)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsAppleExerciseTimeToMinutes() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        )
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .minute(), doubleValue: 24),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(24 * 60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .exerciseDuration,
            interval: validInterval
        )

        let converted = try XCTUnwrap(result.first)
        XCTAssertEqual(converted.metricType, .exerciseDuration)
        XCTAssertEqual(converted.value, 24)
        XCTAssertEqual(converted.unit, .minutes)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testCountsOnlyStoodStandHourSamples() async throws {
        let type = try XCTUnwrap(
            HKObjectType.categoryType(forIdentifier: .appleStandHour)
        )
        let stood = HKCategorySample(
            type: type,
            value: HKCategoryValueAppleStandHour.stood.rawValue,
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60 * 60)
        )
        let idle = HKCategorySample(
            type: type,
            value: HKCategoryValueAppleStandHour.idle.rawValue,
            start: validInterval.start.addingTimeInterval(60 * 60),
            end: validInterval.start.addingTimeInterval(2 * 60 * 60)
        )
        let client = HealthSampleClientSpy(
            quantitySamples: [],
            categorySamples: [stood, idle]
        )
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .standHours,
            interval: validInterval
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, 1)
        XCTAssertEqual(result.first?.unit, .hours)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsHeartRateToBeatsPerMinute() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .heartRate)
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: 61),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .heartRate,
            interval: validInterval
        )

        XCTAssertEqual(result.first?.value, 61)
        XCTAssertEqual(result.first?.unit, .beatsPerMinute)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsRespiratoryRateToBreathsPerMinute() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: 15.5),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .respiratoryRate,
            interval: validInterval
        )

        XCTAssertEqual(result.first?.value, 15.5)
        XCTAssertEqual(result.first?.unit, .breathsPerMinute)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsOxygenSaturationToPercentage() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        )
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.975),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .oxygenSaturation,
            interval: validInterval
        )

        XCTAssertEqual(result.first?.value, 97.5)
        XCTAssertEqual(result.first?.unit, .percentage)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsSleepingWristTemperatureToCelsius() async throws {
        let type = try XCTUnwrap(
            HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)
        )
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: 35.7),
            start: validInterval.start,
            end: validInterval.start.addingTimeInterval(60)
        )
        let client = HealthSampleClientSpy(samples: [sample])
        let service = HealthKitDataService(
            accessService: HealthAccessServiceStub(),
            sampleClient: client
        )

        let result = try await service.fetchSamples(
            for: .wristTemperature,
            interval: validInterval
        )

        XCTAssertEqual(result.first?.value, 35.7)
        XCTAssertEqual(result.first?.unit, .degreesCelsius)
        let requestedIdentifier = await client.requestedIdentifier()
        XCTAssertEqual(requestedIdentifier, type.identifier)
    }

    func testConvertsExpandedMobilityAndCardioFitnessMetrics() async throws {
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(
                by: HKUnit.gramUnit(with: .kilo)
                    .unitMultiplied(by: .minute())
            )
        let cases: [(
            metric: HealthMetricType,
            identifier: HKQuantityTypeIdentifier,
            healthKitUnit: HKUnit,
            input: Double,
            expected: Double,
            domainUnit: HealthMetricUnit
        )] = [
            (.walkingRunningDistance, .distanceWalkingRunning, .meter(), 4_200, 4.2, .kilometers),
            (.flightsClimbed, .flightsClimbed, .count(), 7, 7, .floors),
            (.walkingSpeed, .walkingSpeed, HKUnit.meter().unitDivided(by: .second()), 1.24, 1.24, .metersPerSecond),
            (.walkingStepLength, .walkingStepLength, .meter(), 0.72, 0.72, .meters),
            (.vo2Max, .vo2Max, vo2Unit, 39.4, 39.4, .millilitersPerKilogramPerMinute)
        ]

        for item in cases {
            let type = try XCTUnwrap(
                HKObjectType.quantityType(forIdentifier: item.identifier)
            )
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(
                    unit: item.healthKitUnit,
                    doubleValue: item.input
                ),
                start: validInterval.start,
                end: validInterval.start.addingTimeInterval(60)
            )
            let client = HealthSampleClientSpy(samples: [sample])
            let service = HealthKitDataService(
                accessService: HealthAccessServiceStub(),
                sampleClient: client
            )

            let result = try await service.fetchSamples(
                for: item.metric,
                interval: validInterval
            )

            let converted = try XCTUnwrap(result.first)
            XCTAssertEqual(converted.value, item.expected, accuracy: 0.000_1)
            XCTAssertEqual(converted.unit, item.domainUnit)
            XCTAssertEqual(converted.metricType, item.metric)
            let requestedIdentifier = await client.requestedIdentifier()
            XCTAssertEqual(requestedIdentifier, type.identifier)
        }
    }

    func testSnapshotDoesNotQueryBeforeHealthAccessChoice() async {
        let service = HealthDataServiceStub(
            accessState: .notRequested,
            results: [:]
        )
        let metrics: Set<HealthMetricType> = [.stepCount, .sleepDuration]

        let snapshot = await service.loadSnapshot(
            for: metrics,
            interval: validInterval
        )

        XCTAssertEqual(snapshot[.stepCount], .accessNotRequested)
        XCTAssertEqual(snapshot[.sleepDuration], .accessNotRequested)
        let queriedMetrics = await service.queriedMetrics()
        XCTAssertTrue(queriedMetrics.isEmpty)
    }

    func testSnapshotKeepsVisibleEmptyAndFailedMetricsSeparate() async throws {
        let sample = try HealthMetricSample(
            id: UUID(),
            metricType: .stepCount,
            startDate: validInterval.start,
            endDate: validInterval.start.addingTimeInterval(60),
            value: 100,
            unit: .count,
            source: HealthMetricSource(
                sourceName: "测试来源",
                bundleIdentifier: nil,
                deviceName: nil
            )
        )
        let service = HealthDataServiceStub(
            accessState: .requestCompleted,
            results: [
                .stepCount: .success([sample]),
                .sleepDuration: .success([]),
                .restingHeartRate: .failure(.queryFailed)
            ]
        )
        let metrics: Set<HealthMetricType> = [
            .stepCount,
            .sleepDuration,
            .restingHeartRate
        ]

        let snapshot = await service.loadSnapshot(
            for: metrics,
            interval: validInterval
        )

        XCTAssertEqual(snapshot[.stepCount], .available([sample]))
        XCTAssertEqual(snapshot[.sleepDuration], .noVisibleData)
        XCTAssertEqual(snapshot[.restingHeartRate], .failed(.queryFailed))
        XCTAssertTrue(snapshot.hasPartialVisibility)
        let queriedMetrics = await service.queriedMetrics()
        XCTAssertEqual(queriedMetrics, metrics)
    }

    func testSnapshotDoesNotQueryWhenHealthDataIsUnavailable() async {
        let service = HealthDataServiceStub(
            accessState: .unavailable,
            results: [:]
        )

        let snapshot = await service.loadSnapshot(
            for: [.stepCount],
            interval: validInterval
        )

        XCTAssertEqual(snapshot[.stepCount], .healthDataUnavailable)
        let queriedMetrics = await service.queriedMetrics()
        XCTAssertTrue(queriedMetrics.isEmpty)
    }

    private var validInterval: DateInterval {
        let end = Date()
        return DateInterval(
            start: end.addingTimeInterval(-24 * 60 * 60),
            end: end
        )
    }
}

private actor HealthSampleClientSpy: HealthSampleClient {
    enum TestError: Error {
        case failed
    }

    nonisolated let isHealthDataAvailable = true
    private let quantityResults: [HKQuantitySample]
    private let categoryResults: [HKCategorySample]
    private let queryError: Error?
    private var capturedIdentifier: String?
    private var capturedInterval: DateInterval?

    init(
        samples: [HKQuantitySample],
        queryError: Error? = nil
    ) {
        quantityResults = samples
        categoryResults = []
        self.queryError = queryError
    }

    init(
        quantitySamples: [HKQuantitySample],
        categorySamples: [HKCategorySample],
        queryError: Error? = nil
    ) {
        quantityResults = quantitySamples
        categoryResults = categorySamples
        self.queryError = queryError
    }

    func quantitySamples(
        for type: HKQuantityType,
        interval: DateInterval
    ) async throws -> [HKQuantitySample] {
        capturedIdentifier = type.identifier
        capturedInterval = interval
        if let queryError {
            throw queryError
        }
        return quantityResults
    }

    func categorySamples(
        for type: HKCategoryType,
        interval: DateInterval
    ) async throws -> [HKCategorySample] {
        capturedIdentifier = type.identifier
        capturedInterval = interval
        if let queryError {
            throw queryError
        }
        return categoryResults
    }

    func requestedIdentifier() -> String? {
        capturedIdentifier
    }

    func requestedInterval() -> DateInterval? {
        capturedInterval
    }
}

private actor HealthAccessServiceStub: HealthAccessService {
    func accessState() async -> HealthAccessState {
        .requestCompleted
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {}
}

private actor HealthDataServiceStub: HealthDataService {
    private let currentAccessState: HealthAccessState
    private let results: [
        HealthMetricType: Result<[HealthMetricSample], HealthDataServiceError>
    ]
    private var capturedMetrics = Set<HealthMetricType>()

    init(
        accessState: HealthAccessState,
        results: [
            HealthMetricType: Result<[HealthMetricSample], HealthDataServiceError>
        ]
    ) {
        currentAccessState = accessState
        self.results = results
    }

    func accessState() async -> HealthAccessState {
        currentAccessState
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {}

    func fetchSamples(
        for metric: HealthMetricType,
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        capturedMetrics.insert(metric)
        return try results[metric, default: .success([])].get()
    }

    func queriedMetrics() -> Set<HealthMetricType> {
        capturedMetrics
    }
}
