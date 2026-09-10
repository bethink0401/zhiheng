import Foundation
import SwiftData

enum EffectiveMethodVisibilityStoreError: Error, Equatable {
    case corruptData
    case persistenceFailed
}

@MainActor
protocol EffectiveMethodVisibilityStore {
    func hiddenTemplateIDs() throws -> Set<MicroPlanTemplateID>
    func setHidden(
        _ isHidden: Bool,
        templateID: MicroPlanTemplateID,
        at date: Date
    ) throws
}

@Model
final class EffectiveMethodVisibilityEntity {
    @Attribute(.unique) var templateIDRawValue: String
    var hiddenAt: Date

    init(templateID: MicroPlanTemplateID, hiddenAt: Date) {
        templateIDRawValue = templateID.rawValue
        self.hiddenAt = hiddenAt
    }
}

enum EffectiveMethodVisibilitySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [EffectiveMethodVisibilityEntity.self]
    }
}

enum EffectiveMethodVisibilityMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EffectiveMethodVisibilitySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

@MainActor
final class InMemoryEffectiveMethodVisibilityStore: EffectiveMethodVisibilityStore {
    private var hiddenIDs = Set<MicroPlanTemplateID>()

    func hiddenTemplateIDs() throws -> Set<MicroPlanTemplateID> {
        hiddenIDs
    }

    func setHidden(
        _ isHidden: Bool,
        templateID: MicroPlanTemplateID,
        at date: Date
    ) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
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
final class UnavailableEffectiveMethodVisibilityStore: EffectiveMethodVisibilityStore {
    func hiddenTemplateIDs() throws -> Set<MicroPlanTemplateID> {
        throw EffectiveMethodVisibilityStoreError.persistenceFailed
    }

    func setHidden(
        _ isHidden: Bool,
        templateID: MicroPlanTemplateID,
        at date: Date
    ) throws {
        throw EffectiveMethodVisibilityStoreError.persistenceFailed
    }
}

@MainActor
final class SwiftDataEffectiveMethodVisibilityStore: EffectiveMethodVisibilityStore {
    static let configurationName = "ZhihengEffectiveMethodVisibility"

    private var context: ModelContext

    convenience init() throws {
        let schema = Schema(versionedSchema: EffectiveMethodVisibilitySchemaV1.self)
        let configuration = ModelConfiguration(
            Self.configurationName,
            schema: schema,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EffectiveMethodVisibilityMigrationPlan.self,
            configurations: [configuration]
        )
        self.init(modelContainer: container)
    }

    init(modelContainer: ModelContainer) {
        context = ModelContext(modelContainer)
        context.autosaveEnabled = false
    }

    func hiddenTemplateIDs() throws -> Set<MicroPlanTemplateID> {
        do {
            let entities = try context.fetch(
                FetchDescriptor<EffectiveMethodVisibilityEntity>()
            )
            var result = Set<MicroPlanTemplateID>()
            for entity in entities {
                guard let templateID = MicroPlanTemplateID(
                    rawValue: entity.templateIDRawValue
                ), entity.hiddenAt.timeIntervalSinceReferenceDate.isFinite else {
                    throw EffectiveMethodVisibilityStoreError.corruptData
                }
                result.insert(templateID)
            }
            return result
        } catch let error as EffectiveMethodVisibilityStoreError {
            throw error
        } catch {
            throw EffectiveMethodVisibilityStoreError.persistenceFailed
        }
    }

    func setHidden(
        _ isHidden: Bool,
        templateID: MicroPlanTemplateID,
        at date: Date = Date()
    ) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw EffectiveMethodVisibilityStoreError.persistenceFailed
        }
        do {
            if isHidden {
                if let existing = try entity(for: templateID) {
                    existing.hiddenAt = date
                } else {
                    context.insert(EffectiveMethodVisibilityEntity(
                        templateID: templateID,
                        hiddenAt: date
                    ))
                }
            } else if let existing = try entity(for: templateID) {
                context.delete(existing)
            }
            try context.save()
        } catch {
            resetContextAfterWriteFailure()
            throw EffectiveMethodVisibilityStoreError.persistenceFailed
        }
    }

    private func entity(
        for templateID: MicroPlanTemplateID
    ) throws -> EffectiveMethodVisibilityEntity? {
        let rawValue = templateID.rawValue
        var descriptor = FetchDescriptor<EffectiveMethodVisibilityEntity>(
            predicate: #Predicate { $0.templateIDRawValue == rawValue }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func resetContextAfterWriteFailure() {
        let container = context.container
        context.rollback()
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
}
