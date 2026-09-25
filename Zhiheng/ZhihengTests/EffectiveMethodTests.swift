import XCTest
import SwiftData
@testable import Zhiheng

final class EffectiveMethodTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testEndedRunsFromSameTemplateAreGroupedAndKeepCareKitSources() async throws {
        let older = makePlan(
            suffix: "older",
            templateID: .afternoonWalk,
            dayOffset: -10,
            status: .completed
        )
        let newer = makePlan(
            suffix: "newer",
            templateID: .afternoonWalk,
            dayOffset: -4,
            status: .endedEarly
        )
        let laterOutcome = outcome(index: 1, offset: 3_600, state: .skipped)
        let earlierOutcome = outcome(index: 0, offset: 60, state: .completed)
        let olderProgress = try MicroPlanProgress(
            scheduledCount: 2,
            completedCount: 1,
            skippedCount: 1
        )
        let newerProgress = try MicroPlanProgress(
            scheduledCount: 4,
            completedCount: 1,
            skippedCount: 0
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [older, newer],
            outcomes: [
                older.draft.taskID: [laterOutcome, earlierOutcome],
                newer.draft.taskID: [outcome(index: 0, offset: 120, state: .completed)],
            ],
            progressByPlanID: [
                older.draft.id: olderProgress,
                newer.draft.id: newerProgress,
            ]
        )

