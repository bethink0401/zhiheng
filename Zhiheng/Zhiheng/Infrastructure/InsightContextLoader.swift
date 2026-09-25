import Foundation

enum InsightContextLoadFailure: Equatable, Sendable {
    case invalidFactWindow
    case dateOrTimeZoneMismatch
    case corruptRecords
    case readFailed
}

enum InsightContextLoadState: Equatable, Sendable {
    case available(InsightContextMatch)
    /// Demo facts never read or relabel the user's live subjective records.
    case demoMode
    case failed(InsightContextLoadFailure)
}

enum InsightContextSnapshotValidation: Equatable, Sendable {
    case current
    case stale
    case demoMode
    case failed(InsightContextLoadFailure)
}

/// Reads the existing subjective store as one all-or-nothing snapshot.
/// It never writes, caches, or moves private text into an insight.
@MainActor
final class InsightContextLoader {
    private let store: any SubjectiveRecordStore
    private let demoStore: (any SubjectiveRecordStore)?

    init(
        store: any SubjectiveRecordStore,
        demoStore: (any SubjectiveRecordStore)? = nil
    ) {
        self.store = store
        self.demoStore = demoStore
    }

    func load(for factSet: InsightFactSet) -> InsightContextLoadState {
        let sourceStore: any SubjectiveRecordStore
        if factSet.dataMode == .demo {
            guard let demoStore else { return .demoMode }
            sourceStore = demoStore
        } else {
            sourceStore = store
        }
        let window: InsightContextWindow
        do {
            window = try InsightContextMatcher.window(for: factSet)
        } catch {
            return .failed(.invalidFactWindow)
        }

        do {
            var checkIns: [DailyCheckIn] = []
            for day in window.localDays {
                if let record = try sourceStore.checkIn(on: day) {
                    guard record.localDay == day else {
                        return .failed(.dateOrTimeZoneMismatch)
                    }
                    checkIns.append(record)
                }
            }
            let events = try sourceStore.contextEvents(overlapping: window.interval)
            do {
                return .available(try InsightContextMatcher.match(
                    factSet: factSet,
                    checkIns: checkIns,
                    contextEvents: events
                ))
            } catch InsightContextMatchingError.localDayMismatch {
                return .failed(.dateOrTimeZoneMismatch)
            } catch {
                return .failed(.corruptRecords)
            }
        } catch {
            return .failed(.readFailed)
        }
    }

    /// Re-reading detects additions, edits, deletions and events moved out of the window.
    func validate(
        _ snapshot: InsightContextMatch,
        for factSet: InsightFactSet
    ) -> InsightContextSnapshotValidation {
        switch load(for: factSet) {
        case .available(let current):
            return current == snapshot ? .current : .stale
        case .demoMode:
            return .demoMode
        case .failed(let failure):
            return .failed(failure)
        }
    }
}

/// Reads the same bounded seven-day window for an explicit AI send. Unlike the
/// insight loader, this snapshot preserves user-authored notes and custom names.
/// Record identifiers remain internal and are never copied into the fact pack.
struct AssistantFactContextSnapshot: Equatable, Sendable {
    let window: InsightContextWindow
    let checkIns: [DailyCheckIn]
    let contextEvents: [ContextEvent]
}

enum AssistantFactContextLoadState: Equatable, Sendable {
    case available(AssistantFactContextSnapshot)
    case demoMode
    case failed(InsightContextLoadFailure)
}

@MainActor
final class AssistantFactContextLoader {
    private let store: any SubjectiveRecordStore
    private let demoStore: (any SubjectiveRecordStore)?

    init(
        store: any SubjectiveRecordStore,
        demoStore: (any SubjectiveRecordStore)? = nil
    ) {
        self.store = store
        self.demoStore = demoStore
    }

    func load(for factSet: InsightFactSet) -> AssistantFactContextLoadState {
        let sourceStore: any SubjectiveRecordStore
        if factSet.dataMode == .demo {
            guard let demoStore else { return .demoMode }
            sourceStore = demoStore
        } else {
            sourceStore = store
        }
        let window: InsightContextWindow
        do {
            window = try InsightContextMatcher.window(for: factSet)
        } catch {
            return .failed(.invalidFactWindow)
        }

        do {
            var checkIns: [DailyCheckIn] = []
            for day in window.localDays {
                if let record = try sourceStore.checkIn(on: day) {
                    guard record.localDay == day else {
                        return .failed(.dateOrTimeZoneMismatch)
                    }
                    checkIns.append(record)
                }
            }
            let events = try sourceStore.contextEvents(overlapping: window.interval)
            let match: InsightContextMatch
            do {
                match = try InsightContextMatcher.match(
                    factSet: factSet,
                    checkIns: checkIns,
                    contextEvents: events
                )
            } catch InsightContextMatchingError.localDayMismatch {
                return .failed(.dateOrTimeZoneMismatch)
            } catch {
                return .failed(.corruptRecords)
            }

            var checkInByID: [UUID: DailyCheckIn] = [:]
            for record in checkIns { checkInByID[record.id] = record }
            var eventByID: [UUID: ContextEvent] = [:]
            for event in events { eventByID[event.id] = event }
            return .available(AssistantFactContextSnapshot(
                window: window,
                checkIns: match.checkIns.compactMap {
                    checkInByID[$0.reference.recordID]
                },
                contextEvents: match.contextEvents.compactMap {
                    eventByID[$0.reference.recordID]
                }
            ))
        } catch {
            return .failed(.readFailed)
        }
    }
}
