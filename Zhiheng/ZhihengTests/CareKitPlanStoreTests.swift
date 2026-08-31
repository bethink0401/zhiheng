import CareKitStore
import XCTest
@testable import Zhiheng

final class CareKitPlanStoreTests: XCTestCase {
    @MainActor
    func testAIPlanCandidateStartsRecordsTodayAndEndsThroughSharedSession() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let session = MicroPlanSession(service: service)
        let referenceDate = Date()
        let action = HealthAISuggestedAction(
            templateID: .earlierBedtime,
            rationale: "测试候选"
        )

        let didStart = await session.start(
            from: action,
            referenceDate: referenceDate
        )
        XCTAssertTrue(didStart)
        XCTAssertEqual(session.activePlan?.draft.title, "提前上床")
        XCTAssertEqual(session.progress?.scheduledCount, 5)

        await session.recordToday(.completed, referenceDate: referenceDate)
        XCTAssertEqual(session.todayOutcomeState, .completed)
        XCTAssertEqual(session.progress?.completedCount, 1)

        await session.endEarly(referenceDate: referenceDate)
        XCTAssertNil(session.activePlan)
        XCTAssertEqual(session.displayedPlan?.status, .endedEarly)
        XCTAssertEqual(session.progress?.completedCount, 1)
        XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.history.first?.plan.status, .endedEarly)
        XCTAssertEqual(session.history.first?.progress.completedCount, 1)
    }

    func testRejectsStartingASecondPlanWhileOneIsActive() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        _ = try await service.createPlan(from: makeDraft())

        do {
            _ = try await service.createPlan(from: makeDraft())
            XCTFail("Expected the second active plan to be rejected")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .activePlanExists)
        }
    }

    func testCreatesAndReadsActivePlanWithoutLeakingCareKitTypes() async throws {
        let service: any CarePlanService = CareKitPlanStore(
            inMemoryStoreNamed: UUID().uuidString
        )
        let draft = try makeDraft()

        let created = try await service.createPlan(from: draft)
        let active = try await service.activePlan()

        XCTAssertEqual(created, MicroPlan(draft: draft, status: .active))
        XCTAssertEqual(active, created)
    }

    func testPlanHistoryReturnsEveryPlanNewestFirstAndNormalizesExpiredPlans() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let oldest = try makeDraft(startDayOffset: -10)
        let recent = try makeDraft(startDayOffset: -6)
        let active = try makeDraft()

        _ = try await service.createPlan(from: oldest)
        _ = try await service.createPlan(from: recent)
        _ = try await service.createPlan(from: active)

        let history = try await service.planHistory()

        XCTAssertEqual(history.map(\.draft.id), [active.id, recent.id, oldest.id])
        XCTAssertEqual(history.map(\.status), [.active, .completed, .completed])
    }

    func testRecordsCompletedAndSkippedOutcomesIntoProgress() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft()
        _ = try await service.createPlan(from: draft)

        try await service.recordOutcome(
            PlanOutcomeInput(
                taskID: draft.taskID,
                occurrenceIndex: 0,
                state: .completed,
                recordedAt: draft.startDate.addingTimeInterval(10 * 60 * 60),
                difficulty: 2
            )
        )
        try await service.recordOutcome(
            PlanOutcomeInput(
                taskID: draft.taskID,
                occurrenceIndex: 1,
                state: .skipped,
                recordedAt: draft.startDate.addingTimeInterval(34 * 60 * 60),
                difficulty: nil
            )
        )

        let progress = try await service.progress(for: draft.id)
        XCTAssertEqual(progress.scheduledCount, 3)
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertEqual(progress.skippedCount, 1)
        XCTAssertEqual(progress.unresolvedCount, 1)
        let firstState = try await service.outcomeState(
            for: draft.taskID,
            occurrenceIndex: 0
        )
        let secondState = try await service.outcomeState(
            for: draft.taskID,
            occurrenceIndex: 1
        )
        let thirdState = try await service.outcomeState(
            for: draft.taskID,
            occurrenceIndex: 2
        )
        XCTAssertEqual(firstState, .completed)
        XCTAssertEqual(secondState, .skipped)
        XCTAssertNil(thirdState)
    }

    func testRejectsASecondOutcomeForTheSameOccurrence() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft()
        _ = try await service.createPlan(from: draft)
        let input = try PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: draft.startDate.addingTimeInterval(10 * 60 * 60),
            difficulty: nil
        )
        try await service.recordOutcome(input)

        do {
            try await service.recordOutcome(input)
            XCTFail("Expected a duplicate outcome to be rejected")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .outcomeConflict)
        }
    }

    func testEndingEarlyRemovesFutureOccurrencesFromProgress() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft(startDayOffset: -2)
        _ = try await service.createPlan(from: draft)
        let secondDayStart = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: draft.startDate)
        )

        try await service.endPlan(draft.id, at: secondDayStart)

        let activePlan = try await service.activePlan()
        let recentPlan = try await service.mostRecentPlan()
        XCTAssertNil(activePlan)
        XCTAssertEqual(recentPlan?.status, .endedEarly)
        XCTAssertEqual(recentPlan?.draft.id, draft.id)
        let progress = try await service.progress(for: draft.id)
        XCTAssertEqual(progress.scheduledCount, 1)
        XCTAssertEqual(progress.completedCount, 0)
    }

    func testRejectsOutcomeScheduledAfterAnEarlyEnd() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft(startDayOffset: -2)
        _ = try await service.createPlan(from: draft)
        let secondDayStart = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: draft.startDate)
        )
        try await service.endPlan(draft.id, at: secondDayStart)

        let futureOutcome = try PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 1,
            state: .completed,
            recordedAt: secondDayStart,
            difficulty: nil
        )

        do {
            try await service.recordOutcome(futureOutcome)
            XCTFail("Expected an outcome beyond the early end to be rejected")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .outcomeConflict)
        }
    }

    func testMissingPlanIsAStableDomainError() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)

        do {
            _ = try await service.progress(for: CarePlanID(rawValue: "missing"))
            XCTFail("Expected a missing plan error")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .planNotFound)
        }
    }

    func testOnDiskPlanOutcomeAndLatestVersionSurviveStoreRecreation() async throws {
        let storeName = "zhiheng-tests-\(UUID().uuidString)"
        var writer: CareKitPlanStore? = CareKitPlanStore(onDiskStoreNamed: storeName)
        var reader: CareKitPlanStore?
        var didDeleteStore = false
        defer {
            writer = nil
            reader = nil
            if !didDeleteStore {
                try? OCKStore(name: storeName, type: .onDisk()).delete()
            }
        }

        let draft = try makeDraft(startDayOffset: -2)
        _ = try await writer?.createPlan(from: draft)
        try await writer?.recordOutcome(
            PlanOutcomeInput(
                taskID: draft.taskID,
                occurrenceIndex: 0,
                state: .completed,
                recordedAt: draft.startDate.addingTimeInterval(10 * 60 * 60),
                difficulty: 2
            )
        )
        let secondDayStart = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: draft.startDate)
        )
        try await writer?.endPlan(draft.id, at: secondDayStart)

        writer = nil
        reader = CareKitPlanStore(onDiskStoreNamed: storeName)

        let activePlan = try await reader?.activePlan()
        let progress = try await reader?.progress(for: draft.id)
        XCTAssertNil(activePlan)
        XCTAssertEqual(progress?.scheduledCount, 1)
        XCTAssertEqual(progress?.completedCount, 1)
        XCTAssertEqual(progress?.skippedCount, 0)

        writer = nil
        reader = nil
        try OCKStore(name: storeName, type: .onDisk()).delete()
        didDeleteStore = true
    }

    private func makeDraft(startDayOffset: Int = 0) throws -> MicroPlanDraft {
        let today = Calendar.current.startOfDay(for: Date())
        let start = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: startDayOffset, to: today)
        )
        let end = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 3, to: start)
        )
        return MicroPlanDraft(
            id: CarePlanID(rawValue: "sleep-rhythm-\(UUID().uuidString)"),
            title: "三天作息微计划",
            taskID: CareTaskID(rawValue: "wind-down-\(UUID().uuidString)"),
            taskTitle: "睡前放松十分钟",
            startDate: start,
            endDateExclusive: end,
            scheduledTime: try ScheduledLocalTime(hour: 22, minute: 30)
        )
    }
}
