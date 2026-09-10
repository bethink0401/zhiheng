import Foundation
import SwiftData

@Model
final class DailyCheckInEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var localDayKey: String
    var localYear: Int
    var localMonth: Int
    var localDay: Int
    var timeZoneIdentifier: String
    var energyRawValue: Int
    var stressRawValue: Int
    var bodyFeelingRawValue: Int
    var note: String?
    var recordedAt: Date
    var updatedAt: Date

    init(record: DailyCheckIn) {
        id = record.id
        localDayKey = record.localDay.storageKey
        localYear = record.localDay.year
        localMonth = record.localDay.month
        localDay = record.localDay.day
        timeZoneIdentifier = record.localDay.timeZoneIdentifier
        energyRawValue = record.energy.rawValue
        stressRawValue = record.stress.rawValue
        bodyFeelingRawValue = record.bodyFeeling.rawValue
        note = record.note
        recordedAt = record.recordedAt
        updatedAt = record.updatedAt
    }

    func update(from record: DailyCheckIn) {
        localDayKey = record.localDay.storageKey
        localYear = record.localDay.year
        localMonth = record.localDay.month
        localDay = record.localDay.day
        timeZoneIdentifier = record.localDay.timeZoneIdentifier
        energyRawValue = record.energy.rawValue
        stressRawValue = record.stress.rawValue
        bodyFeelingRawValue = record.bodyFeeling.rawValue
        note = record.note
        updatedAt = record.updatedAt
    }
}

@Model
final class ContextEventEntity {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var customLabel: String?
    var startedAt: Date
    var endedAt: Date?
    var intensityRawValue: Int?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: ContextEvent) {
        id = record.id
        kindRawValue = record.kind.rawValue
        customLabel = record.customLabel
        startedAt = record.startedAt
        endedAt = record.endedAt
        intensityRawValue = record.intensity?.rawValue
        note = record.note
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func update(from record: ContextEvent) {
        kindRawValue = record.kind.rawValue
        customLabel = record.customLabel
        startedAt = record.startedAt
        endedAt = record.endedAt
        intensityRawValue = record.intensity?.rawValue
        note = record.note
        updatedAt = record.updatedAt
    }
}

enum SubjectiveRecordsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DailyCheckInEntity.self,
            ContextEventEntity.self
        ]
    }
}

enum SubjectiveRecordsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SubjectiveRecordsSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum SubjectiveRecordStoreError: Error, Equatable {
    case corruptData
    case persistenceFailed
}

@MainActor
protocol SubjectiveRecordStore {
    @discardableResult
    func save(_ record: DailyCheckIn) throws -> DailyCheckIn
    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn?
    func deleteCheckIn(on day: SubjectiveLocalDay) throws

    func save(_ event: ContextEvent) throws
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent]
    func deleteContextEvent(id: UUID) throws
}

@MainActor
final class UnavailableSubjectiveRecordStore: SubjectiveRecordStore {
    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        throw SubjectiveRecordStoreError.persistenceFailed
    }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        throw SubjectiveRecordStoreError.persistenceFailed
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        throw SubjectiveRecordStoreError.persistenceFailed
    }

    func save(_ event: ContextEvent) throws {
        throw SubjectiveRecordStoreError.persistenceFailed
    }

    func contextEvents(
        overlapping interval: DateInterval
    ) throws -> [ContextEvent] {
        throw SubjectiveRecordStoreError.persistenceFailed
    }

    func deleteContextEvent(id: UUID) throws {
        throw SubjectiveRecordStoreError.persistenceFailed
    }
}

@MainActor
final class SwiftDataSubjectiveRecordStore: SubjectiveRecordStore {
    static let configurationName = "ZhihengSubjectiveRecords"

    private var context: ModelContext

    convenience init() throws {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let configuration = ModelConfiguration(
            Self.configurationName,
            schema: schema,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SubjectiveRecordsMigrationPlan.self,
            configurations: [configuration]
        )
        self.init(modelContainer: container)
    }

    init(modelContainer: ModelContainer) {
        context = ModelContext(modelContainer)
        context.autosaveEnabled = false
    }

