import Foundation
import XCTest
@testable import Zhiheng

final class TodayDashboardPresentationTests: XCTestCase {
    func testFeelingDotsFollowRatingDegreeWithReversedStressDirection() {
        let positiveTones: [DailyFeelingTone] = [.strongWarm, .warm, .neutral, .cool, .strongCool]
        for (index, rating) in SubjectiveRating.allCases.enumerated() {
            XCTAssertEqual(DailyFeelingField.energy.tone(for: rating), positiveTones[index])
            XCTAssertEqual(DailyFeelingField.bodyFeeling.tone(for: rating), positiveTones[index])
            XCTAssertEqual(DailyFeelingField.stress.tone(for: rating), positiveTones[4 - index])
        }
    }

    func testEveryFeelingFieldTintsBothExtremesAndEmphasizesThemMore() throws {
        for field in DailyFeelingField.allCases {
            for (extreme, nearby) in [(SubjectiveRating.one, SubjectiveRating.two), (.five, .four)] {
                let strong = try XCTUnwrap(field.tone(for: extreme))
                let soft = try XCTUnwrap(field.tone(for: nearby))
                XCTAssertTrue(strong.hasTint)
                XCTAssertTrue(soft.hasTint)
                XCTAssertGreaterThan(strong.backgroundOpacity, soft.backgroundOpacity)
                XCTAssertGreaterThan(strong.borderOpacity, soft.borderOpacity)
            }
            XCTAssertEqual(field.tone(for: .three)?.hasTint, false)
        }
    }

    func testUnrecordedFeelingsHaveNoDegreeColor() {
        for field in DailyFeelingField.allCases {
            XCTAssertNil(field.tone(for: nil))
        }
    }

    func testTodayStateCardsMatchReferenceAspectRatioAcrossPhoneWidths() {
        for containerWidth in [339.0, 366.0, 394.0] {
            let width = TodayStateCardsLayout.cardWidth(containerWidth: containerWidth)
            let height = TodayStateCardsLayout.cardHeight(width: width, contentHeight: 180)
            XCTAssertEqual(width * 2 + TodayStateCardsLayout.spacing, containerWidth)
            XCTAssertEqual(width / height, 484.0 / 568.0, accuracy: 0.001)
            XCTAssertLessThan(height, 236)
        }
    }

    func testTodayStateCardsExpandForLongContentInsteadOfClipping() {
        XCTAssertEqual(TodayStateCardsLayout.cardHeight(width: 176, contentHeight: 310), 310)
    }

    func testTodayHRVVisualStateMatchesReferenceState() {
        let current = TodayDashboardMetricValue(
            metric: .heartRateVariability,
            value: 50,
            unit: .milliseconds,
            date: Date(timeIntervalSince1970: 0),
            sourceName: "Apple Watch"
        )

        XCTAssertEqual(
            TodayLoadReference.insufficient(currentHRV: nil).visualState,
            .unavailable
        )
        XCTAssertEqual(
            TodayLoadReference.insufficient(currentHRV: current).visualState,
            .learning
        )

        for (level, expected) in [
            (TodayLoadReference.Level.belowPersonalRange, HRVVisualState.belowPersonalRange),
            (.nearPersonalRange, .nearPersonalRange),
            (.abovePersonalRange, .abovePersonalRange)
        ] {
            let reference = TodayLoadReference.available(
                currentHRV: current,
                baseline: HealthMetricBaseline(
                    metric: .heartRateVariability,
                    interval: DateInterval(
                        start: Date(timeIntervalSince1970: -28 * 86_400),
                        end: Date(timeIntervalSince1970: 0)
                    ),
                    expectedDayCount: 28,
                    validDayCount: 28,
                    coverageRatio: 1,
                    medianValue: 50,
                    medianAbsoluteDeviation: 2,
                    unit: .milliseconds
                ),
                relativeDifference: 0,
                level: level
            )
            XCTAssertEqual(reference.visualState, expected)
        }
    }

