import Foundation

struct CarePlanID: Hashable, Codable, Sendable {
    let rawValue: String
}

struct CareTaskID: Hashable, Codable, Sendable {
    let rawValue: String
}

enum MicroPlanStatus: String, Codable, Sendable {
    case draft
    case active
    case paused
    case completed
    case endedEarly
}

struct ScheduledLocalTime: Equatable, Codable, Sendable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw CarePlanModelError.invalidLocalTime
        }
        self.hour = hour
        self.minute = minute
    }
}

struct MicroPlanDraft: Equatable, Sendable {
    let id: CarePlanID
    let title: String
    let taskID: CareTaskID
    let taskTitle: String
    let startDate: Date

    /// 排除式结束边界。三天计划从第 1 天零点开始，在第 4 天零点结束。
    let endDateExclusive: Date
    let scheduledTime: ScheduledLocalTime
    let templateID: MicroPlanTemplateID?

    init(
        id: CarePlanID,
        title: String,
        taskID: CareTaskID,
        taskTitle: String,
        startDate: Date,
        endDateExclusive: Date,
        scheduledTime: ScheduledLocalTime,
        templateID: MicroPlanTemplateID? = nil
    ) {
        self.id = id
        self.title = title
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startDate = startDate
        self.endDateExclusive = endDateExclusive
        self.scheduledTime = scheduledTime
        self.templateID = templateID
    }
}

struct MicroPlan: Equatable, Sendable {
    let draft: MicroPlanDraft
    let status: MicroPlanStatus
}

enum PlanOutcomeState: String, Codable, Sendable {
    case completed
    case skipped
}

struct PlanOutcomeInput: Equatable, Sendable {
    let taskID: CareTaskID
    let occurrenceIndex: Int
    let state: PlanOutcomeState
    let recordedAt: Date
    let difficulty: Int?

    init(
        taskID: CareTaskID,
        occurrenceIndex: Int,
        state: PlanOutcomeState,
        recordedAt: Date,
        difficulty: Int?
    ) throws {
        guard occurrenceIndex >= 0 else {
            throw CarePlanModelError.invalidOccurrenceIndex
        }
        if let difficulty, !(1...5).contains(difficulty) {
            throw CarePlanModelError.invalidDifficulty
        }

        self.taskID = taskID
        self.occurrenceIndex = occurrenceIndex
        self.state = state
        self.recordedAt = recordedAt
        self.difficulty = difficulty
    }
}

struct MicroPlanProgress: Equatable, Sendable {
    let scheduledCount: Int
    let completedCount: Int
    let skippedCount: Int

    init(scheduledCount: Int, completedCount: Int, skippedCount: Int) throws {
        guard scheduledCount >= 0, completedCount >= 0, skippedCount >= 0 else {
            throw CarePlanModelError.invalidProgressCounts
        }
        guard completedCount + skippedCount <= scheduledCount else {
            throw CarePlanModelError.invalidProgressCounts
        }

        self.scheduledCount = scheduledCount
        self.completedCount = completedCount
        self.skippedCount = skippedCount
    }

    var completionFraction: Double? {
        guard scheduledCount > 0 else { return nil }
        return Double(completedCount) / Double(scheduledCount)
    }

    var unresolvedCount: Int {
        scheduledCount - completedCount - skippedCount
    }
}

enum CarePlanModelError: Error, Equatable, Sendable {
    case invalidLocalTime
    case invalidOccurrenceIndex
    case invalidDifficulty
    case invalidProgressCounts
    case invalidPlanDateRange
}

struct MicroPlanTemplate: Equatable, Sendable {
    let id: MicroPlanTemplateID
    let title: String
    let taskTitle: String
    let durationDays: Int
    let scheduledTime: ScheduledLocalTime

    func makeDraft(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        uniqueID: UUID = UUID()
    ) throws -> MicroPlanDraft {
        let startDate = calendar.startOfDay(for: referenceDate)
        guard let endDateExclusive = calendar.date(
            byAdding: .day,
            value: durationDays,
            to: startDate
        ) else {
            throw CarePlanModelError.invalidPlanDateRange
        }
        let suffix = uniqueID.uuidString.lowercased()
        return MicroPlanDraft(
            id: CarePlanID(rawValue: "microplan.\(id.rawValue).\(suffix)"),
            title: title,
            taskID: CareTaskID(rawValue: "task.\(id.rawValue).\(suffix)"),
            taskTitle: taskTitle,
            startDate: startDate,
            endDateExclusive: endDateExclusive,
            scheduledTime: scheduledTime,
            templateID: id
        )
    }
}

