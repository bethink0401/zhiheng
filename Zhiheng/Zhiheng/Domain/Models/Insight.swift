import CryptoKit
import Foundation

/// Local, aggregate-only insight. Not an AI response, SwiftData entity or CareKit plan.
/// Construction validates structure; wording still requires the separate safety review.
struct Insight: Identifiable, Equatable, Sendable {
    static let modelVersion = "s09-insight-v1"

    let id: UUID
    var insightID: String { id.uuidString }
    let version: String
    let generatedAt: Date
    /// Half-open range covering the evidence, including the personal baseline.
    let analysisInterval: DateInterval
    let timeZoneIdentifier: String
    let dataMode: HealthDataMode
    let facts: [InsightFact]
    let possibleExplanations: [InsightPossibleExplanation]
    let uncertainty: String
    let followUpQuestion: String?
    let recommendation: InsightRecommendation

    init(
        id: UUID, generatedAt: Date, analysisInterval: DateInterval,
        timeZoneIdentifier: String, dataMode: HealthDataMode,
        facts: [InsightFact], possibleExplanations: [InsightPossibleExplanation] = [],
        uncertainty: String, followUpQuestion: String? = nil,
        recommendation: InsightRecommendation = .continueObserving
    ) throws {
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
              analysisInterval.start.timeIntervalSinceReferenceDate.isFinite,
              analysisInterval.end.timeIntervalSinceReferenceDate.isFinite,
              analysisInterval.duration > 0, analysisInterval.end <= generatedAt,
              let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw InsightValidationError.invalidTimeScope
        }
        guard Self.hasText(uncertainty), followUpQuestion.map(Self.hasText) ?? true else {
            throw InsightValidationError.emptyText
        }
        guard !facts.isEmpty else { throw InsightValidationError.missingFacts }
        guard Set(facts.map(\.id)).count == facts.count,
              Set(facts.map(\.metric)).count == facts.count else {
            throw InsightValidationError.duplicateFact
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for fact in facts {
            try fact.validate(in: analysisInterval, calendar: calendar)
        }
        let factsByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        func validateSupport(_ ids: [UUID]) throws {
            guard !ids.isEmpty, Set(ids).count == ids.count,
                  ids.allSatisfy({ factsByID[$0] != nil }) else {
                throw InsightValidationError.invalidFactReference
            }
            guard ids.allSatisfy({ factsByID[$0]?.supportsInterpretation == true }) else {
                throw InsightValidationError.insufficientSupport
            }
        }
        for explanation in possibleExplanations {
            guard Self.hasText(explanation.text) else { throw InsightValidationError.emptyText }
            try validateSupport(explanation.supportingFactIDs)
            for reference in explanation.contextReferences {
                guard reference.dataMode == dataMode else {
                    throw InsightValidationError.mixedDataModes
                }
                guard reference.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                      reference.updatedAt <= generatedAt else {
                    throw InsightValidationError.invalidContextReference
                }
            }
        }
        if case let .considerMicroPlan(_, ids) = recommendation {
            try validateSupport(ids)
        }
        self.id = id
        self.version = Self.modelVersion
        self.generatedAt = generatedAt
        self.analysisInterval = analysisInterval
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dataMode = dataMode
        self.facts = facts
        self.possibleExplanations = possibleExplanations
        self.uncertainty = uncertainty
        self.followUpQuestion = followUpQuestion
        self.recommendation = recommendation
    }

    private static func hasText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Facts contain program results, never free-form model-generated health claims.
struct InsightFact: Identifiable, Equatable, Sendable {
    let id: UUID
    let metric: HealthMetricType
    let evidence: InsightMetricEvidence

    fileprivate var supportsInterpretation: Bool {
        guard case let .evaluated(trend, _) = evidence,
              case .trend = trend.state else { return false }
        return trend.sourceIsStable && !trend.isolatedOutlierExcluded
    }

