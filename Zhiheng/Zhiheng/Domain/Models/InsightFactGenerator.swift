import CryptoKit
import Foundation

struct InsightFactSet: Equatable, Sendable {
    let generatorVersion: String
    let analysisInterval: DateInterval
    let timeZoneIdentifier: String
    let dataMode: HealthDataMode
    let facts: [InsightFact]
}

enum InsightFactGenerationError: Error, Equatable, Sendable {
    case invalidReferenceDate
    case noMetrics
}

/// Converts a shared aggregate health snapshot into typed local facts.
/// It does not read HealthKit, infer causes, create prose or choose an action.
enum InsightFactGenerator {
    static let version = "s09-fact-generator-v1"

    static func generate(
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        dataMode: HealthDataMode,
        referenceDate: Date,
        timeZone: TimeZone,
        metrics: [HealthMetricType] = HealthMetricTrendThresholdCatalog.todayCandidateMetrics
    ) throws -> InsightFactSet {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw InsightFactGenerationError.invalidReferenceDate
        }
        let requested = Set(metrics)
        let orderedMetrics = HealthMetricType.allCases.filter(requested.contains)
        guard !orderedMetrics.isEmpty else { throw InsightFactGenerationError.noMetrics }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: referenceDate)
        guard let currentStart = calendar.date(
            byAdding: .day,
            value: -HealthDataQualityThresholds.shortTermExpectedDays,
            to: end
        ), let start = calendar.date(
            byAdding: .day,
            value: -HealthDataQualityThresholds.baselineExpectedDays,
            to: currentStart
        ), let latestCompleteDay = calendar.date(byAdding: .day, value: -1, to: end) else {
            throw InsightFactGenerationError.invalidReferenceDate
        }
        let interval = DateInterval(start: start, end: end)
        let facts = orderedMetrics.map { metric in
            InsightFact(
                id: stableFactID(
                    metric: metric,
                    intervalEnd: end,
                    timeZone: timeZone,
                    dataMode: dataMode
                ),
                metric: metric,
                evidence: evidence(
                    for: metric,
                    snapshot: snapshot,
                    loadedInterval: loadedInterval,
                    access: access,
                    interval: interval,
                    latestCompleteDay: latestCompleteDay,
                    calendar: calendar
                )
            )
        }
        return InsightFactSet(
            generatorVersion: version,
            analysisInterval: interval,
            timeZoneIdentifier: timeZone.identifier,
            dataMode: dataMode,
            facts: facts
        )
    }

    private static func evidence(
        for metric: HealthMetricType,
        snapshot: HealthDataSnapshot?,
        loadedInterval: DateInterval?,
        access: HealthAccessState,
        interval: DateInterval,
        latestCompleteDay: Date,
        calendar: Calendar
    ) -> InsightMetricEvidence {
        guard HealthMetricTrendThresholdCatalog.threshold(for: metric) != nil else {
            return .unavailable(.unsupportedMetric)
        }
        switch access {
        case .notRequested: return .unavailable(.accessNotRequested)
        case .unavailable: return .unavailable(.healthDataUnavailable)
        case .requestCompleted: break
        }
        guard let snapshot else { return .unavailable(.notLoaded) }
        guard let loadedInterval else { return .unavailable(.notLoaded) }
        guard loadedInterval.start <= interval.start, loadedInterval.end >= interval.end else {
            return .unavailable(.queryWindowIncomplete)
        }
        guard let state = snapshot[metric] else { return .unavailable(.notLoaded) }
        let values: [HealthMetricSample]
        switch state {
        case .accessNotRequested: return .unavailable(.accessNotRequested)
        case .healthDataUnavailable: return .unavailable(.healthDataUnavailable)
        case .noVisibleData: return .unavailable(.noVisibleData)
        case .failed(.healthDataUnavailable): return .unavailable(.healthDataUnavailable)
        case .failed: return .unavailable(.queryFailed)
        case .available(let samples):
            values = samples.filter {
                $0.metricType == metric && $0.endDate >= interval.start && $0.endDate < interval.end
            }
        }
        guard !values.isEmpty else { return .unavailable(.noVisibleData) }

        let summary = sourceSummary(metric: metric, samples: values, calendar: calendar)
        guard !summary.hasConflict else { return .unavailable(.sourceConflict) }
        guard summary.selectedDays.contains(latestCompleteDay) else {
            return .unavailable(.recentDataGap)
        }
        guard let trend = HealthMetricTrendEvidenceBuilder.make(
            metric: metric,
            samples: values,
            endingAt: interval.end.addingTimeInterval(-1),
            calendar: calendar
        ) else {
            return .unavailable(.analysisUnavailable)
        }
        // Exact source metadata changing across days is treated conservatively even
        // if an underlying provider keeps the same bundle identifier.
        if summary.sources.count > 1, trend.sourceIsStable {
            return .unavailable(.sourceChanged)
        }
        return .evaluated(trend, sources: summary.sources)
    }

    private struct SourceSummary {
        let sources: [HealthMetricSource]
        let selectedDays: Set<Date>
        let hasConflict: Bool
    }

    private static func sourceSummary(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        calendar: Calendar
    ) -> SourceSummary {
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        var sources = Set<HealthMetricSource>()
        var selectedDays = Set<Date>()
        var hasConflict = false
        for (day, values) in grouped {
            let selected: [HealthMetricSample]?
            switch metric {
            case .stepCount, .sleepDuration, .activeEnergy, .exerciseDuration:
                selected = PreferredHealthMetricSourceSelector.samples(from: values)
            default:
                selected = Set(values.map(\.source)).count == 1 ? values : nil
            }
            guard let selected else {
                hasConflict = true
                continue
            }
            selectedDays.insert(day)
            sources.formUnion(selected.map(\.source))
        }
        return SourceSummary(
            sources: sources.sorted { sourceKey($0) < sourceKey($1) },
            selectedDays: selectedDays,
            hasConflict: hasConflict
        )
    }

    private static func sourceKey(_ source: HealthMetricSource) -> String {
        [source.sourceName, source.bundleIdentifier ?? "", source.deviceName ?? "",
         source.productType ?? ""].joined(separator: "\u{1F}")
    }

    private static func stableFactID(
        metric: HealthMetricType,
        intervalEnd: Date,
        timeZone: TimeZone,
        dataMode: HealthDataMode
    ) -> UUID {
        let name = [
            version, metric.rawValue, dataMode.rawValue, timeZone.identifier,
            String(intervalEnd.timeIntervalSince1970.bitPattern)
        ].joined(separator: "\u{1F}")
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        // RFC 9562 UUID version 8: application-defined bytes with the standard variant.
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