enum MicroPlanTemplateLibrary {
    static let all: [MicroPlanTemplate] = [
        template(
            .afternoonCaffeineCutoff,
            title: "下午咖啡截止",
            task: "15:00 后不摄入含咖啡因饮品",
            hour: 15
        ),
        template(
            .earlierBedtime,
            title: "提前上床",
            task: "比平时提前 30 分钟上床",
            hour: 22,
            minute: 30
        ),
        template(
            .afternoonWalk,
            title: "午后步行",
            task: "午后轻松步行 10 分钟",
            hour: 15
        ),
        template(
            .movementBreak,
            title: "工作间歇活动",
            task: "安排一次 5 分钟活动间歇",
            hour: 15
        ),
        template(
            .reducedTrainingLoad,
            title: "短期降低运动负荷",
            task: "今天把训练强度降低一级",
            hour: 18
        ),
        template(
            .bedtimeBreathing,
            title: "睡前呼吸",
            task: "睡前做 5 分钟缓慢呼吸",
            hour: 22
        ),
        template(
            .morningDaylight,
            title: "晨间日光",
            task: "起床后到户外接触自然光 10 分钟",
            hour: 8
        ),
        template(
            .afterMealWalk,
            title: "饭后散步",
            task: "晚餐后轻松步行 10 分钟",
            hour: 19,
            minute: 30
        ),
        template(
            .consistentWakeTime,
            title: "固定起床时间",
            task: "在目标时间前后 30 分钟内起床",
            hour: 7,
            minute: 30
        ),
        template(
            .gentleMobility,
            title: "轻柔活动",
            task: "做 8 分钟轻柔拉伸或关节活动",
            hour: 18
        ),
    ].compactMap { $0 }

    static func template(for id: MicroPlanTemplateID) -> MicroPlanTemplate? {
        all.first(where: { $0.id == id })
    }

    static func templateID(for draft: MicroPlanDraft) -> MicroPlanTemplateID? {
        if let templateID = draft.templateID { return templateID }
        return all.first { template in
            draft.id.rawValue.contains(template.id.rawValue)
                || draft.taskID.rawValue.contains(template.id.rawValue)
                || draft.title == template.title
        }?.id
    }

    private static func template(
        _ id: MicroPlanTemplateID,
        title: String,
        task: String,
        hour: Int,
        minute: Int = 0
    ) -> MicroPlanTemplate? {
        guard let scheduledTime = try? ScheduledLocalTime(
            hour: hour,
            minute: minute
        ) else { return nil }
        return MicroPlanTemplate(
            id: id,
            title: title,
            taskTitle: task,
            durationDays: 5,
            scheduledTime: scheduledTime
        )
    }
}

enum MicroPlanTrendMetric: String, Equatable, Identifiable, Sendable {
    case sleepOnset
    case sleepDuration
    case stepCount
    case activeEnergy
    case standHours
    case exerciseDuration
    case heartRateVariability
    case walkingRunningDistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepOnset: "入睡时间"
        case .sleepDuration: "睡眠时长"
        case .stepCount: "步数"
        case .activeEnergy: "活动能量"
        case .standHours: "站立小时"
        case .exerciseDuration: "运动分钟"
        case .heartRateVariability: "HRV"
        case .walkingRunningDistance: "步行与跑步距离"
        }
    }

    var healthMetric: HealthMetricType? {
        switch self {
        case .sleepOnset: nil
        case .sleepDuration: .sleepDuration
        case .stepCount: .stepCount
        case .activeEnergy: .activeEnergy
        case .standHours: .standHours
        case .exerciseDuration: .exerciseDuration
        case .heartRateVariability: .heartRateVariability
        case .walkingRunningDistance: .walkingRunningDistance
        }
    }
}

struct MicroPlanTrendPoint: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct MicroPlanTrendPresentation: Identifiable, Equatable, Sendable {
    var id: MicroPlanTrendMetric { metric }
    let metric: MicroPlanTrendMetric
    let points: [MicroPlanTrendPoint]
    let planStartDate: Date
    let beforeMedian: Double?
    let planMedian: Double?
    let beforeValidDayCount: Int
    let planValidDayCount: Int

    var latestValue: Double? { points.last?.value }

    var changeFromBefore: Double? {
        guard beforeValidDayCount >= 2, planValidDayCount >= 2,
              let beforeMedian, let planMedian else { return nil }
        return planMedian - beforeMedian
    }
}