    fileprivate func validate(in interval: DateInterval, calendar: Calendar) throws {
        guard case let .evaluated(trend, sources) = evidence else { return }
        let numbers = [trend.currentMedianValue, trend.baselineMedianValue,
                       trend.relativeChange, trend.effectiveRelativeThreshold]
        guard trend.metric == metric, trend.unit == metric.expectedUnit,
              trend.currentExpectedDayCount == HealthDataQualityThresholds.shortTermExpectedDays,
              trend.baselineExpectedDayCount == HealthDataQualityThresholds.baselineExpectedDays,
              (0...trend.currentExpectedDayCount).contains(trend.currentValidDayCount),
              (0...trend.baselineExpectedDayCount).contains(trend.baselineValidDayCount),
              numbers.compactMap({ $0 }).allSatisfy(\.isFinite),
              trend.configuredMinimumRelativeChange.isFinite,
              trend.configuredMinimumRelativeChange >= 0,
              trend.effectiveRelativeThreshold.map({ $0 >= 0 }) ?? true,
              !trend.thresholdVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              trend.currentInterval.start >= interval.start,
              trend.currentInterval.end <= interval.end,
              trend.baselineInterval.start >= interval.start,
              trend.baselineInterval.end == trend.currentInterval.start,
              calendar.startOfDay(for: trend.currentInterval.end) == trend.currentInterval.end,
              calendar.date(byAdding: .day, value: -trend.currentExpectedDayCount,
                            to: trend.currentInterval.end) == trend.currentInterval.start,
              calendar.date(byAdding: .day, value: -trend.baselineExpectedDayCount,
                            to: trend.baselineInterval.end) == trend.baselineInterval.start else {
            throw InsightValidationError.invalidEvidence
        }
        let alignment = [trend.alignedDayCount, trend.analysisDayCount, trend.requiredAlignedDayCount]
        if alignment.contains(where: { $0 != nil }) {
            guard let aligned = trend.alignedDayCount, let analysis = trend.analysisDayCount,
                  let required = trend.requiredAlignedDayCount, analysis > 0,
                  analysis <= trend.currentValidDayCount,
                  (0...analysis).contains(aligned), (1...analysis).contains(required) else {
                throw InsightValidationError.invalidEvidence
            }
        }
        let currentReady = trend.currentValidDayCount >= HealthDataQualityThresholds.shortTermMinimumValidDays
        let baselineReady = trend.baselineValidDayCount >= HealthDataQualityThresholds.baselineMinimumValidDays
        let consistent: Bool
        switch trend.state {
        case .currentWindowInsufficient: consistent = !currentReady
        case .baselineInsufficient: consistent = currentReady && !baselineReady
        case .sourceChanged: consistent = currentReady && baselineReady && !trend.sourceIsStable
        case .trend:
            consistent = currentReady && baselineReady && trend.sourceIsStable
                && trend.currentMedianValue != nil && trend.baselineMedianValue != nil
                && !sources.isEmpty && Set(sources).count == 1
        }
        guard consistent else { throw InsightValidationError.invalidEvidence }
    }
}

enum InsightMetricEvidence: Equatable, Sendable {
    /// Reuses the trend engine's medians, ranges, coverage, thresholds and quality flags.
    case evaluated(HealthMetricTrendEvidence, sources: [HealthMetricSource])
    case unavailable(InsightDataUnavailableReason)
}

enum InsightDataUnavailableReason: String, CaseIterable, Sendable {
    case accessNotRequested, healthDataUnavailable, noVisibleData, queryFailed
    case notLoaded, queryWindowIncomplete, sourceConflict, sourceChanged
    case recentDataGap, unsupportedMetric, analysisUnavailable
}

struct InsightPossibleExplanation: Equatable, Sendable {
    let text: String
    let supportingFactIDs: [UUID]
    /// References only: matching and rechecking edited/deleted records belong to S09-03.
    let contextReferences: [InsightContextReference]
}

struct InsightContextReference: Equatable, Sendable {
    enum Kind: String, Sendable { case dailyCheckIn, contextEvent }
    let kind: Kind
    let recordID: UUID
    let updatedAt: Date
    let dataMode: HealthDataMode
}

enum InsightRecommendation: Equatable, Sendable {
    case continueObserving
    /// A candidate only; a user must confirm before the CareKit adapter creates a plan.
    case considerMicroPlan(templateID: MicroPlanTemplateID, supportingFactIDs: [UUID])
}

/// A local, aggregate-only candidate. It is not a CareKit draft and cannot start a plan.
struct InsightPlanCandidate: Equatable, Sendable {
    let ruleVersion: String
    let templateID: MicroPlanTemplateID
    let supportingFactIDs: [UUID]

    var recommendation: InsightRecommendation {
        .considerMicroPlan(
            templateID: templateID,
            supportingFactIDs: supportingFactIDs
        )
    }
}

enum InsightPlanCandidateDecision: Equatable, Sendable {
    enum NoCandidateReason: Equatable, Sendable {
        case nonLiveMode
        case contextUnavailable
        case waitingForContext
        case noQualifiedChange
        case noLowRiskMatch
        case contextNeedsCaution
    }

    case noCandidate(NoCandidateReason)
    case candidate(InsightPlanCandidate)
}

/// Deterministically maps a quality-qualified insight to at most one existing
/// low-risk template. The mapping never creates or starts a CareKit plan.
enum InsightPlanCandidateRule {
    static let version = "s10-insight-plan-candidate-v1"

    static func decide(
        factSet: InsightFactSet,
        contextState: InsightCardContextState
    ) throws -> InsightPlanCandidateDecision {
        switch contextState {
        case .demoMode:
            guard factSet.dataMode == .demo else {
                throw InsightFourLayerCardError.invalidContextState
            }
            return .noCandidate(.nonLiveMode)
        case .readFailed:
            guard factSet.dataMode == .live else {
                throw InsightFourLayerCardError.invalidContextState
            }
            return .noCandidate(.contextUnavailable)
        case .available(let context):
            guard factSet.dataMode == .live else {
                throw InsightFourLayerCardError.invalidContextState
            }
            let followUp = try InsightFollowUpQuestionRule.decide(
                factSet: factSet,
                context: context
            )
            if case .ask = followUp {
                return .noCandidate(.waitingForContext)
            }

            let changes = rankedChanges(
                InsightFollowUpQuestionRule.meaningfulChangeFacts(in: factSet)
            )
            guard !changes.isEmpty else {
                return .noCandidate(.noQualifiedChange)
            }
            if context.contextEvents.contains(where: {
                $0.kind == .illness || $0.kind == .deviceNotWorn
            }) {
                return .noCandidate(.contextNeedsCaution)
            }
            for fact in changes {
                if let templateID = template(for: fact, context: context) {
                    return .candidate(InsightPlanCandidate(
                        ruleVersion: version,
                        templateID: templateID,
                        supportingFactIDs: [fact.id]
                    ))
                }
            }
            return .noCandidate(.noLowRiskMatch)
        }
    }

