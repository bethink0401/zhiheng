import Foundation

struct DemoHealthSampleDraft: Equatable, Sendable {
    let metricType: HealthMetricType
    let startDate: Date
    let endDate: Date
    let value: Double
    let sleepStage: HealthSleepStage?

    init(
        metricType: HealthMetricType,
        startDate: Date,
        endDate: Date,
        value: Double,
        sleepStage: HealthSleepStage? = nil
    ) {
        self.metricType = metricType
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.sleepStage = sleepStage
    }
}

enum DemoHealthScenarioFactory {
    static func dashboard(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) throws -> DemoHealthDataService {
        let finalDay = calendar.startOfDay(for: endDate)
        var drafts = [DemoHealthSampleDraft]()

        // Ninety days gives every dashboard, detail, 7/28-day trend and coverage
        // view the same coherent story. The values are deterministic but use
        // weekly rhythms and small multi-day oscillations instead of straight
        // lines, so refreshing never changes the story underneath the user.
        for index in 0..<90 {
            let dayOffset = index - 89
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: finalDay),
                  let sleepEnd = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: day)
            else { throw HealthDataServiceError.queryFailed }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let rhythm = sin(Double(index) * 1.37) * 0.11
            let slowerRhythm = cos(Double(index) * 0.43) * 0.08
            let recentSleep: [Double] = [6.90, 6.72, 6.55, 6.43, 6.34, 6.51, 6.39, 6.47]
            let sleepHours: Double
            if dayOffset >= -7 {
                sleepHours = recentSleep[dayOffset + 7]
            } else if (-16 ... -12).contains(dayOffset) {
                // A completed bedtime experiment improved this short window,
                // followed later by a deadline-heavy week. This is a temporal
                // story, not a causal claim.
                sleepHours = 7.28 + Double(dayOffset + 16) * 0.08 + rhythm * 0.35
            } else {
                sleepHours = 7.18 + (isWeekend ? 0.24 : 0) + rhythm + slowerRhythm
            }
            let awakeHours = 0.18 + Double(index % 3) * 0.025
            let nightStart = sleepEnd.addingTimeInterval(
                -(sleepHours + awakeHours) * 60 * 60
            )
            var segmentStart = nightStart
            for (stage, duration, countedHours) in [
                (HealthSleepStage.core, sleepHours * 0.12, sleepHours * 0.12),
                (.deep, sleepHours * 0.08, sleepHours * 0.08),
                (.core, sleepHours * 0.07, sleepHours * 0.07),
                (.rem, sleepHours * 0.06, sleepHours * 0.06),
                (.core, sleepHours * 0.14, sleepHours * 0.14),
                (.awake, awakeHours * 0.5, 0),
                (.core, sleepHours * 0.11, sleepHours * 0.11),
                (.deep, sleepHours * 0.10, sleepHours * 0.10),
                (.core, sleepHours * 0.09, sleepHours * 0.09),
                (.rem, sleepHours * 0.08, sleepHours * 0.08),
                (.core, sleepHours * 0.07, sleepHours * 0.07),
                (.awake, awakeHours * 0.5, 0),
                (.core, sleepHours * 0.04, sleepHours * 0.04),
                (.rem, sleepHours * 0.04, sleepHours * 0.04)
            ] {
                let segmentEnd = segmentStart.addingTimeInterval(duration * 60 * 60)
                drafts.append(DemoHealthSampleDraft(
                    metricType: .sleepDuration,
                    startDate: segmentStart,
                    endDate: segmentEnd,
                    value: countedHours,
                    sleepStage: stage
                ))
                segmentStart = segmentEnd
            }
            let activityPressure = dayOffset >= -7 ? Double(dayOffset + 7) : 0
            let hrv = dayOffset >= -7
                ? 44.0 - activityPressure * 0.45 + rhythm * 4
                : 50.5 + rhythm * 7 + slowerRhythm * 3
            // One isolated wearable gap demonstrates that missing is not zero,
            // while six recent valid days still support the main trend.
            if dayOffset != -4 {
                try append(metric: .heartRateVariability, value: hrv, day: day, hour: 7, to: &drafts, calendar: calendar)
            }
            if dayOffset == 0 {
                for (hour, value) in [
                    (0, 48.0), (2, 45.0), (4, 43.0), (6, 46.0),
                    (8, 42.0), (9, 40.0), (10, 41.0)
                ] {
                    try append(
                        metric: .heartRateVariability,
                        value: value,
                        day: day,
                        hour: hour,
                        to: &drafts,
                        calendar: calendar
                    )
                }
            }
            let restingHeartRate = dayOffset >= -7
                ? 61.2 + activityPressure * 0.32 + abs(rhythm) * 4
                : 58.2 + rhythm * 5 + (isWeekend ? -0.6 : 0)
            try append(metric: .restingHeartRate, value: restingHeartRate, day: day, hour: 8, to: &drafts, calendar: calendar)
            // Activity follows recognisable workday/weekend shapes. Recent days
            // deliberately rise and fall instead of forming an artificial ramp,
            // and active energy is not derived from step count: strength work,
            // cycling and brisk walks can produce different kcal/step ratios.
            let recentSteps = [8_240.0, 10_680, 7_360, 12_140, 8_910, 10_420, 7_780, 9_630]
            let recentEnergy = [418.0, 572, 386, 648, 463, 594, 521, 489]
            let weekdayStepBase = [7_150.0, 8_420, 9_160, 7_780, 10_080, 8_760, 11_240]
            let weekdayEnergyBase = [438.0, 452, 516, 421, 562, 486, 608]
            let weekdayIndex = max(0, min(6, weekday - 1))
            let dailySteps = dayOffset >= -7
                ? recentSteps[dayOffset + 7]
                : max(4_650, weekdayStepBase[weekdayIndex] + rhythm * 6_800 + slowerRhythm * 2_900)
            let dailyEnergy = dayOffset >= -7
                ? recentEnergy[dayOffset + 7]
                : max(285, weekdayEnergyBase[weekdayIndex] + cos(Double(index) * 0.81) * 44 + sin(Double(index) * 0.29) * 26)
            let strideKilometers = 0.00069 + slowerRhythm * 0.00018
            let dailyDistance = max(3.1, dailySteps * strideKilometers)
            let isHigherEnergyDay = dailyEnergy >= 540
            let stepDistribution = activityDistribution(
                isWeekend: isWeekend,
                isHigherEnergyDay: isHigherEnergyDay,
                kind: .steps
            )
            let energyDistribution = activityDistribution(
                isWeekend: isWeekend,
                isHigherEnergyDay: isHigherEnergyDay,
                kind: .energy
            )
            for (hour, fraction) in stepDistribution {
                try append(metric: .stepCount, value: dailySteps * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
                try append(metric: .walkingRunningDistance, value: dailyDistance * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            for (hour, fraction) in energyDistribution {
                try append(metric: .activeEnergy, value: dailyEnergy * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            let recentExercise = [31.0, 48, 22, 61, 34, 52, 45, 37]
            let exercise = dayOffset >= -7
                ? recentExercise[dayOffset + 7]
                : 24 + (isWeekend ? 11 : 0) + rhythm * 31 + (isHigherEnergyDay ? 12 : 0)
            try append(metric: .exerciseDuration, value: max(16, exercise), day: day, hour: 18, to: &drafts, calendar: calendar)
            let standCount = dayOffset >= -7 ? 11 + (index % 2) : 9 + (index % 4)
            for hour in 9..<(9 + min(standCount, 13)) {
                try append(metric: .standHours, value: 1, day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            for hour in [1, 3, 5] {
                try append(metric: .heartRate, value: restingHeartRate - 3 + Double((index + hour) % 4), day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            if dayOffset != -4 {
                try append(metric: .respiratoryRate, value: 15.0 + rhythm * 1.4, day: day, hour: 4, to: &drafts, calendar: calendar)
                try append(metric: .oxygenSaturation, value: 97.6 + rhythm * 2.1, day: day, hour: 4, to: &drafts, calendar: calendar)
                try append(metric: .wristTemperature, value: 35.78 + rhythm * 0.55, day: day, hour: 6, to: &drafts, calendar: calendar)
            }
            try append(metric: .flightsClimbed, value: Double(4 + (index * 3) % 7), day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .walkingSpeed, value: 1.22 + rhythm * 0.22, day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .walkingStepLength, value: 0.70 + slowerRhythm * 0.28, day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .vo2Max, value: 39.1 + slowerRhythm * 2.2, day: day, hour: 8, to: &drafts, calendar: calendar)
        }
        return try DemoHealthDataService(drafts: drafts)
    }

    private static func append(
        metric: HealthMetricType,
        value: Double,
        day: Date,
        hour: Int,
        to drafts: inout [DemoHealthSampleDraft],
        calendar: Calendar
    ) throws {
        guard let end = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else {
            throw HealthDataServiceError.queryFailed
        }
        drafts.append(DemoHealthSampleDraft(
            metricType: metric,
            startDate: end.addingTimeInterval(-60),
            endDate: end,
            value: value
        ))
    }

    private enum ActivityDistributionKind {
        case steps
        case energy
    }

    private static func activityDistribution(
        isWeekend: Bool,
        isHigherEnergyDay: Bool,
        kind: ActivityDistributionKind
    ) -> [(Int, Double)] {
        if isWeekend {
            return kind == .steps
                ? [(7, 0.01), (8, 0.03), (9, 0.08), (10, 0.14), (11, 0.13),
                   (14, 0.17), (16, 0.15), (18, 0.14), (20, 0.10), (22, 0.05)]
                : [(7, 0.01), (8, 0.03), (9, 0.06), (10, 0.12), (11, 0.11),
                   (14, 0.15), (16, 0.18), (18, 0.18), (20, 0.11), (22, 0.05)]
        }
        if isHigherEnergyDay {
            return kind == .steps
                ? [(6, 0.01), (7, 0.06), (8, 0.15), (10, 0.04), (12, 0.13),
                   (14, 0.05), (17, 0.10), (18, 0.24), (20, 0.15), (22, 0.07)]
                : [(6, 0.01), (7, 0.05), (8, 0.10), (10, 0.03), (12, 0.10),
                   (14, 0.04), (17, 0.08), (18, 0.35), (20, 0.18), (22, 0.06)]
        }
        return kind == .steps
            ? [(6, 0.01), (7, 0.07), (8, 0.16), (10, 0.05), (12, 0.15),
               (14, 0.06), (17, 0.12), (18, 0.19), (20, 0.12), (22, 0.07)]
            : [(6, 0.02), (7, 0.06), (8, 0.12), (10, 0.04), (12, 0.12),
               (14, 0.05), (17, 0.10), (18, 0.25), (20, 0.17), (22, 0.07)]
    }

    static func sleepDecline(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) throws -> DemoHealthDataService {
        let finalDay = calendar.startOfDay(for: endDate)
        let baselinePattern = [7.4, 7.6, 7.5, 7.3]
        let recentDecline = [7.0, 6.8, 6.6, 6.4, 6.2, 6.0, 5.8]
        var drafts = [DemoHealthSampleDraft]()

        for index in 0..<35 {
            guard let day = calendar.date(
                byAdding: .day,
                value: index - 34,
                to: finalDay
            ), let sleepEnd = calendar.date(
                bySettingHour: 7,
                minute: 0,
                second: 0,
                of: day
            ) else {
                throw HealthDataServiceError.queryFailed
            }
            let hours = index < 28
                ? baselinePattern[index % baselinePattern.count]
                : recentDecline[index - 28]
            drafts.append(DemoHealthSampleDraft(
                metricType: .sleepDuration,
                startDate: sleepEnd.addingTimeInterval(-hours * 60 * 60),
                endDate: sleepEnd,
                value: hours
            ))
        }
        return try DemoHealthDataService(drafts: drafts)
    }

    static func activityLoadIncrease(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) throws -> DemoHealthDataService {
        let finalDay = calendar.startOfDay(for: endDate)
        let baselineEnergy = [280.0, 300.0, 320.0, 295.0]
        let baselineMinutes = [25.0, 30.0, 35.0, 28.0]
        let recentEnergy = [350.0, 400.0, 450.0, 500.0, 550.0, 600.0, 650.0]
        let recentMinutes = [35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0]
        var drafts = [DemoHealthSampleDraft]()

        for index in 0..<35 {
            guard let day = calendar.date(
                byAdding: .day,
                value: index - 34,
                to: finalDay
            ), let sampleTime = calendar.date(
                bySettingHour: 10,
                minute: 0,
                second: 0,
                of: day
            ) else {
                throw HealthDataServiceError.queryFailed
            }
            let energy = index < 28
                ? baselineEnergy[index % baselineEnergy.count]
                : recentEnergy[index - 28]
            let minutes = index < 28
                ? baselineMinutes[index % baselineMinutes.count]
                : recentMinutes[index - 28]
            let sampleEnd = sampleTime.addingTimeInterval(60)
            drafts.append(DemoHealthSampleDraft(
                metricType: .activeEnergy,
                startDate: sampleTime,
                endDate: sampleEnd,
                value: energy
            ))
            drafts.append(DemoHealthSampleDraft(
                metricType: .exerciseDuration,
                startDate: sampleTime,
                endDate: sampleEnd,
                value: minutes
            ))
        }
        return try DemoHealthDataService(drafts: drafts)
    }

    static func missingWearableData(
        endingAt endDate: Date,
        calendar: Calendar = .current
    ) throws -> DemoHealthDataService {
        let finalDay = calendar.startOfDay(for: endDate)
        var drafts = [DemoHealthSampleDraft]()

        // The final four days intentionally have no samples. Missing wearable
        // data is represented by absence, never by zero-valued measurements.
        for index in 0..<31 {
            guard let day = calendar.date(
                byAdding: .day,
                value: index - 34,
                to: finalDay
            ), let sampleTime = calendar.date(
                bySettingHour: 10,
                minute: 0,
                second: 0,
                of: day
            ) else {
                throw HealthDataServiceError.queryFailed
            }
            let sampleEnd = sampleTime.addingTimeInterval(60)
            drafts.append(DemoHealthSampleDraft(
                metricType: .stepCount,
                startDate: sampleTime,
                endDate: sampleEnd,
                value: 6_500 + Double((index % 4) * 250)
            ))
            drafts.append(DemoHealthSampleDraft(
                metricType: .restingHeartRate,
                startDate: sampleTime,
                endDate: sampleEnd,
                value: 58 + Double(index % 3)
            ))
        }
        return try DemoHealthDataService(drafts: drafts)
    }
}

actor DemoHealthDataService: HealthDataService {
    static let sourceName = "知衡演示数据"

    private let samplesByMetric: [HealthMetricType: [HealthMetricSample]]

    init(drafts: [DemoHealthSampleDraft]) throws {
        var grouped = [HealthMetricType: [HealthMetricSample]]()
        for (index, draft) in drafts.enumerated() {
            let idText = String(
                format: "00000000-0000-4000-8000-%012X",
                index + 1
            )
            guard let id = UUID(uuidString: idText) else {
                throw HealthDataServiceError.queryFailed
            }
            let sample = try HealthMetricSample(
                id: id,
                metricType: draft.metricType,
                startDate: draft.startDate,
                endDate: draft.endDate,
                value: draft.value,
                unit: draft.metricType.expectedUnit,
                source: HealthMetricSource(
                    sourceName: Self.sourceName,
                    bundleIdentifier: nil,
                    deviceName: nil
                ),
                sleepStage: draft.sleepStage
            )
            grouped[draft.metricType, default: []].append(sample)
        }
        samplesByMetric = grouped.mapValues { samples in
            samples.sorted { $0.startDate < $1.startDate }
        }
    }

    var dataMode: HealthDataMode { .demo }

    func accessState() async -> HealthAccessState {
        .requestCompleted
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {
        // Demo data is generated locally and never opens a system permission prompt.
    }

    func fetchSamples(
        for metric: HealthMetricType,
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        guard interval.end > interval.start else {
            throw HealthDataServiceError.invalidInterval
        }
        return samplesByMetric[metric, default: []].filter { sample in
            sample.endDate >= interval.start && sample.startDate <= interval.end
        }
    }
}

/// In-memory subjective records that belong only to the synthetic demo person.
/// Demo edits last for the current app run and never touch the user's SwiftData store.
@MainActor
final class DemoSubjectiveRecordStore: SubjectiveRecordStore {
    private var checkInsByDay: [String: DailyCheckIn]
    private var events: [ContextEvent]

    init(
        endingAt referenceDate: Date = Date(),
        calendar sourceCalendar: Calendar = .current
    ) {
        let calendar = sourceCalendar
        let timeZone = calendar.timeZone
        let finalDay = calendar.startOfDay(for: referenceDate)
        var checkIns: [String: DailyCheckIn] = [:]

        // A compact but coherent subjective arc: a calmer baseline, improved
        // feelings during an earlier bedtime experiment, then a demanding week.
        let ratings: [(Int, Int, Int, Int, String?)] = [
            (-21, 3, 3, 3, nil), (-20, 3, 3, 3, nil),
            (-19, 3, 4, 3, "截止日前任务比较集中。"),
            (-18, 2, 4, 3, nil), (-17, 3, 3, 3, nil),
            (-16, 3, 3, 3, "开始尝试提前收尾。"),
            (-15, 4, 3, 4, nil), (-14, 4, 2, 4, nil),
            (-13, 4, 2, 4, "早上起来比前几天轻松。"),
            (-12, 4, 2, 4, nil),
            (-7, 3, 3, 3, nil), (-6, 3, 4, 3, "晚上处理了临时任务。"),
            (-5, 2, 4, 3, nil), (-4, 2, 4, 2, "忘记佩戴手表大约半天。"),
            (-3, 2, 5, 2, nil), (-2, 3, 4, 3, "下午喝了一杯咖啡。"),
            (-1, 2, 4, 3, nil), (0, 2, 4, 3, "这周工作节奏偏紧，想先把睡眠稳住。")
        ]
        for (position, item) in ratings.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: item.0, to: finalDay),
                  let recordedAt = calendar.date(bySettingHour: 20, minute: 40, second: 0, of: date),
                  let energy = SubjectiveRating(rawValue: item.1),
                  let stress = SubjectiveRating(rawValue: item.2),
                  let body = SubjectiveRating(rawValue: item.3),
                  let record = try? DailyCheckIn(
                    id: Self.uuid(position + 1),
                    localDay: SubjectiveLocalDay(date: date, timeZone: timeZone),
                    energy: energy,
                    stress: stress,
                    bodyFeeling: body,
                    note: item.4,
                    recordedAt: recordedAt
                  ) else { continue }
            checkIns[record.localDay.storageKey] = record
        }
        checkInsByDay = checkIns

        let eventDrafts: [(Int, Int, ContextEventKind, ContextEventIntensity, String?)] = [
            (-19, 18, .deadline, .high, "项目进入集中交付阶段。"),
            (-16, 15, .caffeine, .medium, "当天把最后一杯改到 15:00 前。"),
            (-13, 19, .highIntensityExercise, .medium, nil),
            (-6, 21, .overtime, .high, "处理临时任务到较晚。"),
            (-4, 13, .deviceNotWorn, .medium, "半天未佩戴设备。"),
            (-3, 18, .highIntensityExercise, .high, "这次训练量比平时高。"),
            (-2, 16, .caffeine, .medium, "下午临时加了一杯咖啡。"),
            (0, 10, .deadline, .high, "本周仍有一项截止日。")
        ]
        events = eventDrafts.enumerated().compactMap { position, item in
            guard let day = calendar.date(byAdding: .day, value: item.0, to: finalDay),
                  let start = calendar.date(bySettingHour: item.1, minute: 0, second: 0, of: day)
            else { return nil }
            return try? ContextEvent(
                id: Self.uuid(100 + position),
                kind: item.2,
                startedAt: start,
                intensity: item.3,
                note: item.4,
                createdAt: start
            )
        }
    }

    func save(_ record: DailyCheckIn) throws -> DailyCheckIn {
        checkInsByDay[record.localDay.storageKey] = record
        return record
    }

    func checkIn(on day: SubjectiveLocalDay) throws -> DailyCheckIn? {
        checkInsByDay[day.storageKey]
    }

    func deleteCheckIn(on day: SubjectiveLocalDay) throws {
        checkInsByDay.removeValue(forKey: day.storageKey)
    }

    func save(_ event: ContextEvent) throws {
        events.removeAll { $0.id == event.id }
        events.append(event)
    }

    func contextEvents(overlapping interval: DateInterval) throws -> [ContextEvent] {
        events.filter {
            $0.startedAt < interval.end && ($0.endedAt ?? $0.startedAt) >= interval.start
        }.sorted { $0.startedAt < $1.startedAt }
    }

    func deleteContextEvent(id: UUID) throws {
        events.removeAll { $0.id == id }
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "10000000-0000-4000-8000-%012X",
            value
        ))!
    }
}
