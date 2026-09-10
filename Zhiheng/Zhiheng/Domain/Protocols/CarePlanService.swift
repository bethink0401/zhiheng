import Foundation

enum CarePlanServiceError: Error, Equatable, Sendable {
    case activePlanExists
    case invalidPlanState
    case planNotFound
    case taskNotFound
    case outcomeConflict
    case persistenceFailed
}

/// 正式 CareKitStore 适配器实现此协议；上层不得直接导入 CareKit。
protocol CarePlanService: Sendable {
    func createPlan(from draft: MicroPlanDraft) async throws -> MicroPlan
    func activePlan() async throws -> MicroPlan?
    func mostRecentPlan() async throws -> MicroPlan?
    func planHistory() async throws -> [MicroPlan]
    func recordOutcome(_ input: PlanOutcomeInput) async throws
    func outcomeState(
        for taskID: CareTaskID,
        occurrenceIndex: Int
    ) async throws -> PlanOutcomeState?
    func outcomeRecords(for taskID: CareTaskID) async throws -> [PlanOutcomeRecord]
    func occurrenceIndex(
        for taskID: CareTaskID,
        on date: Date
    ) async throws -> Int?
    func progress(for planID: CarePlanID) async throws -> MicroPlanProgress
    func pausePlan(_ planID: CarePlanID, at date: Date) async throws
    func resumePlan(_ planID: CarePlanID, at date: Date) async throws
    func endPlan(_ planID: CarePlanID, at date: Date) async throws
    func deletePlan(_ planID: CarePlanID) async throws
}

enum PlanBaselineStoreError: Error, Equatable {
    case persistenceFailed
    case unsupportedSchema
}

@MainActor
protocol PlanBaselineStore {
    func save(_ snapshot: MicroPlanBaselineSnapshot) throws
    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot?
    func delete(for carePlanID: CarePlanID) throws
}

@MainActor
final class InMemoryPlanBaselineStore: PlanBaselineStore {
    private var snapshots = [CarePlanID: MicroPlanBaselineSnapshot]()

    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        snapshots[snapshot.carePlanID] = snapshot
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        snapshots[carePlanID]
    }

    func delete(for carePlanID: CarePlanID) throws {
        snapshots[carePlanID] = nil
    }
}

@MainActor
final class UnavailablePlanBaselineStore: PlanBaselineStore {
    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        throw PlanBaselineStoreError.persistenceFailed
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        throw PlanBaselineStoreError.persistenceFailed
    }

    func delete(for carePlanID: CarePlanID) throws {
        throw PlanBaselineStoreError.persistenceFailed
    }
}