    private static func rankedChanges(_ facts: [InsightFact]) -> [InsightFact] {
        let metricOrder = Dictionary(uniqueKeysWithValues:
            HealthMetricType.allCases.enumerated().map { ($0.element, $0.offset) }
        )
        return facts.sorted { left, right in
            let leftRank = rank(left)
            let rightRank = rank(right)
            if leftRank.level != rightRank.level { return leftRank.level > rightRank.level }
            if leftRank.magnitude != rightRank.magnitude {
                return leftRank.magnitude > rightRank.magnitude
            }
            return (metricOrder[left.metric] ?? .max) < (metricOrder[right.metric] ?? .max)
        }
    }

    private static func rank(_ fact: InsightFact) -> (level: Int, magnitude: Double) {
        guard case let .evaluated(trend, _) = fact.evidence,
              case let .trend(level) = trend.state else { return (0, 0) }
        let priority = level == .sustainedChange ? 2 : 1
        let magnitude = abs(trend.relativeChange ?? 0)
            / max(trend.effectiveRelativeThreshold ?? 1, 0.000_001)
        return (priority, magnitude)
    }

    private static func template(
        for fact: InsightFact,
        context: InsightContextMatch
    ) -> MicroPlanTemplateID? {
        guard case let .evaluated(trend, _) = fact.evidence,
              let relativeChange = trend.relativeChange else { return nil }
        let eventKinds = Set(context.contextEvents.map(\.kind))
        let needsCare = context.checkIns.contains {
            $0.energy.rawValue <= SubjectiveRating.two.rawValue
                || $0.stress.rawValue >= SubjectiveRating.four.rawValue
                || $0.bodyFeeling.rawValue <= SubjectiveRating.two.rawValue
        }
        let highStress = context.checkIns.contains {
            $0.stress.rawValue >= SubjectiveRating.four.rawValue
        }

        switch (fact.metric, relativeChange.sign) {
        case (.sleepDuration, .minus):
            if eventKinds.contains(.caffeine) { return .afternoonCaffeineCutoff }
            if highStress { return .bedtimeBreathing }
            return .earlierBedtime
        case (.stepCount, .minus):
            guard !needsCare else { return nil }
            if !eventKinds.isDisjoint(with: [.overtime, .deadline, .caregiving]) {
                return .movementBreak
            }
            return .afternoonWalk
        case (.activeEnergy, .minus):
            return needsCare ? nil : .movementBreak
        case (.exerciseDuration, .minus):
            return needsCare ? nil : .gentleMobility
        case (.exerciseDuration, .plus):
            return needsCare && eventKinds.contains(.highIntensityExercise)
                ? .reducedTrainingLoad
                : nil
        case (.heartRateVariability, .minus), (.restingHeartRate, .plus):
            if eventKinds.contains(.highIntensityExercise) {
                return .reducedTrainingLoad
            }
            return needsCare ? .bedtimeBreathing : nil
        default:
            return nil
        }
    }
}

enum InsightValidationError: Error, Equatable, Sendable {
    case invalidTimeScope, emptyText, missingFacts, duplicateFact, invalidEvidence
    case invalidFactReference, insufficientSupport, mixedDataModes, invalidContextReference
}

/// A single, traceable request for missing context. It is not an inferred fact.
struct InsightFollowUpQuestion: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case missingSubjectiveContext
        case missingLifeContext
        case subjectiveObjectiveMismatch
    }

    let id: UUID
    let ruleVersion: String
    let kind: Kind
    let text: String
    let supportingFactIDs: [UUID]
    /// References only; free-form notes and custom labels remain in the source store.
    let contextReferences: [InsightContextReference]
}

enum InsightFollowUpDecision: Equatable, Sendable {
    enum NoQuestionReason: Equatable, Sendable {
        case nonLiveMode
        case contextAlreadyAvailable
        case noHighValueGap
        case alreadyHandled
    }

    case noQuestion(NoQuestionReason)
    case ask(InsightFollowUpQuestion)
}

enum InsightFollowUpRuleError: Error, Equatable, Sendable {
    case invalidFactSet
    case invalidContextMatch
}

/// Deterministic, local rules that return either no question or exactly one question.
/// The rule never treats a context record as the cause of a health metric change.
enum InsightFollowUpQuestionRule {
    static let version = "s09-follow-up-question-v1"

    static func decide(
        factSet: InsightFactSet,
        context: InsightContextMatch,
        handledQuestionIDs: Set<UUID> = []
    ) throws -> InsightFollowUpDecision {
        try validate(factSet: factSet, context: context)
        guard factSet.dataMode == .live else {
            return .noQuestion(.nonLiveMode)
        }

        let orderedFacts = HealthMetricType.allCases.compactMap { metric in
            factSet.facts.first(where: { $0.metric == metric })
        }
        let changeFacts = meaningfulChangeFacts(in: factSet)

        let candidate: InsightFollowUpQuestion?
        if !changeFacts.isEmpty, context.checkIns.isEmpty {
            candidate = question(
                kind: .missingSubjectiveContext,
                text: "为了补充背景，最近一周你的精力、压力或身体感受是否也有明显不同？",
                facts: changeFacts,
                context: context,
                factSet: factSet
            )
        } else if !changeFacts.isEmpty, context.contextEvents.isEmpty {
            candidate = question(
                kind: .missingLifeContext,
                text: "为了补充背景，最近一周是否有作息、工作安排、旅行、身体感受或运动量方面的变化？",
                facts: changeFacts,
                context: context,
                factSet: factSet
            )
        } else if !changeFacts.isEmpty {
            return .noQuestion(.contextAlreadyAvailable)
        } else if hasSubjectiveObjectiveMismatch(facts: orderedFacts, context: context),
                  context.contextEvents.isEmpty {
            let stableFacts = HealthMetricTrendThresholdCatalog.coreMetrics.compactMap { metric in
                orderedFacts.first(where: { $0.metric == metric })
            }
            candidate = question(
                kind: .subjectiveObjectiveMismatch,
                text: "为了理解这段感受，最近一周是否有作息、工作安排、身体感受或其他生活变化？",
                facts: stableFacts,
                context: context,
                factSet: factSet
            )
        } else if hasSubjectiveObjectiveMismatch(facts: orderedFacts, context: context) {
            return .noQuestion(.contextAlreadyAvailable)
        } else {
            return .noQuestion(.noHighValueGap)
        }

        guard let candidate else { return .noQuestion(.noHighValueGap) }
        guard !handledQuestionIDs.contains(candidate.id) else {
            return .noQuestion(.alreadyHandled)
        }
        return .ask(candidate)
    }

