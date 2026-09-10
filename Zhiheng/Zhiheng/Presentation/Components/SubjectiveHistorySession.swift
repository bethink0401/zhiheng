import Combine
import Foundation

enum SubjectiveHistoryRecord: Identifiable, Equatable {
    case checkIn(DailyCheckIn)
    case event(ContextEvent)

    var id: String {
        switch self {
        case .checkIn(let record): "feeling-\(record.id)"
        case .event(let event): "event-\(event.id)"
        }
    }

    var title: String {
        switch self {
        case .checkIn: "当日感受"
        case .event(let event): event.customLabel ?? event.kind.title
        }
    }

    func deletionMessage(timeZone: TimeZone) -> String {
        let dateText: String
        switch self {
        case .checkIn(let record): dateText = record.localDay.storageKey
        case .event(let event):
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            dateText = formatter.string(from: event.startedAt)
        }
        return "将删除「\(title)」（原记录：\(dateText)）。只删除这条记录，不影响其他记录或微计划。删除后无法恢复。"
    }
}

/// Only editable content is exposed; record identity and historical dates stay frozen.
struct SubjectiveHistoryDraft {
    let original: SubjectiveHistoryRecord
    var energy: SubjectiveRating?
    var stress: SubjectiveRating?
    var bodyFeeling: SubjectiveRating?
    var kind: ContextEventKind = .custom
    var customLabel = ""
    var note = ""

    init(record: SubjectiveHistoryRecord) {
        original = record
        switch record {
        case .checkIn(let record):
            energy = record.energy
            stress = record.stress
            bodyFeeling = record.bodyFeeling
            note = record.note ?? ""
        case .event(let event):
            kind = event.kind
            customLabel = event.customLabel ?? ""
            note = event.note ?? ""
        }
    }

    var validationMessage: String? {
        do {
            _ = try updatedRecord(at: Date())
            return nil
        } catch SubjectiveRecordValidationError.missingCustomLabel {
            return "请填写自定义标签名称。"
        } catch SubjectiveRecordValidationError.textTooLong(let limit) {
            return limit == ContextEvent.customLabelCharacterLimit
                ? "标签名称最多 \(limit) 字，请缩短后再保存。"
                : "备注最多 \(limit) 字，请缩短后再保存。"
        } catch {
            return "请完成三项感受选择，并检查输入。"
        }
    }

    func updatedRecord(at date: Date) throws -> SubjectiveHistoryRecord {
        switch original {
        case .checkIn(let record):
            guard let energy, let stress, let bodyFeeling else {
                throw SubjectiveRecordStoreError.corruptData
            }
            return .checkIn(try DailyCheckIn(
                id: record.id, localDay: record.localDay,
                energy: energy, stress: stress, bodyFeeling: bodyFeeling, note: note,
                recordedAt: record.recordedAt, updatedAt: date
            ))
        case .event(let event):
            return .event(try ContextEvent(
                id: event.id, kind: kind, customLabel: kind == .custom ? customLabel : nil,
                startedAt: event.startedAt, endedAt: event.endedAt, intensity: event.intensity,
                note: note, createdAt: event.createdAt, updatedAt: date
            ))
        }
    }
}

@MainActor
final class SubjectiveHistorySession: ObservableObject {
    @Published private(set) var checkIn: DailyCheckIn?
    @Published private(set) var events: [ContextEvent] = []
    @Published private(set) var selectedDate = Date()
    @Published private(set) var timeZone = TimeZone.autoupdatingCurrent
    @Published private(set) var isEnabled = false
    @Published private(set) var didLoad = false
    @Published private(set) var requiresReload = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published var isPresented = false
    @Published private(set) var editingRecord: SubjectiveHistoryRecord?
    @Published private(set) var deletionCandidate: SubjectiveHistoryRecord?
    @Published private(set) var timelineDays: [HealthContextTimelineDay] = []
    @Published private(set) var timelineError: String?

    var onRecordsChanged: ((SubjectiveHistoryRecord) -> Void)?
    private let store: any SubjectiveRecordStore
    private var interval: DateInterval?
    private var selectedDay: SubjectiveLocalDay?

    init(store: any SubjectiveRecordStore) { self.store = store }

    var canModify: Bool { isEnabled && didLoad && !requiresReload }

    func setDataMode(_ mode: HealthDataMode) {
        isEnabled = mode == .live
        guard !isEnabled else { return }
        isPresented = false
        timelineDays = []
        timelineError = nil
        editingRecord = nil
        deletionCandidate = nil
        checkIn = nil
        events = []
        interval = nil
        selectedDay = nil
        didLoad = false
        requiresReload = false
        errorMessage = nil
        notice = nil
    }

    func open(at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        guard isEnabled else { return }
        load(for: date, timeZone: timeZone, now: date)
        isPresented = true
    }

