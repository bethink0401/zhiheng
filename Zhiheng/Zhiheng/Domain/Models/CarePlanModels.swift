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
    static let maximumFeedbackLength = 160

    let taskID: CareTaskID
    let occurrenceIndex: Int
    let state: PlanOutcomeState
    let recordedAt: Date
    let difficulty: Int?
    let feedback: String?

    init(
        taskID: CareTaskID,
        occurrenceIndex: Int,
        state: PlanOutcomeState,
        recordedAt: Date,
        difficulty: Int?,
        feedback: String? = nil
    ) throws {
        guard occurrenceIndex >= 0 else {
            throw CarePlanModelError.invalidOccurrenceIndex
        }
        if let difficulty, !(1...5).contains(difficulty) {
            throw CarePlanModelError.invalidDifficulty
        }

        let normalizedFeedback = feedback?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let normalizedFeedback,
           normalizedFeedback.count > Self.maximumFeedbackLength {
            throw CarePlanModelError.invalidFeedback
        }

        self.taskID = taskID
        self.occurrenceIndex = occurrenceIndex
        self.state = state
        self.recordedAt = recordedAt
        self.difficulty = difficulty
        self.feedback = normalizedFeedback?.isEmpty == false
            ? normalizedFeedback
            : nil
    }
}

struct PlanOutcomeRecord: Equatable, Sendable {
    let occurrenceIndex: Int
    let state: PlanOutcomeState
    let recordedAt: Date
    let feedback: String?
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
    case invalidFeedback
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

enum MicroPlanTrendMetric: String, Codable, Equatable, Identifiable, Sendable {
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

struct MicroPlanBaselineMetricSnapshot: Codable, Equatable, Sendable {
    let metric: MicroPlanTrendMetric
    let median: Double?
    let validDayCount: Int
}

struct MicroPlanBaselineSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let carePlanID: CarePlanID
    let planStartDate: Date
    let capturedAt: Date
    let dataMode: HealthDataMode
    let metrics: [MicroPlanBaselineMetricSnapshot]
    let schemaVersion: Int

    func metric(_ metric: MicroPlanTrendMetric) -> MicroPlanBaselineMetricSnapshot? {
        metrics.first { $0.metric == metric }
    }
}

enum MicroPlanEvaluationVerdict: String, Codable, Equatable, Sendable {
    case mayHaveHelped
    case noClearChange
    case insufficientExecution
    case insufficientData
    case subjectiveObjectiveMismatch

    var title: String {
        switch self {
        case .mayHaveHelped: "可能有帮助"
        case .noClearChange: "暂未观察到明显变化"
        case .insufficientExecution: "执行不足，暂时无法判断"
        case .insufficientData: "数据不足，建议继续观察"
        case .subjectiveObjectiveMismatch: "主观和客观结果不同步"
        }
    }
}

enum MicroPlanEvaluationDirection: String, Codable, Equatable, Sendable {
    case favorable
    case neutral
    case unfavorable
}

struct MicroPlanEvaluationMetricFact: Codable, Equatable, Sendable {
    let metric: MicroPlanTrendMetric
    let healthMetric: HealthMetricType?
    let beforeMedian: Double
    let planMedian: Double
    let changeFromBefore: Double
    let beforeValidDayCount: Int
    let planValidDayCount: Int
    let direction: MicroPlanEvaluationDirection
}

struct MicroPlanEvaluationFactPack: Codable, Equatable, Sendable {
    let planID: String
    let planTitle: String
    let taskTitle: String
    let status: MicroPlanStatus
    let scheduledCount: Int
    let completedCount: Int
    let skippedCount: Int
    let completionRate: Double?
    let userFeedback: [String]
    let metrics: [MicroPlanEvaluationMetricFact]
    let dataQualitySummary: String
    let localVerdict: MicroPlanEvaluationVerdict
}

struct MicroPlanEvaluationPresentation: Equatable, Sendable {
    let factPack: MicroPlanEvaluationFactPack
    let summary: String

    var verdict: MicroPlanEvaluationVerdict { factPack.localVerdict }
}

enum MicroPlanEvaluationFactory {
    static let minimumCompletionRate = 0.6

