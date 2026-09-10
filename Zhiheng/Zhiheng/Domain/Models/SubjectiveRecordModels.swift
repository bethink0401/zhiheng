import Foundation

enum SubjectiveRating: Int, CaseIterable, Codable, Sendable {
    case one = 1
    case two
    case three
    case four
    case five
}

struct SubjectiveLocalDay: Hashable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let timeZoneIdentifier: String

    init(
        date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
        timeZoneIdentifier = timeZone.identifier
    }

    init(
        year: Int,
        month: Int,
        day: Int,
        timeZoneIdentifier: String
    ) throws {
        guard (1...12).contains(month),
              (1...31).contains(day),
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw SubjectiveRecordValidationError.invalidLocalDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            throw SubjectiveRecordValidationError.invalidLocalDay
        }
        self.year = year
        self.month = month
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var storageKey: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct DailyCheckIn: Identifiable, Equatable, Sendable {
    static let noteCharacterLimit = 160

    let id: UUID
    let localDay: SubjectiveLocalDay
    var energy: SubjectiveRating
    var stress: SubjectiveRating
    var bodyFeeling: SubjectiveRating
    var note: String?
    let recordedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        localDay: SubjectiveLocalDay,
        energy: SubjectiveRating,
        stress: SubjectiveRating,
        bodyFeeling: SubjectiveRating,
        note: String? = nil,
        recordedAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        self.id = id
        self.localDay = localDay
        self.energy = energy
        self.stress = stress
        self.bodyFeeling = bodyFeeling
        self.note = try SubjectiveRecordText.normalized(
            note,
            maximumLength: Self.noteCharacterLimit
        )
        self.recordedAt = recordedAt
        self.updatedAt = updatedAt ?? recordedAt
    }
}

enum ContextEventKind: String, CaseIterable, Codable, Sendable {
    case overtime
    case deadline
    case travel
    case nightShift
    case caffeine
    case alcohol
    case illness
    case highIntensityExercise
    case nap
    case caregiving
    case deviceNotWorn
    case custom

    static let defaultKinds: [Self] = [
        .overtime, .deadline, .travel, .nightShift, .caffeine, .alcohol,
        .illness, .highIntensityExercise, .nap, .caregiving, .deviceNotWorn
    ]

    var title: String {
        switch self {
        case .overtime: "加班"
        case .deadline: "考试或截止日期"
        case .travel: "旅行"
        case .nightShift: "夜班"
        case .caffeine: "咖啡"
        case .alcohol: "饮酒"
        case .illness: "生病"
        case .highIntensityExercise: "高强度运动"
        case .nap: "午睡"
        case .caregiving: "照护家人"
        case .deviceNotWorn: "未佩戴设备"
        case .custom: "自定义"
        }
    }
}

enum ContextEventIntensity: Int, CaseIterable, Codable, Sendable {
    case low = 1
    case medium
    case high
}

struct ContextEvent: Identifiable, Equatable, Sendable {
    static let customLabelCharacterLimit = 30
    static let noteCharacterLimit = 160

    let id: UUID
    var kind: ContextEventKind
    var customLabel: String?
    var startedAt: Date
    var endedAt: Date?
    var intensity: ContextEventIntensity?
    var note: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ContextEventKind,
        customLabel: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        intensity: ContextEventIntensity? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        guard endedAt.map({ $0 >= startedAt }) ?? true else {
            throw SubjectiveRecordValidationError.invalidEventInterval
        }
        let normalizedLabel = try SubjectiveRecordText.normalized(
            customLabel,
            maximumLength: Self.customLabelCharacterLimit
        )
        guard kind != .custom || normalizedLabel != nil else {
            throw SubjectiveRecordValidationError.missingCustomLabel
        }
        self.id = id
        self.kind = kind
        self.customLabel = kind == .custom ? normalizedLabel : nil
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.intensity = intensity
        self.note = try SubjectiveRecordText.normalized(
            note,
            maximumLength: Self.noteCharacterLimit
        )
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum SubjectiveRecordValidationError: Error, Equatable {
    case invalidLocalDay
    case invalidEventInterval
    case missingCustomLabel
    case textTooLong(maximumLength: Int)
}

enum SubjectiveRecordText {
    static func normalized(
        _ value: String?,
        maximumLength: Int
    ) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maximumLength else {
            throw SubjectiveRecordValidationError.textTooLong(
                maximumLength: maximumLength
            )
        }
        return trimmed
    }
}
