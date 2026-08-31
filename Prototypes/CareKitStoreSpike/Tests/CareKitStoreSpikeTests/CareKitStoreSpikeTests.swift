import CareKitStore
import XCTest
@testable import CareKitStoreSpike

final class CareKitStoreSpikeTests: XCTestCase {
    func testThreeDayPlanStoresTaskOutcomesAndCurrentProgress() async throws {
        let store = OCKStore(name: UUID().uuidString, type: .inMemory)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        // CareKit 的 schedule end 是排除式边界；三天计划应结束在第 4 天零点。
        let scheduleEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))
        let queryEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))

        let plan = try await store.addCarePlan(
            OCKCarePlan(
                id: "sleep-rhythm-3-day",
                title: "三天作息微计划",
                patientUUID: nil
            )
        )

        let schedule = OCKSchedule.dailyAtTime(
            hour: 22,
            minutes: 30,
            start: start,
            end: scheduleEnd,
            text: "准备睡前放松"
        )

        let task = try await store.addTask(
            OCKTask(
                id: "wind-down",
                title: "睡前放松十分钟",
                carePlanUUID: plan.uuid,
                schedule: schedule
            )
        )

        var feedback = OCKOutcomeValue(true)
        feedback.kind = "completed"

        _ = try await store.addOutcomes([
            OCKOutcome(
                taskUUID: task.uuid,
                taskOccurrenceIndex: 0,
                values: [feedback]
            ),
            OCKOutcome(
                taskUUID: task.uuid,
                taskOccurrenceIndex: 1,
                values: [feedback]
            )
        ])

        let fetchedPlans = try await store.fetchCarePlans(query: OCKCarePlanQuery())
        let fetchedTasks = try await store.fetchTasks(query: OCKTaskQuery(id: task.id))
        let fetchedOutcomes = try await store.fetchOutcomes(query: OCKOutcomeQuery())

        XCTAssertEqual(fetchedPlans.map(\.id), [plan.id])
        XCTAssertEqual(fetchedTasks.map(\.id), [task.id])
        XCTAssertEqual(fetchedOutcomes.count, 2)
        XCTAssertEqual(fetchedOutcomes.first?.values.first?.kind, "completed")

        let adherence = try await store.fetchAdherence(
            query: OCKAdherenceQuery(
                taskIDs: [task.id],
                dateInterval: DateInterval(start: start, end: queryEnd),
                computeProgress: { event in
                    event.computeProgress(by: .checkingOutcomeExists)
                }
            )
        )

        let summary = PlanProgressSummary(adherence: adherence)
        XCTAssertEqual(summary.scheduledDayCount, 3)
        let completedFraction = try XCTUnwrap(summary.completedFraction)
        XCTAssertEqual(completedFraction, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.missingEventDayCount, 0)
    }

    func testTaskUpdateCreatesTraceableVersion() async throws {
        let store = OCKStore(name: UUID().uuidString, type: .inMemory)
        let schedule = OCKSchedule.dailyAtTime(
            hour: 22,
            minutes: 30,
            start: Date(),
            end: nil,
            text: nil
        )

        let original = try await store.addTask(
            OCKTask(
                id: "wind-down",
                title: "睡前放松十分钟",
                carePlanUUID: nil,
                schedule: schedule
            )
        )

        let updated = try await store.updateTask(
            OCKTask(
                id: "wind-down",
                title: "睡前放松十五分钟",
                carePlanUUID: nil,
                schedule: schedule
            )
        )

        XCTAssertEqual(updated.title, "睡前放松十五分钟")
        XCTAssertEqual(updated.previousVersionUUIDs.first, original.uuid)
    }
}
