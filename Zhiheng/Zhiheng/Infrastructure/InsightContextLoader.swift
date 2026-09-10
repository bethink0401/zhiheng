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

    init(store: any SubjectiveRecordStore) {
        self.store = store
    }

    func load(for factSet: InsightFactSet) -> InsightContextLoadState {
        guard factSet.dataMode == .live else { return .demoMode }
        let window: InsightContextWindow
        do {
            window = try InsightContextMatcher.window(for: factSet)
        } catch {
            return .failed(.invalidFactWindow)
        }

        do {
            var checkIns: [DailyCheckIn] = []
            for day in window.localDays {
                if let record = try store.checkIn(on: day) {
                    guard record.localDay == day else {
                        return .failed(.dateOrTimeZoneMismatch)
                    }
                    checkIns.append(record)
                }
            }
            let events = try store.contextEvents(overlapping: window.interval)
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
