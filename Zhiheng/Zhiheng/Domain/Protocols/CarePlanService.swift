import Foundation

enum CarePlanServiceError: Error, Equatable, Sendable {
    case activePlanExists
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
    func progress(for planID: CarePlanID) async throws -> MicroPlanProgress
    func endPlan(_ planID: CarePlanID, at date: Date) async throws
}
