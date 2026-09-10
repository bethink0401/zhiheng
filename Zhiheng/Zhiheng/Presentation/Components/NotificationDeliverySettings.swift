import Combine
import Foundation

enum NotificationReminderFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily
    case everyOtherDay
    case weekly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily:
            "每天最多 1 条"
        case .everyOtherDay:
            "至少间隔 2 天"
        case .weekly:
            "至少间隔 7 天"
        }
    }

    var minimumSpacingInDays: Int {
        switch self {
        case .daily: 1
        case .everyOtherDay: 2
        case .weekly: 7
        }
    }
}

struct NotificationQuietHours: Equatable, Sendable {
    static let defaultStartHour = 22
    static let defaultEndHour = 8

    var isEnabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        isEnabled: Bool = true,
        startHour: Int = defaultStartHour,
        startMinute: Int = 0,
        endHour: Int = defaultEndHour,
        endMinute: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.startHour = (0...23).contains(startHour)
            ? startHour
            : Self.defaultStartHour
        self.startMinute = (0...59).contains(startMinute) ? startMinute : 0
        self.endHour = (0...23).contains(endHour) ? endHour : Self.defaultEndHour
        self.endMinute = (0...59).contains(endMinute) ? endMinute : 0
    }
}

struct NotificationDeliverySettings: Equatable, Sendable {
    var isEnabled: Bool
    var frequency: NotificationReminderFrequency
    var quietHours: NotificationQuietHours

    init(
        isEnabled: Bool = true,
        frequency: NotificationReminderFrequency = .daily,
        quietHours: NotificationQuietHours = .init()
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.quietHours = quietHours
    }
}

struct NotificationDeliveryCandidate: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
}

enum NotificationDeliveryPolicy {
    static let reminderIdentifierPrefixes = [
        MicroPlanReminderPolicy.identifierPrefix,
        LowFrequencyTrendReminderPolicy.identifierPrefix,
        DailyCheckInReminderPolicy.identifierPrefix
    ]

    static func filteredIdentifiers(
        candidates: [NotificationDeliveryCandidate],
        reservingHigherPriorityIdentifiers identifiers: [String],
        settings: NotificationDeliverySettings,
        timeZone: TimeZone
    ) -> Set<String> {
        guard settings.isEnabled else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var occupiedDays = identifiers.compactMap {
            localDayDate(from: $0, calendar: calendar)
        }
        var allowed = Set<String>()

        for candidate in candidates.sorted(by: candidateOrder) {
            guard !isQuietTime(
                candidate.fireDate,
                settings: settings.quietHours,
                timeZone: timeZone
            ) else { continue }

            let candidateDay = calendar.startOfDay(for: candidate.fireDate)
            let isTooClose = occupiedDays.contains { occupiedDay in
                guard let difference = calendar.dateComponents(
                    [.day],
                    from: min(occupiedDay, candidateDay),
                    to: max(occupiedDay, candidateDay)
                ).day else { return true }
                return difference < settings.frequency.minimumSpacingInDays
            }
            guard !isTooClose else { continue }
            occupiedDays.append(candidateDay)
            allowed.insert(candidate.identifier)
        }
        return allowed
    }

    static func lowerPriorityIdentifiersToRemove(
        from pendingIdentifiers: [String],
        matchingPrefixes: [String],
        for scheduledCandidates: [NotificationDeliveryCandidate],
        settings: NotificationDeliverySettings,
        timeZone: TimeZone
    ) -> [String] {
        guard settings.isEnabled, !scheduledCandidates.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let scheduledDays = scheduledCandidates.map {
            calendar.startOfDay(for: $0.fireDate)
        }

        return pendingIdentifiers.filter { identifier in
            guard matchingPrefixes.contains(where: identifier.hasPrefix),
                  let pendingDay = localDayDate(
                    from: identifier,
                    calendar: calendar
                  ) else { return false }
            return scheduledDays.contains { scheduledDay in
                guard let difference = calendar.dateComponents(
                    [.day],
                    from: min(pendingDay, scheduledDay),
                    to: max(pendingDay, scheduledDay)
                ).day else { return true }
                return difference < settings.frequency.minimumSpacingInDays
            }
        }
    }

    static func isQuietTime(
        _ date: Date,
        settings: NotificationQuietHours,
        timeZone: TimeZone
    ) -> Bool {
        guard settings.isEnabled else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return true
        }
        let value = hour * 60 + minute
        let start = settings.startHour * 60 + settings.startMinute
        let end = settings.endHour * 60 + settings.endMinute
        if start == end { return false }
        if start < end {
            return value >= start && value < end
        }
        return value >= start || value < end
    }

    private static func candidateOrder(
        lhs: NotificationDeliveryCandidate,
        rhs: NotificationDeliveryCandidate
    ) -> Bool {
        if lhs.fireDate == rhs.fireDate { return lhs.identifier < rhs.identifier }
        return lhs.fireDate < rhs.fireDate
    }

    private static func localDayDate(
        from identifier: String,
        calendar: Calendar
    ) -> Date? {
        guard let prefix = reminderIdentifierPrefixes.first(where: identifier.hasPrefix)
        else { return nil }
        let components = String(identifier.dropFirst(prefix.count)).split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else { return nil }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }
}

