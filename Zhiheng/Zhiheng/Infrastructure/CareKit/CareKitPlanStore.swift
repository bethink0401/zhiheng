import CareKitStore
import Foundation

actor CareKitPlanStore: CarePlanService {
    private enum MetadataKey {
        static let status = "zhiheng.status"
        static let taskID = "zhiheng.taskID"
        static let taskTitle = "zhiheng.taskTitle"
        static let startDate = "zhiheng.startDate"
        static let endDateExclusive = "zhiheng.endDateExclusive"
        static let scheduledHour = "zhiheng.scheduledHour"
        static let scheduledMinute = "zhiheng.scheduledMinute"
        static let templateID = "zhiheng.templateID"
        static let endedAt = "zhiheng.endedAt"
    }

    private enum OutcomeKind {
        static let state = "zhiheng.outcome.state"
        static let difficulty = "zhiheng.outcome.difficulty"
    }

    private let store: OCKStore

    /// This initializer is intentionally explicit so an in-memory store cannot be
    /// mistaken for the future production persistence configuration.
    init(inMemoryStoreNamed name: String) {
        store = OCKStore(name: name, type: .inMemory)
    }

    /// Production persistence is selected explicitly so previews and unit tests
    /// cannot accidentally write durable plan data.
    init(onDiskStoreNamed name: String) {
        store = OCKStore(name: name, type: .onDisk())
    }

    func createPlan(from draft: MicroPlanDraft) async throws -> MicroPlan {
        do {
            guard try await activePlan() == nil else {
                throw CarePlanServiceError.activePlanExists
            }
            guard draft.endDateExclusive > draft.startDate else {
                throw CarePlanServiceError.persistenceFailed
            }
            guard
                let firstScheduledDate = Calendar.current.date(
                    bySettingHour: draft.scheduledTime.hour,
                    minute: draft.scheduledTime.minute,
                    second: 0,
                    of: draft.startDate
                ),
                firstScheduledDate < draft.endDateExclusive
            else {
                throw CarePlanServiceError.persistenceFailed
            }

            var plan = OCKCarePlan(
                id: draft.id.rawValue,
                title: draft.title,
                patientUUID: nil
            )
            plan.effectiveDate = draft.startDate
            plan.userInfo = metadata(for: draft, status: .active)

            let storedPlan = try await store.addCarePlan(plan)

            do {
                let schedule = OCKSchedule.dailyAtTime(
                    hour: draft.scheduledTime.hour,
                    minutes: draft.scheduledTime.minute,
                    start: draft.startDate,
                    end: draft.endDateExclusive,
                    text: draft.taskTitle
                )
                let task = OCKTask(
                    id: draft.taskID.rawValue,
                    title: draft.taskTitle,
                    carePlanUUID: storedPlan.uuid,
                    schedule: schedule
                )
                _ = try await store.addTask(task)
            } catch {
                _ = try? await store.deleteCarePlan(storedPlan)
                throw CarePlanServiceError.persistenceFailed
            }

            return MicroPlan(draft: draft, status: .active)
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func activePlan() async throws -> MicroPlan? {
        do {
            let plans = try await store.fetchCarePlans(
                query: OCKCarePlanQuery(dateInterval: latestVersionInterval)
            )

            for storedPlan in plans {
                let plan = try decode(storedPlan)
                guard plan.status == .active, Date() < plan.draft.endDateExclusive else {
                    continue
                }
                _ = try await task(with: plan.draft.taskID)
                return plan
            }

            return nil
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func mostRecentPlan() async throws -> MicroPlan? {
        try await planHistory().first
    }

    func planHistory() async throws -> [MicroPlan] {
        do {
            let storedPlans = try await store.fetchCarePlans(
                query: OCKCarePlanQuery(dateInterval: latestVersionInterval)
            )
            var plansByID = [CarePlanID: MicroPlan]()
            for storedPlan in storedPlans {
                let decoded = try decode(storedPlan)
                _ = try await task(with: decoded.draft.taskID)
                if decoded.status == .active, Date() >= decoded.draft.endDateExclusive {
                    plansByID[decoded.draft.id] = MicroPlan(
                        draft: decoded.draft,
                        status: .completed
                    )
                } else {
                    plansByID[decoded.draft.id] = decoded
                }
            }
            return plansByID.values.sorted { first, second in
                first.draft.startDate > second.draft.startDate
            }
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func recordOutcome(_ input: PlanOutcomeInput) async throws {
        do {
            let storedTask = try await task(with: input.taskID)
            let storedPlan = try await carePlan(containing: storedTask)
            let plan = try decode(storedPlan)
            let outcomes = try await outcomes(for: input.taskID)

            guard !outcomes.contains(where: {
                $0.taskOccurrenceIndex == input.occurrenceIndex
            }) else {
                throw CarePlanServiceError.outcomeConflict
            }

            guard
                let event = storedTask.schedule.event(
                    forOccurrenceIndex: input.occurrenceIndex
                ),
                event.start < effectiveQueryEnd(for: storedPlan, draft: plan.draft)
            else {
                throw CarePlanServiceError.outcomeConflict
            }

            var stateValue = OCKOutcomeValue(input.state.rawValue)
            stateValue.kind = OutcomeKind.state
            stateValue.createdDate = input.recordedAt

            var values = [stateValue]
            if let difficulty = input.difficulty {
                var difficultyValue = OCKOutcomeValue(difficulty)
                difficultyValue.kind = OutcomeKind.difficulty
                difficultyValue.createdDate = input.recordedAt
                values.append(difficultyValue)
            }

            var outcome = OCKOutcome(
                taskUUID: storedTask.uuid,
                taskOccurrenceIndex: input.occurrenceIndex,
                values: values
            )
            outcome.effectiveDate = input.recordedAt
            _ = try await store.addOutcome(outcome)
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func progress(for planID: CarePlanID) async throws -> MicroPlanProgress {
        do {
            let storedPlan = try await carePlan(with: planID)
            let plan = try decode(storedPlan)
            let storedTask = try await task(with: plan.draft.taskID)
            let queryEnd = effectiveQueryEnd(for: storedPlan, draft: plan.draft)
            let storedOutcomes = try await outcomes(for: plan.draft.taskID)

            let scheduledThroughQueryEnd: Int
            if queryEnd > plan.draft.startDate {
                scheduledThroughQueryEnd = storedTask.schedule.events(
                    from: plan.draft.startDate,
                    to: queryEnd
                ).count
            } else {
                scheduledThroughQueryEnd = 0
            }
            let recordedOccurrenceCount = storedOutcomes
                .map { $0.taskOccurrenceIndex + 1 }
                .max() ?? 0
            let scheduledCount = max(
                scheduledThroughQueryEnd,
                recordedOccurrenceCount
            )

            var recordedStates: [Int: PlanOutcomeState] = [:]
            for outcome in storedOutcomes {
                guard outcome.taskOccurrenceIndex < scheduledCount else { continue }
                guard recordedStates[outcome.taskOccurrenceIndex] == nil else {
                    throw CarePlanServiceError.outcomeConflict
                }
                guard
                    let rawState = outcome.values.first(where: {
                        $0.kind == OutcomeKind.state
                    })?.stringValue,
                    let state = PlanOutcomeState(rawValue: rawState)
                else {
                    throw CarePlanServiceError.persistenceFailed
                }
                recordedStates[outcome.taskOccurrenceIndex] = state
            }

            return try MicroPlanProgress(
                scheduledCount: scheduledCount,
                completedCount: recordedStates.values.filter { $0 == .completed }.count,
                skippedCount: recordedStates.values.filter { $0 == .skipped }.count
            )
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func outcomeState(
        for taskID: CareTaskID,
        occurrenceIndex: Int
    ) async throws -> PlanOutcomeState? {
        do {
            let matchingOutcomes = try await outcomes(for: taskID).filter {
                $0.taskOccurrenceIndex == occurrenceIndex
            }
            guard matchingOutcomes.count <= 1 else {
                throw CarePlanServiceError.outcomeConflict
            }
            guard let outcome = matchingOutcomes.first else { return nil }
            guard let rawState = outcome.values.first(where: {
                $0.kind == OutcomeKind.state
            })?.stringValue,
            let state = PlanOutcomeState(rawValue: rawState) else {
                throw CarePlanServiceError.persistenceFailed
            }
            return state
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    func endPlan(_ planID: CarePlanID, at date: Date) async throws {
        do {
            let storedPlan = try await carePlan(with: planID)
            let currentPlan = try decode(storedPlan)
            guard date >= currentPlan.draft.startDate else {
                throw CarePlanServiceError.persistenceFailed
            }

            let status: MicroPlanStatus = date < currentPlan.draft.endDateExclusive
                ? .endedEarly
                : .completed

            var updatedPlan = OCKCarePlan(
                id: storedPlan.id,
                title: storedPlan.title,
                patientUUID: storedPlan.patientUUID
            )
            // CareKit version time describes when this mutation becomes current.
            // The user's actual stop time is stored separately in `endedAt`.
            updatedPlan.effectiveDate = Date()
            var updatedMetadata = storedPlan.userInfo ?? [:]
            updatedMetadata[MetadataKey.status] = status.rawValue
            updatedMetadata[MetadataKey.endedAt] = encode(date)
            updatedPlan.userInfo = updatedMetadata
            _ = try await store.updateCarePlan(updatedPlan)
        } catch let error as CarePlanServiceError {
            throw error
        } catch {
            throw CarePlanServiceError.persistenceFailed
        }
    }

    private func carePlan(with id: CarePlanID) async throws -> OCKCarePlan {
        var query = OCKCarePlanQuery(dateInterval: latestVersionInterval)
        query.ids = [id.rawValue]
        guard let plan = try await store.fetchCarePlans(query: query).first else {
            throw CarePlanServiceError.planNotFound
        }
        return plan
    }

    private func task(with id: CareTaskID) async throws -> OCKTask {
        var query = OCKTaskQuery(dateInterval: latestVersionInterval)
        query.ids = [id.rawValue]
        guard let task = try await store.fetchTasks(query: query).first else {
            throw CarePlanServiceError.taskNotFound
        }
        return task
    }

    private func carePlan(containing task: OCKTask) async throws -> OCKCarePlan {
        guard let carePlanUUID = task.carePlanUUID else {
            throw CarePlanServiceError.planNotFound
        }

        var versionQuery = OCKCarePlanQuery()
        versionQuery.uuids = [carePlanUUID]
        guard let referencedVersion = try await store.fetchCarePlans(
            query: versionQuery
        ).first else {
            throw CarePlanServiceError.planNotFound
        }

        return try await carePlan(with: CarePlanID(rawValue: referencedVersion.id))
    }

    private func outcomes(for taskID: CareTaskID) async throws -> [OCKOutcome] {
        var query = OCKOutcomeQuery(dateInterval: latestVersionInterval)
        query.taskIDs = [taskID.rawValue]
        return try await store.fetchOutcomes(query: query)
    }

    private var latestVersionInterval: DateInterval {
        DateInterval(start: .distantPast, end: .distantFuture)
    }

    private func metadata(
        for draft: MicroPlanDraft,
        status: MicroPlanStatus
    ) -> [String: String] {
        var values = [
            MetadataKey.status: status.rawValue,
            MetadataKey.taskID: draft.taskID.rawValue,
            MetadataKey.taskTitle: draft.taskTitle,
            MetadataKey.startDate: encode(draft.startDate),
            MetadataKey.endDateExclusive: encode(draft.endDateExclusive),
            MetadataKey.scheduledHour: String(draft.scheduledTime.hour),
            MetadataKey.scheduledMinute: String(draft.scheduledTime.minute)
        ]
        if let templateID = draft.templateID {
            values[MetadataKey.templateID] = templateID.rawValue
        }
        return values
    }

    private func decode(_ storedPlan: OCKCarePlan) throws -> MicroPlan {
        guard
            let metadata = storedPlan.userInfo,
            let statusRawValue = metadata[MetadataKey.status],
            let status = MicroPlanStatus(rawValue: statusRawValue),
            let taskID = metadata[MetadataKey.taskID],
            let taskTitle = metadata[MetadataKey.taskTitle],
            let startDate = decode(metadata[MetadataKey.startDate]),
            let endDateExclusive = decode(metadata[MetadataKey.endDateExclusive]),
            let hourText = metadata[MetadataKey.scheduledHour],
            let hour = Int(hourText),
            let minuteText = metadata[MetadataKey.scheduledMinute],
            let minute = Int(minuteText)
        else {
            throw CarePlanServiceError.persistenceFailed
        }

        let scheduledTime = try ScheduledLocalTime(hour: hour, minute: minute)
        let draft = MicroPlanDraft(
            id: CarePlanID(rawValue: storedPlan.id),
            title: storedPlan.title,
            taskID: CareTaskID(rawValue: taskID),
            taskTitle: taskTitle,
            startDate: startDate,
            endDateExclusive: endDateExclusive,
            scheduledTime: scheduledTime,
            templateID: metadata[MetadataKey.templateID].flatMap(
                MicroPlanTemplateID.init(rawValue:)
            )
        )
        return MicroPlan(draft: draft, status: status)
    }

    private func effectiveQueryEnd(
        for storedPlan: OCKCarePlan,
        draft: MicroPlanDraft
    ) -> Date {
        guard let endedAt = decode(storedPlan.userInfo?[MetadataKey.endedAt]) else {
            return draft.endDateExclusive
        }
        return min(endedAt, draft.endDateExclusive)
    }

    private func encode(_ date: Date) -> String {
        String(date.timeIntervalSince1970)
    }

    private func decode(_ value: String?) -> Date? {
        guard let value, let interval = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}
