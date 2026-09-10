import Combine
import Foundation
import SwiftData

struct InsightInteractionState: Equatable, Sendable {
    let identity: InsightInteractionIdentity
    let readAt: Date?
    let ignoredAt: Date?
    let remindersDisabledAt: Date?

    var isRead: Bool { readAt != nil }
    var isIgnored: Bool { ignoredAt != nil }
    var areRemindersDisabled: Bool { remindersDisabledAt != nil }

    static func empty(for identity: InsightInteractionIdentity) -> Self {
        Self(
            identity: identity,
            readAt: nil,
            ignoredAt: nil,
            remindersDisabledAt: nil
        )
    }
}

enum InsightInteractionStoreError: Error, Equatable {
    case corruptData
    case persistenceFailed
}

@MainActor
protocol InsightInteractionStore {
    func state(for identity: InsightInteractionIdentity) throws -> InsightInteractionState
    func setRead(
        _ isRead: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState
    func setIgnored(
        _ isIgnored: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState
    func setRemindersDisabled(
        _ isDisabled: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState
}

@Model
final class InsightInteractionEntity {
    @Attribute(.unique) var storageKey: String
    var insightID: UUID
    var topicKey: String
    var dataModeRawValue: String
    var readAt: Date?
    var ignoredAt: Date?
    var updatedAt: Date

    init(
        identity: InsightInteractionIdentity,
        readAt: Date?,
        ignoredAt: Date?,
        updatedAt: Date
    ) {
        storageKey = Self.key(for: identity)
        insightID = identity.insightID
        topicKey = identity.topic.storageKey
        dataModeRawValue = identity.dataMode.rawValue
        self.readAt = readAt
        self.ignoredAt = ignoredAt
        self.updatedAt = updatedAt
    }

    static func key(for identity: InsightInteractionIdentity) -> String {
        "\(identity.dataMode.rawValue):\(identity.insightID.uuidString.lowercased())"
    }
}

@Model
final class InsightReminderPreferenceEntity {
    @Attribute(.unique) var storageKey: String
    var topicKey: String
    var dataModeRawValue: String
    var disabledAt: Date

    init(identity: InsightInteractionIdentity, disabledAt: Date) {
        storageKey = Self.key(for: identity)
        topicKey = identity.topic.storageKey
        dataModeRawValue = identity.dataMode.rawValue
        self.disabledAt = disabledAt
    }

    static func key(for identity: InsightInteractionIdentity) -> String {
        "\(identity.dataMode.rawValue):\(identity.topic.storageKey)"
    }
}

enum InsightInteractionsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            InsightInteractionEntity.self,
            InsightReminderPreferenceEntity.self
        ]
    }
}