final class NotificationDeliverySettingsStore: @unchecked Sendable {
    static let enabledKey = "notificationDelivery.enabled.v1"
    static let frequencyKey = "notificationDelivery.frequency.v1"
    static let quietEnabledKey = "notificationDelivery.quiet.enabled.v1"
    static let quietStartHourKey = "notificationDelivery.quiet.startHour.v1"
    static let quietStartMinuteKey = "notificationDelivery.quiet.startMinute.v1"
    static let quietEndHourKey = "notificationDelivery.quiet.endHour.v1"
    static let quietEndMinuteKey = "notificationDelivery.quiet.endMinute.v1"

    private let preferences: UserDefaults
    private let lock = NSLock()
    private var settings: NotificationDeliverySettings

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        settings = Self.load(from: preferences)
    }

    func current() -> NotificationDeliverySettings {
        lock.withLock { settings }
    }

    func replace(with updated: NotificationDeliverySettings) {
        lock.withLock {
            settings = updated
            preferences.set(updated.isEnabled, forKey: Self.enabledKey)
            preferences.set(updated.frequency.rawValue, forKey: Self.frequencyKey)
            preferences.set(updated.quietHours.isEnabled, forKey: Self.quietEnabledKey)
            preferences.set(updated.quietHours.startHour, forKey: Self.quietStartHourKey)
            preferences.set(updated.quietHours.startMinute, forKey: Self.quietStartMinuteKey)
            preferences.set(updated.quietHours.endHour, forKey: Self.quietEndHourKey)
            preferences.set(updated.quietHours.endMinute, forKey: Self.quietEndMinuteKey)
        }
    }

    static func load(from preferences: UserDefaults) -> NotificationDeliverySettings {
        let enabled = preferences.object(forKey: enabledKey) as? Bool ?? true
        let quietEnabled = preferences.object(forKey: quietEnabledKey) as? Bool ?? true
        let frequency = preferences.string(forKey: frequencyKey)
            .flatMap(NotificationReminderFrequency.init(rawValue:)) ?? .daily
        let startHour = preferences.object(forKey: quietStartHourKey) as? Int
        let startMinute = preferences.object(forKey: quietStartMinuteKey) as? Int
        let endHour = preferences.object(forKey: quietEndHourKey) as? Int
        let endMinute = preferences.object(forKey: quietEndMinuteKey) as? Int
        return NotificationDeliverySettings(
            isEnabled: enabled,
            frequency: frequency,
            quietHours: NotificationQuietHours(
                isEnabled: quietEnabled,
                startHour: startHour ?? NotificationQuietHours.defaultStartHour,
                startMinute: startMinute ?? 0,
                endHour: endHour ?? NotificationQuietHours.defaultEndHour,
                endMinute: endMinute ?? 0
            )
        )
    }
}

@MainActor
final class NotificationDeliverySettingsSession: ObservableObject {
    @Published private(set) var settings: NotificationDeliverySettings
    private let store: NotificationDeliverySettingsStore

    init(
        store: NotificationDeliverySettingsStore,
        initialSettings: NotificationDeliverySettings
    ) {
        self.store = store
        settings = initialSettings
    }

    var quietStartTime: Date {
        time(hour: settings.quietHours.startHour, minute: settings.quietHours.startMinute)
    }

    var quietEndTime: Date {
        time(hour: settings.quietHours.endHour, minute: settings.quietHours.endMinute)
    }

    func setEnabled(_ isEnabled: Bool) async {
        guard settings.isEnabled != isEnabled else { return }
        settings.isEnabled = isEnabled
        store.replace(with: settings)
    }

    func setFrequency(_ frequency: NotificationReminderFrequency) async {
        guard settings.frequency != frequency else { return }
        settings.frequency = frequency
        store.replace(with: settings)
    }

    func setQuietHoursEnabled(_ isEnabled: Bool) async {
        guard settings.quietHours.isEnabled != isEnabled else { return }
        settings.quietHours.isEnabled = isEnabled
        store.replace(with: settings)
    }

    func updateQuietStart(from date: Date, timeZone: TimeZone = .autoupdatingCurrent) async {
        await updateQuietTime(from: date, updatesStart: true, timeZone: timeZone)
    }

    func updateQuietEnd(from date: Date, timeZone: TimeZone = .autoupdatingCurrent) async {
        await updateQuietTime(from: date, updatesStart: false, timeZone: timeZone)
    }

    private func updateQuietTime(
        from date: Date,
        updatesStart: Bool,
        timeZone: TimeZone
    ) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        var updated = settings
        if updatesStart {
            updated.quietHours.startHour = hour
            updated.quietHours.startMinute = minute
        } else {
            updated.quietHours.endHour = hour
            updated.quietHours.endMinute = minute
        }
        guard updated != settings else { return }
        settings = updated
        store.replace(with: updated)
    }

    private func time(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}
