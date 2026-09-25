import Foundation

/// “我的有效方法”形成前的只读来源投影。
///
/// 这里直接保留 CareKit 适配层返回的计划和 Outcome 领域值，不把执行事实复制到
/// SwiftData。完成率在本投影中由 CareKit 进度形成并经 Outcomes 核对；效果和可信度
/// 由后续任务基于这些来源值计算。
struct EffectiveMethodCandidateRun: Equatable, Sendable {
    let plan: MicroPlan
    let outcomes: [PlanOutcomeRecord]
    let completion: EffectiveMethodCompletionFact

    fileprivate init?(
        plan: MicroPlan,
        outcomes: [PlanOutcomeRecord],
        progress: MicroPlanProgress
    ) throws {
        guard plan.status == .completed || plan.status == .endedEarly else {
            return nil
        }
        self.plan = plan
        self.outcomes = outcomes
        self.completion = try EffectiveMethodCompletionFact(
            progress: progress,
            outcomes: outcomes
        )
    }
}

enum EffectiveMethodCompletionFactError: Error, Equatable, Sendable {
    case duplicateOutcomeOccurrence
    case outcomeOutsideSchedule
    case progressOutcomeMismatch
}

/// 完成率的唯一分母和计数来自 CareKit 进度查询；Outcomes 用于逐次核对。
struct EffectiveMethodCompletionFact: Equatable, Sendable {
    let scheduledCount: Int
    let completedCount: Int
    let skippedCount: Int
    let unresolvedCount: Int
    let recordedOutcomeCount: Int
    let completionRate: Double?

    fileprivate init(
        progress: MicroPlanProgress,
        outcomes: [PlanOutcomeRecord]
    ) throws {
        let occurrenceIndexes = outcomes.map(\.occurrenceIndex)
        guard Set(occurrenceIndexes).count == occurrenceIndexes.count else {
            throw EffectiveMethodCompletionFactError.duplicateOutcomeOccurrence
        }
        guard occurrenceIndexes.allSatisfy({
            $0 >= 0 && $0 < progress.scheduledCount
        }) else {
            throw EffectiveMethodCompletionFactError.outcomeOutsideSchedule
        }

        let completedOutcomeCount = outcomes.filter {
            $0.state == .completed
        }.count
        let skippedOutcomeCount = outcomes.filter {
            $0.state == .skipped
        }.count
        guard
            completedOutcomeCount == progress.completedCount,
            skippedOutcomeCount == progress.skippedCount
        else {
            throw EffectiveMethodCompletionFactError.progressOutcomeMismatch
        }

        scheduledCount = progress.scheduledCount
        completedCount = progress.completedCount
        skippedCount = progress.skippedCount
        unresolvedCount = progress.unresolvedCount
        recordedOutcomeCount = outcomes.count
        completionRate = progress.completionFraction
    }

    fileprivate init(aggregating facts: [EffectiveMethodCompletionFact]) {
        let totalScheduledCount = facts.reduce(0) { $0 + $1.scheduledCount }
        let totalCompletedCount = facts.reduce(0) { $0 + $1.completedCount }
        scheduledCount = totalScheduledCount
        completedCount = totalCompletedCount
        skippedCount = facts.reduce(0) { $0 + $1.skippedCount }
        unresolvedCount = facts.reduce(0) { $0 + $1.unresolvedCount }
        recordedOutcomeCount = facts.reduce(0) { $0 + $1.recordedOutcomeCount }
        completionRate = totalScheduledCount > 0
            ? Double(totalCompletedCount) / Double(totalScheduledCount)
            : nil
    }
}

struct EffectiveMethodCandidate: Identifiable, Equatable, Sendable {
    let sourcePlanTemplateID: MicroPlanTemplateID
    let title: String
    let runs: [EffectiveMethodCandidateRun]
    let completion: EffectiveMethodCompletionFact

    var id: String {
        "effective-method-candidate.\(sourcePlanTemplateID.rawValue)"
    }

    var lastRunDate: Date {
        runs[0].plan.draft.endDateExclusive
    }

    fileprivate init?(
        sourcePlanTemplateID: MicroPlanTemplateID,
        title: String,
        runs: [EffectiveMethodCandidateRun]
    ) {
        guard !runs.isEmpty else { return nil }
        self.sourcePlanTemplateID = sourcePlanTemplateID
        self.title = title
        self.runs = runs
        self.completion = EffectiveMethodCompletionFact(
            aggregating: runs.map(\.completion)
        )
    }
}

