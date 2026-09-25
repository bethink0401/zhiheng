import Foundation
import XCTest
@testable import Zhiheng

final class DemoHealthDataServiceTests: XCTestCase {
    func testDemoProviderIsExplicitAndNeedsNoHealthPermission() async throws {
        let service = try DemoHealthDataService(drafts: [])

        let dataMode = await service.dataMode
        let accessState = await service.accessState()
        XCTAssertEqual(dataMode, .demo)
        XCTAssertEqual(accessState, .requestCompleted)
        try await service.requestReadAccess(for: Set(HealthMetricType.allCases))
    }

    func testDraftsBecomeDeterministicClearlyLabeledDomainSamples() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(24 * 60 * 60)
        let drafts = [
            DemoHealthSampleDraft(
                metricType: .stepCount,
                startDate: secondDate,
                endDate: secondDate.addingTimeInterval(60),
                value: 7_200
            ),
            DemoHealthSampleDraft(
                metricType: .stepCount,
                startDate: firstDate,
                endDate: firstDate.addingTimeInterval(60),
                value: 6_800
            )
        ]
        let service = try DemoHealthDataService(drafts: drafts)
        let interval = DateInterval(
            start: firstDate.addingTimeInterval(-60),
            end: secondDate.addingTimeInterval(120)
        )

        let samples = try await service.fetchSamples(
            for: .stepCount,
            interval: interval
        )

