import SwiftUI
import UIKit

enum SevenDayHealthReportExportError: Error, Equatable, Sendable {
    case emptyDisplayName
    case displayNameTooLong
    case invalidSummary
    case invalidPDFData
}

struct SevenDayHealthReportExportOptions: Equatable, Sendable {
    static let anonymous = SevenDayHealthReportExportOptions(validatedDisplayName: nil)

    let displayName: String?

    private init(validatedDisplayName: String?) {
        displayName = validatedDisplayName
    }

    static func includingDisplayName(
        _ rawValue: String
    ) throws -> SevenDayHealthReportExportOptions {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SevenDayHealthReportExportError.emptyDisplayName
        }
        guard trimmed.count <= SevenDayHealthReportPrivacyPolicy.maximumDisplayNameLength else {
            throw SevenDayHealthReportExportError.displayNameTooLong
        }
        return SevenDayHealthReportExportOptions(validatedDisplayName: trimmed)
    }
}

enum SevenDayHealthReportPrivacyPolicy {
    static let maximumDisplayNameLength = 40

    static let includedItems = [
        "最近 7 个完整日的聚合健康记录与 28 天个人基线对照",
        "已保存感受的分项汇总和结构化生活情境",
        "本地建议、数据来源与不确定性说明"
    ]

    static let excludedItems = [
        "手机号、身份证及默认关闭的姓名",
        "备注、自定义事件名称、底层记录 ID 和原始健康样本",
        "CareKit 反馈、AI 对话和任何云端新增内容"
    ]

    static let externalHandlingNotice =
        "报告离开知衡后，由你选择的接收应用管理副本。请只分享给你信任的人或服务。"
}

struct SevenDayHealthReportExportGate: Equatable, Sendable {
    private(set) var isAwaitingConfirmation = false
    private var confirmedOptions: SevenDayHealthReportExportOptions?

    mutating func begin() {
        isAwaitingConfirmation = true
        confirmedOptions = nil
    }

    mutating func cancel() {
        isAwaitingConfirmation = false
        confirmedOptions = nil
    }

    @discardableResult
    mutating func confirm(_ options: SevenDayHealthReportExportOptions) -> Bool {
        guard isAwaitingConfirmation else { return false }
        isAwaitingConfirmation = false
        confirmedOptions = options
        return true
    }

    mutating func consumeConfirmedOptions() -> SevenDayHealthReportExportOptions? {
        defer { confirmedOptions = nil }
        return confirmedOptions
    }
}

struct SevenDayHealthReportTemporaryFile: Identifiable, Equatable, Sendable {
    var id: URL { fileURL }

    let fileURL: URL
    fileprivate let cleanupRootURL: URL
}

enum SevenDayHealthReportTemporaryFileStore {
    private static let parentDirectoryName = "ZhihengReportShare"
    static let fileName = "知衡-7天健康摘要.pdf"
    static let protectionType = FileProtectionType.complete
    static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    static func create(
        pdfData: Data,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> SevenDayHealthReportTemporaryFile {
        guard pdfData.starts(with: Data("%PDF".utf8)) else {
            throw SevenDayHealthReportExportError.invalidPDFData
        }

        let parent = baseDirectory.appendingPathComponent(
            parentDirectoryName,
            isDirectory: true
        )
        let root = parent.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protectionType]
        )

        var protectedRoot = root
        var rootValues = URLResourceValues()
        rootValues.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(rootValues)

        var fileURL = root.appendingPathComponent(fileName, isDirectory: false)
        try pdfData.write(to: fileURL, options: writingOptions)
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        try fileURL.setResourceValues(fileValues)

        return SevenDayHealthReportTemporaryFile(
            fileURL: fileURL,
            cleanupRootURL: root
        )
    }

    static func cleanup(_ file: SevenDayHealthReportTemporaryFile) {
        guard file.cleanupRootURL.deletingLastPathComponent().lastPathComponent == parentDirectoryName else {
            return
        }
        try? FileManager.default.removeItem(at: file.cleanupRootURL)
    }

    static func cleanupStaleExports(
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        let parent = baseDirectory.appendingPathComponent(
            parentDirectoryName,
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: parent)
    }
}

