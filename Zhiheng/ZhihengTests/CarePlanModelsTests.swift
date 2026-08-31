import Foundation
import XCTest
@testable import Zhiheng

final class CarePlanModelsTests: XCTestCase {
    func testTemplateLibraryCoversEveryAIPlanAndBuildsFiveDayDrafts() throws {
        XCTAssertEqual(
            Set(MicroPlanTemplateLibrary.all.map(\.id)),
            Set(MicroPlanTemplateID.allCases)
        )
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let stableID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )

        for template in MicroPlanTemplateLibrary.all {
            let draft = try template.makeDraft(
                referenceDate: referenceDate,
                calendar: calendar,
                uniqueID: stableID
            )
            XCTAssertEqual(
                calendar.dateComponents(
                    [.day],
                    from: draft.startDate,
                    to: draft.endDateExclusive
                ).day,
                5
            )
            XCTAssertTrue(draft.id.rawValue.contains(template.id.rawValue))
            XCTAssertTrue(draft.taskID.rawValue.contains(template.id.rawValue))
            XCTAssertFalse(draft.title.isEmpty)
            XCTAssertFalse(draft.taskTitle.isEmpty)
            XCTAssertEqual(draft.templateID, template.id)
        }
    }

    func testEveryPlanTemplateSelectsItsRelevantTrendCards() {
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .earlierBedtime),
            [.sleepOnset, .sleepDuration]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .afternoonWalk),
            [.stepCount, .activeEnergy]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .movementBreak),
            [.standHours, .stepCount]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .reducedTrainingLoad),
            [.exerciseDuration, .heartRateVariability]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .morningDaylight),
            [.sleepOnset, .sleepDuration]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .afterMealWalk),
            [.stepCount, .walkingRunningDistance]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .consistentWakeTime),
            [.sleepOnset, .sleepDuration]
        )
        XCTAssertEqual(
            MicroPlanTrendPresentationFactory.metrics(for: .gentleMobility),
            [.exerciseDuration, .activeEnergy]
        )
    }

    func testSleepPlanTrendComparesPlanDaysWithPriorDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try date(2026, 1, 10, 0, 0, calendar: calendar)
        let template = try XCTUnwrap(
            MicroPlanTemplateLibrary.template(for: .earlierBedtime)
        )
        let draft = try template.makeDraft(
            referenceDate: start,
            calendar: calendar,
            uniqueID: try XCTUnwrap(
                UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
            )
        )
        let source = HealthMetricSource(
            sourceName: "Apple Watch",
            bundleIdentifier: "test.watch",
            deviceName: "Watch"
        )
        let samples = try (5...14).map { wakeDay in
            let isPlanDay = wakeDay >= 10
            let onsetHour = isPlanDay ? 22 : 23
            let onsetDay = wakeDay - 1
            return try HealthMetricSample(
                id: UUID(),
                metricType: .sleepDuration,
                startDate: date(2026, 1, onsetDay, onsetHour, 30, calendar: calendar),
                endDate: date(2026, 1, wakeDay, 6, 30, calendar: calendar),
                value: isPlanDay ? 8 : 7,
                unit: .hours,
                source: source,
                sleepStage: .core
            )
        }
        let snapshot = HealthDataSnapshot(states: [
            .sleepDuration: .available(samples)
        ])

        let cards = MicroPlanTrendPresentationFactory.make(
            plan: MicroPlan(draft: draft, status: .active),
            snapshot: snapshot,
            referenceDate: try date(2026, 1, 14, 12, 0, calendar: calendar),
            calendar: calendar
        )

        let onset = try XCTUnwrap(cards.first { $0.metric == .sleepOnset })
        let duration = try XCTUnwrap(cards.first { $0.metric == .sleepDuration })
        XCTAssertEqual(onset.beforeValidDayCount, 5)
        XCTAssertEqual(onset.planValidDayCount, 5)
        XCTAssertEqual(try XCTUnwrap(onset.changeFromBefore), -1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(duration.changeFromBefore), 1, accuracy: 0.001)
    }

    func testTwoOfThreeCompletedHasTwoThirdsProgress() throws {
        let progress = try MicroPlanProgress(
            scheduledCount: 3,
            completedCount: 2,
            skippedCount: 0
        )

        XCTAssertEqual(try XCTUnwrap(progress.completionFraction), 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(progress.unresolvedCount, 1)
    }

    func testNoScheduledTaskDoesNotBecomeZeroPercent() throws {
        let progress = try MicroPlanProgress(
            scheduledCount: 0,
            completedCount: 0,
            skippedCount: 0
        )

        XCTAssertNil(progress.completionFraction)
    }

    func testRejectsImpossibleProgressCounts() {
        XCTAssertThrowsError(
            try MicroPlanProgress(
                scheduledCount: 3,
                completedCount: 3,
                skippedCount: 1
            )
        ) { error in
            XCTAssertEqual(error as? CarePlanModelError, .invalidProgressCounts)
        }
    }

    func testValidatesOutcomeOccurrenceAndDifficulty() {
        let taskID = CareTaskID(rawValue: "wind-down")

        XCTAssertThrowsError(
            try PlanOutcomeInput(
                taskID: taskID,
                occurrenceIndex: -1,
                state: .completed,
                recordedAt: Date(),
                difficulty: 3
            )
        ) { error in
            XCTAssertEqual(error as? CarePlanModelError, .invalidOccurrenceIndex)
        }

        XCTAssertThrowsError(
            try PlanOutcomeInput(
                taskID: taskID,
                occurrenceIndex: 0,
                state: .completed,
                recordedAt: Date(),
                difficulty: 6
            )
        ) { error in
            XCTAssertEqual(error as? CarePlanModelError, .invalidDifficulty)
        }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
