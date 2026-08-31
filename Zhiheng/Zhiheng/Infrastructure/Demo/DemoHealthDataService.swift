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

        for index in 0..<35 {
            guard let day = calendar.date(byAdding: .day, value: index - 34, to: finalDay),
                  let sleepEnd = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: day)
            else { throw HealthDataServiceError.queryFailed }
            let recentOffset = Double(max(index - 27, 0))
            let sleepHours = 7.2 + Double(index % 4) * 0.12
            let awakeHours = 0.22
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
            try append(metric: .heartRateVariability, value: 47 + Double(index % 5), day: day, hour: 7, to: &drafts, calendar: calendar)
            if index == 34 {
                for (hour, value) in [
                    (0, 58.0), (2, 61.0), (4, 57.0), (6, 60.0),
                    (8, 49.0), (9, 45.0), (10, 41.0)
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
            try append(metric: .restingHeartRate, value: 58 + Double(index % 3), day: day, hour: 8, to: &drafts, calendar: calendar)
            for (hour, fraction) in [
                (1, 0.04), (3, 0.03), (5, 0.05), (7, 0.07), (9, 0.11),
                (11, 0.16), (13, 0.14), (16, 0.16), (19, 0.14), (21, 0.10)
            ] {
                try append(metric: .stepCount, value: (5_200 + recentOffset * 280) * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
                try append(metric: .activeEnergy, value: (340 + recentOffset * 18) * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
                try append(metric: .walkingRunningDistance, value: (4.1 + recentOffset * 0.18) * fraction, day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            try append(metric: .exerciseDuration, value: 24 + Double(index % 5) * 3, day: day, hour: 18, to: &drafts, calendar: calendar)
            for hour in 9..<(9 + min(8 + index % 4, 12)) {
                try append(metric: .standHours, value: 1, day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            for hour in [1, 3, 5] {
                try append(metric: .heartRate, value: 55 + Double((index + hour) % 5), day: day, hour: hour, to: &drafts, calendar: calendar)
            }
            try append(metric: .respiratoryRate, value: 15.2 + Double(index % 4) * 0.2, day: day, hour: 4, to: &drafts, calendar: calendar)
            try append(metric: .oxygenSaturation, value: 97 + Double(index % 3) * 0.3, day: day, hour: 4, to: &drafts, calendar: calendar)
            try append(metric: .wristTemperature, value: 35.7 + Double(index % 3) * 0.05, day: day, hour: 6, to: &drafts, calendar: calendar)
            try append(metric: .flightsClimbed, value: 5 + Double(index % 5), day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .walkingSpeed, value: 1.18 + Double(index % 4) * 0.02, day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .walkingStepLength, value: 0.68 + Double(index % 4) * 0.01, day: day, hour: 8, to: &drafts, calendar: calendar)
            try append(metric: .vo2Max, value: 38 + Double(index % 4) * 0.3, day: day, hour: 8, to: &drafts, calendar: calendar)
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