    /// Seven bounded check-in reads and one event read; publish only after all succeed.
    func loadTimeline(endingAt date: Date, now: Date = Date()) {
        timelineDays = []
        timelineError = nil
        guard isEnabled else { return }
        guard SubjectiveLocalDay(date: date, timeZone: timeZone).storageKey
                <= SubjectiveLocalDay(date: now, timeZone: timeZone).storageKey else {
            timelineError = "不能查看未来日期。"
            return
        }
        let intervals = HealthContextTimeline.intervals(endingAt: date, timeZone: timeZone)
        guard let first = intervals.last, let last = intervals.first else {
            timelineError = "无法确定日期范围，请重新打开。"
            return
        }
        do {
            let events = try store.contextEvents(overlapping: DateInterval(start: first.start, end: last.end))
            let days = try intervals.map { interval in
                let localDay = SubjectiveLocalDay(date: interval.start, timeZone: timeZone)
                return HealthContextTimelineDay(
                    interval: interval, localDay: localDay,
                    checkIn: try store.checkIn(on: localDay),
                    events: HealthContextTimeline.overlapping(events, interval: interval)
                )
            }
            timelineDays = days
        } catch {
            timelineError = "感受和生活事件读取失败，未显示不完整记录。请重试。"
        }
    }

    func load(for date: Date, timeZone: TimeZone = .autoupdatingCurrent, now: Date = Date()) {
        guard isEnabled else { return }
        selectedDate = date
        // Freeze the browsing timezone, so an in-flight edit cannot silently change date.
        self.timeZone = TimeZone(identifier: timeZone.identifier) ?? .gmt
        selectedDay = SubjectiveLocalDay(date: date, timeZone: timeZone)
        editingRecord = nil
        deletionCandidate = nil
        checkIn = nil
        events = []
        didLoad = false
        requiresReload = false
        errorMessage = nil
        notice = nil
        guard let selectedDay,
              selectedDay.storageKey <= SubjectiveLocalDay(date: now, timeZone: timeZone).storageKey else {
            interval = nil
            errorMessage = "只能查看今天或以前的记录。"
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let window = DateInterval(start: start, end: end)
        interval = window
        do {
            let loadedCheckIn = try store.checkIn(on: selectedDay)
            let loadedEvents = try store.contextEvents(overlapping: window)
            checkIn = loadedCheckIn
            events = loadedEvents
            didLoad = true
        } catch {
            errorMessage = "暂时无法读取历史记录，请重新读取。"
        }
    }

    func beginEditing(_ record: SubjectiveHistoryRecord) {
        guard canModify, contains(record), deletionCandidate == nil else { return }
        errorMessage = nil
        notice = nil
        editingRecord = record
    }

    func cancelEditing() {
        editingRecord = nil
        if requiresReload { load(for: selectedDate, timeZone: timeZone) }
    }

    @discardableResult
    func save(_ draft: SubjectiveHistoryDraft, at date: Date = Date()) -> Bool {
        guard canModify, editingRecord == draft.original, contains(draft.original) else { return false }
        if let message = draft.validationMessage {
            errorMessage = message
            return false
        }
        do {
            guard try isCurrent(draft.original) else { return rejectStaleRecord() }
            let updated = try draft.updatedRecord(at: date)
            switch updated {
            case .checkIn(let record): checkIn = try store.save(record)
            case .event(let event):
                try store.save(event)
                events = events.map { $0.id == event.id ? event : $0 }
            }
            editingRecord = nil
            errorMessage = nil
            notice = "修改已保存到本机"
            onRecordsChanged?(updated)
            return true
        } catch {
            errorMessage = "暂时无法保存，修改内容仍保留，请重试。"
            return false
        }
    }

    func requestDeletion(_ record: SubjectiveHistoryRecord) {
        guard canModify, editingRecord == nil, contains(record) else { return }
        errorMessage = nil
        notice = nil
        deletionCandidate = record
    }

    func cancelDeletion() { deletionCandidate = nil }

    @discardableResult
    func confirmDeletion() -> Bool {
        guard canModify, let record = deletionCandidate, contains(record) else { return false }
        deletionCandidate = nil
        do {
            guard try isCurrent(record) else { return rejectStaleRecord() }
            switch record {
            case .checkIn(let checkIn):
                try store.deleteCheckIn(on: checkIn.localDay)
                self.checkIn = nil
            case .event(let event):
                try store.deleteContextEvent(id: event.id)
                events.removeAll { $0.id == event.id }
            }
            errorMessage = nil
            notice = "已删除这条记录"
            onRecordsChanged?(record)
            return true
        } catch {
            errorMessage = "暂时无法删除，记录仍保留，请重试。"
            return false
        }
    }

    private func contains(_ record: SubjectiveHistoryRecord) -> Bool {
        switch record {
        case .checkIn(let record): checkIn == record
        case .event(let event): events.contains(event)
        }
    }

    private func isCurrent(_ record: SubjectiveHistoryRecord) throws -> Bool {
        switch record {
        case .checkIn(let record): return try store.checkIn(on: record.localDay) == record
        case .event(let event):
            guard let interval else { return false }
            return try store.contextEvents(overlapping: interval).contains(event)
        }
    }

    private func rejectStaleRecord() -> Bool {
        requiresReload = true
        errorMessage = "这条记录已变化或已删除，请关闭编辑并重新读取。"
        return false
    }
}