    @discardableResult
    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        do {
            if let existing = try checkInEntity(dayKey: record.localDay.storageKey) {
                existing.update(from: record)
                try context.save()
                return try map(existing)
            }
            let entity = DailyCheckInEntity(record: record)
            context.insert(entity)
            try context.save()
            return try map(entity)
        } catch let error as SubjectiveRecordStoreError {
            resetContextAfterWriteFailure()
            throw error
        } catch {
            resetContextAfterWriteFailure()
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        do {
            guard let entity = try checkInEntity(dayKey: day.storageKey) else {
                return nil
            }
            return try map(entity)
        } catch let error as SubjectiveRecordStoreError {
            throw error
        } catch {
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        do {
            guard let entity = try checkInEntity(dayKey: day.storageKey) else {
                return
            }
            context.delete(entity)
            try context.save()
        } catch {
            resetContextAfterWriteFailure()
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    func save(_ event: ContextEvent) throws {
        do {
            if let existing = try contextEventEntity(id: event.id) {
                existing.update(from: event)
            } else {
                context.insert(ContextEventEntity(record: event))
            }
            try context.save()
        } catch {
            resetContextAfterWriteFailure()
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    func contextEvents(
        overlapping interval: DateInterval
    ) throws -> [ContextEvent] {
        do {
            let descriptor = FetchDescriptor<ContextEventEntity>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
                .filter { entity in
                    entity.startedAt < interval.end
                        && (entity.endedAt ?? entity.startedAt) >= interval.start
                }
                .map(map)
        } catch let error as SubjectiveRecordStoreError {
            throw error
        } catch {
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    func deleteContextEvent(id: UUID) throws {
        do {
            guard let entity = try contextEventEntity(id: id) else {
                return
            }
            context.delete(entity)
            try context.save()
        } catch {
            resetContextAfterWriteFailure()
            throw SubjectiveRecordStoreError.persistenceFailed
        }
    }

    private func resetContextAfterWriteFailure() {
        let container = context.container
        context.rollback()
        // A failed save can leave registered instances visible in this context.
        // Rebuild from the same store, never from an in-memory copy of the records.
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func checkInEntity(
        dayKey: String
    ) throws -> DailyCheckInEntity? {
        var descriptor = FetchDescriptor<DailyCheckInEntity>(
            predicate: #Predicate { $0.localDayKey == dayKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func contextEventEntity(
        id: UUID
    ) throws -> ContextEventEntity? {
        var descriptor = FetchDescriptor<ContextEventEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func map(_ entity: DailyCheckInEntity) throws -> DailyCheckIn {
        guard let energy = SubjectiveRating(rawValue: entity.energyRawValue),
              let stress = SubjectiveRating(rawValue: entity.stressRawValue),
              let bodyFeeling = SubjectiveRating(
                rawValue: entity.bodyFeelingRawValue
              ) else {
            throw SubjectiveRecordStoreError.corruptData
        }
        do {
            return try DailyCheckIn(
                id: entity.id,
                localDay: SubjectiveLocalDay(
                    year: entity.localYear,
                    month: entity.localMonth,
                    day: entity.localDay,
                    timeZoneIdentifier: entity.timeZoneIdentifier
                ),
                energy: energy,
                stress: stress,
                bodyFeeling: bodyFeeling,
                note: entity.note,
                recordedAt: entity.recordedAt,
                updatedAt: entity.updatedAt
            )
        } catch {
            throw SubjectiveRecordStoreError.corruptData
        }
    }

    private func map(_ entity: ContextEventEntity) throws -> ContextEvent {
        guard let kind = ContextEventKind(rawValue: entity.kindRawValue) else {
            throw SubjectiveRecordStoreError.corruptData
        }
        let intensity: ContextEventIntensity?
        if let rawValue = entity.intensityRawValue {
            guard let storedIntensity = ContextEventIntensity(
                rawValue: rawValue
            ) else {
                throw SubjectiveRecordStoreError.corruptData
            }
            intensity = storedIntensity
        } else {
            intensity = nil
        }
        do {
            return try ContextEvent(
                id: entity.id,
                kind: kind,
                customLabel: entity.customLabel,
                startedAt: entity.startedAt,
                endedAt: entity.endedAt,
                intensity: intensity,
                note: entity.note,
                createdAt: entity.createdAt,
                updatedAt: entity.updatedAt
            )
        } catch {
            throw SubjectiveRecordStoreError.corruptData
        }
    }
}