    func testSelectedDateUsesOnlyThatDaysGoalData() throws {
        let context = try makeContext()
        let samples = [
            try sample(.stepCount, value: 8_000, day: context.days[1], hour: 10),
            try sample(.stepCount, value: 4_000, day: context.days[0], hour: 10)
        ]
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: samples]),
            selectedDate: context.days[0],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.values[.stepCount]?.value, 4_000)
        guard case let .available(progress) = presentation.goalProgress else {
            return XCTFail("Expected goal progress")
        }
        XCTAssertEqual(progress.percentage, 50)
    }

    func testSelectedDatePreservesStepAndActiveEnergyTotalsAndUnits() throws {
        let context = try makeContext()
        let steps = [
            try sample(.stepCount, value: 1_500, day: context.days[0], hour: 8),
            try sample(.stepCount, value: 2_500, day: context.days[0], hour: 18),
            try sample(.stepCount, value: 9_000, day: context.days[1], hour: 18)
        ]
        let energy = [
            try sample(.activeEnergy, value: 120, day: context.days[0], hour: 8),
            try sample(.activeEnergy, value: 360, day: context.days[0], hour: 18),
            try sample(.activeEnergy, value: 800, day: context.days[1], hour: 18)
        ]
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: steps, .activeEnergy: energy]),
            selectedDate: context.days[0],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.values[.stepCount]?.value, 4_000)
        XCTAssertEqual(presentation.values[.stepCount]?.unit, .count)
        XCTAssertEqual(presentation.values[.activeEnergy]?.value, 480)
        XCTAssertEqual(presentation.values[.activeEnergy]?.unit, .kilocalories)
        XCTAssertEqual(presentation.stepHourlyBars[8].value, 1_500)
        XCTAssertEqual(presentation.stepHourlyBars[18].value, 2_500)
        XCTAssertEqual(presentation.energyHourlyBars[8].value, 120)
        XCTAssertEqual(presentation.energyHourlyBars[18].value, 360)
    }

    func testDateWindowCanPageIndependentlyFromToday() throws {
        let context = try makeContext(dayCount: 15)
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([:]),
            selectedDate: context.days[7],
            today: context.days[14],
            dateWindowEnd: context.days[7],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.dateStatuses.map(\.date), Array(context.days[1...7]))
    }

    func testHourlySeriesHasTwentyFourModelDrivenBuckets() throws {
        let context = try makeContext()
        let samples = [
            try sample(.stepCount, value: 200, day: context.days[1], hour: 8),
            try sample(.stepCount, value: 300, day: context.days[1], hour: 8),
            try sample(.stepCount, value: 400, day: context.days[1], hour: 12)
        ]
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: samples]),
            selectedDate: context.days[1],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.stepHourlyBars.count, 24)
        XCTAssertEqual(presentation.stepHourlyBars[8].value, 500)
        XCTAssertEqual(presentation.stepHourlyBars[12].value, 400)
    }

    func testNightVitalsAreAveragedOnlyInsideSleepInterval() throws {
        let context = try makeContext()
        let sleep = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: context.days[1].addingTimeInterval(-7 * 60 * 60),
            endDate: context.days[1].addingTimeInterval(7 * 60 * 60),
            value: 7,
            unit: .hours,
            source: source
        )
        let heart = [
            try sample(.heartRate, value: 50, day: context.days[1], hour: 1),
            try sample(.heartRate, value: 60, day: context.days[1], hour: 5),
            try sample(.heartRate, value: 120, day: context.days[1], hour: 12)
        ]
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: [sleep], .heartRate: heart]),
            selectedDate: context.days[1],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        let sleepingHeartRate = presentation.nightVitals.first { $0.metric == .heartRate }
        XCTAssertEqual(sleepingHeartRate?.value, 55)
    }

    func testNightContextPrefersWatchSleepWhenPhoneAlsoWritesSleep() throws {
        let context = try makeContext()
        let wakeDate = context.days[1].addingTimeInterval(7 * 60 * 60)
        let phoneSource = HealthMetricSource(
            sourceName: "iPhone",
            bundleIdentifier: nil,
            deviceName: "iPhone"
        )
        let watchSleep = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: wakeDate.addingTimeInterval(-7 * 60 * 60),
            endDate: wakeDate,
            value: 7,
            unit: .hours,
            source: source,
            sleepStage: .core
        )
        let phoneSleep = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: wakeDate.addingTimeInterval(-8 * 60 * 60),
            endDate: wakeDate,
            value: 8,
            unit: .hours,
            source: phoneSource,
            sleepStage: .core
        )
        let sleepingHeart = try sample(
            .heartRate,
            value: 56,
            day: context.days[1],
            hour: 3
        )
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([
                .sleepDuration: [phoneSleep, watchSleep],
                .heartRate: [sleepingHeart]
            ]),
            selectedDate: context.days[1],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.values[.sleepDuration]?.value, 7)
        XCTAssertEqual(presentation.nightVitals.first { $0.metric == .heartRate }?.value, 56)
    }

    func testSleepPresentationPreservesHealthKitStageAndAwakeDuration() throws {
        let context = try makeContext()
        let sleepEnd = context.days[1].addingTimeInterval(7 * 60 * 60)
        let core = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: sleepEnd.addingTimeInterval(-2 * 60 * 60),
            endDate: sleepEnd.addingTimeInterval(-30 * 60),
            value: 1.5,
            unit: .hours,
            source: source,
            sleepStage: .core
        )
        let awake = try HealthMetricSample(
            id: UUID(),
            metricType: .sleepDuration,
            startDate: sleepEnd.addingTimeInterval(-30 * 60),
            endDate: sleepEnd,
            value: 0,
            unit: .hours,
            source: source,
            sleepStage: .awake
        )
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: [core, awake]]),
            selectedDate: context.days[1],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.values[.sleepDuration]?.value, 1.5)
        XCTAssertEqual(presentation.sleepSegments.map(\.stage), [.core, .awake])
        XCTAssertEqual(
            presentation.sleepSegments.last?.endDate.timeIntervalSince(
                presentation.sleepSegments.last?.startDate ?? sleepEnd
            ),
            30 * 60
        )
    }

    func testLoadReferenceRequiresFourteenPriorValidDays() throws {
        let context = try makeContext(dayCount: 16)
        let hrv = try context.days.enumerated().map { index, day in
            try sample(.heartRateVariability, value: index == 15 ? 35 : 50, day: day, hour: 7)
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.heartRateVariability: hrv]),
            selectedDate: context.days[15],
            today: context.days[15],
            goals: .standard,
            calendar: context.calendar
        )

        guard case let .available(_, baseline, difference, level) = presentation.loadReference else {
            return XCTFail("Expected load reference")
        }
        XCTAssertEqual(baseline.validDayCount, 15)
        XCTAssertEqual(difference, -0.3, accuracy: 0.0001)
        XCTAssertEqual(level, .belowPersonalRange)
    }

    func testRecoveryStaysUnavailableWithTooFewComponents() throws {
        let context = try makeContext()
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([
                .sleepDuration: [try sample(.sleepDuration, value: 7, day: context.days[1], hour: 7)]
            ]),
            selectedDate: context.days[1],
            today: context.days[1],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(
            presentation.trainingReadiness,
            .insufficient(availableComponentCount: 1, requiredComponentCount: 4)
        )
    }

    func testCompleteDemoNightUsesDirectSleepAssessment() async throws {
        let context = try makeContext(dayCount: 35)
        let selectedDate = try XCTUnwrap(context.days.last)
        let service = try DemoHealthScenarioFactory.dashboard(
            endingAt: selectedDate.addingTimeInterval(12 * 60 * 60),
            calendar: context.calendar
        )
        let interval = DateInterval(
            start: context.days[0],
            end: selectedDate.addingTimeInterval(24 * 60 * 60)
        )
        let snapshot = await service.loadSnapshot(
            for: Set(HealthMetricType.allCases),
            interval: interval
        )
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot,
            selectedDate: selectedDate,
            today: selectedDate,
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.nightSummary.title, "指标正常，睡得不错")
        XCTAssertGreaterThanOrEqual(presentation.nightSummary.availableVitalCount, 3)
    }

    func testImportantChangeExplainsSustainedSleepDeclineWithDataQuality() throws {
        let context = try makeContext(dayCount: 35)
        let sleep = try context.days.enumerated().map { index, day in
            try sample(
                .sleepDuration,
                value: index < 28 ? 7.5 : 6.5,
                day: day,
                hour: 7
            )
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: sleep]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        let change = try XCTUnwrap(presentation.importantChange)
        XCTAssertEqual(change.metric, .sleepDuration)
        XCTAssertTrue(change.whatChanged.contains("减少 13%"))
        XCTAssertEqual(change.currentMedian, 6.5, accuracy: 0.001)
        XCTAssertTrue(change.actionText.contains("固定上床时间"))
    }

    func testImportantChangeRequiresFourRecentValidDays() throws {
        let context = try makeContext(dayCount: 35)
        let baseline = try context.days.prefix(28).map {
            try sample(.stepCount, value: 8_000, day: $0, hour: 20)
        }
        let recent = try context.days.suffix(3).map {
            try sample(.stepCount, value: 3_000, day: $0, hour: 20)
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: baseline + recent]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertNil(presentation.importantChange)
    }

    func testImportantChangeIgnoresSingleDayOutlier() throws {
        let context = try makeContext(dayCount: 35)
        let steps = try context.days.enumerated().map { index, day in
            try sample(
                .stepCount,
                value: index == 34 ? 2_000 : 8_000,
                day: day,
                hour: 20
            )
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: steps]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertNil(presentation.importantChange)
    }

    func testImportantChangeKeepsSustainedShiftWhenOneOutlierCanBeExcluded() throws {
        let context = try makeContext(dayCount: 35)
        let sleep = try context.days.enumerated().map { index, day in
            let value: Double
            if index < 28 {
                value = 8
            } else if index == 34 {
                value = 2
            } else {
                value = 7.2
            }
            return try sample(
                .sleepDuration,
                value: value,
                day: day,
                hour: 7
            )
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: sleep]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        let change = try XCTUnwrap(presentation.importantChange)
        XCTAssertEqual(change.metric, .sleepDuration)
        XCTAssertTrue(change.whatChanged.contains("减少 10%"))
        XCTAssertEqual(change.currentMedian, 7.2, accuracy: 0.001)
    }

    func testImportantChangeCardValueUsesWindowMedianNotLatestDay() throws {
        let context = try makeContext(dayCount: 35)
        let samples = try context.days.enumerated().map { index, day in
            try sample(.sleepDuration, value: index < 28 ? 8 : (index == 34 ? 7 : 6), day: day, hour: 7)
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: samples]),
            selectedDate: context.days[34], today: context.days[34],
            goals: .standard, calendar: context.calendar
        )
        let change = try XCTUnwrap(presentation.importantChange)
        XCTAssertEqual(change.currentMedian, 6, accuracy: 0.001)
        XCTAssertEqual(change.relativeDifference, -0.25, accuracy: 0.001)
        XCTAssertEqual(change.metricTitle, "睡眠时长")
        XCTAssertEqual(change.metric.expectedUnit, .hours)
    }

    func testImportantChangeCardEnergyValueAndPercentageShareTheSameTrend() throws {
        let context = try makeContext(dayCount: 35)
        let samples = try context.days.enumerated().map { index, day in
            try sample(.activeEnergy, value: index < 28 ? 500 : 650, day: day, hour: 20)
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.activeEnergy: samples]),
            selectedDate: context.days[34], today: context.days[34],
            goals: .standard, calendar: context.calendar
        )
        let change = try XCTUnwrap(presentation.importantChange)
        XCTAssertEqual(change.currentMedian, 650, accuracy: 0.001)
        XCTAssertEqual(change.relativeDifference, 0.3, accuracy: 0.001)
        XCTAssertEqual(change.metricTitle, "活动能量")
        XCTAssertEqual(change.metric.expectedUnit, .kilocalories)
        XCTAssertTrue(change.whatChanged.contains("650"))
    }

    func testImportantChangeSelectsOnlyStrongestQualifiedChange() throws {
        let context = try makeContext(dayCount: 35)
        let sleep = try context.days.enumerated().map { index, day in
            try sample(
                .sleepDuration,
                value: index < 28 ? 7 : 6.3,
                day: day,
                hour: 7
            )
        }
        let steps = try context.days.enumerated().map { index, day in
            try sample(
                .stepCount,
                value: index < 28 ? 8_000 : 4_800,
                day: day,
                hour: 20
            )
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.sleepDuration: sleep, .stepCount: steps]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertEqual(presentation.importantChange?.metric, .stepCount)
    }

    func testImportantChangeStopsWhenDataSourceChanges() throws {
        let context = try makeContext(dayCount: 35)
        let phoneSource = HealthMetricSource(
            sourceName: "iPhone",
            bundleIdentifier: "com.apple.health.phone",
            deviceName: "iPhone"
        )
        let baseline = try context.days.prefix(28).map {
            try sample(.stepCount, value: 8_000, day: $0, hour: 20)
        }
        let recent = try context.days.suffix(7).map { day in
            let end = day.addingTimeInterval(20 * 60 * 60)
            return try HealthMetricSample(
                id: UUID(),
                metricType: .stepCount,
                startDate: end.addingTimeInterval(-60),
                endDate: end,
                value: 4_000,
                unit: .count,
                source: phoneSource
            )
        }
        let presentation = TodayDashboardPresentationFactory.make(
            snapshot: snapshot([.stepCount: baseline + recent]),
            selectedDate: context.days[34],
            today: context.days[34],
            goals: .standard,
            calendar: context.calendar
        )

        XCTAssertNil(presentation.importantChange)
    }

    private func makeContext(dayCount: Int = 2) throws -> (
        calendar: Calendar,
        days: [Date]
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1
        )))
        let days = try (0..<dayCount).map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: first))
        }
        return (calendar, days)
    }

    private var source: HealthMetricSource {
        HealthMetricSource(
            sourceName: "Apple Watch",
            bundleIdentifier: nil,
            deviceName: "Apple Watch"
        )
    }

    private func sample(
        _ metric: HealthMetricType,
        value: Double,
        day: Date,
        hour: Int
    ) throws -> HealthMetricSample {
        let end = day.addingTimeInterval(Double(hour) * 60 * 60)
        let start = metric == .sleepDuration
            ? end.addingTimeInterval(-value * 60 * 60)
            : end.addingTimeInterval(-60)
        return try HealthMetricSample(
            id: UUID(),
            metricType: metric,
            startDate: start,
            endDate: end,
            value: value,
            unit: metric.expectedUnit,
            source: source
        )
    }

    private func snapshot(
        _ samples: [HealthMetricType: [HealthMetricSample]]
    ) -> HealthDataSnapshot {
        HealthDataSnapshot(states: Dictionary(uniqueKeysWithValues:
            HealthMetricType.allCases.map { metric in
                let values = samples[metric, default: []]
                return (metric, values.isEmpty ? .noVisibleData : .available(values))
            }
        ))
    }
}