enum EffectiveMethodConfidenceLevel: String, Equatable, Sendable {
    case preliminaryObservation
    case possiblySuitable
    case fairlyStable
    case unclear

    var title: String {
        switch self {
        case .preliminaryObservation: "初步观察"
        case .possiblySuitable: "可能适合"
        case .fairlyStable: "较稳定"
        case .unclear: "不明确"
        }
    }
}

enum EffectiveMethodConfidenceReason: String, Equatable, Sendable {
    case oneAssessableRun
    case twoConsistentHelpfulRuns
    case repeatedConsistentHelpfulRuns
    case missingEvaluation
    case invalidEvaluationSources
    case insufficientExecution
    case insufficientData
    case subjectiveObjectiveMismatch
    case inconsistentResults
    case noConsistentBenefit
}

enum EffectiveMethodRunDataQuality: String, Equatable, Sendable {
    case sufficient
    case insufficient
    case unavailable
}

enum EffectiveMethodSubjectiveDimension: String, CaseIterable, Equatable, Sendable {
    case energy
    case stress
    case bodyFeeling

    var title: String {
        switch self {
        case .energy: "精力"
        case .stress: "压力"
        case .bodyFeeling: "身体感受"
        }
    }
}

struct EffectiveMethodSubjectiveMetricFact: Equatable, Sendable {
    let dimension: EffectiveMethodSubjectiveDimension
    let beforeMedian: Double
    let planMedian: Double

    var changeFromBefore: Double { planMedian - beforeMedian }
}

enum EffectiveMethodSubjectiveRunState: String, Equatable, Sendable {
    case available
    case notRecorded
    case insufficient
    case unavailable
}

/// 一次计划的结构化每日感受对照。备注和 CareKit 反馈文本不会进入本事实。
struct EffectiveMethodSubjectiveRunChange: Equatable, Sendable {
    static let minimumRecordedDayCount = 2
    static let unavailable = EffectiveMethodSubjectiveRunChange(
        state: .unavailable,
        metrics: [],
        beforeRecordedDayCount: 0,
        planRecordedDayCount: 0
    )

    let state: EffectiveMethodSubjectiveRunState
    let metrics: [EffectiveMethodSubjectiveMetricFact]
    let beforeRecordedDayCount: Int
    let planRecordedDayCount: Int

    static func make(
        before: [DailyCheckIn],
        duringPlan: [DailyCheckIn]
    ) -> Self {
        guard !before.isEmpty || !duringPlan.isEmpty else {
            return EffectiveMethodSubjectiveRunChange(
                state: .notRecorded,
                metrics: [],
                beforeRecordedDayCount: 0,
                planRecordedDayCount: 0
            )
        }
        guard before.count >= minimumRecordedDayCount,
              duringPlan.count >= minimumRecordedDayCount else {
            return EffectiveMethodSubjectiveRunChange(
                state: .insufficient,
                metrics: [],
                beforeRecordedDayCount: before.count,
                planRecordedDayCount: duringPlan.count
            )
        }
        let metrics = EffectiveMethodSubjectiveDimension.allCases.map { dimension in
            EffectiveMethodSubjectiveMetricFact(
                dimension: dimension,
                beforeMedian: median(before.map { value(for: dimension, in: $0) }),
                planMedian: median(duringPlan.map { value(for: dimension, in: $0) })
            )
        }
        return EffectiveMethodSubjectiveRunChange(
            state: .available,
            metrics: metrics,
            beforeRecordedDayCount: before.count,
            planRecordedDayCount: duringPlan.count
        )
    }

