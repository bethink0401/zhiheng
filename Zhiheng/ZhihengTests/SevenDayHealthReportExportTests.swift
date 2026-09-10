import PDFKit
import XCTest
@testable import Zhiheng

@MainActor
final class SevenDayHealthReportExportTests: XCTestCase {
    private let privateSentinel = "PRIVATE-NOTE-DO-NOT-EXPORT"

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func objectiveFact(
        metric: HealthMetricType,
        value: Double,
        change: Double = 0,
        state: HealthMetricTrendEvidenceState = .trend(.noClearChange)
    ) -> SevenDayHealthSummary.ObjectiveFact {
        SevenDayHealthSummary.ObjectiveFact(
            metric: metric,
            unit: metric.expectedUnit,
            currentMedianValue: value,
            baselineMedianValue: value / (1 + change),
            relativeChange: change,
            currentValidDayCount: 7,
            currentExpectedDayCount: 7,
            baselineValidDayCount: 28,
            baselineExpectedDayCount: 28,
            trendState: state,
            sourceNames: ["知衡测试来源"],
            unavailableReason: nil
        )
    }

    private func summary(
        dataMode: HealthDataMode = .live,
        facts: [SevenDayHealthSummary.ObjectiveFact]? = nil,
        subjectiveState: SevenDayHealthSummary.SubjectiveState? = nil,
        contextState: SevenDayHealthSummary.ContextState? = nil
    ) -> SevenDayHealthSummary {
        SevenDayHealthSummary(
            version: SevenDayHealthSummary.version,
            generatedAt: date("2026-09-07T10:00:00Z"),
            interval: DateInterval(
                start: date("2026-08-30T16:00:00Z"),
                end: date("2026-09-06T16:00:00Z")
            ),
            baselineInterval: DateInterval(
                start: date("2026-08-02T16:00:00Z"),
                end: date("2026-08-30T16:00:00Z")
            ),
            timeZoneIdentifier: "Asia/Shanghai",
            dataMode: dataMode,
            title: "本周有一项变化值得看",
            factSummary: "最近 7 个完整日，步数中位数为 6,040 步，相比个人基线上升 16%。",
            uncertainty: "有限窗口只反映同期变化，不能证明因果。",
            objectiveFacts: facts ?? [
                objectiveFact(metric: .sleepDuration, value: 7.3),
                objectiveFact(metric: .heartRateVariability, value: 49),
                objectiveFact(metric: .restingHeartRate, value: 59),
                objectiveFact(
                    metric: .stepCount,
                    value: 6_040,
                    change: 0.16,
                    state: .trend(.sustainedChange)
                )
            ],
            subjectiveState: subjectiveState ?? .available(.init(
                recordedDayCount: 3,
                expectedDayCount: 7,
                energyMedian: 4,
                stressMedian: 2,
                bodyFeelingMedian: 4.5
            )),
            contextState: contextState ?? .available([
                .init(kind: .caffeine, count: 2),
                .init(kind: .deadline, count: 1)
            ]),
            recommendation: .init(
                text: "保持当前节奏，继续观察未来几天。",
                sourceText: "来源：本地 7/28 天趋势与结构化记录；未使用 AI。",
                usesAI: false,
                automaticallyCreatesPlan: false
            )
        )
    }

