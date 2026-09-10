import SwiftData
import XCTest
@testable import Zhiheng

final class InsightInteractionStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_788_451_200)

    @MainActor
    func testVersionedSchemaAndMigrationPlanAreExplicit() throws {
        let container = try makeContainer()

        XCTAssertEqual(
            container.schema.version,
            InsightInteractionsSchemaV1.versionIdentifier
        )
        XCTAssertTrue(
            container.migrationPlan == InsightInteractionsMigrationPlan.self
        )
        XCTAssertEqual(InsightInteractionsMigrationPlan.schemas.count, 1)
        XCTAssertTrue(InsightInteractionsMigrationPlan.stages.isEmpty)
    }

    @MainActor
    func testReadAndIgnoreCanEachBeRestoredWithoutDeletingTheOther() throws {
        let store = SwiftDataInsightInteractionStore(
            modelContainer: try makeContainer()
        )
        let identity = identity()

        var state = try store.setRead(true, for: identity, at: date)
        XCTAssertTrue(state.isRead)
        XCTAssertFalse(state.isIgnored)

        state = try store.setIgnored(true, for: identity, at: date.addingTimeInterval(1))
        XCTAssertTrue(state.isRead)
        XCTAssertTrue(state.isIgnored)

        state = try store.setIgnored(false, for: identity, at: date.addingTimeInterval(2))
        XCTAssertTrue(state.isRead)
        XCTAssertFalse(state.isIgnored)

        state = try store.setRead(false, for: identity, at: date.addingTimeInterval(3))
        XCTAssertFalse(state.isRead)
        XCTAssertFalse(state.isIgnored)
    }

    @MainActor
    func testReminderPreferenceAppliesToFutureInsightOfSameTopic() throws {
        let store = SwiftDataInsightInteractionStore(
            modelContainer: try makeContainer()
        )
        let first = identity(id: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!)
        let future = identity(id: UUID(uuidString: "71000000-0000-0000-0000-000000000002")!)

        _ = try store.setRemindersDisabled(true, for: first, at: date)

        XCTAssertTrue(try store.state(for: first).areRemindersDisabled)
        XCTAssertTrue(try store.state(for: future).areRemindersDisabled)
        XCTAssertFalse(try store.state(for: future).isIgnored)
    }

    @MainActor
    func testReminderPreferenceDoesNotCrossTopicOrDataMode() throws {
        let store = SwiftDataInsightInteractionStore(
            modelContainer: try makeContainer()
        )
        let liveMetric = identity()
        let liveStable = identity(topic: .stableOverview)
        let demoMetric = identity(mode: .demo)

        _ = try store.setRemindersDisabled(true, for: liveMetric, at: date)

        XCTAssertFalse(try store.state(for: liveStable).areRemindersDisabled)
        XCTAssertFalse(try store.state(for: demoMetric).areRemindersDisabled)
    }

    @MainActor
    func testRestoringReminderPreferenceAffectsEveryFutureInsightOfTopic() throws {
        let store = SwiftDataInsightInteractionStore(
            modelContainer: try makeContainer()
        )
        let first = identity(id: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!)
        let future = identity(id: UUID(uuidString: "72000000-0000-0000-0000-000000000002")!)
        _ = try store.setRemindersDisabled(true, for: first, at: date)

        _ = try store.setRemindersDisabled(
            false,
            for: future,
            at: date.addingTimeInterval(1)
        )

        XCTAssertFalse(try store.state(for: first).areRemindersDisabled)
        XCTAssertFalse(try store.state(for: future).areRemindersDisabled)
    }

    @MainActor
    func testDiskRebuildRestoresInteractionAndReminderPreference() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "InsightInteractions-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "interactions.store")
        let identity = identity()

        do {
            let writer = SwiftDataInsightInteractionStore(
                modelContainer: try makeDiskContainer(url: url)
            )
            _ = try writer.setRead(true, for: identity, at: date)
            _ = try writer.setIgnored(true, for: identity, at: date)
            _ = try writer.setRemindersDisabled(true, for: identity, at: date)
        }

        let reader = SwiftDataInsightInteractionStore(
            modelContainer: try makeDiskContainer(url: url)
        )
        let restored = try reader.state(for: identity)
        XCTAssertTrue(restored.isRead)
        XCTAssertTrue(restored.isIgnored)
        XCTAssertTrue(restored.areRemindersDisabled)
    }

    @MainActor
    func testCorruptStoredIdentityIsRejected() throws {
        let container = try makeContainer()
        let identity = identity()
        let context = ModelContext(container)
        let entity = InsightInteractionEntity(
            identity: identity,
            readAt: date,
            ignoredAt: nil,
            updatedAt: date
        )
        entity.topicKey = InsightInteractionTopic.stableOverview.storageKey
        context.insert(entity)
        try context.save()

        let store = SwiftDataInsightInteractionStore(modelContainer: container)
        XCTAssertThrowsError(try store.state(for: identity)) {
            XCTAssertEqual($0 as? InsightInteractionStoreError, .corruptData)
        }
    }

    @MainActor
    func testSessionDoesNotPublishOptimisticSuccessWhenWriteFails() {
        let identity = identity()
        let store = InteractionStoreStub()
        let session = InsightInteractionSession(store: store)
        session.load(for: identity)
        XCTAssertFalse(session.state?.isRead ?? true)

        store.failsWrites = true
        session.setRead(true, at: date)

        XCTAssertFalse(session.state?.isRead ?? true)
        XCTAssertTrue(session.errorMessage?.contains("原来的洞察状态已保留") == true)
    }

    @MainActor
    func testSessionReadFailureKeepsContentControlsUnavailableUntilRetry() {
        let identity = identity()
        let store = InteractionStoreStub()
        store.failsReads = true
        let session = InsightInteractionSession(store: store)

        session.load(for: identity)

        XCTAssertFalse(session.isAvailable)
        XCTAssertEqual(session.state, .empty(for: identity))
        XCTAssertTrue(session.errorMessage?.contains("内容仍可查看") == true)

        store.failsReads = false
        session.retry()
        XCTAssertTrue(session.isAvailable)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: InsightInteractionsSchemaV1.self)
        let configuration = ModelConfiguration(
            "InsightInteractionTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: InsightInteractionsMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @MainActor
    private func makeDiskContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: InsightInteractionsSchemaV1.self)
        let configuration = ModelConfiguration(
            "InsightInteractionDiskTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: InsightInteractionsMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func identity(
        id: UUID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
        topic: InsightInteractionTopic = .metricChange(.stepCount),
        mode: HealthDataMode = .live
    ) -> InsightInteractionIdentity {
        InsightInteractionIdentity(insightID: id, topic: topic, dataMode: mode)
    }
}