        let candidates = try await EffectiveMethodCandidateGenerator.load(from: source)

        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.id, "effective-method-candidate.afternoonWalk")
        XCTAssertEqual(candidate.sourcePlanTemplateID, .afternoonWalk)
        XCTAssertEqual(candidate.title, "午后步行")
        XCTAssertEqual(candidate.runs.map(\.plan.draft.id), [newer.draft.id, older.draft.id])
        XCTAssertEqual(candidate.runs[0].plan.status, .endedEarly)
        XCTAssertEqual(candidate.runs[1].plan.draft.taskID, older.draft.taskID)
        XCTAssertEqual(candidate.runs[1].outcomes.map(\.occurrenceIndex), [0, 1])
        XCTAssertEqual(candidate.runs[0].completion.scheduledCount, 4)
        XCTAssertEqual(candidate.runs[0].completion.completedCount, 1)
        XCTAssertEqual(candidate.runs[0].completion.skippedCount, 0)
        XCTAssertEqual(candidate.completion.scheduledCount, 6)
        XCTAssertEqual(candidate.completion.completedCount, 2)
        XCTAssertEqual(candidate.completion.skippedCount, 1)
        XCTAssertEqual(candidate.completion.unresolvedCount, 3)
        XCTAssertEqual(candidate.completion.recordedOutcomeCount, 3)
        XCTAssertEqual(
            try XCTUnwrap(candidate.completion.completionRate),
            2.0 / 6.0,
            accuracy: 0.000_001
        )
    }

    func testOnlyEndedKnownTemplatesAreReadAndEmptyOutcomesRemainVisible() async throws {
        let ended = makePlan(
            suffix: "ended",
            templateID: .earlierBedtime,
            dayOffset: -6,
            status: .completed
        )
        let active = makePlan(
            suffix: "active",
            templateID: .afternoonWalk,
            dayOffset: 0,
            status: .active
        )
        let paused = makePlan(
            suffix: "paused",
            templateID: .movementBreak,
            dayOffset: -2,
            status: .paused
        )
        let unknown = makePlan(
            suffix: "unknown",
            templateID: nil,
            dayOffset: -8,
            status: .endedEarly,
            title: "外部计划"
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [active, unknown, ended, paused, ended],
            outcomes: [:]
        )

        let candidates = try await EffectiveMethodCandidateGenerator.load(from: source)
        let requests = await source.outcomeRequests()
        let progressRequests = await source.progressRequests()

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.sourcePlanTemplateID, .earlierBedtime)
        XCTAssertEqual(candidates.first?.runs.count, 1)
        XCTAssertEqual(candidates.first?.runs.first?.outcomes, [])
        XCTAssertEqual(requests, [ended.draft.taskID])
        XCTAssertEqual(progressRequests, [ended.draft.id])
        XCTAssertEqual(candidates.first?.completion.completedCount, 0)
        XCTAssertEqual(candidates.first?.completion.scheduledCount, 5)
    }

    func testCandidateOrderIsDeterministicForShuffledInputs() async throws {
        let walk = makePlan(
            suffix: "walk",
            templateID: .afternoonWalk,
            dayOffset: -8,
            status: .completed
        )
        let sleep = makePlan(
            suffix: "sleep",
            templateID: .earlierBedtime,
            dayOffset: -3,
            status: .completed
        )
        let first = EffectiveMethodCarePlanServiceStub(
            history: [walk, sleep],
            outcomes: [
                walk.draft.taskID: [
                    outcome(index: 1, offset: 200, state: .skipped),
                    outcome(index: 0, offset: 100, state: .completed),
                ],
            ]
        )
        let second = EffectiveMethodCarePlanServiceStub(
            history: [sleep, walk],
            outcomes: [
                walk.draft.taskID: [
                    outcome(index: 0, offset: 100, state: .completed),
                    outcome(index: 1, offset: 200, state: .skipped),
                ],
            ]
        )

        let firstResult = try await EffectiveMethodCandidateGenerator.load(from: first)
        let secondResult = try await EffectiveMethodCandidateGenerator.load(from: second)

        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(
            firstResult.map(\.sourcePlanTemplateID),
            [.earlierBedtime, .afternoonWalk]
        )
    }

    func testOutcomeReadFailureDoesNotReturnPartialCandidates() async throws {
        let walk = makePlan(
            suffix: "walk",
            templateID: .afternoonWalk,
            dayOffset: -8,
            status: .completed
        )
        let sleep = makePlan(
            suffix: "sleep",
            templateID: .earlierBedtime,
            dayOffset: -3,
            status: .completed
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [walk, sleep],
            outcomes: [walk.draft.taskID: [outcome(index: 0)]],
            failingTaskID: sleep.draft.taskID
        )

        do {
            _ = try await EffectiveMethodCandidateGenerator.load(from: source)
            XCTFail("Expected an Outcome read failure")
        } catch {
            XCTAssertEqual(error as? EffectiveMethodSourceError, .outcomeReadFailed)
        }
    }

    func testEmptyHistoryProducesNoCandidatesOrOutcomeReads() async throws {
        let source = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])

        let candidates = try await EffectiveMethodCandidateGenerator.load(from: source)
        let requests = await source.outcomeRequests()
        let progressRequests = await source.progressRequests()

        XCTAssertEqual(candidates, [])
        XCTAssertEqual(requests, [])
        XCTAssertEqual(progressRequests, [])
    }

    func testZeroScheduledOccurrencesKeepCompletionRateUnknown() async throws {
        let ended = makePlan(
            suffix: "zero-schedule",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .endedEarly
        )
        let progress = try MicroPlanProgress(
            scheduledCount: 0,
            completedCount: 0,
            skippedCount: 0
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [:],
            progressByPlanID: [ended.draft.id: progress]
        )

        let candidates = try await EffectiveMethodCandidateGenerator.load(
            from: source
        )
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidate.completion.scheduledCount, 0)
        XCTAssertEqual(candidate.completion.recordedOutcomeCount, 0)
        XCTAssertNil(candidate.completion.completionRate)
    }

    func testOutcomeAndProgressMismatchIsRejected() async throws {
        let ended = makePlan(
            suffix: "mismatch",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let progress = try MicroPlanProgress(
            scheduledCount: 5,
            completedCount: 0,
            skippedCount: 0
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [ended.draft.taskID: [outcome(index: 0)]],
            progressByPlanID: [ended.draft.id: progress]
        )

        do {
            _ = try await EffectiveMethodCandidateGenerator.load(from: source)
            XCTFail("Expected inconsistent CareKit facts to be rejected")
        } catch {
            XCTAssertEqual(
                error as? EffectiveMethodCompletionFactError,
                .progressOutcomeMismatch
            )
        }
    }

    func testDuplicateAndOutOfScheduleOutcomesAreRejected() async throws {
        let ended = makePlan(
            suffix: "invalid-occurrence",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let cases: [(
            outcomes: [PlanOutcomeRecord],
            progress: MicroPlanProgress,
            expected: EffectiveMethodCompletionFactError
        )] = [
            (
                [outcome(index: 0), outcome(index: 0, offset: 60)],
                try MicroPlanProgress(
                    scheduledCount: 5,
                    completedCount: 2,
                    skippedCount: 0
                ),
                .duplicateOutcomeOccurrence
            ),
            (
                [outcome(index: 5)],
                try MicroPlanProgress(
                    scheduledCount: 5,
                    completedCount: 1,
                    skippedCount: 0
                ),
                .outcomeOutsideSchedule
            ),
        ]

        for value in cases {
            let source = EffectiveMethodCarePlanServiceStub(
                history: [ended],
                outcomes: [ended.draft.taskID: value.outcomes],
                progressByPlanID: [ended.draft.id: value.progress]
            )
            do {
                _ = try await EffectiveMethodCandidateGenerator.load(from: source)
                XCTFail("Expected invalid Outcome occurrences to be rejected")
            } catch {
                XCTAssertEqual(
                    error as? EffectiveMethodCompletionFactError,
                    value.expected
                )
            }
        }
    }

    func testProgressReadFailureDoesNotReturnPartialCandidates() async throws {
        let ended = makePlan(
            suffix: "progress-failure",
            templateID: .earlierBedtime,
            dayOffset: -5,
            status: .completed
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [:],
            failingPlanID: ended.draft.id
        )

        do {
            _ = try await EffectiveMethodCandidateGenerator.load(from: source)
            XCTFail("Expected a progress read failure")
        } catch {
            XCTAssertEqual(error as? EffectiveMethodSourceError, .progressReadFailed)
        }
    }

    func testSingleAssessableRunAlwaysRemainsPreliminary() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4])

        for verdict in [
            MicroPlanEvaluationVerdict.mayHaveHelped,
            MicroPlanEvaluationVerdict.noClearChange,
        ] {
            let confidence = EffectiveMethodConfidenceRule.evaluate(
                candidate: candidate,
                evaluations: evaluationFacts(for: candidate, verdicts: [verdict])
            )

            XCTAssertEqual(confidence.level, .preliminaryObservation)
            XCTAssertEqual(confidence.level.title, "初步观察")
            XCTAssertEqual(confidence.reason, .oneAssessableRun)
            XCTAssertEqual(confidence.totalRunCount, 1)
            XCTAssertEqual(confidence.assessableRunCount, 1)
            XCTAssertEqual(confidence.ruleVersion, "s11-method-confidence-v1")
            XCTAssertEqual(
                confidence.helpfulRunCount,
                verdict == .mayHaveHelped ? 1 : 0
            )
        }
    }

    func testTwoConsistentHelpfulRunsArePossiblySuitable() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [3, 5])

        let confidence = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: evaluationFacts(
                for: candidate,
                verdicts: [.mayHaveHelped, .mayHaveHelped]
            )
        )

        XCTAssertEqual(confidence.level, .possiblySuitable)
        XCTAssertEqual(confidence.level.title, "可能适合")
        XCTAssertEqual(confidence.reason, .twoConsistentHelpfulRuns)
        XCTAssertEqual(confidence.assessableRunCount, 2)
        XCTAssertEqual(confidence.helpfulRunCount, 2)
    }

    func testThreeOrMoreConsistentHelpfulRunsAreFairlyStable() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [3, 4, 5, 5])

        let confidence = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: evaluationFacts(
                for: candidate,
                verdicts: Array(repeating: .mayHaveHelped, count: 4)
            )
        )

        XCTAssertEqual(confidence.level, .fairlyStable)
        XCTAssertEqual(confidence.level.title, "较稳定")
        XCTAssertEqual(confidence.reason, .repeatedConsistentHelpfulRuns)
        XCTAssertEqual(confidence.totalRunCount, 4)
        XCTAssertEqual(confidence.assessableRunCount, 4)
        XCTAssertEqual(confidence.helpfulRunCount, 4)
    }

    func testMixedOrRepeatedNeutralResultsRemainUnclear() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4, 4])
        let cases: [(
            verdicts: [MicroPlanEvaluationVerdict],
            reason: EffectiveMethodConfidenceReason
        )] = [
            ([.mayHaveHelped, .noClearChange], .inconsistentResults),
            ([.noClearChange, .noClearChange], .noConsistentBenefit),
        ]

        for value in cases {
            let confidence = EffectiveMethodConfidenceRule.evaluate(
                candidate: candidate,
                evaluations: evaluationFacts(
                    for: candidate,
                    verdicts: value.verdicts
                )
            )

            XCTAssertEqual(confidence.level, .unclear)
            XCTAssertEqual(confidence.level.title, "不明确")
            XCTAssertEqual(confidence.reason, value.reason)
        }
    }

    func testExecutionAndEvaluationQualityGateToUnclear() async throws {
        let zeroSchedule = try await confidenceCandidate(
            completedCounts: [0],
            scheduledCount: 0
        )
        let zeroScheduleResult = EffectiveMethodConfidenceRule.evaluate(
            candidate: zeroSchedule,
            evaluations: evaluationFacts(
                for: zeroSchedule,
                verdicts: [.mayHaveHelped]
            )
        )
        XCTAssertEqual(zeroScheduleResult.level, .unclear)
        XCTAssertEqual(zeroScheduleResult.reason, .insufficientExecution)

        let lowCompletion = try await confidenceCandidate(completedCounts: [2])
        let lowCompletionResult = EffectiveMethodConfidenceRule.evaluate(
            candidate: lowCompletion,
            evaluations: evaluationFacts(
                for: lowCompletion,
                verdicts: [.mayHaveHelped]
            )
        )
        XCTAssertEqual(lowCompletionResult.level, .unclear)
        XCTAssertEqual(lowCompletionResult.reason, .insufficientExecution)

        let assessableCompletion = try await confidenceCandidate(completedCounts: [4])
        let verdictCases: [(
            verdict: MicroPlanEvaluationVerdict,
            reason: EffectiveMethodConfidenceReason
        )] = [
            (.insufficientExecution, .insufficientExecution),
            (.insufficientData, .insufficientData),
            (.subjectiveObjectiveMismatch, .subjectiveObjectiveMismatch),
        ]
        for value in verdictCases {
            let confidence = EffectiveMethodConfidenceRule.evaluate(
                candidate: assessableCompletion,
                evaluations: evaluationFacts(
                    for: assessableCompletion,
                    verdicts: [value.verdict]
                )
            )
            XCTAssertEqual(confidence.level, .unclear)
            XCTAssertEqual(confidence.reason, value.reason)
        }
    }

    func testMissingDuplicateAndForeignEvaluationSourcesRemainUnclear() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4, 4])
        let first = try XCTUnwrap(candidate.runs.first)
        let singleFact = EffectiveMethodRunEvaluationFact(
            carePlanID: first.plan.draft.id,
            verdict: .mayHaveHelped
        )
        let foreignFact = EffectiveMethodRunEvaluationFact(
            carePlanID: CarePlanID(rawValue: "plan.foreign"),
            verdict: .mayHaveHelped
        )

        let missing = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: [singleFact]
        )
        let duplicate = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: [singleFact, singleFact]
        )
        let foreign = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: evaluationFacts(
                for: candidate,
                verdicts: [.mayHaveHelped, .mayHaveHelped]
            ) + [foreignFact]
        )

        XCTAssertEqual(missing.reason, .missingEvaluation)
        XCTAssertEqual(duplicate.reason, .invalidEvaluationSources)
        XCTAssertEqual(foreign.reason, .invalidEvaluationSources)
        XCTAssertEqual([missing.level, duplicate.level, foreign.level], [
            .unclear, .unclear, .unclear,
        ])
    }

    func testConfidenceIsIndependentOfEvaluationInputOrder() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [3, 5])
        let ordered = evaluationFacts(
            for: candidate,
            verdicts: [.mayHaveHelped, .mayHaveHelped]
        )

        let first = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: ordered
        )
        let second = EffectiveMethodConfidenceRule.evaluate(
            candidate: candidate,
            evaluations: Array(ordered.reversed())
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.level, .possiblySuitable)
    }

    func testMethodCardShowsWeightedCompletionCountAndPartialDataQuality() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [3, 5])
        let evaluations = zip(
            candidate.runs,
            [
                (MicroPlanEvaluationVerdict.mayHaveHelped, EffectiveMethodRunDataQuality.sufficient),
                (MicroPlanEvaluationVerdict.mayHaveHelped, EffectiveMethodRunDataQuality.insufficient),
            ]
        ).map { run, value in
            EffectiveMethodRunEvaluationFact(
                carePlanID: run.plan.draft.id,
                verdict: value.0,
                dataQuality: value.1
            )
        }

        let card = EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: evaluations
        )

        XCTAssertEqual(card.id, candidate.id)
        XCTAssertEqual(card.sourcePlanTemplateID, .afternoonWalk)
        XCTAssertEqual(card.title, "午后步行")
        XCTAssertEqual(card.executionCount, 2)
        XCTAssertEqual(card.completion.completedCount, 8)
        XCTAssertEqual(card.completion.scheduledCount, 10)
        XCTAssertEqual(try XCTUnwrap(card.completion.completionRate), 0.8)
        XCTAssertEqual(card.dataQuality.level, .partial)
        XCTAssertEqual(card.dataQuality.sufficientRunCount, 1)
        XCTAssertEqual(card.dataQuality.insufficientRunCount, 1)
        XCTAssertEqual(card.dataQuality.detail, "1/2 次有可判断的计划前后数据")
        XCTAssertEqual(card.confidence.level, .unclear)
    }

    func testMissingOrUnavailableEvaluationIsNotPresentedAsGoodData() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4, 4])
        let firstRun = try XCTUnwrap(candidate.runs.first)
        let card = EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: [EffectiveMethodRunEvaluationFact(
                carePlanID: firstRun.plan.draft.id,
                verdict: .insufficientData,
                dataQuality: .unavailable
            )]
        )

        XCTAssertEqual(card.dataQuality.level, .unavailable)
        XCTAssertEqual(card.dataQuality.unavailableRunCount, 2)
        XCTAssertEqual(card.dataQuality.sufficientRunCount, 0)
        XCTAssertEqual(card.confidence.reason, .missingEvaluation)
    }

    func testSubjectiveChangeUsesStructuredRatingMedians() throws {
        let before = [
            try checkIn(dayOffset: -2, energy: .two, stress: .four, body: .two),
            try checkIn(dayOffset: -1, energy: .four, stress: .two, body: .four),
        ]
        let during = [
            try checkIn(dayOffset: 0, energy: .four, stress: .two, body: .three),
            try checkIn(dayOffset: 1, energy: .five, stress: .one, body: .four),
            try checkIn(dayOffset: 2, energy: .three, stress: .three, body: .five),
        ]

        let change = EffectiveMethodSubjectiveRunChange.make(
            before: before,
            duringPlan: during
        )

        XCTAssertEqual(change.state, .available)
        XCTAssertEqual(change.beforeRecordedDayCount, 2)
        XCTAssertEqual(change.planRecordedDayCount, 3)
        XCTAssertEqual(change.metrics.map(\.dimension), [
            .energy, .stress, .bodyFeeling,
        ])
        XCTAssertEqual(change.metrics[0].beforeMedian, 3)
        XCTAssertEqual(change.metrics[0].planMedian, 4)
        XCTAssertEqual(change.metrics[0].changeFromBefore, 1)
        XCTAssertEqual(change.metrics[1].beforeMedian, 3)
        XCTAssertEqual(change.metrics[1].planMedian, 2)
        XCTAssertEqual(change.metrics[2].beforeMedian, 3)
        XCTAssertEqual(change.metrics[2].planMedian, 4)
    }

    func testSubjectiveChangeDistinguishesNoRecordFromInsufficientRecord() throws {
        let notRecorded = EffectiveMethodSubjectiveRunChange.make(
            before: [],
            duringPlan: []
        )
        let insufficient = EffectiveMethodSubjectiveRunChange.make(
            before: [try checkIn(dayOffset: -1)],
            duringPlan: [
                try checkIn(dayOffset: 0),
                try checkIn(dayOffset: 1),
            ]
        )

        XCTAssertEqual(notRecorded.state, .notRecorded)
        XCTAssertEqual(notRecorded.metrics, [])
        XCTAssertEqual(insufficient.state, .insufficient)
        XCTAssertEqual(insufficient.beforeRecordedDayCount, 1)
        XCTAssertEqual(insufficient.planRecordedDayCount, 2)
        XCTAssertEqual(insufficient.metrics, [])
    }

    func testMethodCardSeparatesObjectiveAndSubjectiveChanges() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4, 4])
        let newer = candidate.runs[0]
        let older = candidate.runs[1]
        let subjective = EffectiveMethodSubjectiveRunChange.make(
            before: [
                try checkIn(dayOffset: -2, energy: .two, stress: .four, body: .three),
                try checkIn(dayOffset: -1, energy: .three, stress: .three, body: .three),
            ],
            duringPlan: [
                try checkIn(dayOffset: 0, energy: .four, stress: .two, body: .four),
                try checkIn(dayOffset: 1, energy: .five, stress: .two, body: .four),
            ]
        )
        let objective = MicroPlanEvaluationMetricFact(
            metric: .stepCount,
            healthMetric: .stepCount,
            beforeMedian: 6_000,
            planMedian: 7_200,
            changeFromBefore: 1_200,
            beforeValidDayCount: 5,
            planValidDayCount: 4,
            direction: .favorable
        )
        let evaluations = [
            EffectiveMethodRunEvaluationFact(
                carePlanID: newer.plan.draft.id,
                verdict: .mayHaveHelped,
                objectiveMetrics: [objective],
                subjectiveChange: subjective
            ),
            EffectiveMethodRunEvaluationFact(
                carePlanID: older.plan.draft.id,
                verdict: .insufficientData,
                dataQuality: .insufficient,
                objectiveDataQuality: .insufficient,
                subjectiveChange: EffectiveMethodSubjectiveRunChange.make(
                    before: [],
                    duringPlan: []
                )
            ),
        ]

        let card = EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: evaluations
        )

        XCTAssertEqual(card.objectiveChange.availability, .partial)
        XCTAssertEqual(card.objectiveChange.comparableRunCount, 1)
        XCTAssertEqual(card.objectiveChange.metrics, [objective])
        XCTAssertEqual(
            card.objectiveChange.sourceRunDate,
            newer.plan.draft.endDateExclusive
        )
        XCTAssertEqual(card.subjectiveChange.availability, .partial)
        XCTAssertEqual(card.subjectiveChange.comparableRunCount, 1)
        XCTAssertEqual(card.subjectiveChange.metrics, subjective.metrics)
        XCTAssertEqual(card.subjectiveChange.beforeRecordedDayCount, 2)
        XCTAssertEqual(card.subjectiveChange.planRecordedDayCount, 2)
    }

    func testMethodCardKeepsObjectiveAndSubjectiveAvailabilityIndependent() async throws {
        let candidate = try await confidenceCandidate(completedCounts: [4])
        let run = try XCTUnwrap(candidate.runs.first)
        let objective = MicroPlanEvaluationMetricFact(
            metric: .activeEnergy,
            healthMetric: .activeEnergy,
            beforeMedian: 280,
            planMedian: 310,
            changeFromBefore: 30,
            beforeValidDayCount: 5,
            planValidDayCount: 5,
            direction: .favorable
        )

        let card = EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: [EffectiveMethodRunEvaluationFact(
                carePlanID: run.plan.draft.id,
                verdict: .mayHaveHelped,
                objectiveMetrics: [objective],
                subjectiveChange: .unavailable
            )]
        )

        XCTAssertEqual(card.objectiveChange.availability, .available)
        XCTAssertEqual(card.objectiveChange.metrics, [objective])
        XCTAssertEqual(card.subjectiveChange.availability, .unavailable)
        XCTAssertEqual(card.subjectiveChange.metrics, [])
    }

    @MainActor
    func testEffectiveMethodsDemoModeDoesNotReadRealCareKitHistory() async throws {
        let source = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])
        let session = MicroPlanSession(service: source)

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .demo)

        let historyRequestCount = await source.historyRequestCount()
        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected synthetic demo methods")
        }
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.sourcePlanTemplateID, .earlierBedtime)
        XCTAssertEqual(cards.first?.executionCount, 2)
        XCTAssertEqual(cards.first?.completion.completionRate, 0.8)
        XCTAssertEqual(historyRequestCount, 0)
    }

    @MainActor
    func testEffectiveMethodsDistinguishEmptyAndCareKitReadFailure() async throws {
        let emptySource = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])
        let emptySession = MicroPlanSession(service: emptySource)
        await emptySession.refreshEffectiveMethods(snapshot: nil, dataMode: .live)
        XCTAssertEqual(emptySession.effectiveMethodsState, .empty)

        let failedSource = EffectiveMethodCarePlanServiceStub(
            history: [],
            outcomes: [:],
            failsHistoryRead: true
        )
        let failedSession = MicroPlanSession(service: failedSource)
        await failedSession.refreshEffectiveMethods(snapshot: nil, dataMode: .live)
        XCTAssertEqual(failedSession.effectiveMethodsState, .failed)
    }

    @MainActor
    func testSessionLoadsRealCandidateFactsAndKeepsInsufficientQualityVisible() async throws {
        let ended = makePlan(
            suffix: "visible-card",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let records = (0..<4).map { outcome(index: $0, offset: Double($0)) }
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [ended.draft.taskID: records],
            progressByPlanID: [ended.draft.id: try MicroPlanProgress(
                scheduledCount: 5,
                completedCount: 4,
                skippedCount: 0
            )]
        )
        let session = MicroPlanSession(
            service: source,
            subjectiveRecordStore: EmptySubjectiveRecordStore()
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected an effective method card")
        }
        let card = try XCTUnwrap(cards.first)
        XCTAssertEqual(card.executionCount, 1)
        XCTAssertEqual(try XCTUnwrap(card.completion.completionRate), 0.8)
        XCTAssertEqual(card.dataQuality.level, .insufficient)
        XCTAssertEqual(card.confidence.level, .unclear)
        XCTAssertEqual(card.confidence.reason, .insufficientData)
    }

    @MainActor
    func testSessionReadsOnlyStructuredCheckInsFromBeforeAndPlanWindows() async throws {
        let ended = makePlan(
            suffix: "subjective-window",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let records = (0..<4).map { outcome(index: $0, offset: Double($0)) }
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [ended.draft.taskID: records],
            progressByPlanID: [ended.draft.id: try MicroPlanProgress(
                scheduledCount: 5,
                completedCount: 4,
                skippedCount: 0
            )]
        )
        let start = ended.draft.startDate
        let checkIns = [
            try checkIn(on: start, dayOffset: -5, energy: .two, stress: .four, body: .two),
            try checkIn(on: start, dayOffset: -4, energy: .four, stress: .two, body: .four),
            try checkIn(on: start, dayOffset: 0, energy: .four, stress: .two, body: .three),
            try checkIn(on: start, dayOffset: 1, energy: .five, stress: .one, body: .five),
            // 计划采用半开区间，结束日记录不得进入计划期中位数。
            try checkIn(on: start, dayOffset: 5, energy: .one, stress: .five, body: .one),
        ]
        let session = MicroPlanSession(
            service: source,
            subjectiveRecordStore: EffectiveMethodSubjectiveRecordStoreStub(
                records: checkIns
            )
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected an effective method card")
        }
        let subjective = try XCTUnwrap(cards.first?.subjectiveChange)
        XCTAssertEqual(subjective.availability, .available)
        XCTAssertEqual(subjective.beforeRecordedDayCount, 2)
        XCTAssertEqual(subjective.planRecordedDayCount, 2)
        XCTAssertEqual(subjective.metrics.first?.beforeMedian, 3)
        XCTAssertEqual(subjective.metrics.first?.planMedian, 4.5)
        XCTAssertEqual(cards.first?.objectiveChange.availability, .insufficient)
    }

    @MainActor
    func testSubjectiveReadFailureDoesNotEraseObjectiveStatus() async throws {
        let ended = makePlan(
            suffix: "subjective-failure",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [:]
        )
        let session = MicroPlanSession(
            service: source,
            subjectiveRecordStore: EffectiveMethodSubjectiveRecordStoreStub(
                records: [],
                failsCheckInRead: true
            )
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected an effective method card")
        }
        XCTAssertEqual(cards.first?.objectiveChange.availability, .insufficient)
        XCTAssertEqual(cards.first?.subjectiveChange.availability, .unavailable)
    }

    @MainActor
    func testRestartFromMethodTemplateCreatesIndependentCareKitPlanAndBaseline() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let baselineStore = InMemoryPlanBaselineStore()
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore,
            subjectiveRecordStore: EmptySubjectiveRecordStore()
        )
        let referenceDate = Date()
        let didStartOriginal = await session.start(
            from: HealthAISuggestedAction(
                templateID: .afternoonWalk,
                rationale: "建立首次历史"
            ),
            referenceDate: referenceDate
        )
        XCTAssertTrue(didStartOriginal)
        let originalPlan = try XCTUnwrap(session.activePlan)
        await session.endEarly(referenceDate: referenceDate)
        await session.refreshEffectiveMethods(
            snapshot: nil,
            dataMode: .live,
            referenceDate: referenceDate
        )
        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected a method card")
        }
        let card = try XCTUnwrap(cards.first)

        let didRestart = await session.restartEffectiveMethod(
            templateID: card.sourcePlanTemplateID,
            healthSnapshot: nil,
            dataMode: .live,
            referenceDate: referenceDate
        )

        XCTAssertTrue(didRestart)
        let restartedPlan = try XCTUnwrap(session.activePlan)
        XCTAssertEqual(restartedPlan.draft.templateID, .afternoonWalk)
        XCTAssertNotEqual(restartedPlan.draft.id, originalPlan.draft.id)
        XCTAssertNotEqual(restartedPlan.draft.taskID, originalPlan.draft.taskID)
        XCTAssertEqual(session.history.map(\.plan.draft.id), [originalPlan.draft.id])
        XCTAssertNotNil(try baselineStore.baseline(for: originalPlan.draft.id))
        XCTAssertNotNil(try baselineStore.baseline(for: restartedPlan.draft.id))
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .activePlanExists)
        XCTAssertFalse(session.showsError)
    }

    @MainActor
    func testActivePlanBlocksMethodRestartBeforeNewBaselineOrPlanIsCreated() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let baselineStore = EffectiveMethodTrackingBaselineStore()
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore
        )
        let didStartOriginal = await session.start(from: HealthAISuggestedAction(
            templateID: .earlierBedtime,
            rationale: "活动计划"
        ))
        XCTAssertTrue(didStartOriginal)
        let existingPlanID = try XCTUnwrap(session.activePlan?.draft.id)
        XCTAssertEqual(baselineStore.savedPlanIDs.count, 1)

        let didRestart = await session.restartEffectiveMethod(
            templateID: .afternoonWalk,
            healthSnapshot: nil,
            dataMode: .live
        )
        let planHistoryCount = try await service.planHistory().count

        XCTAssertFalse(didRestart)
        XCTAssertEqual(session.activePlan?.draft.id, existingPlanID)
        XCTAssertEqual(planHistoryCount, 1)
        XCTAssertEqual(baselineStore.savedPlanIDs.count, 1)
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .activePlanExists)
        XCTAssertTrue(session.showsError)
        XCTAssertEqual(
            session.message,
            "你已经有一个进行中的微计划。先完成或结束它，再开始新的计划。"
        )
    }

    @MainActor
    func testDemoModeBlocksMethodRestartWithoutReadingCareKit() async throws {
        let source = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])
        let baselineStore = EffectiveMethodTrackingBaselineStore()
        let session = MicroPlanSession(
            service: source,
            baselineStore: baselineStore
        )

        let didRestart = await session.restartEffectiveMethod(
            templateID: .afternoonWalk,
            healthSnapshot: nil,
            dataMode: .demo
        )
        let activePlanRequestCount = await source.activePlanRequestCount()
        let historyRequestCount = await source.historyRequestCount()

        XCTAssertFalse(didRestart)
        XCTAssertEqual(activePlanRequestCount, 0)
        XCTAssertEqual(historyRequestCount, 0)
        XCTAssertEqual(baselineStore.savedPlanIDs, [])
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .demoMode)
    }

    @MainActor
    func testActivePlanReadFailureDisablesRestartWithoutCreatingBaseline() async throws {
        let source = EffectiveMethodCarePlanServiceStub(
            history: [],
            outcomes: [:],
            failsActivePlanRead: true
        )
        let baselineStore = EffectiveMethodTrackingBaselineStore()
        let session = MicroPlanSession(
            service: source,
            baselineStore: baselineStore
        )

        let didRestart = await session.restartEffectiveMethod(
            templateID: .afternoonWalk,
            healthSnapshot: nil,
            dataMode: .live
        )
        let activePlanRequestCount = await source.activePlanRequestCount()
        let historyRequestCount = await source.historyRequestCount()

        XCTAssertFalse(didRestart)
        XCTAssertEqual(activePlanRequestCount, 1)
        XCTAssertEqual(historyRequestCount, 0)
        XCTAssertEqual(baselineStore.savedPlanIDs, [])
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .unavailable)
        XCTAssertTrue(session.showsError)
    }

    @MainActor
    func testRestartBaselineFailureDoesNotCreateCareKitPlanAndRemainsRetryable() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let baselineStore = EffectiveMethodTrackingBaselineStore(failsSave: true)
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore
        )

        let didRestart = await session.restartEffectiveMethod(
            templateID: .afternoonWalk,
            healthSnapshot: nil,
            dataMode: .live
        )
        let history = try await service.planHistory()

        XCTAssertFalse(didRestart)
        XCTAssertEqual(history, [])
        XCTAssertEqual(baselineStore.savedPlanIDs, [])
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .available)
        XCTAssertTrue(session.showsError)
    }

    @MainActor
    func testRestartCareKitFailureRollsBackNewBaselineAndRemainsRetryable() async throws {
        let source = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])
        let baselineStore = EffectiveMethodTrackingBaselineStore()
        let session = MicroPlanSession(
            service: source,
            baselineStore: baselineStore
        )

        let didRestart = await session.restartEffectiveMethod(
            templateID: .afternoonWalk,
            healthSnapshot: nil,
            dataMode: .live
        )
        let savedPlanID = try XCTUnwrap(baselineStore.savedPlanIDs.first)

        XCTAssertFalse(didRestart)
        XCTAssertEqual(baselineStore.savedPlanIDs.count, 1)
        XCTAssertNil(try baselineStore.baseline(for: savedPlanID))
        XCTAssertEqual(session.effectiveMethodRestartAvailability, .available)
        XCTAssertTrue(session.showsError)
    }

    @MainActor
    func testBaselineReadFailureKeepsCandidateWithUnavailableQuality() async throws {
        let ended = makePlan(
            suffix: "unavailable-baseline",
            templateID: .earlierBedtime,
            dayOffset: -5,
            status: .completed
        )
        let records = (0..<4).map { outcome(index: $0, offset: Double($0)) }
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [ended.draft.taskID: records],
            progressByPlanID: [ended.draft.id: try MicroPlanProgress(
                scheduledCount: 5,
                completedCount: 4,
                skippedCount: 0
            )]
        )
        let session = MicroPlanSession(
            service: source,
            baselineStore: UnavailablePlanBaselineStore()
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected candidate to remain visible")
        }
        XCTAssertEqual(cards.first?.dataQuality.level, .unavailable)
        XCTAssertEqual(cards.first?.confidence.reason, .insufficientData)
    }

    func testRealCareKitPlanTaskAndOutcomeProduceCandidate() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let template = try XCTUnwrap(
            MicroPlanTemplateLibrary.template(for: .afternoonWalk)
        )
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -10, to: Date())
        )
        let draft = try template.makeDraft(
            referenceDate: referenceDate,
            uniqueID: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!
        )
        _ = try await service.createPlan(from: draft)
        let recordedAt = try XCTUnwrap(Calendar.current.date(
            bySettingHour: draft.scheduledTime.hour,
            minute: draft.scheduledTime.minute,
            second: 0,
            of: draft.startDate
        ))
        try await service.recordOutcome(PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: recordedAt,
            difficulty: nil,
            feedback: "当天感觉轻松"
        ))

        let candidates = try await EffectiveMethodCandidateGenerator.load(from: service)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.sourcePlanTemplateID, .afternoonWalk)
        XCTAssertEqual(candidate.runs.first?.plan.status, .completed)
        XCTAssertEqual(candidate.runs.first?.plan.draft.id, draft.id)
        XCTAssertEqual(candidate.runs.first?.plan.draft.taskID, draft.taskID)
        XCTAssertEqual(candidate.runs.first?.outcomes.first?.state, .completed)
        XCTAssertEqual(candidate.runs.first?.outcomes.first?.feedback, "当天感觉轻松")
        XCTAssertEqual(candidate.completion.scheduledCount, 5)
        XCTAssertEqual(candidate.completion.completedCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(candidate.completion.completionRate),
            0.2,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testVisibilityStorePersistsHideAndRestoreAcrossContexts() throws {
        let schema = Schema(versionedSchema: EffectiveMethodVisibilitySchemaV1.self)
        let configuration = ModelConfiguration(
            "EffectiveMethodVisibilityTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EffectiveMethodVisibilityMigrationPlan.self,
            configurations: [configuration]
        )
        let hiddenAt = Date(timeIntervalSince1970: 1_800_100_000)
        let writer = SwiftDataEffectiveMethodVisibilityStore(modelContainer: container)
        try writer.setHidden(true, templateID: .afternoonWalk, at: hiddenAt)

        let reader = SwiftDataEffectiveMethodVisibilityStore(modelContainer: container)
        XCTAssertEqual(try reader.hiddenTemplateIDs(), [.afternoonWalk])

        try reader.setHidden(false, templateID: .afternoonWalk, at: hiddenAt)
        let verifier = SwiftDataEffectiveMethodVisibilityStore(modelContainer: container)
        XCTAssertEqual(try verifier.hiddenTemplateIDs(), [])
    }

    @MainActor
    func testVisibilityStoreRejectsUnknownTemplateWithoutReturningPartialPreferences() throws {
        let schema = Schema(versionedSchema: EffectiveMethodVisibilitySchemaV1.self)
        let configuration = ModelConfiguration(
            "EffectiveMethodVisibilityCorruptTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EffectiveMethodVisibilityMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.insert(EffectiveMethodVisibilityEntity(
            templateID: .afternoonWalk,
            hiddenAt: baseDate
        ))
        let corrupt = EffectiveMethodVisibilityEntity(
            templateID: .earlierBedtime,
            hiddenAt: baseDate
        )
        corrupt.templateIDRawValue = "removed-template"
        context.insert(corrupt)
        try context.save()

        let store = SwiftDataEffectiveMethodVisibilityStore(modelContainer: container)
        XCTAssertThrowsError(try store.hiddenTemplateIDs()) {
            XCTAssertEqual(
                $0 as? EffectiveMethodVisibilityStoreError,
                .corruptData
            )
        }
    }

    @MainActor
    func testSessionHidesAndRestoresMethodWithoutDeletingCareKitHistory() async throws {
        let ended = makePlan(
            suffix: "visibility-control",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let source = EffectiveMethodCarePlanServiceStub(
            history: [ended],
            outcomes: [:]
        )
        let visibility = EffectiveMethodVisibilityStoreStub()
        let session = MicroPlanSession(
            service: source,
            effectiveMethodVisibilityStore: visibility
        )
        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)
        guard case .loaded(let initialCards) = session.effectiveMethodsState else {
            return XCTFail("Expected a method card")
        }
        XCTAssertEqual(initialCards.map(\.sourcePlanTemplateID), [.afternoonWalk])

        XCTAssertTrue(session.setEffectiveMethodHidden(
            true,
            templateID: .afternoonWalk,
            at: baseDate
        ))
        guard case .loaded(let visibleAfterHide) = session.effectiveMethodsState else {
            return XCTFail("Expected a loaded hidden state")
        }
        XCTAssertEqual(visibleAfterHide, [])
        XCTAssertEqual(
            session.hiddenEffectiveMethods.map(\.sourcePlanTemplateID),
            [.afternoonWalk]
        )
        let deleteCountAfterHide = await source.deleteRequestCount()
        let historyAfterHide = try await source.planHistory()
        XCTAssertEqual(deleteCountAfterHide, 0)
        XCTAssertEqual(historyAfterHide.map(\.draft.id), [ended.draft.id])

        XCTAssertTrue(session.setEffectiveMethodHidden(
            false,
            templateID: .afternoonWalk,
            at: baseDate
        ))
        guard case .loaded(let visibleAfterRestore) = session.effectiveMethodsState else {
            return XCTFail("Expected a restored method card")
        }
        XCTAssertEqual(visibleAfterRestore.map(\.sourcePlanTemplateID), [.afternoonWalk])
        XCTAssertEqual(session.hiddenEffectiveMethods, [])
        let deleteCountAfterRestore = await source.deleteRequestCount()
        XCTAssertEqual(deleteCountAfterRestore, 0)
    }

    @MainActor
    func testVisibilityReadFailureDoesNotExposeOrMisclassifyMethodCards() async throws {
        let ended = makePlan(
            suffix: "visibility-read-failure",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let visibility = EffectiveMethodVisibilityStoreStub(failsReads: true)
        let session = MicroPlanSession(
            service: EffectiveMethodCarePlanServiceStub(
                history: [ended],
                outcomes: [:]
            ),
            effectiveMethodVisibilityStore: visibility
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        XCTAssertEqual(session.effectiveMethodsState, .failed)
        XCTAssertEqual(session.hiddenEffectiveMethods, [])
        XCTAssertEqual(visibility.readCount, 1)
    }

    @MainActor
    func testVisibilityWriteFailureKeepsOriginalMethodLists() async throws {
        let ended = makePlan(
            suffix: "visibility-write-failure",
            templateID: .afternoonWalk,
            dayOffset: -5,
            status: .completed
        )
        let visibility = EffectiveMethodVisibilityStoreStub(failsWrites: true)
        let session = MicroPlanSession(
            service: EffectiveMethodCarePlanServiceStub(
                history: [ended],
                outcomes: [:]
            ),
            effectiveMethodVisibilityStore: visibility
        )
        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .live)

        XCTAssertFalse(session.setEffectiveMethodHidden(
            true,
            templateID: .afternoonWalk,
            at: baseDate
        ))

        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected the original loaded state")
        }
        XCTAssertEqual(cards.map(\.sourcePlanTemplateID), [.afternoonWalk])
        XCTAssertEqual(session.hiddenEffectiveMethods, [])
        XCTAssertTrue(session.showsError)
        XCTAssertEqual(session.message, "方法暂时无法隐藏，原列表没有改变。")
    }

    @MainActor
    func testDemoModeDoesNotReadOrWriteMethodVisibilityPreferences() async throws {
        let source = EffectiveMethodCarePlanServiceStub(history: [], outcomes: [:])
        let visibility = EffectiveMethodVisibilityStoreStub()
        let session = MicroPlanSession(
            service: source,
            effectiveMethodVisibilityStore: visibility
        )

        await session.refreshEffectiveMethods(snapshot: nil, dataMode: .demo)
        let didHide = session.setEffectiveMethodHidden(
            true,
            templateID: .afternoonWalk,
            at: baseDate
        )

        XCTAssertFalse(didHide)
        guard case .loaded(let cards) = session.effectiveMethodsState else {
            return XCTFail("Expected synthetic demo methods")
        }
        XCTAssertEqual(cards.map(\.sourcePlanTemplateID), [.earlierBedtime])
        XCTAssertEqual(visibility.readCount, 0)
        XCTAssertEqual(visibility.writeCount, 0)
        let historyReadCount = await source.historyRequestCount()
        XCTAssertEqual(historyReadCount, 0)
    }

    func testEvidenceFiltersExposeStableUserFacingCategories() {
        XCTAssertEqual(
            EffectiveMethodEvidenceFilter.allCases.map(\.title),
            ["全部", "睡眠", "精力", "压力", "可坚持性"]
        )
        XCTAssertEqual(EffectiveMethodEvidenceFilter.minimumAdherenceRate, 0.6)
    }

    func testSleepFilterRequiresFavorableComparableSleepEvidence() async throws {
        let favorableSleep = try await methodCardForFilter(objectiveMetrics: [
            evaluationMetric(
                metric: .sleepDuration,
                change: 0.6,
                direction: .favorable
            ),
        ])
        let neutralSleep = try await methodCardForFilter(objectiveMetrics: [
            evaluationMetric(
                metric: .sleepDuration,
                change: 0.1,
                direction: .neutral
            ),
        ])
        let favorableActivity = try await methodCardForFilter(objectiveMetrics: [
            evaluationMetric(
                metric: .activeEnergy,
                change: 30,
                direction: .favorable
            ),
        ])

        XCTAssertTrue(EffectiveMethodEvidenceFilter.sleep.matches(favorableSleep))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.sleep.matches(neutralSleep))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.sleep.matches(favorableActivity))
    }

    func testEnergyAndStressFiltersUseOnlyTheirOwnSubjectiveDirection() async throws {
        let higherEnergy = try await methodCardForFilter(subjectiveMetrics: [
            subjectiveMetric(.energy, before: 2.5, plan: 3.5),
            subjectiveMetric(.stress, before: 3, plan: 4),
        ])
        let lowerStress = try await methodCardForFilter(subjectiveMetrics: [
            subjectiveMetric(.energy, before: 4, plan: 3),
            subjectiveMetric(.stress, before: 4, plan: 2.5),
        ])
        let unchanged = try await methodCardForFilter(subjectiveMetrics: [
            subjectiveMetric(.energy, before: 3, plan: 3),
            subjectiveMetric(.stress, before: 3, plan: 3),
        ])

        XCTAssertTrue(EffectiveMethodEvidenceFilter.energy.matches(higherEnergy))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.stress.matches(higherEnergy))
        XCTAssertTrue(EffectiveMethodEvidenceFilter.stress.matches(lowerStress))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.energy.matches(lowerStress))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.energy.matches(unchanged))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.stress.matches(unchanged))
    }

    func testAdherenceFilterUsesWeightedCareKitCompletionBoundary() async throws {
        let atBoundary = try await methodCardForFilter(completedCount: 3)
        let belowBoundary = try await methodCardForFilter(completedCount: 2)

        XCTAssertTrue(EffectiveMethodEvidenceFilter.adherence.matches(atBoundary))
        XCTAssertFalse(EffectiveMethodEvidenceFilter.adherence.matches(belowBoundary))
        XCTAssertEqual(atBoundary.completion.completionRate, 0.6)
        XCTAssertEqual(belowBoundary.completion.completionRate, 0.4)
    }

    func testFilteringPreservesSourceOrderAndDoesNotChangeCards() async throws {
        let sleepCard = try await methodCardForFilter(objectiveMetrics: [
            evaluationMetric(
                metric: .sleepOnset,
                change: -0.5,
                direction: .favorable
            ),
        ])
        let activityCard = try await methodCardForFilter(objectiveMetrics: [
            evaluationMetric(
                metric: .stepCount,
                change: 1_000,
                direction: .favorable
            ),
        ])
        let source = [activityCard, sleepCard]

        XCTAssertEqual(EffectiveMethodEvidenceFilter.all.apply(to: source), source)
        XCTAssertEqual(
            EffectiveMethodEvidenceFilter.sleep.apply(to: source),
            [sleepCard]
        )
        XCTAssertEqual(source, [activityCard, sleepCard])
    }

    private func methodCardForFilter(
        completedCount: Int = 4,
        objectiveMetrics: [MicroPlanEvaluationMetricFact] = [],
        subjectiveMetrics: [EffectiveMethodSubjectiveMetricFact] = []
    ) async throws -> EffectiveMethodCardPresentation {
        let candidate = try await confidenceCandidate(
            completedCounts: [completedCount]
        )
        let run = try XCTUnwrap(candidate.runs.first)
        let subjectiveChange = EffectiveMethodSubjectiveRunChange(
            state: subjectiveMetrics.isEmpty ? .notRecorded : .available,
            metrics: subjectiveMetrics,
            beforeRecordedDayCount: subjectiveMetrics.isEmpty ? 0 : 2,
            planRecordedDayCount: subjectiveMetrics.isEmpty ? 0 : 2
        )
        return EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: [EffectiveMethodRunEvaluationFact(
                carePlanID: run.plan.draft.id,
                verdict: .mayHaveHelped,
                objectiveMetrics: objectiveMetrics,
                subjectiveChange: subjectiveChange
            )]
        )
    }

    private func evaluationMetric(
        metric: MicroPlanTrendMetric,
        change: Double,
        direction: MicroPlanEvaluationDirection
    ) -> MicroPlanEvaluationMetricFact {
        MicroPlanEvaluationMetricFact(
            metric: metric,
            healthMetric: metric.healthMetric,
            beforeMedian: 10,
            planMedian: 10 + change,
            changeFromBefore: change,
            beforeValidDayCount: 5,
            planValidDayCount: 5,
            direction: direction
        )
    }

    private func subjectiveMetric(
        _ dimension: EffectiveMethodSubjectiveDimension,
        before: Double,
        plan: Double
    ) -> EffectiveMethodSubjectiveMetricFact {
        EffectiveMethodSubjectiveMetricFact(
            dimension: dimension,
            beforeMedian: before,
            planMedian: plan
        )
    }

    private func makePlan(
        suffix: String,
        templateID: MicroPlanTemplateID?,
        dayOffset: Int,
        status: MicroPlanStatus,
        title: String? = nil
    ) -> MicroPlan {
        let start = baseDate.addingTimeInterval(Double(dayOffset) * 86_400)
        let rawTemplateID = templateID?.rawValue ?? "external"
        let draft = MicroPlanDraft(
            id: CarePlanID(rawValue: "plan.\(rawTemplateID).\(suffix)"),
            title: title ?? templateID?.title ?? "计划",
            taskID: CareTaskID(rawValue: "task.\(rawTemplateID).\(suffix)"),
            taskTitle: "任务 \(suffix)",
            startDate: start,
            endDateExclusive: start.addingTimeInterval(5 * 86_400),
            scheduledTime: try! ScheduledLocalTime(hour: 15, minute: 0),
            templateID: templateID
        )
        return MicroPlan(draft: draft, status: status)
    }

    private func outcome(
        index: Int,
        offset: TimeInterval = 0,
        state: PlanOutcomeState = .completed
    ) -> PlanOutcomeRecord {
        PlanOutcomeRecord(
            occurrenceIndex: index,
            state: state,
            recordedAt: baseDate.addingTimeInterval(offset),
            feedback: nil
        )
    }

    private func checkIn(
        on anchor: Date? = nil,
        dayOffset: Int,
        energy: SubjectiveRating = .three,
        stress: SubjectiveRating = .three,
        body: SubjectiveRating = .three
    ) throws -> DailyCheckIn {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let date = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: anchor ?? baseDate
        ))
        return try DailyCheckIn(
            localDay: SubjectiveLocalDay(date: date, timeZone: calendar.timeZone),
            energy: energy,
            stress: stress,
            bodyFeeling: body,
            note: "不会进入方法变化事实的合成备注",
            recordedAt: date
        )
    }

    private func confidenceCandidate(
        completedCounts: [Int],
        scheduledCount: Int = 5
    ) async throws -> EffectiveMethodCandidate {
        var plans = [MicroPlan]()
        var outcomesByTaskID = [CareTaskID: [PlanOutcomeRecord]]()
        var progressByPlanID = [CarePlanID: MicroPlanProgress]()
        for (index, completedCount) in completedCounts.enumerated() {
            let plan = makePlan(
                suffix: "confidence-\(index)",
                templateID: .afternoonWalk,
                dayOffset: -(index + 1) * 6,
                status: .completed
            )
            plans.append(plan)
            outcomesByTaskID[plan.draft.taskID] = (0..<completedCount).map {
                outcome(index: $0, offset: Double(index * 1_000 + $0))
            }
            progressByPlanID[plan.draft.id] = try MicroPlanProgress(
                scheduledCount: scheduledCount,
                completedCount: completedCount,
                skippedCount: 0
            )
        }
        let source = EffectiveMethodCarePlanServiceStub(
            history: plans,
            outcomes: outcomesByTaskID,
            progressByPlanID: progressByPlanID
        )
        let candidates = try await EffectiveMethodCandidateGenerator.load(from: source)
        return try XCTUnwrap(candidates.first)
    }

    private func evaluationFacts(
        for candidate: EffectiveMethodCandidate,
        verdicts: [MicroPlanEvaluationVerdict]
    ) -> [EffectiveMethodRunEvaluationFact] {
        XCTAssertEqual(candidate.runs.count, verdicts.count)
        return zip(candidate.runs, verdicts).map { run, verdict in
            EffectiveMethodRunEvaluationFact(
                carePlanID: run.plan.draft.id,
                verdict: verdict
            )
        }
    }

}

