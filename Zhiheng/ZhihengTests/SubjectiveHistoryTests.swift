import XCTest
import SwiftData
@testable import Zhiheng

@MainActor
final class SubjectiveHistoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)
    private let zone = TimeZone(identifier: "Asia/Shanghai")!

    private func checkIn(at date: Date? = nil) throws -> DailyCheckIn {
        let date = date ?? self.date
        return try DailyCheckIn(localDay: SubjectiveLocalDay(date: date, timeZone: zone),
            energy: .two, stress: .four, bodyFeeling: .three, note: "合成备注",
            recordedAt: date)
    }

    private func event(at date: Date? = nil) throws -> ContextEvent {
        let date = date ?? self.date
        return try ContextEvent(kind: .custom, customLabel: "合成事件", startedAt: date,
            endedAt: date.addingTimeInterval(60), intensity: .medium,
            note: "合成背景", createdAt: date)
    }

    private func session(_ store: HistoryTestStore) -> SubjectiveHistorySession {
        let session = SubjectiveHistorySession(store: store)
        session.setDataMode(.live)
        session.open(at: date, timeZone: zone)
        return session
    }

    func testEmptyAndFutureDatesNeverCreateRecords() {
        let store = HistoryTestStore()
        let history = session(store)
        XCTAssertTrue(history.didLoad)
        XCTAssertNil(history.checkIn)
        XCTAssertTrue(history.events.isEmpty)
        history.load(for: date.addingTimeInterval(86_400), timeZone: zone, now: date)
        XCTAssertFalse(history.canModify)
        XCTAssertNotNil(history.errorMessage)
        XCTAssertEqual(store.writes, 0)
    }

    func testDeletionMessageContainsTargetOriginalDateAndIrreversibleWarning() throws {
        let record = try checkIn()
        let feelingMessage = SubjectiveHistoryRecord.checkIn(record).deletionMessage(timeZone: .gmt)
        XCTAssertTrue(feelingMessage.contains(record.localDay.storageKey))
        XCTAssertTrue(feelingMessage.contains("当日感受"))
        XCTAssertTrue(feelingMessage.contains("无法恢复"))
        let event = try ContextEvent(kind: .custom, customLabel: "合成目标", startedAt: Date(timeIntervalSince1970: 0))
        let eventMessage = SubjectiveHistoryRecord.event(event).deletionMessage(timeZone: zone)
        XCTAssertTrue(eventMessage.contains("合成目标"))
        XCTAssertTrue(eventMessage.contains("1970-01-01 08:00"))
        XCTAssertTrue(eventMessage.contains("不影响其他记录或微计划"))
        XCTAssertTrue(eventMessage.contains("无法恢复"))
    }

    func testFeelingEditPreservesOriginalDateTimezoneIdentityAndCreationTime() throws {
        let store = HistoryTestStore()
        let original = try checkIn()
        store.checkIns[original.localDay.storageKey] = original
        let history = session(store)
        history.beginEditing(.checkIn(original))
        var draft = SubjectiveHistoryDraft(record: .checkIn(original))
        draft.energy = .five
        draft.stress = .one
        draft.note = "  更新合成备注  "
        let later = date.addingTimeInterval(86_400)
        XCTAssertTrue(history.save(draft, at: later))
        let saved = try XCTUnwrap(history.checkIn)
        XCTAssertEqual(saved.localDay, original.localDay)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.recordedAt, original.recordedAt)
        XCTAssertEqual(saved.updatedAt, later)
        XCTAssertEqual(saved.energy, .five)
        XCTAssertEqual(saved.note, "更新合成备注")
        XCTAssertNil(history.editingRecord)
        XCTAssertEqual(store.checkIns.count, 1)
    }

    func testEventEditPreservesIntervalIntensityAndIdentity() throws {
        let store = HistoryTestStore()
        let original = try event()
        store.events[original.id] = original
        let history = session(store)
        history.beginEditing(.event(original))
        var draft = SubjectiveHistoryDraft(record: .event(original))
        draft.kind = .nap
        draft.note = " "
        XCTAssertTrue(history.save(draft, at: date.addingTimeInterval(60)))
        let saved = try XCTUnwrap(history.events.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.startedAt, original.startedAt)
        XCTAssertEqual(saved.endedAt, original.endedAt)
        XCTAssertEqual(saved.intensity, original.intensity)
        XCTAssertEqual(saved.createdAt, original.createdAt)
        XCTAssertEqual(saved.kind, .nap)
        XCTAssertNil(saved.customLabel)
        XCTAssertNil(saved.note)
    }

    func testDraftValidationCoversCustomNamesNotesAndMissingRatings() throws {
        var draft = SubjectiveHistoryDraft(record: .event(try event()))
        draft.customLabel = " \n "
        XCTAssertNotNil(draft.validationMessage)
        draft.customLabel = String(repeating: "🌱", count: 31)
        XCTAssertNotNil(draft.validationMessage)
        draft.customLabel = String(repeating: "🌱", count: 30)
        draft.note = String(repeating: "好", count: 161)
        XCTAssertNotNil(draft.validationMessage)
        XCTAssertEqual(draft.note.count, 161)
        draft.note = String(repeating: "好", count: 160)
        XCTAssertNil(draft.validationMessage)
        var feeling = SubjectiveHistoryDraft(record: .checkIn(try checkIn()))
        feeling.energy = nil
        XCTAssertNotNil(feeling.validationMessage)
    }

    func testCancelEditAndDeleteDoNotWrite() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        history.beginEditing(.checkIn(record))
        history.cancelEditing()
        history.requestDeletion(.checkIn(record))
        history.cancelDeletion()
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertEqual(history.checkIn, record)
        XCTAssertEqual(store.writes, 0)
    }

    func testDeletingFeelingLeavesOtherDatesAndEventsUntouched() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        let previous = try checkIn(at: date.addingTimeInterval(-86_400))
        let event = try event()
        store.checkIns = [record.localDay.storageKey: record, previous.localDay.storageKey: previous]
        store.events[event.id] = event
        let history = session(store)
        history.requestDeletion(.checkIn(record))
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(history.confirmDeletion())
        XCTAssertNil(history.checkIn)
        XCTAssertNil(store.checkIns[record.localDay.storageKey])
        XCTAssertEqual(store.checkIns[previous.localDay.storageKey], previous)
        XCTAssertEqual(store.events[event.id], event)
        XCTAssertFalse(history.confirmDeletion())
    }

    func testDeletingOneEventDoesNotDeleteSameKindOrFeeling() throws {
        let store = HistoryTestStore()
        let first = try event()
        let second = try event(at: date.addingTimeInterval(120))
        let record = try checkIn()
        store.events = [first.id: first, second.id: second]
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        history.requestDeletion(.event(first))
        XCTAssertTrue(history.confirmDeletion())
        XCTAssertEqual(history.events, [second])
        XCTAssertEqual(history.checkIn, record)
    }

    func testReadFailureShowsNoPartialOrStaleDataAndCanRetry() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        store.failsEventReads = true
        history.load(for: date, timeZone: zone)
        XCTAssertFalse(history.didLoad)
        XCTAssertNil(history.checkIn)
        history.beginEditing(.checkIn(record))
        history.requestDeletion(.checkIn(record))
        XCTAssertNil(history.editingRecord)
        XCTAssertNil(history.deletionCandidate)
        store.failsEventReads = false
        history.load(for: date, timeZone: zone)
        XCTAssertEqual(history.checkIn, record)
    }

    func testSaveAndDeleteFailuresKeepOriginalRecordsAndAllowRetry() throws {
        let store = HistoryTestStore()
        let record = try event()
        store.events[record.id] = record
        let history = session(store)
        history.beginEditing(.event(record))
        var draft = SubjectiveHistoryDraft(record: .event(record))
        draft.customLabel = "新合成标签"
        store.failsWrites = true
        XCTAssertFalse(history.save(draft))
        XCTAssertEqual(history.editingRecord, .event(record))
        XCTAssertEqual(history.events, [record])
        draft.note = "重试前的新文字"
        store.failsWrites = false
        XCTAssertTrue(history.save(draft))
        let updated = try XCTUnwrap(history.events.first)
        XCTAssertEqual(updated.note, draft.note)
        history.requestDeletion(.event(updated))
        store.failsWrites = true
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertEqual(history.events, [updated])
        store.failsWrites = false
        history.requestDeletion(.event(updated))
        XCTAssertTrue(history.confirmDeletion())
    }

    func testDeletedFeelingCannotBeRecreatedByStaleEditor() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        history.beginEditing(.checkIn(record))
        store.checkIns.removeAll()
        XCTAssertFalse(history.save(SubjectiveHistoryDraft(record: .checkIn(record))))
        XCTAssertTrue(history.requiresReload)
        XCTAssertEqual(store.writes, 0)
        history.cancelEditing()
        XCTAssertNil(history.checkIn)
        XCTAssertTrue(history.didLoad)
    }

    func testChangedEventCannotBeOverwrittenOrDeletedByStaleSnapshot() throws {
        let store = HistoryTestStore()
        let original = try event()
        store.events[original.id] = original
        let history = session(store)
        history.beginEditing(.event(original))
        var changed = original
        changed.note = "另一处更新"
        store.events[original.id] = changed
        XCTAssertFalse(history.save(SubjectiveHistoryDraft(record: .event(original))))
        XCTAssertEqual(store.events[original.id], changed)
        history.cancelEditing()
        history.requestDeletion(.event(changed))
        store.events[original.id] = original
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertTrue(history.requiresReload)
        XCTAssertEqual(store.writes, 0)
    }

    func testChangedFeelingCannotBeDeletedByStaleConfirmation() throws {
        let store = HistoryTestStore()
        let original = try checkIn()
        store.checkIns[original.localDay.storageKey] = original
        let history = session(store)
        history.requestDeletion(.checkIn(original))
        var replacement = original
        replacement.energy = .five
        store.checkIns[original.localDay.storageKey] = replacement
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertEqual(store.checkIns[original.localDay.storageKey], replacement)
    }

    func testModeChangeClearsPrivateStateAndBlocksEveryOperation() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        history.beginEditing(.checkIn(record))
        let reads = store.reads
        history.setDataMode(.demo)
        history.open(at: date)
        history.load(for: date)
        history.beginEditing(.checkIn(record))
        history.requestDeletion(.checkIn(record))
        XCTAssertFalse(history.save(SubjectiveHistoryDraft(record: .checkIn(record))))
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertFalse(history.isPresented)
        XCTAssertNil(history.checkIn)
        XCTAssertNil(history.editingRecord)
        XCTAssertTrue(history.events.isEmpty)
        XCTAssertEqual(store.reads, reads)
        XCTAssertEqual(store.writes, 0)
        history.setDataMode(.live)
        XCTAssertFalse(history.canModify)
        history.open(at: date, timeZone: zone)
        XCTAssertEqual(history.checkIn, record)
    }

    func testChangingDateInvalidatesEditorAndPendingDeletion() throws {
        let store = HistoryTestStore()
        let record = try checkIn()
        store.checkIns[record.localDay.storageKey] = record
        let history = session(store)
        history.beginEditing(.checkIn(record))
        history.load(for: date.addingTimeInterval(-86_400), timeZone: zone)
        XCTAssertFalse(history.save(SubjectiveHistoryDraft(record: .checkIn(record))))
        history.load(for: date, timeZone: zone)
        history.requestDeletion(.checkIn(record))
        history.load(for: date.addingTimeInterval(-86_400), timeZone: zone)
        XCTAssertFalse(history.confirmDeletion())
        XCTAssertEqual(store.writes, 0)
    }

    func testDSTWindowKeepsCrossDayEventAndExcludesNextMidnight() throws {
        let store = HistoryTestStore()
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        let overlap = try ContextEvent(kind: .travel, startedAt: start.addingTimeInterval(-60), endedAt: start.addingTimeInterval(60))
        let next = try ContextEvent(kind: .travel, startedAt: end)
        store.events = [overlap.id: overlap, next.id: next]
        let history = session(store)
        history.load(for: start, timeZone: zone)
        XCTAssertEqual(history.events, [overlap])
        XCTAssertEqual(history.timeZone.identifier, zone.identifier)
    }

    func testDiskEditsAndIndependentDeletionsSurviveStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let original = try checkIn()
        let event = try event()
        do {
            let store = try diskStore(url)
            try store.save(original)
            try store.save(event)
            let history = SubjectiveHistorySession(store: store)
            history.setDataMode(.live)
            history.open(at: date, timeZone: zone)
            history.beginEditing(.checkIn(original))
            var draft = SubjectiveHistoryDraft(record: .checkIn(original))
            draft.note = "磁盘更新"
            XCTAssertTrue(history.save(draft, at: date.addingTimeInterval(60)))
            history.beginEditing(.event(event))
            var eventDraft = SubjectiveHistoryDraft(record: .event(event))
            eventDraft.customLabel = "更新标签"
            XCTAssertTrue(history.save(eventDraft, at: date.addingTimeInterval(60)))
        }
        do {
            let store = try diskStore(url)
            XCTAssertEqual(try store.checkIn(on: original.localDay)?.note, "磁盘更新")
            let history = SubjectiveHistorySession(store: store)
            history.setDataMode(.live)
            history.open(at: date, timeZone: zone)
            XCTAssertEqual(history.events.first?.customLabel, "更新标签")
            history.requestDeletion(.checkIn(try XCTUnwrap(history.checkIn)))
            XCTAssertTrue(history.confirmDeletion())
            XCTAssertEqual(history.events.count, 1)
            history.requestDeletion(.event(try XCTUnwrap(history.events.first)))
            XCTAssertTrue(history.confirmDeletion())
        }
        let finalStore = try diskStore(url)
        XCTAssertNil(try finalStore.checkIn(on: original.localDay))
        XCTAssertTrue(try finalStore.contextEvents(overlapping: DateInterval(start: date, duration: 3600)).isEmpty)
    }

    func testReadOnlyDiskRollsBackFeelingInsertUpdateDeleteAndEventUpdate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "readonly.store")
        let original = try checkIn()
        let event = try event()
        do {
            let store = try diskStore(url)
            try store.save(original)
            try store.save(event)
        }
        let store = try diskStore(url, allowsSave: false)
        var edited = original
        edited.note = "不能保存的修改"
        XCTAssertThrowsError(try store.save(edited))
        XCTAssertEqual(try store.checkIn(on: original.localDay), original)
        let newDay = try checkIn(at: date.addingTimeInterval(-86_400))
        XCTAssertThrowsError(try store.save(newDay))
        XCTAssertNil(try store.checkIn(on: newDay.localDay))
        XCTAssertThrowsError(try store.deleteCheckIn(on: original.localDay))
        XCTAssertEqual(try store.checkIn(on: original.localDay), original)
        var changedEvent = event
        changedEvent.customLabel = "不能保存"
        XCTAssertThrowsError(try store.save(changedEvent))
        XCTAssertEqual(try store.contextEvents(overlapping: DateInterval(start: date, duration: 3600)), [event])
    }

    func testTodayHistoryEditsAndDeletionSynchronizeWithoutReprompting() throws {
        let store = HistoryTestStore()
        let today = Date()
        let record = try DailyCheckIn(localDay: SubjectiveLocalDay(date: today), energy: .two, stress: .four, bodyFeeling: .three)
        store.checkIns[record.localDay.storageKey] = record
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try preferences())
        coordinator.enterApp(at: today, dataMode: .live)
        coordinator.history.open(at: today)
        coordinator.history.beginEditing(.checkIn(record))
        var draft = SubjectiveHistoryDraft(record: .checkIn(record))
        draft.energy = .five
        XCTAssertTrue(coordinator.history.save(draft))
        XCTAssertEqual(coordinator.session.energy, .five)
        coordinator.history.requestDeletion(.checkIn(try XCTUnwrap(coordinator.history.checkIn)))
        XCTAssertTrue(coordinator.history.confirmDeletion())
        XCTAssertNil(coordinator.session.energy)
        XCTAssertNil(coordinator.session.savedCheckIn)
        coordinator.history.isPresented = false
        coordinator.enterApp(at: today, dataMode: .live)
        XCTAssertFalse(coordinator.isPresented)
        coordinator.openManually(at: today)
        XCTAssertTrue(coordinator.isPresented)
    }

    func testPastFeelingAndEventChangesKeepUnsubmittedTodayDraft() throws {
        let store = HistoryTestStore()
        let coordinator = DailyCheckInCoordinator(store: store, preferences: try preferences())
        let now = Date()
        coordinator.enterApp(at: now, dataMode: .live)
        coordinator.session.energy = .five
        coordinator.session.note = "今日未提交草稿"
        coordinator.dismiss()
        let past = try checkIn(at: now.addingTimeInterval(-86_400))
        coordinator.refreshAfterHistoryChange(.checkIn(past), at: now)
        coordinator.refreshAfterHistoryChange(.event(try event(at: now)), at: now)
        XCTAssertEqual(coordinator.session.energy, .five)
        XCTAssertEqual(coordinator.session.note, "今日未提交草稿")
        XCTAssertEqual(store.writes, 0)
    }

    func testHistoryOpenAcrossMidnightNeverTriggersFeelingSheet() throws {
        let coordinator = DailyCheckInCoordinator(store: HistoryTestStore(), preferences: try preferences())
        coordinator.enterApp(at: date, dataMode: .live, timeZone: zone)
        coordinator.markPresented()
        coordinator.dismiss()
        coordinator.history.open(at: date, timeZone: zone)
        coordinator.enterApp(at: date.addingTimeInterval(86_400), dataMode: .live, timeZone: zone)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(coordinator.history.isPresented)
        XCTAssertEqual(coordinator.history.selectedDate, date)
        coordinator.history.isPresented = false
        coordinator.enterApp(at: date.addingTimeInterval(86_400), dataMode: .live, timeZone: zone)
        XCTAssertFalse(coordinator.isPresented)
        coordinator.openManually(at: date.addingTimeInterval(86_400), timeZone: zone)
        XCTAssertTrue(coordinator.isPresented)
    }

    private func diskStore(_ url: URL, allowsSave: Bool = true) throws -> SwiftDataSubjectiveRecordStore {
        let schema = Schema(versionedSchema: SubjectiveRecordsSchemaV1.self)
        let config = ModelConfiguration("HistoryTests", schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
        return SwiftDataSubjectiveRecordStore(modelContainer: try ModelContainer(for: schema,
            migrationPlan: SubjectiveRecordsMigrationPlan.self, configurations: [config]))
    }

    private func preferences() throws -> UserDefaults {
        let name = "HistoryTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return preferences
    }
}

@MainActor
private final class HistoryTestStore: SubjectiveRecordStore {
    var checkIns: [String: DailyCheckIn] = [:]
    var events: [UUID: ContextEvent] = [:]
    var failsWrites = false
    var failsEventReads = false
    var writes = 0
    var reads = 0

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        try attemptWrite()
        checkIns[record.localDay.storageKey] = record
        return record
    }
    func save(_ event: ContextEvent) throws {
        try attemptWrite()
        events[event.id] = event
    }
    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        reads += 1
        return checkIns[day.storageKey]
    }
    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] {
        reads += 1
        if failsEventReads { throw SubjectiveRecordStoreError.persistenceFailed }
        return events.values.filter { $0.startedAt < interval.end && ($0.endedAt ?? $0.startedAt) >= interval.start }
            .sorted { $0.startedAt > $1.startedAt }
    }
    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        try attemptWrite()
        checkIns[day.storageKey] = nil
    }
    func deleteContextEvent(id: UUID) throws {
        try attemptWrite()
        events[id] = nil
    }
    private func attemptWrite() throws {
        writes += 1
        if failsWrites { throw SubjectiveRecordStoreError.persistenceFailed }
    }
}