@MainActor
enum SevenDayHealthReportPDFRenderer {
    static let pageBounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    static func render(
        summary: SevenDayHealthSummary,
        options: SevenDayHealthReportExportOptions
    ) throws -> Data {
        guard summary.version == SevenDayHealthSummary.version,
              summary.objectiveFacts.map(\.metric) == SevenDayHealthSummaryFactory.objectiveMetrics,
              !summary.factSummary.isEmpty,
              !summary.uncertainty.isEmpty,
              !summary.recommendation.text.isEmpty,
              !summary.recommendation.usesAI,
              !summary.recommendation.automaticallyCreatesPlan else {
            throw SevenDayHealthReportExportError.invalidSummary
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "知衡 7 天健康摘要",
            kCGPDFContextAuthor as String: "知衡",
            kCGPDFContextSubject as String: summary.dataMode == .demo
                ? "演示数据健康摘要"
                : "个人聚合健康摘要",
            kCGPDFContextCreator as String: "知衡 iPhone App"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)
        let data = renderer.pdfData { context in
            let writer = ReportPDFWriter(
                context: context,
                summary: summary,
                options: options,
                pageBounds: pageBounds
            )
            writer.draw()
        }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw SevenDayHealthReportExportError.invalidPDFData
        }
        return data
    }
}

@MainActor
private final class ReportPDFWriter {
    private let context: UIGraphicsPDFRendererContext
    private let summary: SevenDayHealthSummary
    private let options: SevenDayHealthReportExportOptions
    private let pageBounds: CGRect
    private let horizontalMargin: CGFloat = 46
    private let contentBottom: CGFloat = 784
    private var y: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat {
        pageBounds.width - horizontalMargin * 2
    }

    init(
        context: UIGraphicsPDFRendererContext,
        summary: SevenDayHealthSummary,
        options: SevenDayHealthReportExportOptions,
        pageBounds: CGRect
    ) {
        self.context = context
        self.summary = summary
        self.options = options
        self.pageBounds = pageBounds
    }

    func draw() {
        beginPage()
        drawIdentityAndScope()
        drawOverview()
        drawObjectiveFacts()
        drawSubjectiveState()
        drawContextState()
        drawRecommendation()
        drawPrivacyNotice()
    }

    private func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = 42

        drawRaw(
            "知衡",
            rect: CGRect(x: horizontalMargin, y: y, width: 80, height: 24),
            font: .systemFont(ofSize: 18, weight: .bold),
            color: UIColor(red: 0.05, green: 0.47, blue: 0.43, alpha: 1)
        )
        drawRaw(
            "7 天健康摘要",
            rect: CGRect(x: horizontalMargin + 82, y: y + 2, width: 180, height: 22),
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .label
        )
        if summary.dataMode == .demo {
            drawRaw(
                "演示数据 - 非真实健康记录",
                rect: CGRect(x: pageBounds.width - horizontalMargin - 190, y: y + 3, width: 190, height: 20),
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: .systemOrange,
                alignment: .right
            )
        }