    private static func value(
        for dimension: EffectiveMethodSubjectiveDimension,
        in checkIn: DailyCheckIn
    ) -> Double {
        switch dimension {
        case .energy: Double(checkIn.energy.rawValue)
        case .stress: Double(checkIn.stress.rawValue)
        case .bodyFeeling: Double(checkIn.bodyFeeling.rawValue)
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

/// 一次计划的本地评估引用。稳定计划 ID 用于和 CareKit 执行来源逐次对应；
/// 客观项只含聚合中位数，主观项只含结构化 1～5 分，不保存自由文本或原始样本。
struct EffectiveMethodRunEvaluationFact: Equatable, Sendable {
    let carePlanID: CarePlanID
    let verdict: MicroPlanEvaluationVerdict
    let dataQuality: EffectiveMethodRunDataQuality
    let objectiveDataQuality: EffectiveMethodRunDataQuality
    let objectiveMetrics: [MicroPlanEvaluationMetricFact]
    let subjectiveChange: EffectiveMethodSubjectiveRunChange

    init(
        carePlanID: CarePlanID,
        verdict: MicroPlanEvaluationVerdict,
        dataQuality: EffectiveMethodRunDataQuality = .sufficient,
        objectiveDataQuality: EffectiveMethodRunDataQuality? = nil,
        objectiveMetrics: [MicroPlanEvaluationMetricFact] = [],
        subjectiveChange: EffectiveMethodSubjectiveRunChange = .unavailable
    ) {
        self.carePlanID = carePlanID
        self.verdict = verdict
        self.dataQuality = dataQuality
        self.objectiveDataQuality = objectiveDataQuality
            ?? (objectiveMetrics.isEmpty ? .insufficient : .sufficient)
        self.objectiveMetrics = objectiveMetrics
        self.subjectiveChange = subjectiveChange
    }
}

struct EffectiveMethodConfidence: Equatable, Sendable {
    let level: EffectiveMethodConfidenceLevel
    let reason: EffectiveMethodConfidenceReason
    let totalRunCount: Int
    let assessableRunCount: Int
    let helpfulRunCount: Int
    let ruleVersion: String
}

enum EffectiveMethodDataQualityLevel: String, Equatable, Sendable {
    case sufficient
    case partial
    case insufficient
    case unavailable

    var title: String {
        switch self {
        case .sufficient: "可判断"
        case .partial: "部分可判断"
        case .insufficient: "数据不足"
        case .unavailable: "暂时无法读取"
        }
    }
}

struct EffectiveMethodDataQuality: Equatable, Sendable {
    let level: EffectiveMethodDataQualityLevel
    let totalRunCount: Int
    let sufficientRunCount: Int
    let insufficientRunCount: Int
    let unavailableRunCount: Int

    var detail: String {
        switch level {
        case .sufficient:
            "全部 \(totalRunCount) 次都有可判断的计划前后数据"
        case .partial:
            "\(sufficientRunCount)/\(totalRunCount) 次有可判断的计划前后数据"
        case .insufficient:
            "\(totalRunCount) 次执行的计划前后数据都不足"
        case .unavailable:
            "历史评估数据暂时无法完整读取"
        }
    }
}

enum EffectiveMethodChangeAvailability: String, Equatable, Sendable {
    case available
    case partial
    case notRecorded
    case insufficient
    case unavailable
}

struct EffectiveMethodObjectiveChangePresentation: Equatable, Sendable {
    let availability: EffectiveMethodChangeAvailability
    let metrics: [MicroPlanEvaluationMetricFact]
    let sourceRunDate: Date?
    let comparableRunCount: Int
    let totalRunCount: Int

    var detail: String {
        switch availability {
        case .available:
            "全部 \(totalRunCount) 次执行都有客观指标对照；下面显示最近一次。"
        case .partial:
            "\(comparableRunCount)/\(totalRunCount) 次执行有客观指标对照；下面显示最近一次。"
        case .insufficient:
            "计划前或计划期的相关健康数据不足 2 个有效日。"
        case .unavailable:
            "客观健康数据暂时无法完整读取。"
        case .notRecorded:
            "尚无客观健康数据记录。"
        }
    }
}

struct EffectiveMethodSubjectiveChangePresentation: Equatable, Sendable {
    let availability: EffectiveMethodChangeAvailability
    let metrics: [EffectiveMethodSubjectiveMetricFact]
    let sourceRunDate: Date?
    let comparableRunCount: Int
    let totalRunCount: Int
    let beforeRecordedDayCount: Int
    let planRecordedDayCount: Int

    var detail: String {
        switch availability {
        case .available:
            "全部 \(totalRunCount) 次执行都有每日感受对照；下面显示最近一次。"
        case .partial:
            "\(comparableRunCount)/\(totalRunCount) 次执行有每日感受对照；下面显示最近一次。"
        case .notRecorded:
            "计划前和计划期均未记录每日感受；未记录不等于没有变化。"
        case .insufficient:
            "已有每日感受记录，但计划前或计划期不足 2 天。"
        case .unavailable:
            "每日感受记录暂时无法完整读取。"
        }
    }
}

struct EffectiveMethodCardPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let sourcePlanTemplateID: MicroPlanTemplateID
    let title: String
    let executionCount: Int
    let completion: EffectiveMethodCompletionFact
    let dataQuality: EffectiveMethodDataQuality
    let confidence: EffectiveMethodConfidence
    let objectiveChange: EffectiveMethodObjectiveChangePresentation
    let subjectiveChange: EffectiveMethodSubjectiveChangePresentation
    let lastRunDate: Date
}

/// 只根据方法卡已经展示的结构化证据筛选，不推断模板用途或计划因果。
enum EffectiveMethodEvidenceFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case sleep
    case energy
    case stress
    case adherence

    static let minimumSubjectiveDifference = 0.05
    static let minimumAdherenceRate = MicroPlanEvaluationFactory.minimumCompletionRate

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .sleep: "睡眠"
        case .energy: "精力"
        case .stress: "压力"
        case .adherence: "可坚持性"
        }
    }

    var evidenceDescription: String {
        switch self {
        case .all:
            "显示全部未隐藏的方法。"
        case .sleep:
            "显示有睡眠指标同期向好变化的方法。"
        case .energy:
            "显示计划期精力中位数高于计划前的方法。"
        case .stress:
            "显示计划期压力中位数低于计划前的方法。"
        case .adherence:
            "显示 CareKit 加权历史完成率至少 60% 的方法。"
        }
    }

    func matches(_ card: EffectiveMethodCardPresentation) -> Bool {
        switch self {
        case .all:
            return true
        case .sleep:
            return card.objectiveChange.metrics.contains {
                ($0.metric == .sleepOnset || $0.metric == .sleepDuration)
                    && $0.direction == .favorable
            }
        case .energy:
            return card.subjectiveChange.metrics.contains {
                $0.dimension == .energy
                    && $0.changeFromBefore > Self.minimumSubjectiveDifference
            }
        case .stress:
            return card.subjectiveChange.metrics.contains {
                $0.dimension == .stress
                    && $0.changeFromBefore < -Self.minimumSubjectiveDifference
            }
        case .adherence:
            guard card.completion.scheduledCount > 0,
                  let rate = card.completion.completionRate else { return false }
            return rate >= Self.minimumAdherenceRate
        }
    }

    func apply(
        to cards: [EffectiveMethodCardPresentation]
    ) -> [EffectiveMethodCardPresentation] {
        cards.filter(matches)
    }
}