enum MicroPlanTrendPresentationFactory {
    static func metrics(for templateID: MicroPlanTemplateID) -> [MicroPlanTrendMetric] {
        switch templateID {
        case .afternoonCaffeineCutoff, .earlierBedtime, .bedtimeBreathing,
             .morningDaylight, .consistentWakeTime:
            [.sleepOnset, .sleepDuration]
        case .afternoonWalk:
            [.stepCount, .activeEnergy]
        case .afterMealWalk:
            [.stepCount, .walkingRunningDistance]
        case .movementBreak:
            [.standHours, .stepCount]
        case .reducedTrainingLoad:
            [.exerciseDuration, .heartRateVariability]
        case .gentleMobility:
            [.exerciseDuration, .activeEnergy]
        }
    }

    static func make(
        plan: MicroPlan,
        snapshot: HealthDataSnapshot?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [MicroPlanTrendPresentation] {
        guard let templateID = MicroPlanTemplateLibrary.templateID(for: plan.draft) else {
            return []
        }
        let start = calendar.startOfDay(for: plan.draft.startDate)
        let finalPlanDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: plan.draft.endDateExclusive
        ) ?? start
        let followUpEnd = calendar.date(byAdding: .day, value: 2, to: finalPlanDay)
            ?? finalPlanDay
        let end = min(calendar.startOfDay(for: referenceDate), followUpEnd)
        let comparisonStart = calendar.date(byAdding: .day, value: -5, to: start)
            ?? start

        return metrics(for: templateID).map { metric in
            let points = points(
                for: metric,
                snapshot: snapshot,
                endingAt: end,
                startingAt: comparisonStart,
                calendar: calendar
            )
            let beforeValues = points.filter { $0.date < start }.map(\.value)
            let planValues = points.filter {
                $0.date >= start && $0.date <= min(end, finalPlanDay)
            }.map(\.value)
            return MicroPlanTrendPresentation(
                metric: metric,
                points: points,
                planStartDate: start,
                beforeMedian: median(beforeValues),
                planMedian: median(planValues),
                beforeValidDayCount: beforeValues.count,
                planValidDayCount: planValues.count
            )
        }
    }

    private static func points(
        for metric: MicroPlanTrendMetric,
        snapshot: HealthDataSnapshot?,
        endingAt end: Date,
        startingAt start: Date,
        calendar: Calendar
    ) -> [MicroPlanTrendPoint] {
        guard let snapshot else { return [] }
        if metric == .sleepOnset || metric == .sleepDuration {
            guard case let .available(samples) = snapshot[.sleepDuration] else {
                return []
            }
            return nightlySleepPoints(
                metric: metric,
                samples: samples,
                startingAt: start,
                endingAt: end,
                calendar: calendar
            )
        }
        guard let healthMetric = metric.healthMetric,
              case let .available(samples) = snapshot[healthMetric] else {
            return []
        }
        return HealthMetricDailySeriesCalculator.points(
            metric: healthMetric,
            samples: samples,
            endingAt: end,
            window: .twentyEightDays,
            calendar: calendar
        )
        .filter { $0.date >= start && $0.date <= end }
        .map { MicroPlanTrendPoint(date: $0.date, value: $0.value) }
    }

    private static func nightlySleepPoints(
        metric: MicroPlanTrendMetric,
        samples: [HealthMetricSample],
        startingAt start: Date,
        endingAt end: Date,
        calendar: Calendar
    ) -> [MicroPlanTrendPoint] {
        let grouped = Dictionary(grouping: samples) { sample in
            let day = calendar.startOfDay(for: sample.endDate)
            let endHour = calendar.component(.hour, from: sample.endDate)
            if endHour >= 18 {
                return calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return day
        }

        return grouped.compactMap { wakeDay, nightSamples in
            guard wakeDay >= start, wakeDay <= end,
                  let selected = PreferredHealthMetricSourceSelector.samples(
                    from: nightSamples
                  ) else { return nil }
            let asleep = selected.filter {
                $0.sleepStage != .awake && $0.value > 0
            }
            guard !asleep.isEmpty else { return nil }
            let value: Double
            if metric == .sleepOnset {
                guard let onset = asleep.map(\.startDate).min() else { return nil }
                let components = calendar.dateComponents([.hour, .minute], from: onset)
                let hour = Double(components.hour ?? 0)
                let minute = Double(components.minute ?? 0) / 60
                value = hour < 12 ? hour + 24 + minute : hour + minute
            } else {
                value = asleep.reduce(0) { $0 + $1.value }
            }
            return MicroPlanTrendPoint(date: wakeDay, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
