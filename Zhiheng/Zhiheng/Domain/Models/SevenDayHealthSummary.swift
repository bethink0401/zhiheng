import Foundation

struct SevenDayHealthSummary: Equatable, Sendable {
    struct ObjectiveFact: Identifiable, Equatable, Sendable {
        var id: HealthMetricType { metric }

        let metric: HealthMetricType
        let unit: HealthMetricUnit
        let currentMedianValue: Double?
        let baselineMedianValue: Double?
        let relativeChange: Double?
        let currentValidDayCount: Int?
        let currentExpectedDayCount: Int?
        let baselineValidDayCount: Int?
        let baselineExpectedDayCount: Int?
        let trendState: HealthMetricTrendEvidenceState?
        let sourceNames: [String]
        let unavailableReason: InsightDataUnavailableReason?
    }

    struct SubjectiveValues: Equatable, Sendable {
        let recordedDayCount: Int
        let expectedDayCount: Int
        let energyMedian: Double
        let stressMedian: Double
        let bodyFeelingMedian: Double
    }

    enum SubjectiveState: Equatable, Sendable {
        case available(SubjectiveValues)
        case notRecorded
        case demoMode
        case unavailable
    }

    struct ContextEventCount: Identifiable, Equatable, Sendable {
        var id: ContextEventKind { kind }
        let kind: ContextEventKind
        let count: Int
    }

    enum ContextState: Equatable, Sendable {
        case available([ContextEventCount])
        case notRecorded
        case demoMode
        case unavailable
    }

    struct Recommendation: Equatable, Sendable {
        let text: String
        let sourceText: String
        let usesAI: Bool
        let automaticallyCreatesPlan: Bool
    }

    static let version = "s13-seven-day-health-summary-v1"

    let version: String
    let generatedAt: Date
    let interval: DateInterval
    let baselineInterval: DateInterval
    let timeZoneIdentifier: String
    let dataMode: HealthDataMode
    let title: String
    let factSummary: String
    let uncertainty: String
    let objectiveFacts: [ObjectiveFact]
    let subjectiveState: SubjectiveState
    let contextState: ContextState
    let recommendation: Recommendation
}

enum SevenDayHealthSummaryError: Error, Equatable, Sendable {
    case invalidFactSet
    case invalidContextState
}

/// Builds an in-memory report projection from the existing insight facts and
/// structured context. It does not query, persist, call AI or create a plan.
enum SevenDayHealthSummaryFactory {
    static let objectiveMetrics: [HealthMetricType] = [
        .sleepDuration,
        .heartRateVariability,
        .restingHeartRate,
        .stepCount
    ]

    static func make(
        factSet: InsightFactSet,
        contextState: InsightContextLoadState,
        generatedAt: Date
    ) throws -> SevenDayHealthSummary {
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
              generatedAt >= factSet.analysisInterval.end,
              TimeZone(identifier: factSet.timeZoneIdentifier) != nil,
              Set(factSet.facts.map(\.metric)).count == factSet.facts.count,
              Set(objectiveMetrics).isSubset(of: Set(factSet.facts.map(\.metric))) else {
            throw SevenDayHealthSummaryError.invalidFactSet
        }

        let window: InsightContextWindow
        do {
            window = try InsightContextMatcher.window(for: factSet)
        } catch {
            throw SevenDayHealthSummaryError.invalidFactSet
        }

        let cardContext: InsightCardContextState
        let subjectiveState: SevenDayHealthSummary.SubjectiveState
        let summaryContextState: SevenDayHealthSummary.ContextState
        switch contextState {
        case .available(let context):
            guard factSet.dataMode == .live,
                  context.dataMode == .live,
                  context.window == window else {
                throw SevenDayHealthSummaryError.invalidContextState
            }
            cardContext = .available(context)
            subjectiveState = subjectiveSummary(context.checkIns)
            summaryContextState = eventSummary(context.contextEvents)
        case .demoMode:
            guard factSet.dataMode == .demo else {
                throw SevenDayHealthSummaryError.invalidContextState
            }
            cardContext = .demoMode
            subjectiveState = .demoMode
            summaryContextState = .demoMode
        case .failed:
            guard factSet.dataMode == .live else {
                throw SevenDayHealthSummaryError.invalidContextState
            }
            cardContext = .readFailed
            subjectiveState = .unavailable
            summaryContextState = .unavailable
        }

        let card: InsightFourLayerCardPresentation
        do {
            card = try InsightFourLayerCardFactory.make(
                factSet: factSet,
                contextState: cardContext
            )
        } catch {
            throw SevenDayHealthSummaryError.invalidContextState
        }
        guard let factSummary = card.layers.first(where: { $0.kind == .fact })?.text,
              let uncertainty = card.layers.first(where: { $0.kind == .uncertainty })?.text,
              let recommendationText = card.layers.first(where: {
                  $0.kind == .recommendation
              })?.text else {
            throw SevenDayHealthSummaryError.invalidFactSet
        }

        let factsByMetric = Dictionary(uniqueKeysWithValues:
            factSet.facts.map { ($0.metric, $0) }
        )
        let objectiveFacts = try objectiveMetrics.map { metric in
            guard let fact = factsByMetric[metric] else {
                throw SevenDayHealthSummaryError.invalidFactSet
            }
            return objectiveFact(from: fact)
        }

        return SevenDayHealthSummary(
            version: SevenDayHealthSummary.version,
            generatedAt: generatedAt,
            interval: window.interval,
            baselineInterval: DateInterval(
                start: factSet.analysisInterval.start,
                end: window.interval.start
            ),
            timeZoneIdentifier: factSet.timeZoneIdentifier,
            dataMode: factSet.dataMode,
            title: card.title,
            factSummary: factSummary,
            uncertainty: uncertainty,
            objectiveFacts: objectiveFacts,
            subjectiveState: subjectiveState,
            contextState: summaryContextState,
            recommendation: SevenDayHealthSummary.Recommendation(
                text: recommendationText,
                sourceText: recommendationSource(
                    dataMode: factSet.dataMode,
                    contextState: contextState,
                    hasPlanCandidate: card.planCandidate != nil
                ),
                usesAI: false,
                automaticallyCreatesPlan: false
            )
        )
    }