    static func make(
        plan: MicroPlan,
        progress: MicroPlanProgress,
        outcomes: [PlanOutcomeRecord],
        trends: [MicroPlanTrendPresentation]
    ) -> MicroPlanEvaluationPresentation {
        let metricFacts = trends.compactMap { trend -> MicroPlanEvaluationMetricFact? in
            guard trend.hasFrozenBaseline,
                  let beforeMedian = trend.beforeMedian,
                  let planMedian = trend.planMedian,
                  let change = trend.changeFromBefore else { return nil }
            return MicroPlanEvaluationMetricFact(
                metric: trend.metric,
                healthMetric: trend.metric.healthMetric,
                beforeMedian: beforeMedian,
                planMedian: planMedian,
                changeFromBefore: change,
                beforeValidDayCount: trend.beforeValidDayCount,
                planValidDayCount: trend.planValidDayCount,
                direction: direction(
                    for: trend.metric,
                    templateID: MicroPlanTemplateLibrary.templateID(for: plan.draft),
                    beforeMedian: beforeMedian,
                    change: change
                )
            )
        }
        let feedback = outcomes.compactMap(\.feedback)
        let verdict: MicroPlanEvaluationVerdict
        if progress.scheduledCount == 0
            || (progress.completionFraction ?? 0) < minimumCompletionRate {
            verdict = .insufficientExecution
        } else if metricFacts.isEmpty {
            verdict = .insufficientData
        } else if metricFacts.filter({ $0.direction == .favorable }).count
                    > metricFacts.filter({ $0.direction == .unfavorable }).count {
            verdict = .mayHaveHelped
        } else {
            verdict = .noClearChange
        }

        let hasFrozenBaseline = trends.contains { $0.hasFrozenBaseline }
        let hasMismatchedDataMode = trends.contains { $0.hasMismatchedDataMode }
        let qualitySummary: String
        if hasMismatchedDataMode {
            qualitySummary = "计划开始基线与当前数据来源不同，无法形成可靠评估"
        } else if !trends.isEmpty && !hasFrozenBaseline {
            qualitySummary = "计划开始基线未保存，无法形成可靠历史评估"
        } else if metricFacts.isEmpty {
            qualitySummary = "相关指标在计划前或计划期间不足 2 个有效日"
        } else {
            qualitySummary = "\(metricFacts.count) 项相关指标具备计划前后对照"
        }
        let factPack = MicroPlanEvaluationFactPack(
            planID: plan.draft.id.rawValue,
            planTitle: plan.draft.title,
            taskTitle: plan.draft.taskTitle,
            status: plan.status,
            scheduledCount: progress.scheduledCount,
            completedCount: progress.completedCount,
            skippedCount: progress.skippedCount,
            completionRate: progress.completionFraction,
            userFeedback: feedback,
            metrics: metricFacts,
            dataQualitySummary: qualitySummary,
            localVerdict: verdict
        )
        return MicroPlanEvaluationPresentation(
            factPack: factPack,
            summary: summary(for: verdict)
        )
    }

    private static func direction(
        for metric: MicroPlanTrendMetric,
        templateID: MicroPlanTemplateID?,
        beforeMedian: Double,
        change: Double
    ) -> MicroPlanEvaluationDirection {
        let threshold = metric == .sleepOnset
            ? 0.25
            : max(abs(beforeMedian) * 0.05, 0.01)
        guard abs(change) >= threshold else { return .neutral }
        let expectsDecrease = metric == .sleepOnset
            || (templateID == .reducedTrainingLoad && metric == .exerciseDuration)
        let favorable = expectsDecrease ? change < 0 : change > 0
        return favorable ? .favorable : .unfavorable
    }