    private static func validate(
        factSet: InsightFactSet,
        context: InsightContextMatch
    ) throws {
        guard !factSet.generatorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !factSet.facts.isEmpty,
              Set(factSet.facts.map(\.id)).count == factSet.facts.count,
              Set(factSet.facts.map(\.metric)).count == factSet.facts.count,
              TimeZone(identifier: factSet.timeZoneIdentifier) != nil else {
            throw InsightFollowUpRuleError.invalidFactSet
        }
        let expectedWindow: InsightContextWindow
        do {
            expectedWindow = try InsightContextMatcher.window(for: factSet)
        } catch {
            throw InsightFollowUpRuleError.invalidFactSet
        }
        let references = context.references
        let referenceKeys = references.map {
            "\($0.kind.rawValue):\($0.recordID.uuidString.lowercased())"
        }
        guard context.matcherVersion == InsightContextMatch.matcherVersion,
              context.dataMode == factSet.dataMode,
              context.window == expectedWindow,
              Set(referenceKeys).count == referenceKeys.count,
              references.allSatisfy({
                  $0.dataMode == factSet.dataMode
                      && $0.updatedAt.timeIntervalSinceReferenceDate.isFinite
              }) else {
            throw InsightFollowUpRuleError.invalidContextMatch
        }
    }

    fileprivate static func meaningfulChangeFacts(in factSet: InsightFactSet) -> [InsightFact] {
        HealthMetricType.allCases.compactMap { metric in
            factSet.facts.first(where: { $0.metric == metric })
        }.filter(isMeaningfulChange)
    }

    private static func isMeaningfulChange(_ fact: InsightFact) -> Bool {
        guard case let .evaluated(trend, sources) = fact.evidence,
              trend.currentValidDayCount >= HealthDataQualityThresholds.shortTermMinimumValidDays,
              trend.baselineValidDayCount >= HealthDataQualityThresholds.baselineMinimumValidDays,
              trend.sourceIsStable,
              !trend.isolatedOutlierExcluded,
              sources.count == 1 else { return false }
        switch trend.state {
        case .trend(.sustainedChange):
            return true
        case .trend(.worthObserving):
            guard let change = trend.relativeChange,
                  let threshold = trend.effectiveRelativeThreshold else { return false }
            return abs(change) >= threshold
        default:
            return false
        }
    }

    private static func hasSubjectiveObjectiveMismatch(
        facts: [InsightFact],
        context: InsightContextMatch
    ) -> Bool {
        guard context.checkIns.contains(where: needsCare) else { return false }
        return HealthMetricTrendThresholdCatalog.coreMetrics.allSatisfy { metric in
            guard let fact = facts.first(where: { $0.metric == metric }),
                  case let .evaluated(trend, sources) = fact.evidence,
                  case .trend(.noClearChange) = trend.state else { return false }
            return trend.currentValidDayCount >= HealthDataQualityThresholds.shortTermMinimumValidDays
                && trend.baselineValidDayCount >= HealthDataQualityThresholds.baselineMinimumValidDays
                && trend.sourceIsStable
                && !trend.isolatedOutlierExcluded
                && sources.count == 1
        }
    }

    private static func needsCare(_ checkIn: InsightMatchedCheckIn) -> Bool {
        checkIn.energy.rawValue <= SubjectiveRating.two.rawValue
            || checkIn.stress.rawValue >= SubjectiveRating.four.rawValue
            || checkIn.bodyFeeling.rawValue <= SubjectiveRating.two.rawValue
    }

    private static func question(
        kind: InsightFollowUpQuestion.Kind,
        text: String,
        facts: [InsightFact],
        context: InsightContextMatch,
        factSet: InsightFactSet
    ) -> InsightFollowUpQuestion {
        InsightFollowUpQuestion(
            id: stableQuestionID(kind: kind, factSet: factSet),
            ruleVersion: version,
            kind: kind,
            text: text,
            supportingFactIDs: facts.map(\.id),
            contextReferences: context.references
        )
    }

    private static func stableQuestionID(
        kind: InsightFollowUpQuestion.Kind,
        factSet: InsightFactSet
    ) -> UUID {
        let name = [
            version,
            kind.rawValue,
            factSet.dataMode.rawValue,
            factSet.timeZoneIdentifier,
            String(factSet.analysisInterval.end.timeIntervalSince1970.bitPattern)
        ].joined(separator: "\u{1F}")
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct InsightFourLayerCardPresentation: Equatable, Sendable {
    struct Layer: Identifiable, Equatable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case fact
            case possibleExplanation
            case uncertainty
            case recommendation

            var title: String {
                switch self {
                case .fact: "观察到的事实"
                case .possibleExplanation: "可能解释"
                case .uncertainty: "不确定性"
                case .recommendation: "建议"
                }
            }
        }

        var id: Kind { kind }
        let kind: Kind
        let text: String
    }