    private static func objectiveFact(
        from fact: InsightFact
    ) -> SevenDayHealthSummary.ObjectiveFact {
        switch fact.evidence {
        case .evaluated(let trend, let sources):
            return SevenDayHealthSummary.ObjectiveFact(
                metric: fact.metric,
                unit: trend.unit,
                currentMedianValue: trend.currentMedianValue,
                baselineMedianValue: trend.baselineMedianValue,
                relativeChange: trend.relativeChange,
                currentValidDayCount: trend.currentValidDayCount,
                currentExpectedDayCount: trend.currentExpectedDayCount,
                baselineValidDayCount: trend.baselineValidDayCount,
                baselineExpectedDayCount: trend.baselineExpectedDayCount,
                trendState: trend.state,
                sourceNames: Array(Set(sources.map(\.displayName))).sorted(),
                unavailableReason: nil
            )
        case .unavailable(let reason):
            return SevenDayHealthSummary.ObjectiveFact(
                metric: fact.metric,
                unit: fact.metric.expectedUnit,
                currentMedianValue: nil,
                baselineMedianValue: nil,
                relativeChange: nil,
                currentValidDayCount: nil,
                currentExpectedDayCount: nil,
                baselineValidDayCount: nil,
                baselineExpectedDayCount: nil,
                trendState: nil,
                sourceNames: [],
                unavailableReason: reason
            )
        }
    }

    private static func subjectiveSummary(
        _ checkIns: [InsightMatchedCheckIn]
    ) -> SevenDayHealthSummary.SubjectiveState {
        guard !checkIns.isEmpty else { return .notRecorded }
        return .available(SevenDayHealthSummary.SubjectiveValues(
            recordedDayCount: checkIns.count,
            expectedDayCount: HealthDataQualityThresholds.shortTermExpectedDays,
            energyMedian: median(checkIns.map { Double($0.energy.rawValue) }),
            stressMedian: median(checkIns.map { Double($0.stress.rawValue) }),
            bodyFeelingMedian: median(checkIns.map { Double($0.bodyFeeling.rawValue) })
        ))
    }

    private static func eventSummary(
        _ events: [InsightMatchedContextEvent]
    ) -> SevenDayHealthSummary.ContextState {
        guard !events.isEmpty else { return .notRecorded }
        let grouped = Dictionary(grouping: events, by: \.kind)
        let values = ContextEventKind.allCases.compactMap { kind in
            grouped[kind].map {
                SevenDayHealthSummary.ContextEventCount(kind: kind, count: $0.count)
            }
        }
        return .available(values)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func recommendationSource(
        dataMode: HealthDataMode,
        contextState: InsightContextLoadState,
        hasPlanCandidate: Bool
    ) -> String {
        if dataMode == .demo {
            return "来源：明确标注的演示健康事实与本地规则；未读取真实感受，未使用 AI。"
        }
        if case .failed = contextState {
            return "来源：本地 7/28 天趋势与数据质量；主观记录暂时无法读取，未使用 AI。"
        }
        if hasPlanCandidate {
            return "来源：本地 7/28 天趋势、结构化感受与生活情境、低风险模板规则；未使用 AI。"
        }
        return "来源：本地 7/28 天趋势、数据质量与本机结构化记录；未使用 AI。"
    }
}
