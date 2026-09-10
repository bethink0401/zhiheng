import XCTest
@testable import Zhiheng

final class InsightTests: XCTestCase {
    private let zone = "Asia/Shanghai"
    private var end: Date { ISO8601DateFormatter().date(from: "2026-09-02T16:00:00Z")! }
    private var now: Date { end.addingTimeInterval(3_600) }
    private var interval: DateInterval { DateInterval(start: end.addingTimeInterval(-35 * 86_400), end: end) }
    private let source = HealthMetricSource(sourceName: "合成设备", bundleIdentifier: "test.insight", deviceName: nil)
    private let insightID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let factID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    private func trend(
        metric: HealthMetricType = .stepCount, unit: HealthMetricUnit = .count,
        state: HealthMetricTrendEvidenceState = .trend(.sustainedChange),
        currentCount: Int = 7, baselineCount: Int = 28,
        currentValue: Double? = 7_000, baselineValue: Double? = 5_000,
        relative: Double? = 0.4, stable: Bool = true, outlier: Bool = false,
        currentInterval: DateInterval? = nil, baselineInterval: DateInterval? = nil,
        thresholdVersion: String = "synthetic-v1", aligned: Int? = 7,
        analysis: Int? = 7, required: Int? = 4
    ) -> HealthMetricTrendEvidence {
        HealthMetricTrendEvidence(metric: metric, unit: unit, state: state,
            currentInterval: currentInterval ?? DateInterval(start: end.addingTimeInterval(-7 * 86_400), end: end),
            currentValidDayCount: currentCount, currentExpectedDayCount: 7,
            baselineInterval: baselineInterval ?? DateInterval(start: interval.start, end: end.addingTimeInterval(-7 * 86_400)),
            baselineValidDayCount: baselineCount, baselineExpectedDayCount: 28,
            currentMedianValue: currentValue, baselineMedianValue: baselineValue, relativeChange: relative,
            configuredMinimumRelativeChange: 0.15, effectiveRelativeThreshold: 0.15,
            alignedDayCount: aligned, analysisDayCount: analysis, requiredAlignedDayCount: required,
            isolatedOutlierExcluded: outlier, sourceIsStable: stable, thresholdVersion: thresholdVersion)
    }

    private func fact(_ value: HealthMetricTrendEvidence? = nil, sources: [HealthMetricSource]? = nil) -> InsightFact {
        InsightFact(id: factID, metric: .stepCount, evidence: .evaluated(value ?? trend(), sources: sources ?? [source]))
    }

    private func make(
        facts: [InsightFact]? = nil, explanations: [InsightPossibleExplanation] = [],
        uncertainty: String = "只是同期观察，不能说明因果关系。", question: String? = nil,
        recommendation: InsightRecommendation = .continueObserving, mode: HealthDataMode = .live,
        interval: DateInterval? = nil, zone: String? = nil, generatedAt: Date? = nil
    ) throws -> Insight {
        try Insight(id: insightID, generatedAt: generatedAt ?? now,
            analysisInterval: interval ?? self.interval, timeZoneIdentifier: zone ?? self.zone,
            dataMode: mode, facts: facts ?? [fact()], possibleExplanations: explanations,
            uncertainty: uncertainty, followUpQuestion: question, recommendation: recommendation)
    }

    private func explanation(ids: [UUID]? = nil, text: String = "可能与近期日常安排有关，尚需了解背景。",
                             references: [InsightContextReference] = []) -> InsightPossibleExplanation {
        InsightPossibleExplanation(text: text, supportingFactIDs: ids ?? [factID], contextReferences: references)
    }

