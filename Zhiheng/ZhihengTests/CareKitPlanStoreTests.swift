import CareKitStore
import SwiftData
import XCTest
@testable import Zhiheng

final class CareKitPlanStoreTests: XCTestCase {
    @MainActor
    func testAIPlanCandidateStartsRecordsTodayAndEndsThroughSharedSession() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let baselineStore = InMemoryPlanBaselineStore()
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore
        )
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
        XCTAssertEqual(
            session.baselineSnapshot?.carePlanID,
            session.activePlan?.draft.id
        )
        XCTAssertEqual(session.baselineSnapshot?.dataMode, .live)
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

    @MainActor
    func testSessionLoadsOnlyPlanIntervalContextFromSharedSwiftDataStore() async throws {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SubjectiveRecordsMigrationPlan.self,
            configurations: [ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        let subjectiveStore = SwiftDataSubjectiveRecordStore(
            modelContainer: container
        )
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let referenceDate = Date()
        let planStart = Calendar.current.startOfDay(for: referenceDate)
        let planEnd = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 5, to: planStart)
        )
        try subjectiveStore.save(ContextEvent(
            kind: .custom,
            customLabel: "私人行程名称",
            startedAt: planStart.addingTimeInterval(60 * 60),
            intensity: .medium,
            note: "私人备注"
        ))
        try subjectiveStore.save(ContextEvent(
            kind: .travel,
            startedAt: planEnd,
            intensity: .high
        ))
        let session = MicroPlanSession(
            service: service,
            subjectiveRecordStore: subjectiveStore
        )

        let didStart = await session.start(
            from: HealthAISuggestedAction(
                templateID: .afternoonWalk,
                rationale: "计划期背景测试"
            ),
            dataMode: .live,
            referenceDate: referenceDate
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(session.evaluationContext.status, .recorded)
        XCTAssertEqual(session.evaluationContext.events.count, 1)
        XCTAssertEqual(session.evaluationContext.events.first?.kind, .custom)
        XCTAssertEqual(session.evaluationContext.events.first?.occurrenceCount, 1)
        XCTAssertEqual(session.evaluationContext.events.first?.highestIntensity, .medium)
    }

    @MainActor
    func testContextReadFailureDoesNotHidePlanAndStaysUnknown() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let session = MicroPlanSession(
            service: service,
            subjectiveRecordStore: UnavailableSubjectiveRecordStore()
        )

        let didStart = await session.start(from: HealthAISuggestedAction(
            templateID: .afternoonWalk,
            rationale: "读取失败测试"
        ))

        XCTAssertTrue(didStart)
        XCTAssertNotNil(session.activePlan)
        XCTAssertEqual(session.evaluationContext, .unavailable)
        XCTAssertFalse(session.showsError)
    }

    @MainActor
    func testDemoPlanDoesNotReadRealSubjectiveStore() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let subjectiveStore = TrackingSubjectiveRecordStore()
        let session = MicroPlanSession(
            service: service,
            subjectiveRecordStore: subjectiveStore
        )

        let didStart = await session.start(
            from: HealthAISuggestedAction(
                templateID: .afternoonWalk,
                rationale: "演示隔离测试"
            ),
            dataMode: .demo
        )

        XCTAssertTrue(didStart)
        XCTAssertEqual(session.evaluationContext, .demoMode)
        XCTAssertEqual(subjectiveStore.contextReadCount, 0)
    }

    @MainActor
    func testSwiftDataBaselineStoreRoundTripsVersionedSnapshot() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PlanAnalysisMetadataEntity.self,
            configurations: configuration
        )
        let planID = CarePlanID(rawValue: "microplan.baseline.roundtrip")
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = MicroPlanBaselineSnapshot(
            carePlanID: planID,
            planStartDate: capturedAt,
            capturedAt: capturedAt,
            dataMode: .demo,
            metrics: [MicroPlanBaselineMetricSnapshot(
                metric: .stepCount,
                median: 6_500,
                validDayCount: 5
            )],
            schemaVersion: MicroPlanBaselineSnapshot.currentSchemaVersion
        )
        let writer = SwiftDataPlanBaselineStore(modelContainer: container)
        try writer.save(snapshot)

        let reader = SwiftDataPlanBaselineStore(modelContainer: container)
        XCTAssertEqual(try reader.baseline(for: planID), snapshot)
        try reader.delete(for: planID)
        XCTAssertNil(try reader.baseline(for: planID))
    }

    @MainActor
    func testBaselinePersistenceFailurePreventsCareKitPlanCreation() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let session = MicroPlanSession(
            service: service,
            baselineStore: FailingPlanBaselineStore()
        )

        let didStart = await session.start(from: HealthAISuggestedAction(
            templateID: .afternoonWalk,
            rationale: "测试基线失败"
        ))

        XCTAssertFalse(didStart)
        let activePlan = try await service.activePlan()
        XCTAssertNil(activePlan)
        XCTAssertTrue(session.showsError)
    }

    @MainActor
    func testCareKitCreationFailureRollsBackNewBaselineSnapshot() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        _ = try await service.createPlan(from: makeDraft())
        let baselineStore = TrackingPlanBaselineStore()
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore
        )

        let didStart = await session.start(from: HealthAISuggestedAction(
            templateID: .afternoonWalk,
            rationale: "测试 CareKit 创建失败回滚"
        ))

        XCTAssertFalse(didStart)
        XCTAssertEqual(baselineStore.savedPlanIDs.count, 1)
        XCTAssertEqual(baselineStore.deletedPlanIDs, baselineStore.savedPlanIDs)
        XCTAssertTrue(baselineStore.snapshots.isEmpty)
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

    func testPauseAndResumeSkipPausedDaysAndPreserveOutcomeIndexes() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft()
        _ = try await service.createPlan(from: draft)
        let pauseDate = draft.startDate.addingTimeInterval(10 * 60 * 60)
        let resumeDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 2, to: pauseDate)
        )

        try await service.pausePlan(draft.id, at: pauseDate)

        let loadedPausedPlan = try await service.activePlan()
        let pausedPlan = try XCTUnwrap(loadedPausedPlan)
        XCTAssertEqual(pausedPlan.status, .paused)
        do {
            try await service.recordOutcome(PlanOutcomeInput(
                taskID: draft.taskID,
                occurrenceIndex: 0,
                state: .completed,
                recordedAt: pauseDate,
                difficulty: nil
            ))
            XCTFail("Expected paused plans to reject outcomes")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .outcomeConflict)
        }

        try await service.resumePlan(draft.id, at: resumeDate)

        let loadedResumedPlan = try await service.activePlan()
        let resumedPlan = try XCTUnwrap(loadedResumedPlan)
        XCTAssertEqual(resumedPlan.status, .active)
        XCTAssertEqual(
            Calendar.current.dateComponents(
                [.day],
                from: draft.endDateExclusive,
                to: resumedPlan.draft.endDateExclusive
            ).day,
            2
        )
        let pausedDay = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: draft.startDate)
        )
        let pausedOccurrence = try await service.occurrenceIndex(
            for: draft.taskID,
            on: pausedDay
        )
        let resumedOccurrence = try await service.occurrenceIndex(
            for: draft.taskID,
            on: resumeDate
        )
        XCTAssertNil(pausedOccurrence)
        XCTAssertEqual(resumedOccurrence, 0)

        try await service.recordOutcome(PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: resumeDate,
            difficulty: nil
        ))
        let progress = try await service.progress(for: draft.id)
        XCTAssertEqual(progress.scheduledCount, 3)
        XCTAssertEqual(progress.completedCount, 1)
    }

    func testCompletedDayCanPauseAndResumeWithoutExtendingThePlan() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft()
        _ = try await service.createPlan(from: draft)
        let completedAt = draft.startDate.addingTimeInterval(9 * 60 * 60)
        try await service.recordOutcome(PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: completedAt,
            difficulty: nil
        ))
        let pausedAt = draft.startDate.addingTimeInterval(10 * 60 * 60)
        let resumedAt = draft.startDate.addingTimeInterval(11 * 60 * 60)

        try await service.pausePlan(draft.id, at: pausedAt)
        try await service.resumePlan(draft.id, at: resumedAt)

        let loadedResumed = try await service.activePlan()
        let resumed = try XCTUnwrap(loadedResumed)
        XCTAssertEqual(resumed.status, .active)
        XCTAssertEqual(resumed.draft.endDateExclusive, draft.endDateExclusive)
        let outcomeState = try await service.outcomeState(
            for: draft.taskID,
            occurrenceIndex: 0
        )
        XCTAssertEqual(outcomeState, .completed)
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

    @MainActor
    func testSessionRecordsTwoCalendarDaysWithoutOverwritingHistory() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let session = MicroPlanSession(service: service)
        let firstDay = Calendar.current.startOfDay(for: Date())
        let secondDay = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: firstDay)
        )
        let action = HealthAISuggestedAction(
            templateID: .afternoonWalk,
            rationale: "跨天测试"
        )

        let didStart = await session.start(
            from: action,
            referenceDate: firstDay
        )
        XCTAssertTrue(didStart)
        await session.recordToday(.completed, referenceDate: firstDay)
        XCTAssertEqual(session.todayOutcomeState, .completed)

        await session.refresh(referenceDate: secondDay)
        XCTAssertNil(session.todayOutcomeState)
        await session.recordToday(.skipped, referenceDate: secondDay)

        XCTAssertEqual(session.todayOutcomeState, .skipped)
        XCTAssertEqual(session.progress?.completedCount, 1)
        XCTAssertEqual(session.progress?.skippedCount, 1)
        XCTAssertEqual(
            session.outcomeRecords.map(\.state),
            [.completed, .skipped]
        )
    }

    func testOptionalFeedbackIsStoredWithOutcomeAndReadBack() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let draft = try makeDraft()
        _ = try await service.createPlan(from: draft)
        let recordedAt = draft.startDate.addingTimeInterval(10 * 60 * 60)

        try await service.recordOutcome(PlanOutcomeInput(
            taskID: draft.taskID,
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: recordedAt,
            difficulty: nil,
            feedback: "  比昨天更容易开始，结束后感觉轻松。  "
        ))

        let records = try await service.outcomeRecords(for: draft.taskID)
        XCTAssertEqual(records, [PlanOutcomeRecord(
            occurrenceIndex: 0,
            state: .completed,
            recordedAt: recordedAt,
            feedback: "比昨天更容易开始，结束后感觉轻松。"
        )])
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

    @MainActor
    func testDeletingEndedPlanRemovesCareKitHistoryAndSwiftDataBaseline() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let baselineStore = InMemoryPlanBaselineStore()
        let session = MicroPlanSession(
            service: service,
            baselineStore: baselineStore
        )
        let referenceDate = Date()

        let didStart = await session.start(
            from: HealthAISuggestedAction(
                templateID: .earlierBedtime,
                rationale: "删除一致性测试"
            ),
            referenceDate: referenceDate
        )
        XCTAssertTrue(didStart)
        let planID = try XCTUnwrap(session.activePlan?.draft.id)
        let taskID = try XCTUnwrap(session.activePlan?.draft.taskID)
        await session.recordToday(
            .completed,
            feedback: "这条反馈也应被删除",
            referenceDate: referenceDate
        )
        await session.endEarly(referenceDate: referenceDate)
        let endedPlan = try XCTUnwrap(session.displayedPlan)
        XCTAssertNotNil(try baselineStore.baseline(for: planID))
        XCTAssertEqual(session.history.count, 1)

        await session.delete(endedPlan, referenceDate: referenceDate)

        XCTAssertFalse(session.showsError)
        XCTAssertNil(session.displayedPlan)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertNil(try baselineStore.baseline(for: planID))
        do {
            _ = try await service.progress(for: planID)
            XCTFail("Expected deleted CareKit plan to be unavailable")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .planNotFound)
        }
        do {
            _ = try await service.outcomeRecords(for: taskID)
            XCTFail("Expected deleted task outcomes to be unavailable")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .taskNotFound)
        }
    }

    func testDeletingOnePlanLeavesOtherHistoricalPlanUnchanged() async throws {
        let service = CareKitPlanStore(inMemoryStoreNamed: UUID().uuidString)
        let older = try makeDraft(startDayOffset: -10)
        let newer = try makeDraft(startDayOffset: -6)
        _ = try await service.createPlan(from: older)
        _ = try await service.createPlan(from: newer)

        try await service.deletePlan(newer.id)

        let history = try await service.planHistory()
        XCTAssertEqual(history.map(\.draft.id), [older.id])
        XCTAssertEqual(history.first?.status, .completed)
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
                difficulty: 2,
                feedback: "完成后感觉比较平稳"
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
        let outcomes = try await reader?.outcomeRecords(for: draft.taskID)
        XCTAssertNil(activePlan)
        XCTAssertEqual(progress?.scheduledCount, 1)
        XCTAssertEqual(progress?.completedCount, 1)
        XCTAssertEqual(progress?.skippedCount, 0)
        XCTAssertEqual(outcomes?.first?.feedback, "完成后感觉比较平稳")

        writer = nil
        reader = nil
        try OCKStore(name: storeName, type: .onDisk()).delete()
        didDeleteStore = true
    }

    func testDeletedPlanStaysDeletedAfterOnDiskStoreRecreation() async throws {
        let storeName = "zhiheng-delete-tests-\(UUID().uuidString)"
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
                difficulty: nil,
                feedback: "删除后不得跨重启恢复"
            )
        )
        try await writer?.deletePlan(draft.id)

        writer = nil
        reader = CareKitPlanStore(onDiskStoreNamed: storeName)

        let history = try await reader?.planHistory()
        XCTAssertTrue(history?.isEmpty == true)
        do {
            _ = try await reader?.progress(for: draft.id)
            XCTFail("Expected deleted plan to remain unavailable after recreation")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .planNotFound)
        }
        do {
            _ = try await reader?.outcomeRecords(for: draft.taskID)
            XCTFail("Expected deleted task to remain unavailable after recreation")
        } catch let error as CarePlanServiceError {
            XCTAssertEqual(error, .taskNotFound)
        }

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

