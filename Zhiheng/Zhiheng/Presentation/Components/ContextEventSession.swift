import Combine
import Foundation

/// A local, optional record flow independent of the mandatory feeling selections.
@MainActor
final class ContextEventSession: ObservableObject {
    @Published private(set) var events: [ContextEvent] = []
    @Published private(set) var selectedKind: ContextEventKind?
    @Published var customLabel = "" {
        didSet { if oldValue != customLabel, didLoadRecords { errorMessage = nil } }
    }
    @Published var note = "" {
        didSet { if oldValue != note, didLoadRecords { errorMessage = nil } }
    }
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var isRecordingEnabled = false
    @Published private(set) var didLoadRecords = false
    @Published var isPresented = false

    private let store: any SubjectiveRecordStore
    private var dayInterval: DateInterval?
    private var pendingEvent: ContextEvent?
    private var dataMode: HealthDataMode = .live
    private var allowsDemoRecords = false

    init(store: any SubjectiveRecordStore) { self.store = store }

    var canSave: Bool {
        isRecordingEnabled && didLoadRecords && selectedKind != nil && validationMessage == nil
    }

    var validationMessage: String? {
        if selectedKind == .custom {
            do {
                guard try SubjectiveRecordText.normalized(customLabel, maximumLength: ContextEvent.customLabelCharacterLimit) != nil else {
                    return "请填写自定义标签名称。"
                }
            } catch { return "标签名称最多 \(ContextEvent.customLabelCharacterLimit) 字，请缩短后再保存。" }
        }
        do {
            _ = try SubjectiveRecordText.normalized(note, maximumLength: ContextEvent.noteCharacterLimit)
        } catch { return "备注最多 \(ContextEvent.noteCharacterLimit) 字，请缩短后再保存。" }
        return nil
    }

    func prepare(
        at date: Date = Date(),
        dataMode: HealthDataMode,
        timeZone: TimeZone = .autoupdatingCurrent,
        forceRead: Bool = false,
        allowsDemoRecords: Bool = false
    ) {
        self.dataMode = dataMode
        self.allowsDemoRecords = allowsDemoRecords
        let enabled = dataMode == .live || (dataMode == .demo && allowsDemoRecords)
        let canRead = enabled || allowsDemoRecords
        let interval = Self.interval(for: date, timeZone: timeZone)
        let changed = dayInterval != interval || isRecordingEnabled != enabled
        if changed {
            dayInterval = interval
            isRecordingEnabled = enabled
            selectedKind = nil
            customLabel = ""
            note = ""
            pendingEvent = nil
            events = []
            didLoadRecords = false
            errorMessage = nil
            notice = isPresented && enabled ? "已进入新的本地日期，请重新选择生活事件。" : nil
        }
        guard canRead else {
            isPresented = false
            return
        }
        guard changed || forceRead || !didLoadRecords else { return }
        do {
            events = try store.contextEvents(overlapping: interval)
            didLoadRecords = true
            errorMessage = nil
        } catch {
            didLoadRecords = false
            errorMessage = "暂时无法读取生活事件，请重试。"
        }
    }

    func open(at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        guard isRecordingEnabled else { return }
        prepare(
            at: date,
            dataMode: dataMode,
            timeZone: timeZone,
            forceRead: true,
            allowsDemoRecords: allowsDemoRecords
        )
        isPresented = true
    }

    func select(_ kind: ContextEventKind) {
        guard isRecordingEnabled else { return }
        selectedKind = selectedKind == kind ? nil : kind
        pendingEvent = nil
        notice = nil
    }

    @discardableResult
    func save(at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        guard validateDay(at: date, timeZone: timeZone), didLoadRecords, let selectedKind else { return false }
        if let validationMessage {
            errorMessage = validationMessage
            return false
        }
        do {
            // Retain operation identity, but use the latest edited text on a failed-save retry.
            let event = try ContextEvent(
                id: pendingEvent?.id ?? UUID(),
                kind: selectedKind,
                customLabel: selectedKind == .custom ? customLabel : nil,
                startedAt: pendingEvent?.startedAt ?? date,
                note: note,
                createdAt: pendingEvent?.createdAt ?? date,
                updatedAt: date
            )
            pendingEvent = event
            try store.save(event)
            events.removeAll { $0.id == event.id }
            events.insert(event, at: 0)
            self.selectedKind = nil
            customLabel = ""
            note = ""
            pendingEvent = nil
            errorMessage = nil
            notice = "已保存到本机"
            return true
        } catch {
            errorMessage = "暂时无法保存，选择和文字已保留，请重试。"
            return false
        }
    }

    @discardableResult
    func delete(id: UUID, at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        guard validateDay(at: date, timeZone: timeZone), didLoadRecords,
              events.contains(where: { $0.id == id }) else { return false }
        do {
            try store.deleteContextEvent(id: id)
            events.removeAll { $0.id == id }
            errorMessage = nil
            notice = "已删除这条生活事件"
            return true
        } catch {
            errorMessage = "暂时无法删除，记录仍保留，请重试。"
            return false
        }
    }

    private func validateDay(at date: Date, timeZone: TimeZone) -> Bool {
        guard isRecordingEnabled else { return false }
        guard dayInterval == Self.interval(for: date, timeZone: timeZone) else {
            prepare(
                at: date,
                dataMode: dataMode,
                timeZone: timeZone,
                allowsDemoRecords: allowsDemoRecords
            )
            notice = "已进入新的本地日期，请重新选择生活事件。"
            return false
        }
        return true
    }

    private static func interval(for date: Date, timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }
}