enum InsightInteractionsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [InsightInteractionsSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

@MainActor
final class UnavailableInsightInteractionStore: InsightInteractionStore {
    func state(
        for identity: InsightInteractionIdentity
    ) throws -> InsightInteractionState {
        throw InsightInteractionStoreError.persistenceFailed
    }

    func setRead(
        _ isRead: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        throw InsightInteractionStoreError.persistenceFailed
    }

    func setIgnored(
        _ isIgnored: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        throw InsightInteractionStoreError.persistenceFailed
    }

    func setRemindersDisabled(
        _ isDisabled: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        throw InsightInteractionStoreError.persistenceFailed
    }
}

@MainActor
final class SwiftDataInsightInteractionStore: InsightInteractionStore {
    static let configurationName = "ZhihengInsightInteractions"

    private var context: ModelContext

    convenience init() throws {
        let schema = Schema(versionedSchema: InsightInteractionsSchemaV1.self)
        let configuration = ModelConfiguration(
            Self.configurationName,
            schema: schema,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: InsightInteractionsMigrationPlan.self,
            configurations: [configuration]
        )
        self.init(modelContainer: container)
    }

    init(modelContainer: ModelContainer) {
        context = ModelContext(modelContainer)
        context.autosaveEnabled = false
    }

    func state(
        for identity: InsightInteractionIdentity
    ) throws -> InsightInteractionState {
        do {
            let interaction = try interactionEntity(for: identity)
            let preference = try reminderPreferenceEntity(for: identity)
            try validate(interaction, for: identity)
            try validate(preference, for: identity)
            return InsightInteractionState(
                identity: identity,
                readAt: interaction?.readAt,
                ignoredAt: interaction?.ignoredAt,
                remindersDisabledAt: preference?.disabledAt
            )
        } catch let error as InsightInteractionStoreError {
            throw error
        } catch {
            throw InsightInteractionStoreError.persistenceFailed
        }
    }

    func setRead(
        _ isRead: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date = Date()
    ) throws -> InsightInteractionState {
        try updateInteraction(identity: identity, at: date) { entity in
            entity.readAt = isRead ? date : nil
        }
    }

    func setIgnored(
        _ isIgnored: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date = Date()
    ) throws -> InsightInteractionState {
        try updateInteraction(identity: identity, at: date) { entity in
            entity.ignoredAt = isIgnored ? date : nil
        }
    }

    func setRemindersDisabled(
        _ isDisabled: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date = Date()
    ) throws -> InsightInteractionState {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw InsightInteractionStoreError.persistenceFailed
        }
        do {
            if isDisabled {
                if let existing = try reminderPreferenceEntity(for: identity) {
                    existing.disabledAt = date
                } else {
                    context.insert(InsightReminderPreferenceEntity(
                        identity: identity,
                        disabledAt: date
                    ))
                }
            } else if let existing = try reminderPreferenceEntity(for: identity) {
                context.delete(existing)
            }
            try context.save()
            return try state(for: identity)
        } catch let error as InsightInteractionStoreError {
            resetContextAfterWriteFailure()
            throw error
        } catch {
            resetContextAfterWriteFailure()
            throw InsightInteractionStoreError.persistenceFailed
        }
    }

    private func updateInteraction(
        identity: InsightInteractionIdentity,
        at date: Date,
        update: (InsightInteractionEntity) -> Void
    ) throws -> InsightInteractionState {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw InsightInteractionStoreError.persistenceFailed
        }
        do {
            let entity: InsightInteractionEntity
            if let existing = try interactionEntity(for: identity) {
                entity = existing
            } else {
                entity = InsightInteractionEntity(
                    identity: identity,
                    readAt: nil,
                    ignoredAt: nil,
                    updatedAt: date
                )
                context.insert(entity)
            }
            update(entity)
            entity.updatedAt = date
            if entity.readAt == nil, entity.ignoredAt == nil {
                context.delete(entity)
            }
            try context.save()
            return try state(for: identity)
        } catch let error as InsightInteractionStoreError {
            resetContextAfterWriteFailure()
            throw error
        } catch {
            resetContextAfterWriteFailure()
            throw InsightInteractionStoreError.persistenceFailed
        }
    }

    private func interactionEntity(
        for identity: InsightInteractionIdentity
    ) throws -> InsightInteractionEntity? {
        let key = InsightInteractionEntity.key(for: identity)
        var descriptor = FetchDescriptor<InsightInteractionEntity>(
            predicate: #Predicate { $0.storageKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func reminderPreferenceEntity(
        for identity: InsightInteractionIdentity
    ) throws -> InsightReminderPreferenceEntity? {
        let key = InsightReminderPreferenceEntity.key(for: identity)
        var descriptor = FetchDescriptor<InsightReminderPreferenceEntity>(
            predicate: #Predicate { $0.storageKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func validate(
        _ entity: InsightInteractionEntity?,
        for identity: InsightInteractionIdentity
    ) throws {
        guard let entity else { return }
        guard entity.insightID == identity.insightID,
              entity.topicKey == identity.topic.storageKey,
              entity.dataModeRawValue == identity.dataMode.rawValue,
              entity.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              entity.readAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              entity.ignoredAt?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw InsightInteractionStoreError.corruptData
        }
    }

    private func validate(
        _ entity: InsightReminderPreferenceEntity?,
        for identity: InsightInteractionIdentity
    ) throws {
        guard let entity else { return }
        guard entity.topicKey == identity.topic.storageKey,
              entity.dataModeRawValue == identity.dataMode.rawValue,
              entity.disabledAt.timeIntervalSinceReferenceDate.isFinite else {
            throw InsightInteractionStoreError.corruptData
        }
    }

    private func resetContextAfterWriteFailure() {
        let container = context.container
        context.rollback()
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
}

@MainActor
final class InsightInteractionSession: ObservableObject {
    @Published private(set) var state: InsightInteractionState?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAvailable = false

    private let store: any InsightInteractionStore
    private var identity: InsightInteractionIdentity?

    init(store: any InsightInteractionStore) {
        self.store = store
    }

    func load(for identity: InsightInteractionIdentity) {
        self.identity = identity
        do {
            state = try store.state(for: identity)
            isAvailable = true
            errorMessage = nil
        } catch {
            state = .empty(for: identity)
            isAvailable = false
            errorMessage = "洞察操作状态暂时无法读取，内容仍可查看。"
        }
    }

    func clear() {
        identity = nil
        state = nil
        isAvailable = false
        errorMessage = nil
    }

    func setRead(_ isRead: Bool, at date: Date = Date()) {
        mutate { try store.setRead(isRead, for: $0, at: date) }
    }

    func setIgnored(_ isIgnored: Bool, at date: Date = Date()) {
        mutate { try store.setIgnored(isIgnored, for: $0, at: date) }
    }

    func setRemindersDisabled(_ isDisabled: Bool, at date: Date = Date()) {
        mutate { try store.setRemindersDisabled(isDisabled, for: $0, at: date) }
    }

    func retry() {
        guard let identity else { return }
        load(for: identity)
    }

    private func mutate(
        _ operation: (InsightInteractionIdentity) throws -> InsightInteractionState
    ) {
        guard let identity, isAvailable else {
            errorMessage = "请先重新读取洞察操作状态。"
            return
        }
        let previous = state
        do {
            state = try operation(identity)
            errorMessage = nil
        } catch {
            state = previous
            errorMessage = "保存失败，原来的洞察状态已保留，请重试。"
        }
    }
}