    let title: String
    let scopeText: String
    let layers: [Layer]
    let followUpQuestion: String?
    let planCandidate: InsightPlanCandidate?
    let evidence: InsightEvidencePresentation
    let interactionIdentity: InsightInteractionIdentity
    let isDemo: Bool
}

enum InsightInteractionTopic: Equatable, Sendable {
    case metricChange(HealthMetricType)
    case subjectiveObjectiveMismatch
    case stableOverview
    case dataQuality

    var storageKey: String {
        switch self {
        case .metricChange(let metric): "metric-change:\(metric.rawValue)"
        case .subjectiveObjectiveMismatch: "subjective-objective-mismatch"
        case .stableOverview: "stable-overview"
        case .dataQuality: "data-quality"
        }
    }

    var displayTitle: String {
        switch self {
        case .metricChange(let metric):
            "\(InsightFourLayerCardFactory.metricTitle(metric))变化"
        case .subjectiveObjectiveMismatch: "感受与数据对照"
        case .stableOverview: "近期稳定概览"
        case .dataQuality: "数据质量观察"
        }
    }
}

/// Stable, aggregate-only identity used for local read/ignore/reminder controls.
/// It intentionally exposes no source identifiers, sample IDs or subjective record IDs.
struct InsightInteractionIdentity: Equatable, Sendable {
    let insightID: UUID
    let topic: InsightInteractionTopic
    let dataMode: HealthDataMode
}

struct InsightEvidencePresentation: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: UUID
        let metric: HealthMetricType
        let metricTitle: String
        let currentWindowText: String
        let baselineWindowText: String?
        let changeText: String?
        let alignmentText: String?
        let sourceText: String
        let qualityText: String
        let versionText: String
    }

    let title: String
    let summary: String
    let timeZoneText: String
    let items: [Item]
}

enum InsightCardContextState: Equatable, Sendable {
    case available(InsightContextMatch)
    case demoMode
    case readFailed
}

enum InsightFourLayerCardError: Error, Equatable, Sendable {
    case invalidContextState
}

/// Converts typed facts and structured context into four explicitly separated UI layers.
/// It does not call AI, infer diagnoses, create a plan or treat a concurrent event as a cause.
enum InsightFourLayerCardFactory {
    static let version = "s09-four-layer-card-v1"

    static func make(
        factSet: InsightFactSet,
        contextState: InsightCardContextState,
        handledQuestionIDs: Set<UUID> = []
    ) throws -> InsightFourLayerCardPresentation {
        let context: InsightContextMatch?
        let decision: InsightFollowUpDecision?
        switch contextState {
        case .available(let value):
            guard factSet.dataMode == .live else {
                throw InsightFourLayerCardError.invalidContextState
            }
            context = value
            decision = try InsightFollowUpQuestionRule.decide(
                factSet: factSet,
                context: value,
                handledQuestionIDs: handledQuestionIDs
            )
        case .demoMode:
            guard factSet.dataMode == .demo else {
                throw InsightFourLayerCardError.invalidContextState
            }
            context = nil
            decision = nil
        case .readFailed:
            guard factSet.dataMode == .live else {
                throw InsightFourLayerCardError.invalidContextState
            }
            context = nil
            decision = nil
        }

        let changes = rankedChanges(
            InsightFollowUpQuestionRule.meaningfulChangeFacts(in: factSet)
        )
        let primaryChange = changes.first
        let mismatchQuestion: InsightFollowUpQuestion? = if case let .some(.ask(question)) = decision,
                                                            question.kind == .subjectiveObjectiveMismatch {
            question
        } else {
            nil
        }
        let followUpQuestion: String? = if case let .some(.ask(question)) = decision {
            question.text
        } else {
            nil
        }
        let hasCompleteStableSet = !factSet.facts.isEmpty && factSet.facts.allSatisfy { fact in
            guard case let .evaluated(trend, sources) = fact.evidence,
                  case .trend(.noClearChange) = trend.state else { return false }
            return trend.sourceIsStable && !trend.isolatedOutlierExcluded && sources.count == 1
        }
        let evidenceFacts: [InsightFact]
        if let primaryChange {
            evidenceFacts = [primaryChange]
        } else if mismatchQuestion != nil {
            evidenceFacts = canonicalFacts(in: factSet).filter {
                HealthMetricTrendThresholdCatalog.coreMetrics.contains($0.metric)
            }
        } else {
            evidenceFacts = canonicalFacts(in: factSet)
        }
        let topic: InsightInteractionTopic
        if let primaryChange {
            topic = .metricChange(primaryChange.metric)
        } else if mismatchQuestion != nil {
            topic = .subjectiveObjectiveMismatch
        } else if hasCompleteStableSet {
            topic = .stableOverview
        } else {
            topic = .dataQuality
        }
        let interactionIdentity = InsightInteractionIdentity(
            insightID: stableInteractionID(
                factSet: factSet,
                topic: topic,
                evidenceFacts: evidenceFacts,
                decision: decision,
                context: context
            ),
            topic: topic,
            dataMode: factSet.dataMode
        )
        let planCandidate: InsightPlanCandidate? = switch try InsightPlanCandidateRule.decide(
            factSet: factSet,
            contextState: contextState
        ) {
        case .candidate(let value): value
        case .noCandidate: nil
        }

        return InsightFourLayerCardPresentation(
            title: title(
                primaryChange: primaryChange,
                hasMismatch: mismatchQuestion != nil,
                hasCompleteStableSet: hasCompleteStableSet
            ),
            scopeText: "最近 7 个完整日 · 对比此前 28 日个人基线",
            layers: [
                .init(
                    kind: .fact,
                    text: factText(
                        primaryChange: primaryChange,
                        hasMismatch: mismatchQuestion != nil,
                        hasCompleteStableSet: hasCompleteStableSet
                    )
                ),
                .init(
                    kind: .possibleExplanation,
                    text: explanationText(
                        primaryChange: primaryChange,
                        hasMismatch: mismatchQuestion != nil,
                        context: context,
                        contextState: contextState,
                        followUpQuestion: followUpQuestion
                    )
                ),
                .init(
                    kind: .uncertainty,
                    text: uncertaintyText(hasQualifiedChange: primaryChange != nil)
                ),
                .init(
                    kind: .recommendation,
                    text: recommendationText(
                        primaryChange: primaryChange,
                        hasMismatch: mismatchQuestion != nil,
                        hasCompleteStableSet: hasCompleteStableSet,
                        context: context,
                        planCandidate: planCandidate
                    )
                )
            ],
            followUpQuestion: followUpQuestion,
            planCandidate: planCandidate,
            evidence: evidencePresentation(factSet: factSet, facts: evidenceFacts),
            interactionIdentity: interactionIdentity,
            isDemo: factSet.dataMode == .demo
        )
    }