private enum EffectiveMethodSourceError: Error, Equatable {
    case historyReadFailed
    case activePlanReadFailed
    case outcomeReadFailed
    case progressReadFailed
    case unsupportedOperation
}

private actor EffectiveMethodCarePlanServiceStub: CarePlanService {
    private let history: [MicroPlan]
    private let outcomes: [CareTaskID: [PlanOutcomeRecord]]
    private let progressByPlanID: [CarePlanID: MicroPlanProgress]
    private let failingTaskID: CareTaskID?
    private let failingPlanID: CarePlanID?
    private let failsHistoryRead: Bool
    private let failsActivePlanRead: Bool
    private var requestedTaskIDs = [CareTaskID]()
    private var requestedPlanIDs = [CarePlanID]()
    private var requestedHistoryCount = 0
    private var requestedActivePlanCount = 0
    private var requestedDeleteCount = 0

    init(
        history: [MicroPlan],
        outcomes: [CareTaskID: [PlanOutcomeRecord]],
        progressByPlanID: [CarePlanID: MicroPlanProgress] = [:],
        failingTaskID: CareTaskID? = nil,
        failingPlanID: CarePlanID? = nil,
        failsHistoryRead: Bool = false,
        failsActivePlanRead: Bool = false
    ) {
        self.history = history
        self.outcomes = outcomes
        self.progressByPlanID = progressByPlanID
        self.failingTaskID = failingTaskID
        self.failingPlanID = failingPlanID
        self.failsHistoryRead = failsHistoryRead
        self.failsActivePlanRead = failsActivePlanRead
    }

    func planHistory() async throws -> [MicroPlan] {
        requestedHistoryCount += 1
        if failsHistoryRead {
            throw EffectiveMethodSourceError.historyReadFailed
        }
        return history
    }

    func outcomeRecords(for taskID: CareTaskID) async throws -> [PlanOutcomeRecord] {
        requestedTaskIDs.append(taskID)
        if taskID == failingTaskID {
            throw EffectiveMethodSourceError.outcomeReadFailed
        }
        return outcomes[taskID] ?? []
    }

    func outcomeRequests() -> [CareTaskID] { requestedTaskIDs }
    func progressRequests() -> [CarePlanID] { requestedPlanIDs }
    func historyRequestCount() -> Int { requestedHistoryCount }
    func activePlanRequestCount() -> Int { requestedActivePlanCount }
    func deleteRequestCount() -> Int { requestedDeleteCount }

    func createPlan(from draft: MicroPlanDraft) async throws -> MicroPlan {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func activePlan() async throws -> MicroPlan? {
        requestedActivePlanCount += 1
        if failsActivePlanRead {
            throw EffectiveMethodSourceError.activePlanReadFailed
        }
        return nil
    }
    func mostRecentPlan() async throws -> MicroPlan? { history.first }

    func recordOutcome(_ input: PlanOutcomeInput) async throws {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func outcomeState(
        for taskID: CareTaskID,
        occurrenceIndex: Int
    ) async throws -> PlanOutcomeState? {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func occurrenceIndex(
        for taskID: CareTaskID,
        on date: Date
    ) async throws -> Int? {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func progress(for planID: CarePlanID) async throws -> MicroPlanProgress {
        requestedPlanIDs.append(planID)
        if planID == failingPlanID {
            throw EffectiveMethodSourceError.progressReadFailed
        }
        if let progress = progressByPlanID[planID] {
            return progress
        }
        guard let plan = history.first(where: { $0.draft.id == planID }) else {
            throw EffectiveMethodSourceError.unsupportedOperation
        }
        let records = outcomes[plan.draft.taskID] ?? []
        return try MicroPlanProgress(
            scheduledCount: 5,
            completedCount: records.filter { $0.state == .completed }.count,
            skippedCount: records.filter { $0.state == .skipped }.count
        )
    }

    func pausePlan(_ planID: CarePlanID, at date: Date) async throws {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func resumePlan(_ planID: CarePlanID, at date: Date) async throws {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func endPlan(_ planID: CarePlanID, at date: Date) async throws {
        throw EffectiveMethodSourceError.unsupportedOperation
    }

    func deletePlan(_ planID: CarePlanID) async throws {
        requestedDeleteCount += 1
        throw EffectiveMethodSourceError.unsupportedOperation
    }
}

@MainActor
private final class EffectiveMethodVisibilityStoreStub: EffectiveMethodVisibilityStore {
    private(set) var hiddenIDs: Set<MicroPlanTemplateID>
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private let failsReads: Bool
    private let failsWrites: Bool

    init(
        hiddenIDs: Set<MicroPlanTemplateID> = [],
        failsReads: Bool = false,
        failsWrites: Bool = false
    ) {
        self.hiddenIDs = hiddenIDs
        self.failsReads = failsReads
        self.failsWrites = failsWrites
    }

    func hiddenTemplateIDs() throws -> Set<MicroPlanTemplateID> {
        readCount += 1
        if failsReads {
            throw EffectiveMethodVisibilityStoreError.persistenceFailed
        }
        return hiddenIDs
    }

    func setHidden(
        _ isHidden: Bool,
        templateID: MicroPlanTemplateID,
        at date: Date
    ) throws {
        writeCount += 1
        if failsWrites {
            throw EffectiveMethodVisibilityStoreError.persistenceFailed
        }
        if isHidden {
            hiddenIDs.insert(templateID)
        } else {
            hiddenIDs.remove(templateID)
        }
    }
}

@MainActor
private final class EmptySubjectiveRecordStore: SubjectiveRecordStore {
    func save(_ record: DailyCheckIn) throws -> DailyCheckIn { record }
    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? { nil }
    func deleteCheckIn(on day: SubjectiveLocalDay) throws {}
    func save(_ event: ContextEvent) throws {}
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] { [] }
    func deleteContextEvent(id: UUID) throws {}
}

@MainActor
private final class EffectiveMethodSubjectiveRecordStoreStub: SubjectiveRecordStore {
    private let recordsByDay: [String: DailyCheckIn]
    private let failsCheckInRead: Bool

    init(
        records: [DailyCheckIn],
        failsCheckInRead: Bool = false
    ) {
        recordsByDay = Dictionary(
            uniqueKeysWithValues: records.map { ($0.localDay.storageKey, $0) }
        )
        self.failsCheckInRead = failsCheckInRead
    }

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn { record }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        if failsCheckInRead {
            throw SubjectiveRecordStoreError.persistenceFailed
        }
        return recordsByDay[day.storageKey]
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {}
    func save(_ event: ContextEvent) throws {}
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] { [] }
    func deleteContextEvent(id: UUID) throws {}
}

@MainActor
private final class EffectiveMethodTrackingBaselineStore: PlanBaselineStore {
    private(set) var snapshots = [CarePlanID: MicroPlanBaselineSnapshot]()
    private(set) var savedPlanIDs = [CarePlanID]()
    private let failsSave: Bool

    init(failsSave: Bool = false) {
        self.failsSave = failsSave
    }

    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        if failsSave { throw PlanBaselineStoreError.persistenceFailed }
        snapshots[snapshot.carePlanID] = snapshot
        savedPlanIDs.append(snapshot.carePlanID)
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        snapshots[carePlanID]
    }

    func delete(for carePlanID: CarePlanID) throws {
        snapshots[carePlanID] = nil
    }
}