    private func pdfText(_ data: Data) throws -> String {
        let document = try XCTUnwrap(PDFDocument(data: data))
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    func testPrivacyPolicyNamesIncludedExcludedAndExternalCopy() {
        XCTAssertEqual(SevenDayHealthReportPrivacyPolicy.maximumDisplayNameLength, 40)
        XCTAssertTrue(SevenDayHealthReportPrivacyPolicy.includedItems.joined().contains("聚合健康记录"))
        let excluded = SevenDayHealthReportPrivacyPolicy.excludedItems.joined()
        XCTAssertTrue(excluded.contains("原始健康样本"))
        XCTAssertTrue(excluded.contains("备注"))
        XCTAssertTrue(excluded.contains("记录 ID"))
        XCTAssertTrue(excluded.contains("AI 对话"))
        XCTAssertTrue(SevenDayHealthReportPrivacyPolicy.externalHandlingNotice.contains("接收应用"))
        XCTAssertNil(SevenDayHealthReportExportOptions.anonymous.displayName)
    }

    func testOptionalNameIsTrimmedBoundedAndNeverImplicit() throws {
        XCTAssertEqual(
            try SevenDayHealthReportExportOptions.includingDisplayName("  测试用户  ").displayName,
            "测试用户"
        )
        XCTAssertEqual(
            try SevenDayHealthReportExportOptions.includingDisplayName(String(repeating: "名", count: 40)).displayName?.count,
            40
        )
        XCTAssertThrowsError(try SevenDayHealthReportExportOptions.includingDisplayName(" \n ")) { error in
            XCTAssertEqual(error as? SevenDayHealthReportExportError, .emptyDisplayName)
        }
        XCTAssertThrowsError(
            try SevenDayHealthReportExportOptions.includingDisplayName(String(repeating: "名", count: 41))
        ) { error in
            XCTAssertEqual(error as? SevenDayHealthReportExportError, .displayNameTooLong)
        }
    }

    func testConfirmationGateCannotProduceOptionsBeforeConfirmationOrAfterCancel() {
        var gate = SevenDayHealthReportExportGate()
        XCTAssertNil(gate.consumeConfirmedOptions())

        gate.begin()
        XCTAssertTrue(gate.isAwaitingConfirmation)
        XCTAssertNil(gate.consumeConfirmedOptions())
        gate.cancel()
        XCTAssertNil(gate.consumeConfirmedOptions())

        XCTAssertFalse(gate.confirm(.anonymous))
        gate.begin()
        XCTAssertTrue(gate.confirm(.anonymous))
        XCTAssertFalse(gate.isAwaitingConfirmation)
        XCTAssertEqual(gate.consumeConfirmedOptions(), .anonymous)
        XCTAssertNil(gate.consumeConfirmedOptions())
    }

    func testAnonymousPDFContainsEveryReportLayerAndA4Pages() throws {
        let data = try SevenDayHealthReportPDFRenderer.render(
            summary: summary(),
            options: .anonymous
        )
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        for index in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: index))
            let box = page.bounds(for: .mediaBox)
            XCTAssertEqual(box.width, SevenDayHealthReportPDFRenderer.pageBounds.width, accuracy: 1)
            XCTAssertEqual(box.height, SevenDayHealthReportPDFRenderer.pageBounds.height, accuracy: 1)
        }

        let text = try pdfText(data)
        for expected in [
            "7 天健康摘要", "摘要范围", "本周概览", "客观记录", "睡眠时长",
            "HRV", "静息心率", "步数", "主观感受", "生活情境", "下一步",
            "数据来源", "不用于诊断", "不包含原始 HealthKit 样本"
        ] {
            XCTAssertTrue(text.contains(expected), "missing: \(expected)")
        }
        XCTAssertFalse(text.contains("姓名："))
        XCTAssertFalse(text.contains(privateSentinel))
    }

    func testExplicitNameAppearsOnlyInsideCurrentPDF() throws {
        let named = try SevenDayHealthReportExportOptions.includingDisplayName("测试用户")
        let namedText = try pdfText(SevenDayHealthReportPDFRenderer.render(
            summary: summary(),
            options: named
        ))
        let anonymousText = try pdfText(SevenDayHealthReportPDFRenderer.render(
            summary: summary(),
            options: .anonymous
        ))
        XCTAssertTrue(namedText.contains("姓名"))
        XCTAssertTrue(namedText.contains("测试用户"))
        XCTAssertFalse(anonymousText.contains("测试用户"))
        XCTAssertEqual(SevenDayHealthReportTemporaryFileStore.fileName, "知衡-7天健康摘要.pdf")
        XCTAssertFalse(SevenDayHealthReportTemporaryFileStore.fileName.contains("测试用户"))
    }

    func testDemoPDFIsProminentlyLabeledAndExcludesRealContext() throws {
        let report = summary(
            dataMode: .demo,
            subjectiveState: .demoMode,
            contextState: .demoMode
        )
        let text = try pdfText(SevenDayHealthReportPDFRenderer.render(
            summary: report,
            options: .anonymous
        ))
        XCTAssertTrue(text.contains("演示数据 - 非真实健康记录"))
        XCTAssertTrue(text.contains("演示模式不读取或展示你的真实感受记录"))
        XCTAssertTrue(text.contains("演示模式不读取或展示你的真实生活事件"))
        XCTAssertFalse(text.contains(privateSentinel))
    }

    func testUnavailableMetricKeepsReasonAndDoesNotInventMedian() throws {
        var facts = summary().objectiveFacts
        facts[0] = SevenDayHealthSummary.ObjectiveFact(
            metric: .sleepDuration,
            unit: .hours,
            currentMedianValue: nil,
            baselineMedianValue: nil,
            relativeChange: nil,
            currentValidDayCount: nil,
            currentExpectedDayCount: nil,
            baselineValidDayCount: nil,
            baselineExpectedDayCount: nil,
            trendState: nil,
            sourceNames: [],
            unavailableReason: .accessNotRequested
        )
        let text = try pdfText(SevenDayHealthReportPDFRenderer.render(
            summary: summary(facts: facts),
            options: .anonymous
        ))
        let sleepStart = try XCTUnwrap(text.range(of: "睡眠时长"))
        let hrvStart = try XCTUnwrap(text.range(of: "HRV", range: sleepStart.upperBound..<text.endIndex))
        let sleepSection = String(text[sleepStart.lowerBound..<hrvStart.lowerBound])
        XCTAssertTrue(sleepSection.contains("尚未请求访问"))
        XCTAssertTrue(sleepSection.contains("暂无可用来源"))
        XCTAssertFalse(sleepSection.contains("7 天中位数"))
    }

    func testRendererRejectsReorderedOrUnsafeSummary() {
        let reordered = summary().objectiveFacts.reversed()
        XCTAssertThrowsError(try SevenDayHealthReportPDFRenderer.render(
            summary: summary(facts: Array(reordered)),
            options: .anonymous
        )) { error in
            XCTAssertEqual(error as? SevenDayHealthReportExportError, .invalidSummary)
        }

        let base = summary()
        let unsafe = SevenDayHealthSummary(
            version: base.version,
            generatedAt: base.generatedAt,
            interval: base.interval,
            baselineInterval: base.baselineInterval,
            timeZoneIdentifier: base.timeZoneIdentifier,
            dataMode: base.dataMode,
            title: base.title,
            factSummary: base.factSummary,
            uncertainty: base.uncertainty,
            objectiveFacts: base.objectiveFacts,
            subjectiveState: base.subjectiveState,
            contextState: base.contextState,
            recommendation: .init(
                text: base.recommendation.text,
                sourceText: base.recommendation.sourceText,
                usesAI: true,
                automaticallyCreatesPlan: false
            )
        )
        XCTAssertThrowsError(try SevenDayHealthReportPDFRenderer.render(
            summary: unsafe,
            options: .anonymous
        ))
    }

    func testTemporaryFileIsProtectedExcludedFromBackupAndNeutralNamed() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SevenDayHealthReportExportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let data = try SevenDayHealthReportPDFRenderer.render(summary: summary(), options: .anonymous)
        let export = try SevenDayHealthReportTemporaryFileStore.create(
            pdfData: data,
            baseDirectory: base
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.fileURL.path))
        XCTAssertEqual(export.fileURL.lastPathComponent, SevenDayHealthReportTemporaryFileStore.fileName)
        XCTAssertEqual(
            try export.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        XCTAssertEqual(SevenDayHealthReportTemporaryFileStore.protectionType, .complete)
        XCTAssertTrue(SevenDayHealthReportTemporaryFileStore.writingOptions.contains(.completeFileProtection))
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: export.fileURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        #endif
    }

    func testCleanupIsIdempotentAndLeavesSiblingFilesUntouched() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SevenDayHealthReportCleanupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let sibling = base.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)

        let data = try SevenDayHealthReportPDFRenderer.render(summary: summary(), options: .anonymous)
        let export = try SevenDayHealthReportTemporaryFileStore.create(
            pdfData: data,
            baseDirectory: base
        )
        SevenDayHealthReportTemporaryFileStore.cleanup(export)
        SevenDayHealthReportTemporaryFileStore.cleanup(export)

        XCTAssertFalse(FileManager.default.fileExists(atPath: export.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testNextEntryCleanupRemovesInterruptedExportsButNotOtherTemporaryFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SevenDayHealthReportStaleTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let sibling = base.appendingPathComponent("unrelated.tmp")
        try Data("keep".utf8).write(to: sibling)
        let data = try SevenDayHealthReportPDFRenderer.render(summary: summary(), options: .anonymous)
        let first = try SevenDayHealthReportTemporaryFileStore.create(pdfData: data, baseDirectory: base)
        let second = try SevenDayHealthReportTemporaryFileStore.create(pdfData: data, baseDirectory: base)

        SevenDayHealthReportTemporaryFileStore.cleanupStaleExports(baseDirectory: base)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testInvalidDataCreatesNoShareDirectory() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SevenDayHealthReportInvalidTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        XCTAssertThrowsError(try SevenDayHealthReportTemporaryFileStore.create(
            pdfData: Data(privateSentinel.utf8),
            baseDirectory: base
        )) { error in
            XCTAssertEqual(error as? SevenDayHealthReportExportError, .invalidPDFData)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }
}
