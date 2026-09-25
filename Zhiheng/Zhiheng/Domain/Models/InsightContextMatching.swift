import Foundation

/// The current evidence window shared by every S09-02 fact: seven complete local days.
struct InsightContextWindow: Equatable, Sendable {
    let interval: DateInterval
    let localDays: [SubjectiveLocalDay]
    let timeZoneIdentifier: String
}

/// A structured check-in candidate. Free-form notes are intentionally not copied.
struct InsightMatchedCheckIn: Equatable, Sendable {
    let reference: InsightContextReference
    let localDay: SubjectiveLocalDay
    let energy: SubjectiveRating
    let stress: SubjectiveRating
    let bodyFeeling: SubjectiveRating
}

/// A structured life-event candidate. Custom labels and notes remain in their source store.
struct InsightMatchedContextEvent: Equatable, Sendable {
    let reference: InsightContextReference
    let kind: ContextEventKind
    let startedAt: Date
    let endedAt: Date?
    let intensity: ContextEventIntensity?
}

/// Records that happened in the same window as the current facts. This is not evidence of cause.
struct InsightContextMatch: Equatable, Sendable {
    static let matcherVersion = "s09-context-matcher-v1"

    let matcherVersion: String
    let window: InsightContextWindow
    let dataMode: HealthDataMode
    let checkIns: [InsightMatchedCheckIn]
    let contextEvents: [InsightMatchedContextEvent]

    var references: [InsightContextReference] {
        checkIns.map(\.reference) + contextEvents.map(\.reference)
    }
}

enum InsightContextMatchingError: Error, Equatable, Sendable {
    case invalidFactWindow
    case unsupportedDataMode
    case localDayMismatch
    case duplicateRecord
    case duplicateLocalDay
    case invalidRecord
}

/// Pure matching rules. Store access and live/demo isolation are handled by the loader.
enum InsightContextMatcher {
    static func window(for factSet: InsightFactSet) throws -> InsightContextWindow {
        guard !factSet.generatorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !factSet.facts.isEmpty,
              factSet.analysisInterval.start.timeIntervalSinceReferenceDate.isFinite,
              factSet.analysisInterval.end.timeIntervalSinceReferenceDate.isFinite,
              let timeZone = TimeZone(identifier: factSet.timeZoneIdentifier) else {
            throw InsightContextMatchingError.invalidFactWindow
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = factSet.analysisInterval.end
        guard calendar.startOfDay(for: end) == end,
              let start = calendar.date(
                byAdding: .day,
                value: -HealthDataQualityThresholds.shortTermExpectedDays,
                to: end
              ),
              let analysisStart = calendar.date(
                byAdding: .day,
                value: -(HealthDataQualityThresholds.shortTermExpectedDays
                    + HealthDataQualityThresholds.baselineExpectedDays),
                to: end
              ),
              analysisStart == factSet.analysisInterval.start else {
            throw InsightContextMatchingError.invalidFactWindow
        }
        let days = (0..<HealthDataQualityThresholds.shortTermExpectedDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map {
                SubjectiveLocalDay(date: $0, timeZone: timeZone)
            }
        }
        guard days.count == HealthDataQualityThresholds.shortTermExpectedDays else {
            throw InsightContextMatchingError.invalidFactWindow
        }
        return InsightContextWindow(
            interval: DateInterval(start: start, end: end),
            localDays: days,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    static func match(
        factSet: InsightFactSet,
        checkIns: [DailyCheckIn],
        contextEvents: [ContextEvent]
    ) throws -> InsightContextMatch {
        let window = try window(for: factSet)
        let dayOrder = Dictionary(uniqueKeysWithValues:
            window.localDays.enumerated().map { ($0.element, $0.offset) }
        )
        var checkInsByID: [UUID: DailyCheckIn] = [:]
        var checkInIDByDay: [SubjectiveLocalDay: UUID] = [:]
        for record in checkIns {
            guard record.recordedAt.timeIntervalSinceReferenceDate.isFinite,
                  record.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  record.updatedAt >= record.recordedAt else {
                throw InsightContextMatchingError.invalidRecord
            }
            guard dayOrder[record.localDay] != nil else {
                throw InsightContextMatchingError.localDayMismatch
            }
            if let existing = checkInsByID[record.id] {
                guard existing == record else {
                    throw InsightContextMatchingError.duplicateRecord
                }
                continue
            }
            if let existingID = checkInIDByDay[record.localDay], existingID != record.id {
                throw InsightContextMatchingError.duplicateLocalDay
            }
            checkInsByID[record.id] = record
            checkInIDByDay[record.localDay] = record.id
        }

        let matchedCheckIns = checkInsByID.values.sorted {
            let left = dayOrder[$0.localDay] ?? .max
            let right = dayOrder[$1.localDay] ?? .max
            return left == right ? uuidKey($0.id) < uuidKey($1.id) : left < right
        }.map {
            InsightMatchedCheckIn(
                reference: InsightContextReference(
                    kind: .dailyCheckIn,
                    recordID: $0.id,
                    updatedAt: $0.updatedAt,
                    dataMode: factSet.dataMode
                ),
                localDay: $0.localDay,
                energy: $0.energy,
                stress: $0.stress,
                bodyFeeling: $0.bodyFeeling
            )
        }

        var eventsByID: [UUID: ContextEvent] = [:]
        for event in contextEvents where overlaps(event, window.interval) {
            guard event.startedAt.timeIntervalSinceReferenceDate.isFinite,
                  event.endedAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
                  event.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  event.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  event.endedAt.map({ $0 >= event.startedAt }) ?? true,
                  event.updatedAt >= event.createdAt else {
                throw InsightContextMatchingError.invalidRecord
            }
            if let existing = eventsByID[event.id] {
                guard existing == event else {
                    throw InsightContextMatchingError.duplicateRecord
                }
                continue
            }
            eventsByID[event.id] = event
        }
        let matchedEvents = eventsByID.values.sorted {
            $0.startedAt == $1.startedAt
                ? uuidKey($0.id) < uuidKey($1.id)
                : $0.startedAt < $1.startedAt
        }.map {
            InsightMatchedContextEvent(
                reference: InsightContextReference(
                    kind: .contextEvent,
                    recordID: $0.id,
                    updatedAt: $0.updatedAt,
                    dataMode: factSet.dataMode
                ),
                kind: $0.kind,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                intensity: $0.intensity
            )
        }

        return InsightContextMatch(
            matcherVersion: InsightContextMatch.matcherVersion,
            window: window,
            dataMode: factSet.dataMode,
            checkIns: matchedCheckIns,
            contextEvents: matchedEvents
        )
    }

    private static func overlaps(_ event: ContextEvent, _ interval: DateInterval) -> Bool {
        event.startedAt < interval.end && (event.endedAt ?? event.startedAt) >= interval.start
    }

    private static func uuidKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
