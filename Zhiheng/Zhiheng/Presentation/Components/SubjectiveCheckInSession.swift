import Combine
import Foundation

@MainActor
final class SubjectiveCheckInSession: ObservableObject {
    @Published var energy: SubjectiveRating?
    @Published var stress: SubjectiveRating?
    @Published var bodyFeeling: SubjectiveRating?
    @Published var note = "" {
        didSet { if oldValue != note, didLoadRecord { errorMessage = nil } }
    }
    @Published private(set) var savedCheckIn: DailyCheckIn?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRecordingEnabled = true
    @Published private(set) var didLoadRecord = false

    private let store: any SubjectiveRecordStore
    private var loadedDay: SubjectiveLocalDay?

    init(store: any SubjectiveRecordStore) {
        self.store = store
    }

    var isComplete: Bool {
        energy != nil && stress != nil && bodyFeeling != nil
    }

    var canSave: Bool {
        isRecordingEnabled && didLoadRecord && isComplete && noteValidationMessage == nil
    }

    var noteValidationMessage: String? {
        do {
            _ = try SubjectiveRecordText.normalized(note, maximumLength: DailyCheckIn.noteCharacterLimit)
            return nil
        } catch { return "备注最多 \(DailyCheckIn.noteCharacterLimit) 字，请缩短后再保存。" }
    }

    func load(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        isRecordingEnabled: Bool = true
    ) {
        self.isRecordingEnabled = isRecordingEnabled
        didLoadRecord = false
        errorMessage = nil
        guard isRecordingEnabled else {
            loadedDay = nil
            savedCheckIn = nil
            energy = nil
            stress = nil
            bodyFeeling = nil
            note = ""
            return
        }

        let day = SubjectiveLocalDay(date: date, timeZone: timeZone)
        loadedDay = day
        do {
            let record = try store.checkIn(on: day)
            savedCheckIn = record
            energy = record?.energy
            stress = record?.stress
            bodyFeeling = record?.bodyFeeling
            note = record?.note ?? ""
            didLoadRecord = true
        } catch {
            savedCheckIn = nil
            energy = nil
            stress = nil
            bodyFeeling = nil
            note = ""
            errorMessage = "暂时无法读取今日记录，请关闭窗口后重新打开重试。"
        }
    }

    @discardableResult
    func save(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        recordedAt: Date = Date()
    ) -> Bool {
        guard isRecordingEnabled else {
            errorMessage = "演示模式下不会保存你的主观记录。"
            return false
        }
        guard didLoadRecord else {
            errorMessage = "暂时无法读取今日记录，请关闭窗口后重新打开重试。"
            return false
        }
        guard let energy, let stress, let bodyFeeling else {
            errorMessage = "请先完成精力、压力和身体感受三项选择。"
            return false
        }
        if let noteValidationMessage {
            errorMessage = noteValidationMessage
            return false
        }

        let day = SubjectiveLocalDay(date: date, timeZone: timeZone)
        guard loadedDay == day else {
            load(for: date, timeZone: timeZone)
            errorMessage = "日期或时区已变化，请重新确认今日感受。"
            return false
        }
        let existing = loadedDay == day ? savedCheckIn : nil
        do {
            let record = try DailyCheckIn(
                id: existing?.id ?? UUID(),
                localDay: day,
                energy: energy,
                stress: stress,
                bodyFeeling: bodyFeeling,
                note: note,
                recordedAt: existing?.recordedAt ?? recordedAt,
                updatedAt: recordedAt
            )
            let saved = try store.save(record)
            loadedDay = day
            savedCheckIn = saved
            note = saved.note ?? ""
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.persistenceErrorMessage
            return false
        }
    }

    private static let persistenceErrorMessage =
        "暂时无法保存，请稍后重试。你刚才的选择仍保留在页面上。"
}

/// Coordinates the user-initiated daily check-in sheet and current-day state.
@MainActor
final class DailyCheckInCoordinator: ObservableObject {
    static let promptedDayKey = "dailyFeeling.lastPresentedDay"

    let session: SubjectiveCheckInSession
    let contextEvents: ContextEventSession
    let history: SubjectiveHistorySession
    @Published var isPresented = false
    @Published private(set) var referenceDate: Date
    @Published private(set) var notice: String?
    var onCurrentCheckInChanged: (() -> Void)?
    private let preferences: UserDefaults
    private var dayKey: String?
    private var dataMode: HealthDataMode = .live

    init(
        store: any SubjectiveRecordStore,
        preferences: UserDefaults = .standard,
        referenceDate: Date = Date()
    ) {
        session = SubjectiveCheckInSession(store: store)
        contextEvents = ContextEventSession(store: store)
        history = SubjectiveHistorySession(store: store)
        self.preferences = preferences
        self.referenceDate = referenceDate
        history.onRecordsChanged = { [weak self] record in
            self?.refreshAfterHistoryChange(record)
        }
    }

    func enterApp(
        at date: Date = Date(),
        dataMode: HealthDataMode,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        history.setDataMode(dataMode)
        contextEvents.prepare(at: date, dataMode: dataMode, timeZone: timeZone)
        let key = SubjectiveLocalDay(date: date, timeZone: timeZone).storageKey
        let changedDay = dayKey != key
        if changedDay || self.dataMode != dataMode {
            self.dataMode = dataMode
            dayKey = key
            referenceDate = date
            notice = nil
            session.load(for: date, timeZone: timeZone, isRecordingEnabled: dataMode == .live)
            if changedDay && isPresented && dataMode == .live {
                notice = "已进入新的一天，请重新选择今日感受。"
                markPresented()
            }
        }
        guard dataMode == .live else {
            isPresented = false
            return
        }
        // Loading the current day must never interrupt the user with a sheet.
        // The sheet is presented only from the explicit action in `openManually`.
    }

    /// Called only once the sheet is visible, so an interrupted request isn't consumed.
    func markPresented() {
        guard dataMode == .live, let dayKey else { return }
        preferences.set(dayKey, forKey: Self.promptedDayKey)
    }

    func openManually(at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        guard dataMode == .live else { return }
        enterApp(at: date, dataMode: .live, timeZone: timeZone)
        if !session.didLoadRecord {
            session.load(for: date, timeZone: timeZone)
        }
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    /// Refresh only the affected current-day state, without discarding unrelated drafts.
    func refreshAfterHistoryChange(
        _ record: SubjectiveHistoryRecord,
        at date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        guard dataMode == .live else { return }
        switch record {
        case .checkIn(let record):
            let currentDay = SubjectiveLocalDay(date: date, timeZone: timeZone)
            guard record.localDay.storageKey == currentDay.storageKey else { return }
            referenceDate = date
            dayKey = currentDay.storageKey
            session.load(for: date, timeZone: timeZone)
            // An intentional deletion must not immediately cause another daily prompt.
            markPresented()
            onCurrentCheckInChanged?()
        case .event:
            contextEvents.prepare(at: date, dataMode: .live, timeZone: timeZone, forceRead: true)
        }
    }

    @discardableResult
    func save(at date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        guard dataMode == .live else { return false }
        let key = SubjectiveLocalDay(date: date, timeZone: timeZone).storageKey
        guard key == dayKey else {
            enterApp(at: date, dataMode: .live, timeZone: timeZone)
            notice = "已进入新的一天，请重新选择今日感受。"
            return false
        }
        guard session.save(for: date, timeZone: timeZone, recordedAt: date) else { return false }
        markPresented()
        notice = nil
        isPresented = false
        onCurrentCheckInChanged?()
        return true
    }
}