    private func rejects(_ expected: InsightValidationError, _ operation: () throws -> Insight,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? InsightValidationError, expected, file: file, line: line)
        }
    }

    func testLayersIdentityAndEvidenceArePreservedWithoutGeneratingContent() throws {
        let reference = InsightContextReference(kind: .contextEvent, recordID: UUID(), updatedAt: end, dataMode: .live)
        let reason = explanation(references: [reference])
        let value = try make(explanations: [reason], question: "最近的作息有变化吗？",
                             recommendation: .considerMicroPlan(templateID: .consistentWakeTime, supportingFactIDs: [factID]))
        XCTAssertEqual(value.insightID, insightID.uuidString)
        XCTAssertEqual(value.generatedAt, now)
        XCTAssertEqual(value.analysisInterval, interval)
        XCTAssertEqual(value.timeZoneIdentifier, zone)
        XCTAssertEqual(value.facts, [fact()])
        XCTAssertEqual(value.possibleExplanations, [reason])
        XCTAssertEqual(value.followUpQuestion, "最近的作息有变化吗？")
        XCTAssertEqual(value.uncertainty, "只是同期观察，不能说明因果关系。")
        XCTAssertEqual(Insight.modelVersion, "s09-insight-v1")
        XCTAssertEqual(value.version, Insight.modelVersion)
    }

    func testFixedInputsProduceSameModelAndDefaultDoesNotInventExplanationOrQuestion() throws {
        XCTAssertEqual(try make(), try make())
        XCTAssertTrue(try make().possibleExplanations.isEmpty)
        XCTAssertNil(try make().followUpQuestion)
        XCTAssertEqual(try make().recommendation, .continueObserving)
    }

    func testUnavailableReasonsRemainDistinctWithoutZeroValues() throws {
        for reason in InsightDataUnavailableReason.allCases {
            let input = InsightFact(id: factID, metric: .stepCount, evidence: .unavailable(reason))
            let value = try make(facts: [input])
            XCTAssertEqual(value.facts.first?.evidence, .unavailable(reason))
            XCTAssertEqual(value.recommendation, .continueObserving)
        }
    }

    func testEmptyFactsAreRejected() { rejects(.missingFacts) { try make(facts: []) } }

    func testDuplicateFactIDsAndDuplicateMetricsAreRejected() {
        let repeatedID = InsightFact(id: factID, metric: .sleepDuration, evidence: .unavailable(.noVisibleData))
        let repeatedMetric = InsightFact(id: UUID(), metric: .stepCount, evidence: .unavailable(.queryFailed))
        for repeated in [repeatedID, repeatedMetric] {
            rejects(.duplicateFact) { try make(facts: [fact(), repeated]) }
        }
    }

    func testUncertaintyCannotBeOmittedOrWhitespace() {
        for text in ["", " \n\t"] { rejects(.emptyText) { try make(uncertainty: text) } }
    }

    func testPresentQuestionAndExplanationCannotBeBlank() {
        rejects(.emptyText) { try make(question: " \n") }
        rejects(.emptyText) { try make(explanations: [explanation(text: " \n")]) }
    }

    func testInvalidTimezoneAndEmptyOrFutureScopeAreRejected() {
        rejects(.invalidTimeScope) { try make(zone: "Not/A_TimeZone") }
        rejects(.invalidTimeScope) { try make(interval: DateInterval(start: end, duration: 0)) }
        rejects(.invalidTimeScope) { try make(generatedAt: end.addingTimeInterval(-1)) }
    }

    func testEvidenceCannotExtendBeyondInsightScope() {
        rejects(.invalidEvidence) { try make(interval: DateInterval(start: interval.start.addingTimeInterval(1), end: end)) }
    }

    func testMetricAndUnitCannotDisagreeWithEvidence() {
        rejects(.invalidEvidence) { try make(facts: [fact(trend(metric: .sleepDuration))]) }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(unit: .hours))]) }
    }

    func testNonFiniteNumbersAndMissingRuleVersionAreRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            rejects(.invalidEvidence) { try make(facts: [fact(trend(currentValue: value))]) }
            rejects(.invalidEvidence) { try make(facts: [fact(trend(relative: value))]) }
        }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(thresholdVersion: " \n"))]) }
    }

    func testInvalidDayCountsAndIncompleteAlignmentAreRejected() {
        for value in [-1, 8] { rejects(.invalidEvidence) { try make(facts: [fact(trend(currentCount: value))]) } }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(baselineCount: 29))]) }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(aligned: 8))]) }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(analysis: nil))]) }
        rejects(.invalidEvidence) { try make(facts: [fact(trend(required: 0))]) }
    }

    func testWindowsMustBeAdjacentCompletedCalendarDays() {
        let shifted = DateInterval(start: end.addingTimeInterval(-6 * 86_400), end: end)
        rejects(.invalidEvidence) { try make(facts: [fact(trend(currentInterval: shifted))]) }
        let gap = DateInterval(start: interval.start, end: end.addingTimeInterval(-8 * 86_400))
        rejects(.invalidEvidence) { try make(facts: [fact(trend(baselineInterval: gap))]) }
        let partialDay = DateInterval(start: end.addingTimeInterval(-7 * 86_400 + 1), end: end.addingTimeInterval(1))
        rejects(.invalidEvidence) { try make(facts: [fact(trend(currentInterval: partialDay))]) }
    }

    func testInsufficientAndSourceChangedEvidenceCanBeKeptAsFacts() throws {
        let values = [
            trend(state: .currentWindowInsufficient, currentCount: 0, currentValue: nil,
                  aligned: nil, analysis: nil, required: nil),
            trend(state: .baselineInsufficient, baselineCount: 0, baselineValue: nil,
                  aligned: nil, analysis: nil, required: nil),
            trend(state: .sourceChanged, stable: false)
        ]
        for value in values { XCTAssertEqual(try make(facts: [fact(value)]).facts, [fact(value)]) }
    }

    func testTrendCannotClaimReadinessWithTooFewDaysMissingMediansOrUnstableSources() {
        let values = [trend(currentCount: 3), trend(baselineCount: 13), trend(currentValue: nil),
                      trend(baselineValue: nil), trend(stable: false)]
        for value in values { rejects(.invalidEvidence) { try make(facts: [fact(value)]) } }
        rejects(.invalidEvidence) { try make(facts: [fact(sources: [])]) }
        let second = HealthMetricSource(sourceName: "另一合成设备", bundleIdentifier: "test.second", deviceName: nil)
        rejects(.invalidEvidence) { try make(facts: [fact(sources: [source, second])]) }
    }

    func testQualityStateCannotContradictCountsOrSourceStability() {
        for state in [HealthMetricTrendEvidenceState.currentWindowInsufficient, .baselineInsufficient, .sourceChanged] {
            rejects(.invalidEvidence) { try make(facts: [fact(trend(state: state))]) }
        }
    }

    func testExplanationAndRecommendationRequireKnownUniqueFactReferences() {
        for ids in [[], [UUID()], [factID, factID]] {
            rejects(.invalidFactReference) { try make(explanations: [explanation(ids: ids)]) }
            rejects(.invalidFactReference) {
                try make(recommendation: .considerMicroPlan(templateID: .afternoonWalk, supportingFactIDs: ids))
            }
        }
    }

    func testUnavailableInsufficientChangedSourcesAndOutlierCannotSupportInterpretationOrPlan() {
        let unavailable = InsightFact(id: factID, metric: .stepCount, evidence: .unavailable(.queryFailed))
        let values = [unavailable, fact(trend(state: .currentWindowInsufficient, currentCount: 0,
                        currentValue: nil, aligned: nil, analysis: nil, required: nil)),
                      fact(trend(state: .sourceChanged, stable: false)), fact(trend(outlier: true))]
        for input in values {
            rejects(.insufficientSupport) { try make(facts: [input], explanations: [explanation()]) }
            rejects(.insufficientSupport) {
                try make(facts: [input], recommendation: .considerMicroPlan(templateID: .afternoonWalk, supportingFactIDs: [factID]))
            }
        }
    }

    func testMissingUnrelatedMetricDoesNotDiscardValidEvidence() throws {
        let missing = InsightFact(id: UUID(), metric: .sleepDuration, evidence: .unavailable(.noVisibleData))
        let value = try make(facts: [fact(), missing], explanations: [explanation()])
        XCTAssertEqual(value.facts.count, 2)
        XCTAssertEqual(value.possibleExplanations.count, 1)
    }

    func testAllExistingLowRiskTemplatesAreRepresentableAsSingleCandidate() throws {
        for template in MicroPlanTemplateID.allCases {
            let candidate = InsightRecommendation.considerMicroPlan(templateID: template, supportingFactIDs: [factID])
            XCTAssertEqual(try make(recommendation: candidate).recommendation, candidate)
        }
    }

    func testRealAndDemoContextReferencesCannotMixInEitherDirection() throws {
        for mode in [HealthDataMode.live, .demo] {
            let reference = InsightContextReference(kind: .dailyCheckIn, recordID: UUID(), updatedAt: end, dataMode: mode)
            XCTAssertEqual(try make(explanations: [explanation(references: [reference])], mode: mode).dataMode, mode)
            rejects(.mixedDataModes) {
                try make(explanations: [explanation(references: [reference])], mode: mode == .live ? .demo : .live)
            }
        }
    }

    func testFutureContextRevisionIsRejectedWithoutReadingRecordContents() {
        let reference = InsightContextReference(kind: .contextEvent, recordID: UUID(), updatedAt: now.addingTimeInterval(1), dataMode: .live)
        rejects(.invalidContextReference) { try make(explanations: [explanation(references: [reference])]) }
    }

    func testExistingTrendEngineStableRisingFallingOutlierMissingAndGapResultsAreAccepted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        for scenario in 0..<6 {
            let samples: [HealthMetricSample] = try (-35 ... -1).compactMap { offset in
                if scenario == 4 && offset > -7 { return nil }
                if scenario == 5 && [-6, -4, -2].contains(offset) { return nil }
                let value: Double = if scenario == 1 && offset >= -7 { 7_000 }
                    else if scenario == 2 && offset >= -7 { 3_000 }
                    else if scenario == 3 && offset == -1 { 30_000 } else { 5_000 }
                let date = end.addingTimeInterval(Double(offset) * 86_400 + 3_600)
                return try HealthMetricSample(id: UUID(), metricType: .stepCount, startDate: date, endDate: date,
                    value: value, unit: .count, source: source)
            }
            let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(metric: .stepCount, samples: samples,
                endingAt: end.addingTimeInterval(-1), calendar: calendar))
            XCTAssertEqual(try make(facts: [fact(evidence)]).facts.first?.evidence, .evaluated(evidence, sources: [source]))
        }
    }

    func testCalendarDayWindowsSupportDSTWithoutAssumingTwentyFourHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let start = calendar.date(byAdding: .day, value: -35, to: end)!
        let evidence = try XCTUnwrap(HealthMetricTrendEvidenceBuilder.make(metric: .stepCount, samples: [],
            endingAt: end.addingTimeInterval(-1), calendar: calendar))
        let value = try make(facts: [fact(evidence, sources: [])],
            interval: DateInterval(start: start, end: end), zone: calendar.timeZone.identifier, generatedAt: end)
        XCTAssertEqual(value.analysisInterval.duration, 35 * 86_400 - 3_600)
        XCTAssertEqual(value.facts.first?.evidence, .evaluated(evidence, sources: []))
    }

    private func followUpFact(
        id: UUID = UUID(),
        metric: HealthMetricType = .stepCount,
        level: HealthMetricTrendLevel = .sustainedChange,
        relative: Double = 0.4,
        outlier: Bool = false
    ) -> InsightFact {
        InsightFact(
            id: id,
            metric: metric,
            evidence: .evaluated(
                trend(
                    metric: metric,
                    unit: metric.expectedUnit,
                    state: .trend(level),
                    currentValue: relative < 0 ? 3_000 : (relative == 0 ? 5_000 : 7_000),
                    baselineValue: 5_000,
                    relative: relative,
                    outlier: outlier,
                    aligned: level == .noClearChange ? 0 : 7
                ),
                sources: [source]
            )
        )
    }

    private func followUpFactSet(
        mode: HealthDataMode = .live,
        facts: [InsightFact]
    ) -> InsightFactSet {
        InsightFactSet(
            generatorVersion: InsightFactGenerator.version,
            analysisInterval: interval,
            timeZoneIdentifier: zone,
            dataMode: mode,
            facts: facts
        )
    }

    private func followUpContext(
        for factSet: InsightFactSet,
        checkIn: (SubjectiveRating, SubjectiveRating, SubjectiveRating)? = nil,
        hasEvent: Bool = false,
        eventKind: ContextEventKind = .overtime,
        overrideMode: HealthDataMode? = nil
    ) throws -> InsightContextMatch {
        let window = try InsightContextMatcher.window(for: factSet)
        let mode = overrideMode ?? factSet.dataMode
        let checkIns = checkIn.map { energy, stress, body in
            [InsightMatchedCheckIn(
                reference: InsightContextReference(
                    kind: .dailyCheckIn,
                    recordID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                    updatedAt: end,
                    dataMode: mode
                ),
                localDay: window.localDays.last!,
                energy: energy,
                stress: stress,
                bodyFeeling: body
            )]
        } ?? []
        let events = hasEvent ? [InsightMatchedContextEvent(
            reference: InsightContextReference(
                kind: .contextEvent,
                recordID: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                updatedAt: end,
                dataMode: mode
            ),
            kind: eventKind,
            startedAt: window.interval.start.addingTimeInterval(3_600),
            endedAt: nil,
            intensity: .medium
        )] : []
        return InsightContextMatch(
            matcherVersion: InsightContextMatch.matcherVersion,
            window: window,
            dataMode: mode,
            checkIns: checkIns,
            contextEvents: events
        )
    }

    private func userFacingCopy(in card: InsightFourLayerCardPresentation) -> String {
        var parts = [card.title, card.scopeText]
        parts.append(contentsOf: card.layers.map(\.text))
        if let question = card.followUpQuestion { parts.append(question) }
        parts.append(contentsOf: [
            card.evidence.title,
            card.evidence.summary,
            card.evidence.timeZoneText
        ])
        for item in card.evidence.items {
            parts.append(contentsOf: [
                item.metricTitle,
                item.currentWindowText,
                item.sourceText,
                item.qualityText,
                item.versionText
            ])
            parts.append(contentsOf: [
                item.baselineWindowText,
                item.changeText,
                item.alignmentText
            ].compactMap { $0 })
        }
        return parts.joined(separator: "\n")
    }

    func testSustainedChangeWithoutAnyContextAsksOneSubjectiveQuestion() throws {
        let changed = followUpFact(id: factID)
        let facts = followUpFactSet(facts: [changed])
        let context = try followUpContext(for: facts)

        guard case let .ask(question) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected one question") }

        XCTAssertEqual(question.kind, .missingSubjectiveContext)
        XCTAssertEqual(question.ruleVersion, InsightFollowUpQuestionRule.version)
        XCTAssertEqual(question.supportingFactIDs, [factID])
        XCTAssertTrue(question.contextReferences.isEmpty)
        XCTAssertTrue(question.text.contains("精力"))
    }

    func testChangeWithCheckInButNoLifeEventAsksOneLifeContextQuestion() throws {
        let facts = followUpFactSet(facts: [followUpFact(id: factID)])
        let context = try followUpContext(
            for: facts,
            checkIn: (.three, .three, .three)
        )

        guard case let .ask(question) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected one question") }

        XCTAssertEqual(question.kind, .missingLifeContext)
        XCTAssertEqual(question.contextReferences, context.references)
        XCTAssertTrue(question.text.contains("为了补充背景"))
    }

    func testExistingCheckInAndLifeEventSuppressFurtherQuestionWithoutClaimingCause() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let context = try followUpContext(
            for: facts,
            checkIn: (.two, .four, .two),
            hasEvent: true
        )

        XCTAssertEqual(
            try InsightFollowUpQuestionRule.decide(factSet: facts, context: context),
            .noQuestion(.contextAlreadyAvailable)
        )
    }

    func testExistingEventStillAllowsSingleSubjectiveQuestionWhenCheckInIsMissing() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let context = try followUpContext(for: facts, hasEvent: true)

        guard case let .ask(question) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected one question") }
        XCTAssertEqual(question.kind, .missingSubjectiveContext)
        XCTAssertEqual(question.contextReferences, context.references)
    }

    func testStrictStableCoreFactsAndNeedsCareFeelingAskMismatchQuestion() throws {
        let stableFacts = HealthMetricTrendThresholdCatalog.coreMetrics.enumerated().map { index, metric in
            followUpFact(
                id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", index + 1))!,
                metric: metric,
                level: .noClearChange,
                relative: 0
            )
        }
        let facts = followUpFactSet(facts: stableFacts)
        let context = try followUpContext(
            for: facts,
            checkIn: (.two, .four, .three)
        )

        guard case let .ask(question) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected one question") }

        XCTAssertEqual(question.kind, .subjectiveObjectiveMismatch)
        XCTAssertEqual(question.supportingFactIDs, stableFacts.map(\.id))
        XCTAssertEqual(question.contextReferences, context.references)
    }

    func testComfortableOrIncompleteCoreFactsDoNotInventMismatch() throws {
        let stableFacts = HealthMetricTrendThresholdCatalog.coreMetrics.map {
            followUpFact(metric: $0, level: .noClearChange, relative: 0)
        }
        let complete = followUpFactSet(facts: stableFacts)
        let comfortable = try followUpContext(
            for: complete,
            checkIn: (.four, .two, .four)
        )
        XCTAssertEqual(
            try InsightFollowUpQuestionRule.decide(factSet: complete, context: comfortable),
            .noQuestion(.noHighValueGap)
        )

        let incomplete = followUpFactSet(facts: Array(stableFacts.dropLast()))
        let needsCare = try followUpContext(
            for: incomplete,
            checkIn: (.one, .five, .one)
        )
        XCTAssertEqual(
            try InsightFollowUpQuestionRule.decide(factSet: incomplete, context: needsCare),
            .noQuestion(.noHighValueGap)
        )
    }

    func testMaterialWorthObservingCanAskButOutlierAndUnavailableFactsCannot() throws {
        let material = followUpFact(level: .worthObserving, relative: 0.3)
        let materialSet = followUpFactSet(facts: [material])
        XCTAssertNotEqual(
            try InsightFollowUpQuestionRule.decide(
                factSet: materialSet,
                context: followUpContext(for: materialSet)
            ),
            .noQuestion(.noHighValueGap)
        )

        let inputs = [
            followUpFact(level: .worthObserving, relative: 0.05),
            followUpFact(outlier: true),
            InsightFact(id: UUID(), metric: .stepCount, evidence: .unavailable(.queryFailed))
        ]
        for input in inputs {
            let factSet = followUpFactSet(facts: [input])
            XCTAssertEqual(
                try InsightFollowUpQuestionRule.decide(
                    factSet: factSet,
                    context: followUpContext(for: factSet)
                ),
                .noQuestion(.noHighValueGap)
            )
        }
    }

    func testDemoModeNeverAsksRealUserQuestion() throws {
        let facts = followUpFactSet(mode: .demo, facts: [followUpFact()])
        let context = try followUpContext(for: facts)
        XCTAssertEqual(
            try InsightFollowUpQuestionRule.decide(factSet: facts, context: context),
            .noQuestion(.nonLiveMode)
        )
    }

    func testStableQuestionIDAllowsCallerToPreventRepeatInSameWindow() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let context = try followUpContext(for: facts)
        guard case let .ask(first) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected one question") }
        guard case let .ask(second) = try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: context
        ) else { return XCTFail("Expected the same question") }
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(
            try InsightFollowUpQuestionRule.decide(
                factSet: facts,
                context: context,
                handledQuestionIDs: [first.id]
            ),
            .noQuestion(.alreadyHandled)
        )
    }

    func testMismatchedModeAndWindowAreRejectedBeforeQuestionSelection() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let wrongMode = try followUpContext(for: facts, overrideMode: .demo)
        XCTAssertThrowsError(try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: wrongMode
        )) {
            XCTAssertEqual($0 as? InsightFollowUpRuleError, .invalidContextMatch)
        }

        let original = try followUpContext(for: facts)
        let wrongWindow = InsightContextMatch(
            matcherVersion: original.matcherVersion,
            window: InsightContextWindow(
                interval: DateInterval(
                    start: original.window.interval.start.addingTimeInterval(1),
                    end: original.window.interval.end
                ),
                localDays: original.window.localDays,
                timeZoneIdentifier: original.window.timeZoneIdentifier
            ),
            dataMode: original.dataMode,
            checkIns: original.checkIns,
            contextEvents: original.contextEvents
        )
        XCTAssertThrowsError(try InsightFollowUpQuestionRule.decide(
            factSet: facts,
            context: wrongWindow
        )) {
            XCTAssertEqual($0 as? InsightFollowUpRuleError, .invalidContextMatch)
        }
    }

    func testFourLayerCardAlwaysSeparatesTheFourRequiredLayers() throws {
        let facts = followUpFactSet(facts: [followUpFact(id: factID)])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )

        XCTAssertEqual(card.layers.map(\.kind), InsightFourLayerCardPresentation.Layer.Kind.allCases)
        XCTAssertEqual(card.title, "本周有一项变化值得看")
        XCTAssertTrue(card.scopeText.contains("7 个完整日"))
        XCTAssertTrue(card.layers[0].text.contains("步数中位数"))
        XCTAssertTrue(card.layers[0].text.contains("40%"))
        XCTAssertTrue(card.layers[2].text.contains("不能用于诊断或证明因果"))
        XCTAssertNotNil(card.followUpQuestion)
        XCTAssertEqual(card.interactionIdentity.topic, .metricChange(.stepCount))
        XCTAssertEqual(card.interactionIdentity.dataMode, .live)
        XCTAssertFalse(card.isDemo)
    }

    func testInteractionIdentityIsStableForTheSameAggregateCard() throws {
        let facts = followUpFactSet(facts: [followUpFact(id: factID)])
        let context = try followUpContext(for: facts)
        let first = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(context)
        )
        let second = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(context)
        )

        XCTAssertEqual(first.interactionIdentity, second.interactionIdentity)
        XCTAssertEqual(
            Array(first.interactionIdentity.insightID.uuidString.lowercased())[14],
            "8"
        )
    }

    func testInteractionIdentitySeparatesModeAndInsightTopic() throws {
        let liveFacts = followUpFactSet(facts: [followUpFact(id: factID)])
        let live = try InsightFourLayerCardFactory.make(
            factSet: liveFacts,
            contextState: .available(followUpContext(for: liveFacts))
        )
        let demoFacts = followUpFactSet(
            mode: .demo,
            facts: [followUpFact(id: factID)]
        )
        let demo = try InsightFourLayerCardFactory.make(
            factSet: demoFacts,
            contextState: .demoMode
        )
        let stableFacts = followUpFactSet(facts: [
            followUpFact(id: factID, level: .noClearChange, relative: 0)
        ])
        let stable = try InsightFourLayerCardFactory.make(
            factSet: stableFacts,
            contextState: .available(followUpContext(for: stableFacts))
        )

        XCTAssertNotEqual(live.interactionIdentity.insightID, demo.interactionIdentity.insightID)
        XCTAssertEqual(demo.interactionIdentity.dataMode, .demo)
        XCTAssertEqual(stable.interactionIdentity.topic, .stableOverview)
        XCTAssertNotEqual(live.interactionIdentity.topic, stable.interactionIdentity.topic)
    }

    func testFourLayerCardUsesStructuredEventOnlyAsPossibleConcurrentContext() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true
            ))
        )
        let explanation = try XCTUnwrap(
            card.layers.first(where: { $0.kind == .possibleExplanation })
        ).text

        XCTAssertTrue(explanation.contains("加班"))
        XCTAssertTrue(explanation.contains("可能相关"))
        XCTAssertTrue(explanation.contains("不能确定具体原因"))
        XCTAssertNil(card.followUpQuestion)
    }

    func testFourLayerCardReadFailureDoesNotBecomeMissingContextQuestion() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .readFailed
        )
        let explanation = try XCTUnwrap(
            card.layers.first(where: { $0.kind == .possibleExplanation })
        ).text

        XCTAssertNil(card.followUpQuestion)
        XCTAssertTrue(explanation.contains("暂时无法读取"))
        XCTAssertTrue(explanation.contains("不会据此追问或猜测原因"))
    }

    func testFourLayerCardInsufficientEvidenceStaysConservative() throws {
        let facts = followUpFactSet(facts: [
            InsightFact(id: factID, metric: .stepCount, evidence: .unavailable(.queryFailed))
        ])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )

        XCTAssertEqual(card.title, "正在了解你的近期状态")
        XCTAssertTrue(card.layers[0].text.contains("不足以形成可靠"))
        XCTAssertTrue(card.layers[2].text.contains("不会据此判断健康变差"))
        XCTAssertTrue(card.layers[3].text.contains("等有效日与来源稳定后再判断"))
        XCTAssertNil(card.followUpQuestion)
    }

    func testFourLayerCardCompleteStableSetRecommendsObservationWithoutClaimingMissingData() throws {
        let facts = followUpFactSet(facts: HealthMetricTrendThresholdCatalog.todayCandidateMetrics.map {
            followUpFact(metric: $0, level: .noClearChange, relative: 0)
        })
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true
            ))
        )

        XCTAssertEqual(card.title, "本周暂未见明确变化")
        XCTAssertTrue(card.layers[0].text.contains("达到质量门槛"))
        XCTAssertTrue(card.layers[3].text.contains("不额外增加行动负担"))
        XCTAssertFalse(card.layers[3].text.contains("等有效日"))
    }

    func testFourLayerCardMismatchRespectsFeelingAndOffersOnlyOneQuestion() throws {
        let stableFacts = HealthMetricTrendThresholdCatalog.coreMetrics.map {
            followUpFact(metric: $0, level: .noClearChange, relative: 0)
        }
        let facts = followUpFactSet(facts: stableFacts)
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.two, .four, .two)
            ))
        )

        XCTAssertEqual(card.title, "感受值得单独关注")
        XCTAssertTrue(card.layers[0].text.contains("感受记录仍值得单独重视"))
        XCTAssertTrue(card.layers[1].text.contains("不能否定你的感受"))
        XCTAssertTrue(card.layers[3].text.contains("不需要等待设备数据来证明感受"))
        XCTAssertNotNil(card.followUpQuestion)
    }

    func testFourLayerCardDemoModeDoesNotReadOrRequestRealContext() throws {
        let facts = followUpFactSet(mode: .demo, facts: [followUpFact()])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .demoMode
        )

        XCTAssertTrue(card.isDemo)
        XCTAssertNil(card.followUpQuestion)
        XCTAssertTrue(card.layers[1].text.contains("不读取或混用你的真实感受"))
    }

    func testFourLayerCardSelectsOneSustainedChangeBeforeWorthObserving() throws {
        let worthObserving = followUpFact(
            metric: .stepCount,
            level: .worthObserving,
            relative: 0.6
        )
        let sustained = followUpFact(
            metric: .activeEnergy,
            level: .sustainedChange,
            relative: 0.2
        )
        let facts = followUpFactSet(facts: [worthObserving, sustained])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )

        XCTAssertTrue(card.layers[0].text.contains("活动能量中位数"))
        XCTAssertFalse(card.layers[0].text.contains("步数中位数"))
        XCTAssertEqual(card.layers.filter { $0.kind == .fact }.count, 1)
    }

    func testPlanCandidateRuleMapsAQualifiedDecreaseToOneWhitelistTemplate() throws {
        let changed = followUpFact(id: factID, metric: .stepCount, relative: -0.4)
        let facts = followUpFactSet(facts: [changed])
        let context = try followUpContext(
            for: facts,
            checkIn: (.three, .three, .three),
            hasEvent: true,
            eventKind: .custom
        )

        guard case let .candidate(candidate) = try InsightPlanCandidateRule.decide(
            factSet: facts,
            contextState: .available(context)
        ) else { return XCTFail("Expected one plan candidate") }

        XCTAssertEqual(candidate.ruleVersion, InsightPlanCandidateRule.version)
        XCTAssertEqual(candidate.templateID, .afternoonWalk)
        XCTAssertEqual(candidate.supportingFactIDs, [factID])
        XCTAssertEqual(
            candidate.recommendation,
            .considerMicroPlan(templateID: .afternoonWalk, supportingFactIDs: [factID])
        )
        XCTAssertNotNil(MicroPlanTemplateLibrary.template(for: candidate.templateID))
    }

    func testPlanCandidateRuleUsesStructuredContextForSleepAndRecoveryChoices() throws {
        let sleep = followUpFact(id: factID, metric: .sleepDuration, relative: -0.2)
        let sleepFacts = followUpFactSet(facts: [sleep])
        let caffeine = try followUpContext(
            for: sleepFacts,
            checkIn: (.three, .three, .three),
            hasEvent: true,
            eventKind: .caffeine
        )
        let stress = try followUpContext(
            for: sleepFacts,
            checkIn: (.three, .four, .three),
            hasEvent: true,
            eventKind: .custom
        )

        let exerciseID = UUID(uuidString: "20000000-0000-0000-0000-000000000010")!
        let exercise = followUpFact(
            id: exerciseID,
            metric: .exerciseDuration,
            relative: 0.4
        )
        let exerciseFacts = followUpFactSet(facts: [exercise])
        let highLoad = try followUpContext(
            for: exerciseFacts,
            checkIn: (.two, .four, .two),
            hasEvent: true,
            eventKind: .highIntensityExercise
        )

        XCTAssertEqual(
            try candidateTemplate(factSet: sleepFacts, context: caffeine),
            .afternoonCaffeineCutoff
        )
        XCTAssertEqual(
            try candidateTemplate(factSet: sleepFacts, context: stress),
            .bedtimeBreathing
        )
        XCTAssertEqual(
            try candidateTemplate(factSet: exerciseFacts, context: highLoad),
            .reducedTrainingLoad
        )
    }

    func testPlanCandidateRuleMapsLowActivityOnlyWhenFeelingDoesNotNeedCare() throws {
        let cases: [(HealthMetricType, MicroPlanTemplateID)] = [
            (.activeEnergy, .movementBreak),
            (.exerciseDuration, .gentleMobility),
        ]
        for (metric, expected) in cases {
            let facts = followUpFactSet(facts: [
                followUpFact(metric: metric, relative: -0.3)
            ])
            let neutral = try followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true,
                eventKind: .custom
            )
            XCTAssertEqual(
                try candidateTemplate(factSet: facts, context: neutral),
                expected
            )

            let needsCare = try followUpContext(
                for: facts,
                checkIn: (.two, .four, .two),
                hasEvent: true,
                eventKind: .custom
            )
            XCTAssertEqual(
                try InsightPlanCandidateRule.decide(
                    factSet: facts,
                    contextState: .available(needsCare)
                ),
                .noCandidate(.noLowRiskMatch)
            )
        }
    }

    func testPlanCandidateRuleWaitsForBothStructuredContextTypes() throws {
        let facts = followUpFactSet(facts: [
            followUpFact(metric: .sleepDuration, relative: -0.2)
        ])
        let missingBoth = try followUpContext(for: facts)
        let missingEvent = try followUpContext(
            for: facts,
            checkIn: (.three, .three, .three)
        )

        for context in [missingBoth, missingEvent] {
            XCTAssertEqual(
                try InsightPlanCandidateRule.decide(
                    factSet: facts,
                    contextState: .available(context)
                ),
                .noCandidate(.waitingForContext)
            )
        }
    }

    func testPlanCandidateRuleDoesNotUseDemoOrFailedContextAsPersonalEvidence() throws {
        let liveFacts = followUpFactSet(facts: [followUpFact(relative: -0.4)])
        XCTAssertEqual(
            try InsightPlanCandidateRule.decide(
                factSet: liveFacts,
                contextState: .readFailed
            ),
            .noCandidate(.contextUnavailable)
        )

        let demoFacts = followUpFactSet(
            mode: .demo,
            facts: [followUpFact(relative: -0.4)]
        )
        XCTAssertEqual(
            try InsightPlanCandidateRule.decide(
                factSet: demoFacts,
                contextState: .demoMode
            ),
            .noCandidate(.nonLiveMode)
        )
    }

    func testPlanCandidateRuleKeepsQualityDegradationOutOfCandidates() throws {
        let inputs: [InsightFact] = [
            followUpFact(level: .noClearChange, relative: 0),
            followUpFact(relative: -0.4, outlier: true),
            followUpFact(level: .worthObserving, relative: -0.1),
            InsightFact(
                id: UUID(),
                metric: .stepCount,
                evidence: .unavailable(.queryFailed)
            ),
        ]
        for input in inputs {
            let facts = followUpFactSet(facts: [input])
            let context = try followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true,
                eventKind: .custom
            )
            XCTAssertEqual(
                try InsightPlanCandidateRule.decide(
                    factSet: facts,
                    contextState: .available(context)
                ),
                .noCandidate(.noQualifiedChange)
            )
        }
    }

    func testPlanCandidateRuleStopsWhenContextSuggestsCaution() throws {
        let facts = followUpFactSet(facts: [followUpFact(relative: -0.4)])
        for eventKind in [ContextEventKind.illness, .deviceNotWorn] {
            let context = try followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true,
                eventKind: eventKind
            )
            XCTAssertEqual(
                try InsightPlanCandidateRule.decide(
                    factSet: facts,
                    contextState: .available(context)
                ),
                .noCandidate(.contextNeedsCaution)
            )
        }
    }

    func testPlanCandidateRuleDoesNotTurnEveryDirectionIntoAnAction() throws {
        for input in [
            followUpFact(metric: .stepCount, relative: 0.4),
            followUpFact(metric: .restingHeartRate, relative: -0.2),
            followUpFact(metric: .heartRateVariability, relative: 0.2),
        ] {
            let facts = followUpFactSet(facts: [input])
            let context = try followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true,
                eventKind: .custom
            )
            XCTAssertEqual(
                try InsightPlanCandidateRule.decide(
                    factSet: facts,
                    contextState: .available(context)
                ),
                .noCandidate(.noLowRiskMatch)
            )
        }
    }

    func testPlanCandidateRuleReturnsOnlyTheHighestRankedMatchDeterministically() throws {
        let sleepID = UUID(uuidString: "20000000-0000-0000-0000-000000000020")!
        let stepID = UUID(uuidString: "20000000-0000-0000-0000-000000000021")!
        let facts = followUpFactSet(facts: [
            followUpFact(
                id: stepID,
                metric: .stepCount,
                level: .worthObserving,
                relative: -0.6
            ),
            followUpFact(
                id: sleepID,
                metric: .sleepDuration,
                level: .sustainedChange,
                relative: -0.2
            ),
        ])
        let context = try followUpContext(
            for: facts,
            checkIn: (.three, .three, .three),
            hasEvent: true,
            eventKind: .custom
        )

        guard case let .candidate(first) = try InsightPlanCandidateRule.decide(
            factSet: facts,
            contextState: .available(context)
        ), case let .candidate(second) = try InsightPlanCandidateRule.decide(
            factSet: facts,
            contextState: .available(context)
        ) else { return XCTFail("Expected deterministic candidate") }

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.templateID, .earlierBedtime)
        XCTAssertEqual(first.supportingFactIDs, [sleepID])
    }

    func testFourLayerCardSurfacesCandidateWithoutCreatingAPlanDraft() throws {
        let facts = followUpFactSet(facts: [
            followUpFact(id: factID, metric: .sleepDuration, relative: -0.2)
        ])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true,
                eventKind: .custom
            ))
        )

        XCTAssertEqual(card.planCandidate?.templateID, .earlierBedtime)
        XCTAssertEqual(card.planCandidate?.supportingFactIDs, [factID])
        let recommendation = try XCTUnwrap(
            card.layers.first(where: { $0.kind == .recommendation })
        ).text
        XCTAssertTrue(recommendation.contains("5 天低风险候选"))
        XCTAssertTrue(recommendation.contains("是否开始由你确认"))
        XCTAssertTrue(recommendation.contains("不会自动创建计划"))
    }

    private func candidateTemplate(
        factSet: InsightFactSet,
        context: InsightContextMatch
    ) throws -> MicroPlanTemplateID? {
        guard case let .candidate(candidate) = try InsightPlanCandidateRule.decide(
            factSet: factSet,
            contextState: .available(context)
        ) else { return nil }
        return candidate.templateID
    }

    func testFourLayerCardRejectsLiveFactsMarkedAsDemoContext() throws {
        let facts = followUpFactSet(facts: [followUpFact()])
        XCTAssertThrowsError(try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .demoMode
        )) {
            XCTAssertEqual($0 as? InsightFourLayerCardError, .invalidContextState)
        }
    }

    func testEvidenceForPrimaryChangeShowsTheSameWindowsValuesThresholdSourceAndVersions() throws {
        let facts = followUpFactSet(facts: [followUpFact(id: factID)])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )
        let item = try XCTUnwrap(card.evidence.items.first)

        XCTAssertEqual(card.evidence.title, "数据依据与来源")
        XCTAssertEqual(card.evidence.summary, "本地聚合 · 1 项事实")
        XCTAssertEqual(item.id, factID)
        XCTAssertEqual(item.metric, .stepCount)
        XCTAssertTrue(item.currentWindowText.contains("有效日 7/7"))
        XCTAssertTrue(item.currentWindowText.contains("中位数 7,000 步"))
        XCTAssertTrue(try XCTUnwrap(item.baselineWindowText).contains("有效日 28/28"))
        XCTAssertTrue(try XCTUnwrap(item.changeText).contains("+40%"))
        XCTAssertTrue(try XCTUnwrap(item.changeText).contains("实际门槛 15%"))
        XCTAssertTrue(try XCTUnwrap(item.alignmentText).contains("同向日 7/7"))
        XCTAssertEqual(item.sourceText, "合成设备")
        XCTAssertFalse(item.sourceText.contains("test.insight"))
        XCTAssertTrue(item.qualityText.contains("来源稳定"))
        XCTAssertTrue(item.versionText.contains("synthetic-v1"))
        XCTAssertTrue(item.versionText.contains(InsightFactGenerator.version))
        XCTAssertTrue(card.evidence.timeZoneText.contains(zone))
    }

    func testEvidenceForSubjectiveMismatchIncludesAllFourSupportingCoreFacts() throws {
        let stableFacts = HealthMetricTrendThresholdCatalog.coreMetrics.map {
            followUpFact(metric: $0, level: .noClearChange, relative: 0)
        }
        let facts = followUpFactSet(facts: stableFacts)
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.two, .four, .two)
            ))
        )

        XCTAssertEqual(card.evidence.items.map(\.metric), [
            .stepCount, .sleepDuration, .restingHeartRate, .heartRateVariability
        ])
        XCTAssertEqual(card.evidence.items.count, 4)
        XCTAssertTrue(card.evidence.items.allSatisfy { $0.qualityText.contains("来源稳定") })
    }

    func testEvidenceForCompleteStableSetIncludesEveryFactUsedByTheClaim() throws {
        let stableFacts = HealthMetricTrendThresholdCatalog.todayCandidateMetrics.map {
            followUpFact(metric: $0, level: .noClearChange, relative: 0)
        }
        let facts = followUpFactSet(facts: stableFacts)
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(
                for: facts,
                checkIn: (.three, .three, .three),
                hasEvent: true
            ))
        )

        XCTAssertEqual(card.evidence.items.map(\.metric), [
            .stepCount, .sleepDuration, .restingHeartRate, .heartRateVariability,
            .activeEnergy, .exerciseDuration
        ])
        XCTAssertEqual(card.evidence.summary, "本地聚合 · 6 项事实")
    }

    func testUnavailableEvidenceExplainsReasonWithoutInventingZeroOrSource() throws {
        let input = InsightFact(
            id: factID,
            metric: .stepCount,
            evidence: .unavailable(.noVisibleData)
        )
        let facts = followUpFactSet(facts: [input])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )
        let item = try XCTUnwrap(card.evidence.items.first)

        XCTAssertTrue(item.currentWindowText.contains("分析范围"))
        XCTAssertNil(item.baselineWindowText)
        XCTAssertNil(item.changeText)
        XCTAssertNil(item.alignmentText)
        XCTAssertEqual(item.sourceText, "未形成可用来源")
        XCTAssertTrue(item.qualityText.contains("不会按 0 处理"))
        XCTAssertFalse(item.currentWindowText.contains("中位数 0"))
    }

    func testSourceChangeEvidenceShowsReadableNamesWithoutBundleIdentifiers() throws {
        let phone = HealthMetricSource(
            sourceName: "手机来源",
            bundleIdentifier: "private.bundle.identifier",
            deviceName: "iPhone"
        )
        let changed = InsightFact(
            id: factID,
            metric: .stepCount,
            evidence: .evaluated(
                trend(state: .sourceChanged, stable: false),
                sources: [source, phone]
            )
        )
        let facts = followUpFactSet(facts: [changed])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )
        let item = try XCTUnwrap(card.evidence.items.first)

        XCTAssertTrue(item.sourceText.contains("iPhone"))
        XCTAssertTrue(item.sourceText.contains("合成设备"))
        XCTAssertFalse(item.sourceText.contains("private.bundle.identifier"))
        XCTAssertFalse(item.sourceText.contains("test.insight"))
        XCTAssertTrue(item.qualityText.contains("来源发生变化"))
    }

    func testOutlierProtectedEvidenceNamesTheProtectionWithoutClaimingAChange() throws {
        let facts = followUpFactSet(facts: [followUpFact(outlier: true)])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )
        let item = try XCTUnwrap(card.evidence.items.first)

        XCTAssertEqual(card.title, "正在了解你的近期状态")
        XCTAssertTrue(item.qualityText.contains("孤立日期保护"))
        XCTAssertTrue(item.qualityText.contains("原记录仍保留"))
        XCTAssertFalse(item.qualityText.contains("异常日期"))
    }

    func testLowAnxietyCopyMatrixAvoidsDiagnosticAlarmistCausalAndGuaranteedClaims() throws {
        var cards: [InsightFourLayerCardPresentation] = []

        let changed = followUpFactSet(facts: [followUpFact(id: factID)])
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: changed,
            contextState: .available(followUpContext(for: changed))
        ))
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: changed,
            contextState: .available(followUpContext(
                for: changed,
                checkIn: (.three, .three, .three),
                hasEvent: true
            ))
        ))

        let stable = followUpFactSet(facts:
            HealthMetricTrendThresholdCatalog.todayCandidateMetrics.map {
                followUpFact(metric: $0, level: .noClearChange, relative: 0)
            }
        )
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: stable,
            contextState: .available(followUpContext(for: stable))
        ))

        let mismatch = followUpFactSet(facts:
            HealthMetricTrendThresholdCatalog.coreMetrics.map {
                followUpFact(metric: $0, level: .noClearChange, relative: 0)
            }
        )
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: mismatch,
            contextState: .available(followUpContext(
                for: mismatch,
                checkIn: (.two, .four, .two)
            ))
        ))

        let unavailable = followUpFactSet(facts: [
            InsightFact(id: factID, metric: .stepCount, evidence: .unavailable(.queryFailed))
        ])
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: unavailable,
            contextState: .available(followUpContext(for: unavailable))
        ))

        let protected = followUpFactSet(facts: [followUpFact(outlier: true)])
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: protected,
            contextState: .available(followUpContext(for: protected))
        ))

        let demo = followUpFactSet(mode: .demo, facts: [followUpFact()])
        cards.append(try InsightFourLayerCardFactory.make(
            factSet: demo,
            contextState: .demoMode
        ))

        let forbiddenAssertions = [
            "你不健康", "你的压力很危险", "AI 判断你患有", "你可能患有",
            "这个方法已经证明有效", "证明有效", "只要这样做就会改善",
            "一定改善", "保证改善", "无需就医", "就是因为", "导致了",
            "必须立即", "马上处理", "赶紧处理"
        ]
        for card in cards {
            XCTAssertEqual(
                card.layers.map(\.kind),
                InsightFourLayerCardPresentation.Layer.Kind.allCases
            )
            XCTAssertTrue(card.layers.allSatisfy {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            let copy = userFacingCopy(in: card)
            for phrase in forbiddenAssertions {
                XCTAssertFalse(copy.contains(phrase), "Unexpected phrase: \(phrase)")
            }
        }
    }

    func testFollowUpQuestionCopyIsNeutralOptionalAndDoesNotPresupposeCause() throws {
        let changed = followUpFactSet(facts: [followUpFact(id: factID)])
        guard case let .ask(subjective) = try InsightFollowUpQuestionRule.decide(
            factSet: changed,
            context: followUpContext(for: changed)
        ) else { return XCTFail("Expected subjective question") }
        guard case let .ask(life) = try InsightFollowUpQuestionRule.decide(
            factSet: changed,
            context: followUpContext(
                for: changed,
                checkIn: (.three, .three, .three)
            )
        ) else { return XCTFail("Expected life-context question") }

        let stable = followUpFactSet(facts:
            HealthMetricTrendThresholdCatalog.coreMetrics.map {
                followUpFact(metric: $0, level: .noClearChange, relative: 0)
            }
        )
        guard case let .ask(mismatch) = try InsightFollowUpQuestionRule.decide(
            factSet: stable,
            context: followUpContext(
                for: stable,
                checkIn: (.one, .five, .one)
            )
        ) else { return XCTFail("Expected mismatch question") }

        let questions = [subjective.text, life.text, mismatch.text]
        XCTAssertEqual(Set(questions).count, 3)
        for question in questions {
            XCTAssertTrue(question.hasSuffix("？"))
            XCTAssertTrue(question.contains("是否"))
            for phrase in ["为什么", "导致", "造成", "危险", "异常", "患有", "必须", "立即"] {
                XCTAssertFalse(question.contains(phrase), "Unexpected phrase: \(phrase)")
            }
        }
        XCTAssertTrue(questions.allSatisfy { $0.contains("身体感受") })
    }

    func testNumericDirectionNeverBecomesAHealthValueJudgment() throws {
        for relative in [0.4, -0.2] {
            let facts = followUpFactSet(facts: [followUpFact(relative: relative)])
            let card = try InsightFourLayerCardFactory.make(
                factSet: facts,
                contextState: .available(followUpContext(for: facts))
            )
            let factCopy = card.layers[0].text
            XCTAssertTrue(factCopy.contains(relative > 0 ? "上升" : "下降"))
            for phrase in ["更健康", "不健康", "变好", "变差", "改善", "恶化", "危险"] {
                XCTAssertFalse(factCopy.contains(phrase), "Unexpected phrase: \(phrase)")
            }
        }
    }

    func testEveryUnavailableReasonKeepsTheCopyConservativeAndDoesNotInventZero() throws {
        for reason in InsightDataUnavailableReason.allCases {
            let facts = followUpFactSet(facts: [
                InsightFact(id: UUID(), metric: .stepCount, evidence: .unavailable(reason))
            ])
            let card = try InsightFourLayerCardFactory.make(
                factSet: facts,
                contextState: .available(followUpContext(for: facts))
            )
            let copy = userFacingCopy(in: card)

            XCTAssertEqual(card.title, "正在了解你的近期状态")
            XCTAssertNil(card.followUpQuestion)
            XCTAssertTrue(card.layers[0].text.contains("尚不足以形成可靠"))
            XCTAssertTrue(card.layers[2].text.contains("证据不足"))
            XCTAssertFalse(copy.contains("中位数 0"))
            XCTAssertFalse(copy.contains("0 步"))
            XCTAssertFalse(copy.contains("你不健康"))
        }
    }

    func testIsolatedDateCopyStaysTechnicalWithoutCallingTheUserAbnormal() throws {
        let facts = followUpFactSet(facts: [followUpFact(outlier: true)])
        let card = try InsightFourLayerCardFactory.make(
            factSet: facts,
            contextState: .available(followUpContext(for: facts))
        )
        let quality = try XCTUnwrap(card.evidence.items.first).qualityText

        XCTAssertTrue(quality.contains("孤立日期保护"))
        XCTAssertTrue(quality.contains("不参与本次结论"))
        XCTAssertFalse(quality.contains("异常"))
    }
}