@MainActor
private final class FailingPlanBaselineStore: PlanBaselineStore {
    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        throw PlanBaselineStoreError.persistenceFailed
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        nil
    }

    func delete(for carePlanID: CarePlanID) throws {}
}

@MainActor
private final class TrackingPlanBaselineStore: PlanBaselineStore {
    private(set) var snapshots = [CarePlanID: MicroPlanBaselineSnapshot]()
    private(set) var savedPlanIDs = [CarePlanID]()
    private(set) var deletedPlanIDs = [CarePlanID]()

    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        savedPlanIDs.append(snapshot.carePlanID)
        snapshots[snapshot.carePlanID] = snapshot
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        snapshots[carePlanID]
    }

    func delete(for carePlanID: CarePlanID) throws {
        deletedPlanIDs.append(carePlanID)
        snapshots[carePlanID] = nil
    }
}

@MainActor
private final class TrackingSubjectiveRecordStore: SubjectiveRecordStore {
    private(set) var contextReadCount = 0

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn { record }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? { nil }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {}

    func save(_ event: ContextEvent) throws {}

    func contextEvents(
        overlapping interval: DateInterval
    ) throws -> [ContextEvent] {
        contextReadCount += 1
        return []
    }

    func deleteContextEvent(id: UUID) throws {}
}
