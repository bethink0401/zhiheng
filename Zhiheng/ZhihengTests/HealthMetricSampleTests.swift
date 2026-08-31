import Foundation
import XCTest
@testable import Zhiheng

final class HealthMetricSampleTests: XCTestCase {
    private let source = HealthMetricSource(
        sourceName: "测试来源",
        bundleIdentifier: "com.example.fixture",
        deviceName: nil
    )

    func testRealZeroRemainsARealSampleInsteadOfMissingData() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try HealthMetricSample(
            id: UUID(),
            metricType: .stepCount,
            startDate: date,
            endDate: date,
            value: 0,
            unit: .count,
            source: source
        )
        let missing: [HealthMetricSample] = []

        XCTAssertEqual(sample.value, 0)
        XCTAssertEqual([sample].count, 1)
        XCTAssertTrue(missing.isEmpty)
    }

    func testRejectsNegativeAndNonFiniteValues() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertThrowsError(
            try HealthMetricSample(
                id: UUID(),
                metricType: .restingHeartRate,
                startDate: date,
                endDate: date,
                value: -1,
                unit: .beatsPerMinute,
                source: source
            )
        ) { error in
            XCTAssertEqual(error as? HealthMetricSampleValidationError, .negativeValue)
        }

        XCTAssertThrowsError(
            try HealthMetricSample(
                id: UUID(),
                metricType: .heartRateVariability,
                startDate: date,
                endDate: date,
                value: .nan,
                unit: .milliseconds,
                source: source
            )
        ) { error in
            XCTAssertEqual(error as? HealthMetricSampleValidationError, .nonFiniteValue)
        }
    }

    func testRejectsReversedIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        let end = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertThrowsError(
            try HealthMetricSample(
                id: UUID(),
                metricType: .sleepDuration,
                startDate: start,
                endDate: end,
                value: 7,
                unit: .hours,
                source: source
            )
        ) { error in
            XCTAssertEqual(error as? HealthMetricSampleValidationError, .invalidInterval)
        }
    }

    func testEveryMetricHasOneExpectedDomainUnit() {
        let expected: [HealthMetricType: HealthMetricUnit] = [
            .stepCount: .count,
            .sleepDuration: .hours,
            .restingHeartRate: .beatsPerMinute,
            .heartRateVariability: .milliseconds,
            .activeEnergy: .kilocalories,
            .exerciseDuration: .minutes,
            .standHours: .hours,
            .heartRate: .beatsPerMinute,
            .respiratoryRate: .breathsPerMinute,
            .oxygenSaturation: .percentage,
            .wristTemperature: .degreesCelsius,
            .walkingRunningDistance: .kilometers,
            .flightsClimbed: .floors,
            .walkingSpeed: .metersPerSecond,
            .walkingStepLength: .meters,
            .vo2Max: .millilitersPerKilogramPerMinute
        ]

        XCTAssertEqual(HealthMetricType.allCases.count, expected.count)
        for metric in HealthMetricType.allCases {
            XCTAssertEqual(metric.expectedUnit, expected[metric])
        }
    }

    func testInitialConnectionMetricsRemainTheOriginalSixCoreMetrics() {
        XCTAssertEqual(HealthMetricType.initialConnectionMetrics, [
            .stepCount,
            .sleepDuration,
            .restingHeartRate,
            .heartRateVariability,
            .activeEnergy,
            .exerciseDuration
        ])
        XCTAssertEqual(HealthMetricType.allCases.count, 16)
    }

    func testRejectsMetricAndUnitMismatch() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertThrowsError(
            try HealthMetricSample(
                id: UUID(),
                metricType: .stepCount,
                startDate: date,
                endDate: date,
                value: 1,
                unit: .hours,
                source: source
            )
        ) { error in
            XCTAssertEqual(error as? HealthMetricSampleValidationError, .invalidUnit)
        }
    }
}