    private static func stableInteractionID(
        factSet: InsightFactSet,
        topic: InsightInteractionTopic,
        evidenceFacts: [InsightFact],
        decision: InsightFollowUpDecision?,
        context: InsightContextMatch?
    ) -> UUID {
        let questionID: String
        if case let .some(.ask(question)) = decision {
            questionID = question.id.uuidString.lowercased()
        } else {
            questionID = "none"
        }
        let factIDs = evidenceFacts
            .map { $0.id.uuidString.lowercased() }
            .sorted()
            .joined(separator: ",")
        let contextKeys = (context?.references ?? [])
            .map {
                [
                    $0.kind.rawValue,
                    $0.recordID.uuidString.lowercased(),
                    String($0.updatedAt.timeIntervalSince1970.bitPattern)
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: ",")
        let name = [
            version,
            factSet.generatorVersion,
            factSet.dataMode.rawValue,
            factSet.timeZoneIdentifier,
            String(factSet.analysisInterval.start.timeIntervalSince1970.bitPattern),
            String(factSet.analysisInterval.end.timeIntervalSince1970.bitPattern),
            topic.storageKey,
            factIDs,
            questionID,
            contextKeys
        ].joined(separator: "\u{1F}")
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func canonicalFacts(in factSet: InsightFactSet) -> [InsightFact] {
        HealthMetricType.allCases.compactMap { metric in
            factSet.facts.first(where: { $0.metric == metric })
        }
    }

    private static func rankedChanges(_ facts: [InsightFact]) -> [InsightFact] {
        let metricOrder = Dictionary(uniqueKeysWithValues:
            HealthMetricType.allCases.enumerated().map { ($0.element, $0.offset) }
        )
        return facts.sorted { left, right in
            let leftRank = changeRank(left)
            let rightRank = changeRank(right)
            if leftRank.level != rightRank.level { return leftRank.level > rightRank.level }
            if leftRank.magnitude != rightRank.magnitude {
                return leftRank.magnitude > rightRank.magnitude
            }
            return (metricOrder[left.metric] ?? .max) < (metricOrder[right.metric] ?? .max)
        }
    }

    private static func changeRank(_ fact: InsightFact) -> (level: Int, magnitude: Double) {
        guard case let .evaluated(trend, _) = fact.evidence,
              case let .trend(level) = trend.state else { return (0, 0) }
        let rank = level == .sustainedChange ? 2 : 1
        let magnitude = abs(trend.relativeChange ?? 0) / max(trend.effectiveRelativeThreshold ?? 1, 0.000_001)
        return (rank, magnitude)
    }

    private static func title(
        primaryChange: InsightFact?,
        hasMismatch: Bool,
        hasCompleteStableSet: Bool
    ) -> String {
        if primaryChange != nil { return "本周有一项变化值得看" }
        if hasMismatch { return "感受值得单独关注" }
        if hasCompleteStableSet { return "本周暂未见明确变化" }
        return "正在了解你的近期状态"
    }

    private static func factText(
        primaryChange: InsightFact?,
        hasMismatch: Bool,
        hasCompleteStableSet: Bool
    ) -> String {
        if let primaryChange,
           case let .evaluated(trend, _) = primaryChange.evidence,
           let current = trend.currentMedianValue,
           let baseline = trend.baselineMedianValue,
           let relative = trend.relativeChange,
           case let .trend(level) = trend.state {
            let direction = relative >= 0 ? "上升" : "下降"
            let stateText = level == .sustainedChange ? "存在持续变化" : "值得继续观察"
            return "最近 7 个完整日，\(metricTitle(primaryChange.metric))中位数为 \(format(current, unit: trend.unit))，相比此前 28 日个人基线 \(format(baseline, unit: trend.unit))，\(direction) \(formatPercent(abs(relative)))；程序判定为“\(stateText)”。"
        }
        if hasMismatch {
            return "四项核心指标在最近 7 个完整日内均未见明确变化；你保存的感受记录仍值得单独重视。"
        }
        if hasCompleteStableSet {
            return "当前达到质量门槛的指标未见需要强提醒的持续变化。"
        }
        return "目前有效日、个人基线或数据来源尚不足以形成可靠的变化结论。"
    }

    private static func explanationText(
        primaryChange: InsightFact?,
        hasMismatch: Bool,
        context: InsightContextMatch?,
        contextState: InsightCardContextState,
        followUpQuestion: String?
    ) -> String {
        if contextState == .readFailed {
            return "主观记录暂时无法读取，因此本次不补充生活背景，也不会据此追问或猜测原因。"
        }
        if contextState == .demoMode {
            return "演示模式只展示规则效果，不读取或混用你的真实感受和生活事件。"
        }
        if hasMismatch {
            return "设备记录没有明显变化并不能否定你的感受；还需要生活背景才能进一步理解。"
        }
        if primaryChange != nil, let events = context?.contextEvents, !events.isEmpty {
            let titles = Array(Set(events.map { $0.kind.title })).sorted().prefix(2)
            return "同期记录了\(titles.joined(separator: "、"))。这些事件在时间上重叠，可能相关，但目前不能确定具体原因。"
        }
        if primaryChange != nil, context?.checkIns.isEmpty == false {
            return "同期已有主观感受记录，可作为理解变化的背景；它与指标同时出现不代表存在因果关系。"
        }
        if followUpQuestion != nil {
            return "目前缺少关键背景，因此先不猜测原因。"
        }
        return primaryChange == nil
            ? "当前没有足够明确的客观变化需要建立原因解释。"
            : "目前没有足够的同期背景支持具体解释。"
    }

    private static func uncertaintyText(hasQualifiedChange: Bool) -> String {
        if hasQualifiedChange {
            return "该结果基于有限的 7/28 天窗口，只反映相对个人基线的同期变化；未佩戴、测量时间和其他因素都可能影响记录，不能用于诊断或证明因果。"
        }
        return "当前证据不足以支持强结论；缺失数据不会按 0 处理，也不会据此判断健康变差。"
    }

    private static func recommendationText(
        primaryChange: InsightFact?,
        hasMismatch: Bool,
        hasCompleteStableSet: Bool,
        context: InsightContextMatch?,
        planCandidate: InsightPlanCandidate?
    ) -> String {
        if hasMismatch {
            return "优先按自己的感受安排休息或日常节奏，并可补充一个生活背景；不需要等待设备数据来证明感受。"
        }
        if hasCompleteStableSet {
            return "保持当前节奏，继续观察即可；没有明确变化时不额外增加行动负担。"
        }
        guard primaryChange != nil else {
            return "继续按意愿佩戴设备和记录感受，等有效日与来源稳定后再判断。"
        }
        if let planCandidate,
           let template = MicroPlanTemplateLibrary.template(for: planCandidate.templateID) {
            return "可以考虑把“\(template.title)”作为一个 \(template.durationDays) 天低风险候选；是否开始由你确认，本卡不会自动创建计划。"
        }
        let needsCare = context?.checkIns.contains {
            $0.energy.rawValue <= SubjectiveRating.two.rawValue
                || $0.stress.rawValue >= SubjectiveRating.four.rawValue
                || $0.bodyFeeling.rawValue <= SubjectiveRating.two.rawValue
        } == true
        return needsCare
            ? "先照顾当下感受，保持低负担并继续记录未来几天；本卡不会自动创建微计划。"
            : "保持当前节奏，继续观察未来几天；暂不因为单项变化自动调整计划。"
    }

    fileprivate static func metricTitle(_ metric: HealthMetricType) -> String {
        switch metric {
        case .stepCount: "步数"
        case .sleepDuration: "睡眠时长"
        case .restingHeartRate: "静息心率"
        case .heartRateVariability: "HRV"
        case .activeEnergy: "活动能量"
        case .exerciseDuration: "运动分钟"
        case .standHours: "站立小时"
        case .heartRate: "心率"
        case .respiratoryRate: "呼吸频率"
        case .oxygenSaturation: "血氧"
        case .wristTemperature: "睡眠腕温"
        case .walkingRunningDistance: "步行与跑步距离"
        case .flightsClimbed: "爬楼层数"
        case .walkingSpeed: "步行速度"
        case .walkingStepLength: "步长"
        case .vo2Max: "心肺适能"
        }
    }

    private static func formatPercent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(value < 0.1 ? 1 : 0)))
    }

    private static func format(_ value: Double, unit: HealthMetricUnit) -> String {
        let digits: Int = switch unit {
        case .count, .beatsPerMinute, .milliseconds, .kilocalories, .minutes, .floors: 0
        case .hours, .breathsPerMinute, .percentage, .degreesCelsius,
             .millilitersPerKilogramPerMinute: 1
        case .kilometers, .metersPerSecond, .meters: 2
        }
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return switch unit {
        case .count: "\(number) 步"
        case .hours: "\(number) 小时"
        case .beatsPerMinute: "\(number) 次/分"
        case .milliseconds: "\(number) ms"
        case .kilocalories: "\(number) 千卡"
        case .minutes: "\(number) 分钟"
        case .breathsPerMinute: "\(number) 次/分"
        case .percentage: "\(number)%"
        case .degreesCelsius: "\(number)℃"
        case .kilometers: "\(number) 公里"
        case .floors: "\(number) 层"
        case .metersPerSecond: "\(number) 米/秒"
        case .meters: "\(number) 米"
        case .millilitersPerKilogramPerMinute: "\(number) ml/kg·min"
        }
    }

    private static func evidencePresentation(
        factSet: InsightFactSet,
        facts: [InsightFact]
    ) -> InsightEvidencePresentation {
        let items = facts.map { fact in
            evidenceItem(
                fact,
                generatorVersion: factSet.generatorVersion,
                analysisInterval: factSet.analysisInterval,
                timeZoneIdentifier: factSet.timeZoneIdentifier
            )
        }
        return InsightEvidencePresentation(
            title: "数据依据与来源",
            summary: "本地聚合 · \(items.count) 项事实",
            timeZoneText: "按 \(factSet.timeZoneIdentifier) 的完整本地日计算",
            items: items
        )
    }

    private static func evidenceItem(
        _ fact: InsightFact,
        generatorVersion: String,
        analysisInterval: DateInterval,
        timeZoneIdentifier: String
    ) -> InsightEvidencePresentation.Item {
        switch fact.evidence {
        case .evaluated(let trend, let sources):
            let sourceNames = Array(Set(sources.map(\.displayName))).sorted()
            let sourceText = sourceNames.isEmpty
                ? "未形成可用来源"
                : sourceNames.joined(separator: "、")
            let currentValue = trend.currentMedianValue.map { format($0, unit: trend.unit) } ?? "未形成中位数"
            let baselineValue = trend.baselineMedianValue.map { format($0, unit: trend.unit) } ?? "未形成中位数"
            let changeText: String? = if let change = trend.relativeChange,
                                         let threshold = trend.effectiveRelativeThreshold {
                "相对变化 \(signedPercent(change)) · 实际门槛 \(formatPercent(threshold))"
            } else {
                nil
            }
            let alignmentText: String? = if let aligned = trend.alignedDayCount,
                                            let analyzed = trend.analysisDayCount,
                                            let required = trend.requiredAlignedDayCount {
                "同向日 \(aligned)/\(analyzed) · 至少需要 \(required) 日"
            } else {
                nil
            }
            return InsightEvidencePresentation.Item(
                id: fact.id,
                metric: fact.metric,
                metricTitle: metricTitle(fact.metric),
                currentWindowText: "最近窗口 \(intervalText(trend.currentInterval, timeZoneIdentifier: timeZoneIdentifier)) · 有效日 \(trend.currentValidDayCount)/\(trend.currentExpectedDayCount) · 中位数 \(currentValue)",
                baselineWindowText: "基线窗口 \(intervalText(trend.baselineInterval, timeZoneIdentifier: timeZoneIdentifier)) · 有效日 \(trend.baselineValidDayCount)/\(trend.baselineExpectedDayCount) · 中位数 \(baselineValue)",
                changeText: changeText,
                alignmentText: alignmentText,
                sourceText: sourceText,
                qualityText: evidenceQualityText(trend),
                versionText: "趋势规则 \(trend.thresholdVersion) · 事实生成 \(generatorVersion)"
            )
        case .unavailable(let reason):
            return InsightEvidencePresentation.Item(
                id: fact.id,
                metric: fact.metric,
                metricTitle: metricTitle(fact.metric),
                currentWindowText: "分析范围 \(intervalText(analysisInterval, timeZoneIdentifier: timeZoneIdentifier))",
                baselineWindowText: nil,
                changeText: nil,
                alignmentText: nil,
                sourceText: "未形成可用来源",
                qualityText: unavailableReasonText(reason),
                versionText: "事实生成 \(generatorVersion)"
            )
        }
    }

    private static func evidenceQualityText(_ trend: HealthMetricTrendEvidence) -> String {
        switch trend.state {
        case .currentWindowInsufficient:
            "最近窗口有效日不足；至少需要 \(HealthDataQualityThresholds.shortTermMinimumValidDays) 日"
        case .baselineInsufficient:
            "个人基线有效日不足；至少需要 \(HealthDataQualityThresholds.baselineMinimumValidDays) 日"
        case .sourceChanged:
            "两个窗口的数据来源发生变化，本卡不据此形成强结论"
        case .trend:
            if trend.isolatedOutlierExcluded {
                "已启用孤立日期保护；该日期不参与本次结论，原记录仍保留"
            } else if trend.sourceIsStable {
                "来源稳定，没有需要单独保护的孤立日期"
            } else {
                "来源不稳定，本卡不据此形成强结论"
            }
        }
    }

    private static func unavailableReasonText(_ reason: InsightDataUnavailableReason) -> String {
        switch reason {
        case .accessNotRequested: "尚未申请健康数据访问"
        case .healthDataUnavailable: "当前设备无法提供健康数据"
        case .noVisibleData: "当前没有可见记录；不会按 0 处理"
        case .queryFailed: "本次读取失败；不会用旧值或 0 代替"
        case .notLoaded: "健康数据尚未完成加载"
        case .queryWindowIncomplete: "读取范围未完整覆盖 7/28 天窗口"
        case .sourceConflict: "同一日期存在来源冲突，未合并为结论"
        case .sourceChanged: "数据来源发生变化，未形成可比较结论"
        case .recentDataGap: "最近完整日缺少记录，暂不形成趋势"
        case .unsupportedMetric: "该指标尚未配置趋势规则"
        case .analysisUnavailable: "当前无法形成可解释的聚合结果"
        }
    }

    private static func intervalText(
        _ interval: DateInterval,
        timeZoneIdentifier: String
    ) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return "时间范围不可用" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let lastIncludedDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            return "时间范围不可用"
        }
        return "\(dayText(interval.start, calendar: calendar))—\(dayText(lastIncludedDay, calendar: calendar))"
    }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "日期不可用"
        }
        return "\(year)年\(month)月\(day)日"
    }

    private static func signedPercent(_ value: Double) -> String {
        let formatted = formatPercent(value)
        return value > 0 ? "+\(formatted)" : formatted
    }
}