        XCTAssertEqual(samples.map(\.value), [6_800, 7_200])
        XCTAssertTrue(samples.allSatisfy { $0.unit == .count })
        XCTAssertTrue(samples.allSatisfy {
            $0.source.sourceName == DemoHealthDataService.sourceName
        })
        XCTAssertEqual(samples.first?.id.uuidString, "00000000-0000-4000-8000-000000000002")
    }

    func testProviderFiltersByMetricAndRequestedWindow() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try DemoHealthDataService(drafts: [
            DemoHealthSampleDraft(
                metricType: .sleepDuration,
                startDate: date,
                endDate: date.addingTimeInterval(7 * 60 * 60),
                value: 7
            ),
            DemoHealthSampleDraft(
                metricType: .heartRateVariability,
                startDate: date,
                endDate: date.addingTimeInterval(60),
                value: 45
            )
        ])

        let samples = try await service.fetchSamples(
            for: .sleepDuration,
            interval: DateInterval(
                start: date.addingTimeInterval(-60),
                end: date.addingTimeInterval(8 * 60 * 60)
            )
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricType, .sleepDuration)
        XCTAssertEqual(samples.first?.unit, .hours)
    }

    func testDashboardScenarioProvidesEveryDashboardMetric() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.dashboard(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(byAdding: .day, value: -40, to: endDate)),
            end: endDate.addingTimeInterval(60)
        )

        for metric in HealthMetricType.allCases {
            let samples = try await service.fetchSamples(for: metric, interval: interval)
            XCTAssertFalse(samples.isEmpty, "\(metric.rawValue) should have demo samples")
            XCTAssertTrue(samples.allSatisfy { $0.unit == metric.expectedUnit })
            XCTAssertTrue(samples.allSatisfy {
                $0.source.sourceName == DemoHealthDataService.sourceName
            })
        }

        let sleep = try await service.fetchSamples(for: .sleepDuration, interval: interval)
        XCTAssertTrue(Set(sleep.compactMap(\.sleepStage)).isSuperset(
            of: Set(HealthSleepStage.displayedStages)
        ))
        XCTAssertEqual(
            sleep.filter { $0.sleepStage == .awake }.map(\.value).reduce(0, +),
            0
        )
    }

    func testDashboardScenarioUsesNinetyDayNaturalHistoryAndARealMissingDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.dashboard(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(byAdding: .day, value: -100, to: endDate)),
            end: endDate.addingTimeInterval(24 * 60 * 60)
        )

        let restingHeartRate = try await service.fetchSamples(
            for: .restingHeartRate,
            interval: interval
        )
        let hrv = try await service.fetchSamples(
            for: .heartRateVariability,
            interval: interval
        )
        let sleep = try await service.fetchSamples(
            for: .sleepDuration,
            interval: interval
        )

        XCTAssertEqual(restingHeartRate.count, 90)
        XCTAssertEqual(hrv.filter { calendar.component(.hour, from: $0.endDate) == 7 }.count, 89)
        XCTAssertFalse(hrv.contains { $0.value == 0 })
        XCTAssertGreaterThan(Set(restingHeartRate.prefix(28).map { Int($0.value * 10) }).count, 12)

        let sleepByDay = Dictionary(grouping: sleep) {
            calendar.startOfDay(for: $0.endDate)
        }.mapValues { $0.map(\.value).reduce(0, +) }
        let recentSleep = sleepByDay.keys.sorted().suffix(8).compactMap { sleepByDay[$0] }
        XCTAssertEqual(recentSleep.count, 8)
        XCTAssertEqual(try XCTUnwrap(recentSleep.first), 6.90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recentSleep.last), 6.47, accuracy: 0.001)
        XCTAssertGreaterThan(Set(sleepByDay.values.map { Int($0 * 100) }).count, 20)
    }

    func testDashboardActivityUsesVariedDailyTotalsAndAwakeHourPatterns() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.dashboard(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: endDate))),
            end: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)))
        )
        let steps = try await service.fetchSamples(for: .stepCount, interval: interval)
        let energy = try await service.fetchSamples(for: .activeEnergy, interval: interval)
        let stepTotals = Dictionary(grouping: steps) {
            calendar.startOfDay(for: $0.endDate)
        }.mapValues { $0.map(\.value).reduce(0, +) }
        let energyTotals = Dictionary(grouping: energy) {
            calendar.startOfDay(for: $0.endDate)
        }.mapValues { $0.map(\.value).reduce(0, +) }
        let days = stepTotals.keys.sorted()
        let recentSteps = days.compactMap { stepTotals[$0] }
        let recentEnergy = days.compactMap { energyTotals[$0] }

        XCTAssertEqual(recentSteps.count, 8)
        XCTAssertEqual(recentSteps.map { Int($0.rounded()) }, [
            8_240, 10_680, 7_360, 12_140, 8_910, 10_420, 7_780, 9_630,
        ])
        XCTAssertEqual(recentEnergy.map { Int($0.rounded()) }, [
            418, 572, 386, 648, 463, 594, 521, 489,
        ])
        XCTAssertTrue((steps + energy).allSatisfy {
            (6...22).contains(calendar.component(.hour, from: $0.endDate))
        })
        let kcalPerThousandSteps = zip(recentEnergy, recentSteps).map {
            Int(($0.0 / $0.1 * 1_000).rounded())
        }
        XCTAssertGreaterThan(Set(kcalPerThousandSteps).count, 4)
        XCTAssertTrue(zip(recentSteps, recentSteps.dropFirst()).contains { $0.1 < $0.0 })
        XCTAssertTrue(zip(recentSteps, recentSteps.dropFirst()).contains { $0.1 > $0.0 })
    }

    @MainActor
    func testDemoSubjectiveStoreProvidesCoherentEditableInMemoryCheckInsAndEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 12
        )))
        let store = DemoSubjectiveRecordStore(
            endingAt: endDate,
            calendar: calendar
        )
        let localDay = SubjectiveLocalDay(date: endDate, timeZone: calendar.timeZone)
        let today = try XCTUnwrap(store.checkIn(on: localDay))

        XCTAssertEqual(today.energy, .two)
        XCTAssertEqual(today.stress, .four)
        XCTAssertEqual(today.bodyFeeling, .three)
        XCTAssertTrue(today.note?.contains("工作节奏") == true)

        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: endDate)),
            end: endDate.addingTimeInterval(24 * 60 * 60)
        )
        let events = try store.contextEvents(overlapping: interval)
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.contains { $0.kind == .deviceNotWorn })
        XCTAssertTrue(events.contains { $0.kind == .deadline })
        let updated = try DailyCheckIn(
            id: today.id,
            localDay: localDay,
            energy: .four,
            stress: .two,
            bodyFeeling: .four,
            note: "演示修改",
            recordedAt: today.recordedAt,
            updatedAt: endDate
        )
        XCTAssertEqual(try store.save(updated), updated)
        XCTAssertEqual(try store.checkIn(on: localDay), updated)

        let event = try ContextEvent(
            kind: .travel,
            startedAt: endDate,
            note: "演示新增",
            createdAt: endDate
        )
        try store.save(event)
        XCTAssertTrue(try store.contextEvents(overlapping: interval).contains { $0.id == event.id })
        try store.deleteContextEvent(id: event.id)
        XCTAssertFalse(try store.contextEvents(overlapping: interval).contains { $0.id == event.id })

        try store.deleteCheckIn(on: localDay)
        XCTAssertNil(try store.checkIn(on: localDay))
    }

    func testSleepDeclineScenarioHasStableBaselineAndSevenDayDecline() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.sleepDecline(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(
                byAdding: .day,
                value: -40,
                to: endDate
            )),
            end: endDate
        )

        let samples = try await service.fetchSamples(
            for: .sleepDuration,
            interval: interval
        )

        XCTAssertEqual(samples.count, 35)
        XCTAssertEqual(Array(samples.suffix(7).map(\.value)), [
            7.0, 6.8, 6.6, 6.4, 6.2, 6.0, 5.8
        ])
        XCTAssertTrue(samples.prefix(28).allSatisfy {
            (7.3...7.6).contains($0.value)
        })
        XCTAssertTrue(samples.allSatisfy { sample in
            sample.unit == .hours
                && sample.source.sourceName == DemoHealthDataService.sourceName
                && sample.endDate.timeIntervalSince(sample.startDate)
                    == sample.value * 60 * 60
        })
    }

    func testActivityLoadScenarioRaisesEnergyAndExerciseTogether() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.activityLoadIncrease(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(
                byAdding: .day,
                value: -40,
                to: endDate
            )),
            end: endDate
        )

        let energy = try await service.fetchSamples(
            for: .activeEnergy,
            interval: interval
        )
        let exercise = try await service.fetchSamples(
            for: .exerciseDuration,
            interval: interval
        )

        XCTAssertEqual(energy.count, 35)
        XCTAssertEqual(exercise.count, 35)
        XCTAssertEqual(Array(energy.suffix(7).map(\.value)), [
            350, 400, 450, 500, 550, 600, 650
        ])
        XCTAssertEqual(Array(exercise.suffix(7).map(\.value)), [
            35, 40, 45, 50, 55, 60, 65
        ])
        XCTAssertEqual(energy.map(\.startDate), exercise.map(\.startDate))
        XCTAssertTrue(energy.allSatisfy { $0.unit == .kilocalories })
        XCTAssertTrue(exercise.allSatisfy { $0.unit == .minutes })
    }

    func testMissingWearableScenarioUsesAbsenceInsteadOfZero() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 21,
            hour: 12
        )))
        let service = try DemoHealthScenarioFactory.missingWearableData(
            endingAt: endDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(
                byAdding: .day,
                value: -40,
                to: endDate
            )),
            end: endDate
        )

        let steps = try await service.fetchSamples(
            for: .stepCount,
            interval: interval
        )
        let heartRate = try await service.fetchSamples(
            for: .restingHeartRate,
            interval: interval
        )

        XCTAssertEqual(steps.count, 31)
        XCTAssertEqual(heartRate.count, 31)
        XCTAssertFalse(steps.contains { $0.value == 0 })
        XCTAssertFalse(heartRate.contains { $0.value == 0 })
        let lastStep = try XCTUnwrap(steps.last)
        let missingDays = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: lastStep.endDate),
            to: calendar.startOfDay(for: endDate)
        ).day
        XCTAssertEqual(missingDays, 4)
    }
}
