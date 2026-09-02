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

    func testCapturedBaselineKeepsPlanStartValuesAfterHistoricalSamplesChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try date(2026, 1, 10, 0, 0, calendar: calendar)
        let template = try XCTUnwrap(
            MicroPlanTemplateLibrary.template(for: .afternoonWalk)
        )
        let draft = try template.makeDraft(
            referenceDate: start,
            calendar: calendar,
            uniqueID: try XCTUnwrap(
                UUID(uuidString: "22222222-3333-4444-5555-666666666666")
            )
        )
        let source = HealthMetricSource(
            sourceName: "Apple Watch",
            bundleIdentifier: "test.watch",
            deviceName: "Watch"
        )
        let originalSamples = try zip(5...9, [1_000, 2_000, 3_000, 4_000, 5_000]).map {
            day, value in
            try HealthMetricSample(
                id: UUID(),
                metricType: .stepCount,
                startDate: date(2026, 1, day, 9, 0, calendar: calendar),
                endDate: date(2026, 1, day, 10, 0, calendar: calendar),
                value: Double(value),
                unit: .count,
                source: source
            )
        }
        let baseline = MicroPlanTrendPresentationFactory.captureBaseline(
            for: draft,
            snapshot: HealthDataSnapshot(states: [
                .stepCount: .available(originalSamples)
            ]),
            dataMode: .live,
            capturedAt: start,
            calendar: calendar
        )

        let capturedSteps = try XCTUnwrap(baseline.metric(.stepCount))
        XCTAssertEqual(capturedSteps.validDayCount, 5)
        XCTAssertEqual(try XCTUnwrap(capturedSteps.median), 3_000, accuracy: 0.001)
        XCTAssertEqual(baseline.metric(.activeEnergy)?.validDayCount, 0)

        let changedSamples = try (5...14).map { day in
            try HealthMetricSample(
                id: UUID(),
                metricType: .stepCount,
                startDate: date(2026, 1, day, 9, 0, calendar: calendar),
                endDate: date(2026, 1, day, 10, 0, calendar: calendar),
                value: day < 10 ? 9_000 : 6_000,
                unit: .count,
                source: source
            )
        }
        let changedSnapshot = HealthDataSnapshot(states: [
            .stepCount: .available(changedSamples)
        ])
        let plan = MicroPlan(draft: draft, status: .completed)
        let frozen = MicroPlanTrendPresentationFactory.make(
            plan: plan,
            snapshot: changedSnapshot,
            baseline: baseline,
            referenceDate: try date(2026, 1, 14, 12, 0, calendar: calendar),
            calendar: calendar
        )
        let legacyDynamic = MicroPlanTrendPresentationFactory.make(
            plan: plan,
            snapshot: changedSnapshot,
            referenceDate: try date(2026, 1, 14, 12, 0, calendar: calendar),
            calendar: calendar
        )

        let frozenSteps = try XCTUnwrap(frozen.first { $0.metric == .stepCount })
        let dynamicSteps = try XCTUnwrap(
            legacyDynamic.first { $0.metric == .stepCount }
        )
        XCTAssertTrue(frozenSteps.hasFrozenBaseline)
        XCTAssertEqual(try XCTUnwrap(frozenSteps.beforeMedian), 3_000, accuracy: 0.001)
        XCTAssertFalse(dynamicSteps.hasFrozenBaseline)
        XCTAssertEqual(try XCTUnwrap(dynamicSteps.beforeMedian), 9_000, accuracy: 0.001)

        let modeMismatch = MicroPlanTrendPresentationFactory.make(
            plan: plan,
            snapshot: changedSnapshot,
            baseline: baseline,
            dataMode: .demo,
            referenceDate: try date(2026, 1, 14, 12, 0, calendar: calendar),
            calendar: calendar
        )
        let mismatchedSteps = try XCTUnwrap(
            modeMismatch.first { $0.metric == .stepCount }
        )
        XCTAssertFalse(mismatchedSteps.hasFrozenBaseline)
        XCTAssertTrue(mismatchedSteps.hasMismatchedDataMode)

        let missingAtStart = try XCTUnwrap(baseline.metric(.activeEnergy))
        XCTAssertNil(missingAtStart.median)
        let laterEnergySamples = try (5...14).map { day in
            try HealthMetricSample(
                id: UUID(),
                metricType: .activeEnergy,
                startDate: date(2026, 1, day, 9, 0, calendar: calendar),
                endDate: date(2026, 1, day, 10, 0, calendar: calendar),
                value: day < 10 ? 450 : 500,
                unit: .kilocalories,
                source: source
            )
        }
        let energyCards = MicroPlanTrendPresentationFactory.make(
            plan: plan,
            snapshot: HealthDataSnapshot(states: [
                .activeEnergy: .available(laterEnergySamples)
            ]),
            baseline: baseline,
            dataMode: .live,
            referenceDate: try date(2026, 1, 14, 12, 0, calendar: calendar),
            calendar: calendar
        )
        let frozenEnergy = try XCTUnwrap(
            energyCards.first { $0.metric == .activeEnergy }
        )
        XCTAssertTrue(frozenEnergy.hasFrozenBaseline)
        XCTAssertNil(frozenEnergy.beforeMedian)
        XCTAssertEqual(frozenEnergy.beforeValidDayCount, 0)
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

    func testOptionalFeedbackTrimsWhitespaceAndEnforcesLength() throws {
        let input = try PlanOutcomeInput(
            taskID: CareTaskID(rawValue: "wind-down"),
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: Date(),
            difficulty: nil,
            feedback: "  今天做完后感觉放松。  "
        )
        XCTAssertEqual(input.feedback, "今天做完后感觉放松。")

        XCTAssertThrowsError(try PlanOutcomeInput(
            taskID: CareTaskID(rawValue: "wind-down"),
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: Date(),
            difficulty: nil,
            feedback: String(repeating: "感", count: 161)
        )) { error in
            XCTAssertEqual(error as? CarePlanModelError, .invalidFeedback)
        }
    }

    func testEvaluationRequiresEnoughExecutionBeforeConsideringTrends() throws {
        let plan = try evaluationPlan()
        let progress = try MicroPlanProgress(
            scheduledCount: 5,
            completedCount: 2,
            skippedCount: 3
        )
        let evaluation = MicroPlanEvaluationFactory.make(
            plan: plan,
            progress: progress,
            outcomes: [],
            trends: [evaluationTrend(change: 1)]
        )

        XCTAssertEqual(evaluation.verdict, .insufficientExecution)
    }

    func testEvaluationCombinesFeedbackCompletionTrendAndDataQuality() throws {
        let plan = try evaluationPlan()
        let progress = try MicroPlanProgress(
            scheduledCount: 5,
            completedCount: 4,
            skippedCount: 1
        )
        let outcomes = [PlanOutcomeRecord(
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: plan.draft.startDate,
            feedback: "做完后感觉更轻松"
        )]
        let evaluation = MicroPlanEvaluationFactory.make(
            plan: plan,
            progress: progress,
            outcomes: outcomes,
            trends: [evaluationTrend(change: 1)]
        )

        XCTAssertEqual(evaluation.verdict, .mayHaveHelped)
        XCTAssertEqual(evaluation.factPack.completionRate, 0.8)
        XCTAssertEqual(evaluation.factPack.userFeedback, ["做完后感觉更轻松"])
        XCTAssertEqual(evaluation.factPack.metrics.count, 1)
        XCTAssertTrue(evaluation.factPack.dataQualitySummary.contains("1 项"))
    }

    func testEvaluationDoesNotUseLegacyDynamicBaselineAsHistoricalEvidence() throws {
        let plan = try evaluationPlan()
        let progress = try MicroPlanProgress(
            scheduledCount: 5,
            completedCount: 5,
            skippedCount: 0
        )
        let dynamicTrend = MicroPlanTrendPresentation(
            metric: .stepCount,
            points: [],
            planStartDate: plan.draft.startDate,
            beforeMedian: 5_000,
            planMedian: 6_000,
            beforeValidDayCount: 5,
            planValidDayCount: 5,
            hasFrozenBaseline: false
        )

        let evaluation = MicroPlanEvaluationFactory.make(
            plan: plan,
            progress: progress,
            outcomes: [],
            trends: [dynamicTrend]
        )

        XCTAssertEqual(evaluation.verdict, .insufficientData)
        XCTAssertTrue(evaluation.factPack.metrics.isEmpty)
        XCTAssertEqual(
            evaluation.factPack.dataQualitySummary,
            "计划开始基线未保存，无法形成可靠历史评估"
        )
    }

    private func evaluationPlan() throws -> MicroPlan {
        let template = try XCTUnwrap(
            MicroPlanTemplateLibrary.template(for: .afternoonWalk)
        )
        return MicroPlan(
            draft: try template.makeDraft(referenceDate: Date()),
            status: .completed
        )
    }

    private func evaluationTrend(change: Double) -> MicroPlanTrendPresentation {
        MicroPlanTrendPresentation(
            metric: .stepCount,
            points: [],
            planStartDate: Date(),
            beforeMedian: 5_000,
            planMedian: 5_000 + change * 1_000,
            beforeValidDayCount: 5,
            planValidDayCount: 5
        )
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