enum EffectiveMethodCardPresentationFactory {
    static func make(
        candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> EffectiveMethodCardPresentation {
        EffectiveMethodCardPresentation(
            id: candidate.id,
            sourcePlanTemplateID: candidate.sourcePlanTemplateID,
            title: candidate.title,
            executionCount: candidate.runs.count,
            completion: candidate.completion,
            dataQuality: dataQuality(
                for: candidate,
                evaluations: evaluations
            ),
            confidence: EffectiveMethodConfidenceRule.evaluate(
                candidate: candidate,
                evaluations: evaluations
            ),
            objectiveChange: objectiveChange(
                for: candidate,
                evaluations: evaluations
            ),
            subjectiveChange: subjectiveChange(
                for: candidate,
                evaluations: evaluations
            ),
            lastRunDate: candidate.lastRunDate
        )
    }

    private static func objectiveChange(
        for candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> EffectiveMethodObjectiveChangePresentation {
        let sources = validEvaluationSources(for: candidate, evaluations: evaluations)
        guard let sources else {
            return EffectiveMethodObjectiveChangePresentation(
                availability: .unavailable,
                metrics: [],
                sourceRunDate: nil,
                comparableRunCount: 0,
                totalRunCount: candidate.runs.count
            )
        }
        let comparable = candidate.runs.compactMap { run -> (
            EffectiveMethodCandidateRun,
            EffectiveMethodRunEvaluationFact
        )? in
            guard let evaluation = sources[run.plan.draft.id],
                  evaluation.objectiveDataQuality == .sufficient,
                  !evaluation.objectiveMetrics.isEmpty else { return nil }
            return (run, evaluation)
        }
        if let latest = comparable.first {
            return EffectiveMethodObjectiveChangePresentation(
                availability: comparable.count == candidate.runs.count
                    ? .available : .partial,
                metrics: latest.1.objectiveMetrics,
                sourceRunDate: latest.0.plan.draft.endDateExclusive,
                comparableRunCount: comparable.count,
                totalRunCount: candidate.runs.count
            )
        }
        let availability: EffectiveMethodChangeAvailability = sources.values.contains {
            $0.objectiveDataQuality == .unavailable
        } ? .unavailable : .insufficient
        return EffectiveMethodObjectiveChangePresentation(
            availability: availability,
            metrics: [],
            sourceRunDate: nil,
            comparableRunCount: 0,
            totalRunCount: candidate.runs.count
        )
    }

    private static func subjectiveChange(
        for candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> EffectiveMethodSubjectiveChangePresentation {
        let sources = validEvaluationSources(for: candidate, evaluations: evaluations)
        guard let sources else {
            return EffectiveMethodSubjectiveChangePresentation(
                availability: .unavailable,
                metrics: [],
                sourceRunDate: nil,
                comparableRunCount: 0,
                totalRunCount: candidate.runs.count,
                beforeRecordedDayCount: 0,
                planRecordedDayCount: 0
            )
        }
        let comparable = candidate.runs.compactMap { run -> (
            EffectiveMethodCandidateRun,
            EffectiveMethodRunEvaluationFact
        )? in
            guard let evaluation = sources[run.plan.draft.id],
                  evaluation.subjectiveChange.state == .available,
                  !evaluation.subjectiveChange.metrics.isEmpty else { return nil }
            return (run, evaluation)
        }
        if let latest = comparable.first {
            return EffectiveMethodSubjectiveChangePresentation(
                availability: comparable.count == candidate.runs.count
                    ? .available : .partial,
                metrics: latest.1.subjectiveChange.metrics,
                sourceRunDate: latest.0.plan.draft.endDateExclusive,
                comparableRunCount: comparable.count,
                totalRunCount: candidate.runs.count,
                beforeRecordedDayCount: latest.1.subjectiveChange.beforeRecordedDayCount,
                planRecordedDayCount: latest.1.subjectiveChange.planRecordedDayCount
            )
        }
        let states = sources.values.map(\.subjectiveChange.state)
        let availability: EffectiveMethodChangeAvailability
        if states.contains(.unavailable) {
            availability = .unavailable
        } else if states.contains(.insufficient) {
            availability = .insufficient
        } else {
            availability = .notRecorded
        }
        return EffectiveMethodSubjectiveChangePresentation(
            availability: availability,
            metrics: [],
            sourceRunDate: nil,
            comparableRunCount: 0,
            totalRunCount: candidate.runs.count,
            beforeRecordedDayCount: 0,
            planRecordedDayCount: 0
        )
    }

    private static func validEvaluationSources(
        for candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> [CarePlanID: EffectiveMethodRunEvaluationFact]? {
        let expectedPlanIDs = Set(candidate.runs.map(\.plan.draft.id))
        let evaluationPlanIDs = evaluations.map(\.carePlanID)
        guard Set(evaluationPlanIDs).count == evaluationPlanIDs.count,
              Set(evaluationPlanIDs) == expectedPlanIDs else { return nil }
        return Dictionary(uniqueKeysWithValues: evaluations.map { ($0.carePlanID, $0) })
    }

    private static func dataQuality(
        for candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> EffectiveMethodDataQuality {
        let expectedPlanIDs = candidate.runs.map(\.plan.draft.id)
        let grouped = Dictionary(grouping: evaluations, by: \.carePlanID)
        var sufficientRunCount = 0
        var insufficientRunCount = 0
        var unavailableRunCount = 0

        for planID in expectedPlanIDs {
            guard let matches = grouped[planID], matches.count == 1 else {
                unavailableRunCount += 1
                continue
            }
            switch matches[0].dataQuality {
            case .sufficient: sufficientRunCount += 1
            case .insufficient: insufficientRunCount += 1
            case .unavailable: unavailableRunCount += 1
            }
        }
        let hasForeignEvaluation = grouped.keys.contains {
            !expectedPlanIDs.contains($0)
        }
        if hasForeignEvaluation {
            unavailableRunCount = max(unavailableRunCount, 1)
        }

        let level: EffectiveMethodDataQualityLevel
        if hasForeignEvaluation {
            level = .unavailable
        } else if sufficientRunCount == expectedPlanIDs.count {
            level = .sufficient
        } else if sufficientRunCount > 0 {
            level = .partial
        } else if unavailableRunCount > 0 {
            level = .unavailable
        } else {
            level = .insufficient
        }
        return EffectiveMethodDataQuality(
            level: level,
            totalRunCount: expectedPlanIDs.count,
            sufficientRunCount: sufficientRunCount,
            insufficientRunCount: insufficientRunCount,
            unavailableRunCount: unavailableRunCount
        )
    }
}

/// 基于 CareKit 执行事实与本地计划评估的保守可信度规则。
///
/// 单次可判断结果永远只算初步观察；只有所有执行都达到门槛、数据可判断且方向一致为
/// “可能有帮助”时，重复两次与至少三次才逐级提升。AI 与自由文本不参与分档。
enum EffectiveMethodConfidenceRule {
    static let version = "s11-method-confidence-v1"
    static let minimumCompletionRate = MicroPlanEvaluationFactory.minimumCompletionRate

    static func evaluate(
        candidate: EffectiveMethodCandidate,
        evaluations: [EffectiveMethodRunEvaluationFact]
    ) -> EffectiveMethodConfidence {
        let totalRunCount = candidate.runs.count
        let expectedPlanIDs = Set(candidate.runs.map(\.plan.draft.id))
        let evaluationPlanIDs = evaluations.map(\.carePlanID)

        guard Set(evaluationPlanIDs).count == evaluationPlanIDs.count else {
            return result(
                level: .unclear,
                reason: .invalidEvaluationSources,
                totalRunCount: totalRunCount
            )
        }
        let providedPlanIDs = Set(evaluationPlanIDs)
        guard providedPlanIDs.isSubset(of: expectedPlanIDs) else {
            return result(
                level: .unclear,
                reason: .invalidEvaluationSources,
                totalRunCount: totalRunCount
            )
        }
        guard providedPlanIDs == expectedPlanIDs else {
            return result(
                level: .unclear,
                reason: .missingEvaluation,
                totalRunCount: totalRunCount
            )
        }

        guard candidate.runs.allSatisfy({ run in
            guard let rate = run.completion.completionRate else { return false }
            return run.completion.scheduledCount > 0
                && rate >= minimumCompletionRate
        }) else {
            return result(
                level: .unclear,
                reason: .insufficientExecution,
                totalRunCount: totalRunCount
            )
        }
        let evaluationByPlanID = Dictionary(
            uniqueKeysWithValues: evaluations.map { ($0.carePlanID, $0) }
        )
        guard candidate.runs.allSatisfy({ run in
            evaluationByPlanID[run.plan.draft.id]?.dataQuality == .sufficient
        }) else {
            return result(
                level: .unclear,
                reason: .insufficientData,
                totalRunCount: totalRunCount
            )
        }

        let verdicts = candidate.runs.compactMap {
            evaluationByPlanID[$0.plan.draft.id]?.verdict
        }
        if verdicts.contains(.insufficientExecution) {
            return result(
                level: .unclear,
                reason: .insufficientExecution,
                totalRunCount: totalRunCount
            )
        }
        if verdicts.contains(.insufficientData) {
            return result(
                level: .unclear,
                reason: .insufficientData,
                totalRunCount: totalRunCount
            )
        }
        if verdicts.contains(.subjectiveObjectiveMismatch) {
            return result(
                level: .unclear,
                reason: .subjectiveObjectiveMismatch,
                totalRunCount: totalRunCount
            )
        }

        let assessableRunCount = verdicts.count
        let helpfulRunCount = verdicts.filter { $0 == .mayHaveHelped }.count
        if assessableRunCount == 1 {
            return result(
                level: .preliminaryObservation,
                reason: .oneAssessableRun,
                totalRunCount: totalRunCount,
                assessableRunCount: assessableRunCount,
                helpfulRunCount: helpfulRunCount
            )
        }
        guard helpfulRunCount == assessableRunCount else {
            return result(
                level: .unclear,
                reason: helpfulRunCount == 0
                    ? .noConsistentBenefit
                    : .inconsistentResults,
                totalRunCount: totalRunCount,
                assessableRunCount: assessableRunCount,
                helpfulRunCount: helpfulRunCount
            )
        }
        if assessableRunCount == 2 {
            return result(
                level: .possiblySuitable,
                reason: .twoConsistentHelpfulRuns,
                totalRunCount: totalRunCount,
                assessableRunCount: assessableRunCount,
                helpfulRunCount: helpfulRunCount
            )
        }
        return result(
            level: .fairlyStable,
            reason: .repeatedConsistentHelpfulRuns,
            totalRunCount: totalRunCount,
            assessableRunCount: assessableRunCount,
            helpfulRunCount: helpfulRunCount
        )
    }

    private static func result(
        level: EffectiveMethodConfidenceLevel,
        reason: EffectiveMethodConfidenceReason,
        totalRunCount: Int,
        assessableRunCount: Int = 0,
        helpfulRunCount: Int = 0
    ) -> EffectiveMethodConfidence {
        EffectiveMethodConfidence(
            level: level,
            reason: reason,
            totalRunCount: totalRunCount,
            assessableRunCount: assessableRunCount,
            helpfulRunCount: helpfulRunCount,
            ruleVersion: version
        )
    }
}

/// Deterministic read-only cards for the synthetic demo person. They still pass
/// through the production completion, quality and confidence factories, so the
/// displayed 80% and "可能适合" labels are derived facts rather than copy.
enum DemoEffectiveMethodFactory {
    static func cards(
        endingAt referenceDate: Date,
        calendar: Calendar = .current
    ) -> [EffectiveMethodCardPresentation] {
        guard let template = MicroPlanTemplateLibrary.template(for: .earlierBedtime),
              let first = run(template: template, startOffset: -48, endingAt: referenceDate, calendar: calendar),
              let second = run(template: template, startOffset: -16, endingAt: referenceDate, calendar: calendar),
              let candidate = EffectiveMethodCandidate(
                sourcePlanTemplateID: template.id,
                title: template.title,
                runs: [second.run, first.run]
              )
        else { return [] }

        return [EffectiveMethodCardPresentationFactory.make(
            candidate: candidate,
            evaluations: [second.evaluation, first.evaluation]
        )]
    }

    private static func run(
        template: MicroPlanTemplate,
        startOffset: Int,
        endingAt referenceDate: Date,
        calendar: Calendar
    ) -> (run: EffectiveMethodCandidateRun, evaluation: EffectiveMethodRunEvaluationFact)? {
        guard let start = calendar.date(byAdding: .day, value: startOffset, to: referenceDate),
              let draft = try? template.makeDraft(
                referenceDate: start,
                calendar: calendar,
                uniqueID: deterministicUUID(startOffset)
              ) else { return nil }
        let plan = MicroPlan(draft: draft, status: .completed)
        let completedIndexes = startOffset == -48 ? [0, 1, 2, 4] : [0, 1, 2, 3]
        let skippedIndex = startOffset == -48 ? 3 : 4
        let outcomes = completedIndexes.compactMap { index in
            outcome(
                index: index,
                state: .completed,
                plan: plan,
                calendar: calendar
            )
        } + [outcome(
            index: skippedIndex,
            state: .skipped,
            plan: plan,
            calendar: calendar
        )].compactMap { $0 }
        guard let progress = try? MicroPlanProgress(
            scheduledCount: 5,
            completedCount: 4,
            skippedCount: 1
        ), let run = try? EffectiveMethodCandidateRun(
            plan: plan,
            outcomes: outcomes,
            progress: progress
        ) else { return nil }

        let beforeSleep = startOffset == -48 ? 6.92 : 6.88
        let planSleep = startOffset == -48 ? 7.18 : 7.36
        let objective = MicroPlanEvaluationMetricFact(
            metric: .sleepDuration,
            healthMetric: .sleepDuration,
            beforeMedian: beforeSleep,
            planMedian: planSleep,
            changeFromBefore: planSleep - beforeSleep,
            beforeValidDayCount: 5,
            planValidDayCount: 5,
            direction: .favorable
        )
        let subjective = EffectiveMethodSubjectiveRunChange(
            state: .available,
            metrics: [
                .init(dimension: .energy, beforeMedian: 3, planMedian: 4),
                .init(dimension: .stress, beforeMedian: 3, planMedian: 2),
                .init(dimension: .bodyFeeling, beforeMedian: 3, planMedian: 4)
            ],
            beforeRecordedDayCount: 5,
            planRecordedDayCount: 5
        )
        return (run, EffectiveMethodRunEvaluationFact(
            carePlanID: plan.draft.id,
            verdict: .mayHaveHelped,
            dataQuality: .sufficient,
            objectiveDataQuality: .sufficient,
            objectiveMetrics: [objective],
            subjectiveChange: subjective
        ))
    }

    private static func outcome(
        index: Int,
        state: PlanOutcomeState,
        plan: MicroPlan,
        calendar: Calendar
    ) -> PlanOutcomeRecord? {
        guard let day = calendar.date(byAdding: .day, value: index, to: plan.draft.startDate),
              let time = calendar.date(bySettingHour: 22, minute: 35, second: 0, of: day)
        else { return nil }
        return PlanOutcomeRecord(
            occurrenceIndex: index,
            state: state,
            recordedAt: time,
            feedback: state == .completed && index == 3
                ? "当晚更容易收尾，早上的精力感受也更好。"
                : nil
        )
    }

    private static func deterministicUUID(_ offset: Int) -> UUID {
        UUID(uuidString: offset == -48
             ? "20000000-0000-4000-8000-000000000048"
             : "20000000-0000-4000-8000-000000000016")!
    }
}

enum EffectiveMethodCandidateGenerator {
    /// 从 CareKit 的唯一执行事实来源生成内存候选。
    ///
    /// 只有全部合格计划的 Outcomes 与进度都读取并互相核对成功才返回结果，防止
    /// 把读取失败或状态冲突误写成“没有执行”。已结束但暂时没有 Outcome 的计划
    /// 仍保留，交给后续可信度规则明确表达无法判断。
    static func load(
        from service: any CarePlanService
    ) async throws -> [EffectiveMethodCandidate] {
        let history = try await service.planHistory().sorted(by: planComesFirst)
        var seenPlanIDs = Set<CarePlanID>()
        var groupedRuns = [String: [EffectiveMethodCandidateRun]]()

        for plan in history {
            guard plan.status == .completed || plan.status == .endedEarly else {
                continue
            }
            guard seenPlanIDs.insert(plan.draft.id).inserted else { continue }
            guard
                let templateID = MicroPlanTemplateLibrary.templateID(for: plan.draft),
                MicroPlanTemplateLibrary.template(for: templateID) != nil
            else {
                continue
            }

            let outcomes = try await service.outcomeRecords(
                for: plan.draft.taskID
            ).sorted(by: outcomeComesFirst)
            let progress = try await service.progress(for: plan.draft.id)
            guard let run = try EffectiveMethodCandidateRun(
                plan: plan,
                outcomes: outcomes,
                progress: progress
            ) else {
                continue
            }
            groupedRuns[templateID.rawValue, default: []].append(run)
        }

        return groupedRuns.compactMap { rawTemplateID, runs in
            guard
                let templateID = MicroPlanTemplateID(rawValue: rawTemplateID),
                let template = MicroPlanTemplateLibrary.template(for: templateID)
            else {
                return nil
            }
            return EffectiveMethodCandidate(
                sourcePlanTemplateID: templateID,
                title: template.title,
                runs: runs.sorted(by: runComesFirst)
            )
        }.sorted(by: candidateComesFirst)
    }

    private static func planComesFirst(_ first: MicroPlan, _ second: MicroPlan) -> Bool {
        if first.draft.endDateExclusive != second.draft.endDateExclusive {
            return first.draft.endDateExclusive > second.draft.endDateExclusive
        }
        if first.draft.startDate != second.draft.startDate {
            return first.draft.startDate > second.draft.startDate
        }
        return first.draft.id.rawValue < second.draft.id.rawValue
    }

    private static func runComesFirst(
        _ first: EffectiveMethodCandidateRun,
        _ second: EffectiveMethodCandidateRun
    ) -> Bool {
        planComesFirst(first.plan, second.plan)
    }

    private static func outcomeComesFirst(
        _ first: PlanOutcomeRecord,
        _ second: PlanOutcomeRecord
    ) -> Bool {
        if first.occurrenceIndex != second.occurrenceIndex {
            return first.occurrenceIndex < second.occurrenceIndex
        }
        if first.recordedAt != second.recordedAt {
            return first.recordedAt < second.recordedAt
        }
        if first.state.rawValue != second.state.rawValue {
            return first.state.rawValue < second.state.rawValue
        }
        return (first.feedback ?? "") < (second.feedback ?? "")
    }

    private static func candidateComesFirst(
        _ first: EffectiveMethodCandidate,
        _ second: EffectiveMethodCandidate
    ) -> Bool {
        if first.lastRunDate != second.lastRunDate {
            return first.lastRunDate > second.lastRunDate
        }
        return first.sourcePlanTemplateID.rawValue
            < second.sourcePlanTemplateID.rawValue
    }
}
