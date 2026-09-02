import Foundation
import SwiftData

@Model
final class PlanAnalysisMetadataEntity {
    @Attribute(.unique) var carePlanID: String
    var baselinePayload: Data
    var capturedAt: Date
    var schemaVersion: Int

    init(
        carePlanID: String,
        baselinePayload: Data,
        capturedAt: Date,
        schemaVersion: Int
    ) {
        self.carePlanID = carePlanID
        self.baselinePayload = baselinePayload
        self.capturedAt = capturedAt
        self.schemaVersion = schemaVersion
    }
}

@MainActor
final class SwiftDataPlanBaselineStore: PlanBaselineStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init() throws {
        let container = try ModelContainer(for: PlanAnalysisMetadataEntity.self)
        self.init(modelContainer: container)
    }

    init(modelContainer: ModelContainer) {
        context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        encoder.outputFormatting = [.sortedKeys]
    }

    func save(_ snapshot: MicroPlanBaselineSnapshot) throws {
        guard snapshot.schemaVersion == MicroPlanBaselineSnapshot.currentSchemaVersion else {
            throw PlanBaselineStoreError.unsupportedSchema
        }
        do {
            let payload = try encoder.encode(snapshot)
            if let entity = try entity(for: snapshot.carePlanID) {
                entity.baselinePayload = payload
                entity.capturedAt = snapshot.capturedAt
                entity.schemaVersion = snapshot.schemaVersion
            } else {
                context.insert(PlanAnalysisMetadataEntity(
                    carePlanID: snapshot.carePlanID.rawValue,
                    baselinePayload: payload,
                    capturedAt: snapshot.capturedAt,
                    schemaVersion: snapshot.schemaVersion
                ))
            }
            try context.save()
        } catch let error as PlanBaselineStoreError {
            throw error
        } catch {
            throw PlanBaselineStoreError.persistenceFailed
        }
    }

    func baseline(for carePlanID: CarePlanID) throws -> MicroPlanBaselineSnapshot? {
        do {
            guard let entity = try entity(for: carePlanID) else { return nil }
            guard entity.schemaVersion == MicroPlanBaselineSnapshot.currentSchemaVersion else {
                throw PlanBaselineStoreError.unsupportedSchema
            }
            let snapshot = try decoder.decode(
                MicroPlanBaselineSnapshot.self,
                from: entity.baselinePayload
            )
            guard snapshot.carePlanID == carePlanID,
                  snapshot.schemaVersion == entity.schemaVersion else {
                throw PlanBaselineStoreError.persistenceFailed
            }
            return snapshot
        } catch let error as PlanBaselineStoreError {
            throw error
        } catch {
            throw PlanBaselineStoreError.persistenceFailed
        }
    }

    func delete(for carePlanID: CarePlanID) throws {
        do {
            if let entity = try entity(for: carePlanID) {
                context.delete(entity)
                try context.save()
            }
        } catch {
            throw PlanBaselineStoreError.persistenceFailed
        }
    }

    private func entity(
        for carePlanID: CarePlanID
    ) throws -> PlanAnalysisMetadataEntity? {
        let rawValue = carePlanID.rawValue
        var descriptor = FetchDescriptor<PlanAnalysisMetadataEntity>(
            predicate: #Predicate { $0.carePlanID == rawValue }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