@MainActor
private final class InteractionStoreStub: InsightInteractionStore {
    var failsReads = false
    var failsWrites = false
    private var states: [UUID: InsightInteractionState] = [:]

    func state(
        for identity: InsightInteractionIdentity
    ) throws -> InsightInteractionState {
        if failsReads { throw InsightInteractionStoreError.persistenceFailed }
        return states[identity.insightID] ?? .empty(for: identity)
    }

    func setRead(
        _ isRead: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        if failsWrites { throw InsightInteractionStoreError.persistenceFailed }
        let previous = try state(for: identity)
        let updated = InsightInteractionState(
            identity: identity,
            readAt: isRead ? date : nil,
            ignoredAt: previous.ignoredAt,
            remindersDisabledAt: previous.remindersDisabledAt
        )
        states[identity.insightID] = updated
        return updated
    }

    func setIgnored(
        _ isIgnored: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        if failsWrites { throw InsightInteractionStoreError.persistenceFailed }
        let previous = try state(for: identity)
        let updated = InsightInteractionState(
            identity: identity,
            readAt: previous.readAt,
            ignoredAt: isIgnored ? date : nil,
            remindersDisabledAt: previous.remindersDisabledAt
        )
        states[identity.insightID] = updated
        return updated
    }

    func setRemindersDisabled(
        _ isDisabled: Bool,
        for identity: InsightInteractionIdentity,
        at date: Date
    ) throws -> InsightInteractionState {
        if failsWrites { throw InsightInteractionStoreError.persistenceFailed }
        let previous = try state(for: identity)
        let updated = InsightInteractionState(
            identity: identity,
            readAt: previous.readAt,
            ignoredAt: previous.ignoredAt,
            remindersDisabledAt: isDisabled ? date : nil
        )
        states[identity.insightID] = updated
        return updated
    }
}