        UIColor.separator.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: horizontalMargin, y: 71))
        line.addLine(to: CGPoint(x: pageBounds.width - horizontalMargin, y: 71))
        line.lineWidth = 0.6
        line.stroke()

        drawRaw(
            "第 \(pageNumber) 页  ·  本地生成  ·  不用于诊断或急救监护",
            rect: CGRect(x: horizontalMargin, y: pageBounds.height - 34, width: contentWidth, height: 16),
            font: .systemFont(ofSize: 8.5),
            color: .secondaryLabel,
            alignment: .center
        )
        y = 88
    }

    private func drawIdentityAndScope() {
        if let displayName = options.displayName {
            drawText("姓名：\(displayName)", font: .systemFont(ofSize: 11, weight: .semibold), spacingAfter: 5)
        }
        drawText(
            "摘要范围：\(dateRange(summary.interval))",
            font: .systemFont(ofSize: 11, weight: .semibold),
            spacingAfter: 3
        )
        drawText(
            "客观对照：此前不重叠的 28 天个人基线 · 按 \(summary.timeZoneIdentifier) 本地日计算",
            font: .systemFont(ofSize: 9.5),
            color: .secondaryLabel,
            spacingAfter: 3
        )
        drawText(
            "生成时间：\(dateTime(summary.generatedAt))",
            font: .systemFont(ofSize: 9.5),
            color: .secondaryLabel,
            spacingAfter: 14
        )
    }

    private func drawOverview() {
        drawSectionTitle("本周概览")
        drawText(summary.title, font: .systemFont(ofSize: 15, weight: .semibold), spacingAfter: 6)
        drawText(summary.factSummary, font: .systemFont(ofSize: 10.5), spacingAfter: 5)
        drawText(summary.uncertainty, font: .systemFont(ofSize: 9.5), color: .secondaryLabel, spacingAfter: 14)
    }

    private func drawObjectiveFacts() {
        drawSectionTitle("客观记录")
        for fact in summary.objectiveFacts {
            let lines = objectiveLines(fact)
            ensureSpace(lines.reduce(CGFloat(14)) { partial, line in
                partial + measuredHeight(line, font: .systemFont(ofSize: 9.5), width: contentWidth - 14) + 3
            })
            drawText(metricTitle(fact.metric), font: .systemFont(ofSize: 11.5, weight: .semibold), spacingAfter: 3)
            for line in lines {
                drawText("• \(line)", font: .systemFont(ofSize: 9.5), color: .secondaryLabel, indent: 12, spacingAfter: 2)
            }
            y += 5
        }
        y += 5
    }

    private func drawSubjectiveState() {
        drawSectionTitle("主观感受")
        switch summary.subjectiveState {
        case .available(let values):
            drawText("近 7 天有 \(values.recordedDayCount)/\(values.expectedDayCount) 天已保存记录。", font: .systemFont(ofSize: 9.5), color: .secondaryLabel, spacingAfter: 4)
            drawText("精力中位数：\(rating(values.energyMedian))", font: .systemFont(ofSize: 10), spacingAfter: 3)
            drawText("压力中位数：\(rating(values.stressMedian))", font: .systemFont(ofSize: 10), spacingAfter: 3)
            drawText("身体感受中位数：\(rating(values.bodyFeelingMedian))", font: .systemFont(ofSize: 10), spacingAfter: 3)
            drawText("三项分别汇总，不计算综合健康分。", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 12)
        case .notRecorded:
            drawText("这 7 天还没有已保存的感受记录。未记录不代表没有感受。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        case .demoMode:
            drawText("演示模式不读取或展示你的真实感受记录。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        case .unavailable:
            drawText("主观记录暂时无法读取，不会用部分结果拼接报告。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        }
    }

    private func drawContextState() {
        drawSectionTitle("生活情境")
        switch summary.contextState {
        case .available(let events):
            for event in events {
                drawText("\(event.kind.title)：\(event.count) 次", font: .systemFont(ofSize: 10), spacingAfter: 3)
            }
            drawText("只汇总结构化类型和次数；同期出现不代表它导致指标变化。", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 12)
        case .notRecorded:
            drawText("这 7 天没有已保存的生活事件。未记录不等于没有相关情境。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        case .demoMode:
            drawText("演示模式不读取或展示你的真实生活事件。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        case .unavailable:
            drawText("生活事件暂时无法读取，不会把读取失败写成没有事件。", font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)
        }
    }

    private func drawRecommendation() {
        drawSectionTitle("下一步")
        drawText(summary.recommendation.text, font: .systemFont(ofSize: 10.5), spacingAfter: 5)
        drawText(summary.recommendation.sourceText, font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 4)
        drawText("建议不会自动创建微计划；如需行动，仍由你主动确认。", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 14)
    }

    private func drawPrivacyNotice() {
        drawSectionTitle("使用说明")
        drawText(
            "这份报告包含个人聚合健康记录、已保存感受和生活情境。离开知衡后，由接收应用管理副本，请谨慎选择分享对象。",
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: .systemOrange,
            spacingAfter: 5
        )
        drawText(
            "报告不包含原始 HealthKit 样本、备注、自定义事件名称、底层记录 ID、CareKit 反馈或 AI 对话。内容仅用于个人健康管理和沟通准备，不构成诊断、治疗建议或持续监护。",
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel,
            spacingAfter: 0
        )
    }

    private func drawSectionTitle(_ title: String) {
        ensureSpace(70)
        let accent = CGRect(x: horizontalMargin, y: y + 2, width: 3, height: 16)
        UIColor(red: 0.05, green: 0.55, blue: 0.50, alpha: 1).setFill()
        UIBezierPath(roundedRect: accent, cornerRadius: 1.5).fill()
        drawRaw(
            title,
            rect: CGRect(x: horizontalMargin + 10, y: y, width: contentWidth - 10, height: 22),
            font: .systemFont(ofSize: 13, weight: .bold),
            color: .label
        )
        y += 27
    }

    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor = .label,
        indent: CGFloat = 0,
        spacingAfter: CGFloat
    ) {
        let safeText = sanitized(text)
        let width = contentWidth - indent
        let height = measuredHeight(safeText, font: font, width: width)
        ensureSpace(height + spacingAfter)
        drawRaw(
            safeText,
            rect: CGRect(x: horizontalMargin + indent, y: y, width: width, height: height),
            font: font,
            color: color
        )
        y += height + spacingAfter
    }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > contentBottom {
            beginPage()
        }
    }

    private func measuredHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let style = paragraphStyle()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style
        ]
        let rect = (sanitized(text) as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(rect.height) + 1
    }

    private func drawRaw(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let style = paragraphStyle(alignment: alignment)
        (sanitized(text) as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ],
            context: nil
        )
    }

    private func paragraphStyle(alignment: NSTextAlignment = .left) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return style
    }

    private func objectiveLines(_ fact: SevenDayHealthSummary.ObjectiveFact) -> [String] {
        if let reason = fact.unavailableReason {
            return ["状态：\(unavailableText(reason))", "数据来源：暂无可用来源"]
        }
        var lines = ["状态：\(objectiveStatus(fact))"]
        if let value = fact.currentMedianValue {
            lines.append("7 天中位数：\(format(value, unit: fact.unit))")
        }
        if let current = fact.currentValidDayCount,
           let currentExpected = fact.currentExpectedDayCount,
           let baseline = fact.baselineValidDayCount,
           let baselineExpected = fact.baselineExpectedDayCount {
            lines.append("有效日：近 7 天 \(current)/\(currentExpected) · 基线 \(baseline)/\(baselineExpected)")
        }
        if let change = fact.relativeChange {
            lines.append("相较个人基线：\(signedPercent(change))")
        }
        lines.append("数据来源：\(fact.sourceNames.isEmpty ? "暂无可用来源" : fact.sourceNames.joined(separator: "、"))")
        return lines
    }

    private func objectiveStatus(_ fact: SevenDayHealthSummary.ObjectiveFact) -> String {
        switch fact.trendState {
        case .currentWindowInsufficient: "近 7 天数据不足"
        case .baselineInsufficient: "个人基线不足"
        case .sourceChanged: "来源发生变化"
        case .trend(.noClearChange): "未见明确变化"
        case .trend(.worthObserving): "值得继续观察"
        case .trend(.sustainedChange): "存在持续变化"
        case nil: "暂时无法分析"
        }
    }

    private func unavailableText(_ reason: InsightDataUnavailableReason) -> String {
        switch reason {
        case .accessNotRequested: "尚未请求访问"
        case .healthDataUnavailable: "设备暂不可用"
        case .noVisibleData: "暂无可见数据"
        case .queryFailed: "读取失败"
        case .notLoaded: "尚未读取"
        case .queryWindowIncomplete: "读取范围不足"
        case .sourceConflict: "来源暂无法合并"
        case .sourceChanged: "来源发生变化"
        case .recentDataGap: "最近一天缺少记录"
        case .unsupportedMetric: "暂不支持分析"
        case .analysisUnavailable: "暂时无法分析"
        }
    }

    private func metricTitle(_ metric: HealthMetricType) -> String {
        switch metric {
        case .sleepDuration: "睡眠时长"
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "静息心率"
        case .stepCount: "步数"
        default: metric.rawValue
        }
    }

    private func format(_ value: Double, unit: HealthMetricUnit) -> String {
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

    private func signedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.percent.precision(.fractionLength(0))))"
    }

    private func rating(_ value: Double) -> String {
        let digits = value.rounded() == value ? 0 : 1
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) / 5"
    }

    private func dateRange(_ interval: DateInterval) -> String {
        guard let zone = TimeZone(identifier: summary.timeZoneIdentifier) else {
            return "时间范围不可用"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(formatter.string(from: interval.start)) - \(formatter.string(from: end))"
    }

    private func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: summary.timeZoneIdentifier)
        formatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return formatter.string(from: date)
    }

    private func sanitized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
    }
}

@MainActor
struct SystemActivityView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