    private static func summary(for verdict: MicroPlanEvaluationVerdict) -> String {
        switch verdict {
        case .mayHaveHelped:
            "完成率达到评估门槛，相关指标也出现同方向变化。可以先记为可能有帮助，但不能说明是计划造成的。"
        case .noClearChange:
            "完成率足以评估，但相关指标暂未出现一致变化。先保留这次记录，不必急着下结论。"
        case .insufficientExecution:
            "目前完成次数还不足以判断这个计划是否适合你。可以缩小行动或换到更容易执行的时间。"
        case .insufficientData:
            "相关健康数据还不足以形成可靠对照，建议继续观察。"
        case .subjectiveObjectiveMismatch:
            "你的反馈和客观指标没有同步变化，两边都值得保留，暂时不要用一边否定另一边。"
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
    let hasFrozenBaseline: Bool
    let hasMismatchedDataMode: Bool

    init(
        metric: MicroPlanTrendMetric,
        points: [MicroPlanTrendPoint],
        planStartDate: Date,
        beforeMedian: Double?,
        planMedian: Double?,
        beforeValidDayCount: Int,
        planValidDayCount: Int,
        hasFrozenBaseline: Bool = true,
        hasMismatchedDataMode: Bool = false
    ) {
        self.metric = metric
        self.points = points
        self.planStartDate = planStartDate
        self.beforeMedian = beforeMedian
        self.planMedian = planMedian
        self.beforeValidDayCount = beforeValidDayCount
        self.planValidDayCount = planValidDayCount
        self.hasFrozenBaseline = hasFrozenBaseline
        self.hasMismatchedDataMode = hasMismatchedDataMode
    }

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
        baseline: MicroPlanBaselineSnapshot? = nil,
        dataMode: HealthDataMode? = nil,
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
            let linkedBaseline = baseline?.carePlanID == plan.draft.id
                && calendar.isDate(
                    baseline?.planStartDate ?? .distantPast,
                    inSameDayAs: start
                )
                ? baseline
                : nil
            let hasMismatchedDataMode = linkedBaseline != nil
                && dataMode != nil
                && linkedBaseline?.dataMode != dataMode
            let frozenMetric = hasMismatchedDataMode
                ? nil
                : linkedBaseline?.metric(metric)
            let beforeMedian: Double?
            let beforeValidDayCount: Int
            if let frozenMetric {
                beforeMedian = frozenMetric.median
                beforeValidDayCount = frozenMetric.validDayCount
            } else {
                beforeMedian = median(beforeValues)
                beforeValidDayCount = beforeValues.count
            }
            return MicroPlanTrendPresentation(
                metric: metric,
                points: points,
                planStartDate: start,
                beforeMedian: beforeMedian,
                planMedian: median(planValues),
                beforeValidDayCount: beforeValidDayCount,
                planValidDayCount: planValues.count,
                hasFrozenBaseline: frozenMetric != nil,
                hasMismatchedDataMode: hasMismatchedDataMode
            )
        }
    }

    static func captureBaseline(
        for draft: MicroPlanDraft,
        snapshot: HealthDataSnapshot?,
        dataMode: HealthDataMode,
        capturedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> MicroPlanBaselineSnapshot {
        let start = calendar.startOfDay(for: draft.startDate)
        let comparisonStart = calendar.date(byAdding: .day, value: -5, to: start)
            ?? start
        let comparisonEnd = calendar.date(byAdding: .day, value: -1, to: start)
            ?? start
        let templateMetrics: [MicroPlanTrendMetric]
        if let templateID = MicroPlanTemplateLibrary.templateID(for: draft) {
            templateMetrics = metrics(for: templateID)
        } else {
            templateMetrics = []
        }
        let baselineMetrics = templateMetrics.map { metric in
            let values = points(
                for: metric,
                snapshot: snapshot,
                endingAt: comparisonEnd,
                startingAt: comparisonStart,
                calendar: calendar
            ).map(\.value)
            return MicroPlanBaselineMetricSnapshot(
                metric: metric,
                median: median(values),
                validDayCount: values.count
            )
        }
        return MicroPlanBaselineSnapshot(
            carePlanID: draft.id,
            planStartDate: start,
            capturedAt: capturedAt,
            dataMode: dataMode,
            metrics: baselineMetrics,
            schemaVersion: MicroPlanBaselineSnapshot.currentSchemaVersion
        )
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
