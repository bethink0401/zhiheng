import Foundation

enum HealthFactPackBuilder {
    static let includedMetrics: [HealthMetricType] = HealthMetricType.allCases

    static func build(
        snapshot: HealthDataSnapshot,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        supplementalFacts: HealthFactSupplementalFacts? = nil
    ) -> HealthFactPack {
        let historyStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.inventoryExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        let shortTermStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.shortTermExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        let shortTermInterval = DateInterval(
            start: shortTermStart,
            end: referenceDate
        )

        var facts = [HealthFactMetric]()
        var unavailable = [HealthFactUnavailableMetric]()

        for metric in includedMetrics {
            switch snapshot[metric] {
            case let .available(samples):
                let quality = try? HealthDataQualityCalculator.evaluate(
                    metric: metric,
                    samples: samples,
                    interval: shortTermInterval,
                    calendar: calendar
                )
                let baselineResult = HealthMetricBaselineEngine.calculate(
                    metric: metric,
                    samples: samples,
                    endingAt: referenceDate,
                    calendar: calendar
                )
                facts.append(HealthFactMetric(
                    metric: metric,
                    current: currentValue(
                        metric: metric,
                        samples: samples,
                        referenceDate: referenceDate,
                        calendar: calendar
                    ),
                    shortTermQuality: HealthFactDataQuality(
                        expectedDayCount: quality?.expectedDayCount
                            ?? HealthDataQualityThresholds.shortTermExpectedDays,
                        validDayCount: quality?.validDayCount ?? 0,
                        coverageRatio: quality?.coverageRatio ?? 0,
                        longestMissingDayStreak: quality?.longestMissingDayStreak
                            ?? HealthDataQualityThresholds.shortTermExpectedDays,
                        supportsObservation: quality?.supportsShortTermObservation
                            ?? false
                    ),
                    baseline: baseline(from: baselineResult),
                    trend: trend(
                        metric: metric,
                        samples: samples,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                ))
            case .accessNotRequested:
                unavailable.append(.init(
                    metric: metric,
                    reason: .accessNotRequested
                ))
            case .healthDataUnavailable:
                unavailable.append(.init(
                    metric: metric,
                    reason: .healthDataUnavailable
                ))
            case .noVisibleData, .none:
                unavailable.append(.init(
                    metric: metric,
                    reason: .noVisibleData
                ))
            case .failed:
                unavailable.append(.init(
                    metric: metric,
                    reason: .queryFailed
                ))
            }
        }

        return HealthFactPack(
            generatedAt: referenceDate,
            rangeStart: historyStart,
            rangeEnd: referenceDate,
            dataMode: dataMode,
            metrics: facts,
            unavailableMetrics: unavailable,
            highlightedChangeMetric: TodayImportantChangeSelector.select(
                snapshot: snapshot,
                selectedDate: referenceDate,
                calendar: calendar
            )?.metric,
            supplementalFacts: supplementalFacts
        )
    }

    static func empty(
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        supplementalFacts: HealthFactSupplementalFacts? = nil
    ) -> HealthFactPack {
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -(HealthDataQualityThresholds.inventoryExpectedDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
        return HealthFactPack(
            generatedAt: referenceDate,
            rangeStart: rangeStart,
            rangeEnd: referenceDate,
            dataMode: dataMode,
            metrics: [],
            unavailableMetrics: includedMetrics.map {
                HealthFactUnavailableMetric(metric: $0, reason: .noVisibleData)
            },
            supplementalFacts: supplementalFacts
        )
    }

    private static func currentValue(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        referenceDate: Date,
        calendar: Calendar
    ) -> HealthFactCurrentValue? {
        guard case let .value(summary) = HealthMetricSummaryCalculator.summarize(
            metric: metric,
            samples: samples,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            return nil
        }
        return HealthFactCurrentValue(
            value: summary.value,
            unit: summary.unit,
            recordedAt: summary.date
        )
    }

    private static func baseline(
        from result: HealthMetricBaselineResult
    ) -> HealthFactBaseline? {
        guard case let .available(value) = result else { return nil }
        return HealthFactBaseline(
            medianValue: value.medianValue,
            medianAbsoluteDeviation: value.medianAbsoluteDeviation,
            unit: value.unit,
            validDayCount: value.validDayCount,
            expectedDayCount: value.expectedDayCount
        )
    }

    private static func trend(
        metric: HealthMetricType,
        samples: [HealthMetricSample],
        referenceDate: Date,
        calendar: Calendar
    ) -> HealthFactTrend? {
        guard let evidence = HealthMetricTrendEvidenceBuilder.make(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            calendar: calendar
        ) else { return nil }
        let state: HealthFactTrendState
        switch evidence.state {
        case .currentWindowInsufficient:
            state = .currentWindowInsufficient
        case .baselineInsufficient:
            state = .baselineInsufficient
        case .sourceChanged:
            state = .sourceChanged
        case .trend(.noClearChange):
            state = .noClearChange
        case .trend(.worthObserving):
            state = .worthObserving
        case .trend(.sustainedChange):
            state = .sustainedChange
        }
        let direction: HealthMetricTrendDirection? = evidence.relativeChange.map {
            $0 >= 0 ? .higher : .lower
        }
        return HealthFactTrend(
            state: state,
            currentRangeStart: evidence.currentInterval.start,
            currentRangeEnd: evidence.currentInterval.end,
            baselineRangeStart: evidence.baselineInterval.start,
            baselineRangeEnd: evidence.baselineInterval.end,
            currentMedianValue: evidence.currentMedianValue,
            baselineMedianValue: evidence.baselineMedianValue,
            relativeChange: evidence.relativeChange,
            currentValidDayCount: evidence.currentValidDayCount,
            currentExpectedDayCount: evidence.currentExpectedDayCount,
            baselineValidDayCount: evidence.baselineValidDayCount,
            baselineExpectedDayCount: evidence.baselineExpectedDayCount,
            direction: direction,
            isolatedOutlierExcluded: evidence.isolatedOutlierExcluded,
            sourceIsStable: evidence.sourceIsStable
        )
    }
}

enum HealthFactSupplementalFactsBuilder {
    static let recentCheckInNoteLimit = HealthDataQualityThresholds.shortTermExpectedDays
    static let contextEventDetailLimit = 20

    static func build(
        dataMode: HealthDataMode,
        referenceDate: Date,
        timeZone: TimeZone,
        todayCheckIn: DailyCheckIn?,
        didLoadTodayCheckIn: Bool,
        todayContextEvents: [ContextEvent],
        didLoadTodayContextEvents: Bool,
        recentContextState: AssistantFactContextLoadState?,
        plan: MicroPlan?,
        progress: MicroPlanProgress?,
        todayOutcome: PlanOutcomeState?,
        outcomeRecords: [PlanOutcomeRecord],
        didLoadPlan: Bool,
        includesSyntheticDemoFacts: Bool = false
    ) -> HealthFactSupplementalFacts {
        guard dataMode == .live || includesSyntheticDemoFacts else {
            return demoFacts()
        }
        return HealthFactSupplementalFacts(
            todayFeeling: todayFeeling(
                record: todayCheckIn,
                didLoad: didLoadTodayCheckIn
            ),
            recentFeelings: recentFeelings(from: recentContextState),
            todayLifeEvents: lifeEvents(
                events: todayContextEvents,
                didLoad: didLoadTodayContextEvents,
                interval: dayInterval(
                    containing: referenceDate,
                    timeZone: timeZone
                )
            ),
            recentLifeEvents: recentLifeEvents(from: recentContextState),
            microPlan: microPlan(
                plan: plan,
                progress: progress,
                todayOutcome: todayOutcome,
                outcomeRecords: outcomeRecords,
                didLoad: didLoadPlan
            )
        )
    }

    private static func todayFeeling(
        record: DailyCheckIn?,
        didLoad: Bool
    ) -> HealthFactTodayFeeling {
        guard didLoad else {
            return .init(
                status: .unavailable, localDay: nil,
                energy: nil, stress: nil, bodyFeeling: nil, note: nil
            )
        }
        guard let record else {
            return .init(
                status: .notRecorded, localDay: nil,
                energy: nil, stress: nil, bodyFeeling: nil, note: nil
            )
        }
        return .init(
            status: .recorded,
            localDay: record.localDay.storageKey,
            energy: record.energy.rawValue,
            stress: record.stress.rawValue,
            bodyFeeling: record.bodyFeeling.rawValue,
            note: boundedText(
                record.note,
                maximumLength: DailyCheckIn.noteCharacterLimit
            )
        )
    }

    private static func recentFeelings(
        from state: AssistantFactContextLoadState?
    ) -> HealthFactRecentFeelings {
        guard let state else {
            return emptyRecentFeelings(status: .unavailable)
        }
        switch state {
        case .demoMode:
            return emptyRecentFeelings(status: .demoMode)
        case .failed:
            return emptyRecentFeelings(status: .unavailable)
        case .available(let context):
            guard !context.checkIns.isEmpty else {
                return HealthFactRecentFeelings(
                    status: .notRecorded,
                    rangeStart: context.window.interval.start,
                    rangeEnd: context.window.interval.end,
                    recordedDayCount: 0,
                    expectedDayCount: context.window.localDays.count,
                    energyMedian: nil,
                    stressMedian: nil,
                    bodyFeelingMedian: nil,
                    notes: []
                )
            }
            return HealthFactRecentFeelings(
                status: .recorded,
                rangeStart: context.window.interval.start,
                rangeEnd: context.window.interval.end,
                recordedDayCount: context.checkIns.count,
                expectedDayCount: context.window.localDays.count,
                energyMedian: median(context.checkIns.map { Double($0.energy.rawValue) }),
                stressMedian: median(context.checkIns.map { Double($0.stress.rawValue) }),
                bodyFeelingMedian: median(
                    context.checkIns.map { Double($0.bodyFeeling.rawValue) }
                ),
                notes: Array(context.checkIns.sorted {
                    $0.localDay.storageKey < $1.localDay.storageKey
                }.compactMap { record in
                    boundedText(
                        record.note,
                        maximumLength: DailyCheckIn.noteCharacterLimit
                    ).map {
                        HealthFactDailyNote(
                            localDay: record.localDay.storageKey,
                            note: $0
                        )
                    }
                }.prefix(recentCheckInNoteLimit))
            )
        }
    }

    private static func lifeEvents(
        events: [ContextEvent],
        didLoad: Bool,
        interval: DateInterval?
    ) -> HealthFactLifeEvents {
        guard didLoad else {
            return .init(
                status: .unavailable,
                rangeStart: interval?.start,
                rangeEnd: interval?.end,
                events: [],
                details: []
            )
        }
        return .init(
            status: events.isEmpty ? .notRecorded : .recorded,
            rangeStart: interval?.start,
            rangeEnd: interval?.end,
            events: aggregate(events.map { ($0.kind, $0.intensity) }),
            details: eventDetails(events)
        )
    }

    private static func recentLifeEvents(
        from state: AssistantFactContextLoadState?
    ) -> HealthFactLifeEvents {
        guard let state else {
            return .init(
                status: .unavailable, rangeStart: nil, rangeEnd: nil,
                events: [], details: []
            )
        }
        switch state {
        case .demoMode:
            return .init(
                status: .demoMode, rangeStart: nil, rangeEnd: nil,
                events: [], details: []
            )
        case .failed:
            return .init(
                status: .unavailable, rangeStart: nil, rangeEnd: nil,
                events: [], details: []
            )
        case .available(let context):
            return .init(
                status: context.contextEvents.isEmpty ? .notRecorded : .recorded,
                rangeStart: context.window.interval.start,
                rangeEnd: context.window.interval.end,
                events: aggregate(
                    context.contextEvents.map { ($0.kind, $0.intensity) }
                ),
                details: eventDetails(context.contextEvents)
            )
        }
    }

    private static func microPlan(
        plan: MicroPlan?,
        progress: MicroPlanProgress?,
        todayOutcome: PlanOutcomeState?,
        outcomeRecords: [PlanOutcomeRecord],
        didLoad: Bool
    ) -> HealthFactMicroPlan {
        guard didLoad else { return emptyMicroPlan(status: .unavailable) }
        guard let plan else { return emptyMicroPlan(status: .notRecorded) }
        guard let progress else { return emptyMicroPlan(status: .unavailable) }
        return HealthFactMicroPlan(
            status: .recorded,
            templateID: plan.draft.templateID,
            planTitle: plan.draft.title,
            taskTitle: plan.draft.taskTitle,
            planStatus: plan.status,
            startDate: plan.draft.startDate,
            endDateExclusive: plan.draft.endDateExclusive,
            scheduledTime: plan.draft.scheduledTime,
            scheduledCount: progress.scheduledCount,
            completedCount: progress.completedCount,
            skippedCount: progress.skippedCount,
            unresolvedCount: progress.unresolvedCount,
            completionRate: progress.completionFraction,
            todayOutcome: todayOutcome,
            userFeedback: Array(outcomeRecords.compactMap(\.feedback).suffix(7))
        )
    }

    private static func aggregate(
        _ events: [(ContextEventKind, ContextEventIntensity?)]
    ) -> [HealthFactContextEventSummary] {
        ContextEventKind.allCases.compactMap { kind in
            let matches = events.filter { $0.0 == kind }
            guard !matches.isEmpty else { return nil }
            return HealthFactContextEventSummary(
                kind: kind,
                occurrenceCount: matches.count,
                highestIntensity: matches.compactMap { $0.1 }.max {
                    $0.rawValue < $1.rawValue
                }
            )
        }
    }

    private static func eventDetails(
        _ events: [ContextEvent]
    ) -> [HealthFactContextEventDetail] {
        Array(events.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.compactMap { event in
            let customName = event.kind == .custom
                ? boundedText(
                    event.customLabel,
                    maximumLength: ContextEvent.customLabelCharacterLimit
                )
                : nil
            let note = boundedText(
                event.note,
                maximumLength: ContextEvent.noteCharacterLimit
            )
            guard customName != nil || note != nil else { return nil }
            return HealthFactContextEventDetail(
                kind: event.kind,
                customName: customName,
                note: note
            )
        }.prefix(contextEventDetailLimit))
    }

    private static func boundedText(
        _ value: String?,
        maximumLength: Int
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }

    private static func dayInterval(
        containing date: Date,
        timeZone: TimeZone
    ) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func emptyRecentFeelings(
        status: HealthFactRecordStatus
    ) -> HealthFactRecentFeelings {
        .init(
            status: status, rangeStart: nil, rangeEnd: nil,
            recordedDayCount: nil, expectedDayCount: nil,
            energyMedian: nil, stressMedian: nil, bodyFeelingMedian: nil,
            notes: []
        )
    }

    private static func emptyMicroPlan(
        status: HealthFactRecordStatus
    ) -> HealthFactMicroPlan {
        .init(
            status: status, templateID: nil, planTitle: nil, taskTitle: nil,
            planStatus: nil, startDate: nil, endDateExclusive: nil,
            scheduledTime: nil, scheduledCount: nil, completedCount: nil,
            skippedCount: nil, unresolvedCount: nil, completionRate: nil,
            todayOutcome: nil, userFeedback: []
        )
    }

    private static func demoFacts() -> HealthFactSupplementalFacts {
        HealthFactSupplementalFacts(
            todayFeeling: .init(
                status: .demoMode, localDay: nil,
                energy: nil, stress: nil, bodyFeeling: nil, note: nil
            ),
            recentFeelings: emptyRecentFeelings(status: .demoMode),
            todayLifeEvents: .init(
                status: .demoMode, rangeStart: nil, rangeEnd: nil,
                events: [], details: []
            ),
            recentLifeEvents: .init(
                status: .demoMode, rangeStart: nil, rangeEnd: nil,
                events: [], details: []
            ),
            microPlan: emptyMicroPlan(status: .demoMode)
        )
    }
}
