import SwiftUI

@MainActor
struct SevenDayHealthSummaryView: View {
    @ObservedObject var healthSession: HealthDataSession
    let contextLoader: InsightContextLoader
    let dataMode: HealthDataMode

    @State private var summary: SevenDayHealthSummary?
    @State private var errorMessage: String?
    @State private var isRefreshing = false
    @State private var isShowingExportPrivacy = false
    @State private var isPreparingExport = false
    @State private var activeExport: SevenDayHealthReportTemporaryFile?
    @State private var exportErrorMessage: String?
    @State private var exportGate = SevenDayHealthReportExportGate()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let summary {
                    if summary.dataMode == .demo {
                        Label("演示摘要，不是你的真实健康记录", systemImage: "theatermasks.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    rangeCard(summary)
                    overviewCard(summary)
                    objectiveCard(summary)
                    subjectiveCard(summary)
                    contextCard(summary)
                    recommendationCard(summary)
                    exportCard()
                    Text("本摘要由本地聚合规则即时生成，不用于诊断或急救监护，不包含原始 HealthKit 样本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "暂时无法生成摘要",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("正在整理最近 7 天…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("7 天健康摘要")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("刷新 7 天健康摘要")
            }
        }
        .task {
            SevenDayHealthReportTemporaryFileStore.cleanupStaleExports()
            buildSummary()
        }
        .sheet(isPresented: $isShowingExportPrivacy, onDismiss: cancelUnconfirmedExport) {
            SevenDayHealthReportPrivacySheet(
                onCancel: {
                    exportGate.cancel()
                    isShowingExportPrivacy = false
                },
                onConfirm: { options in
                    guard exportGate.confirm(options) else { return }
                    isShowingExportPrivacy = false
                    Task { @MainActor in
                        await Task.yield()
                        prepareConfirmedExport()
                    }
                }
            )
        }
        .sheet(item: $activeExport, onDismiss: cleanupActiveExport) { export in
            SystemActivityView(fileURL: export.fileURL)
                .ignoresSafeArea()
        }
        .alert(
            "暂时无法生成分享报告",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "请稍后重试。")
        }
        .onDisappear(perform: cleanupActiveExport)
    }

    private func buildSummary() {
        do {
            let now = Date()
            let factSet = try InsightFactGenerator.generate(
                snapshot: healthSession.snapshot,
                loadedInterval: healthSession.snapshotInterval,
                access: healthSession.accessState,
                dataMode: dataMode,
                referenceDate: now,
                timeZone: .autoupdatingCurrent,
                metrics: SevenDayHealthSummaryFactory.objectiveMetrics
            )
            summary = try SevenDayHealthSummaryFactory.make(
                factSet: factSet,
                contextState: contextLoader.load(for: factSet),
                generatedAt: now
            )
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = "不会用不完整或错位的数据拼接摘要，请稍后重试。"
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await healthSession.refresh()
        buildSummary()
        isRefreshing = false
    }

    private func rangeCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "摘要范围", systemImage: "calendar") {
            Text(dateRange(summary.interval, timeZoneIdentifier: summary.timeZoneIdentifier))
                .font(.body.weight(.semibold))
            Text("最近 7 个完整日，不含今天；客观趋势对比此前不重叠的 28 天个人基线。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("按 \(summary.timeZoneIdentifier) 的本地日计算")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func overviewCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "本周概览", systemImage: "sparkles") {
            Text(summary.title)
                .font(.title3.weight(.semibold))
            Text(summary.factSummary)
            Text(summary.uncertainty)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func objectiveCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "客观记录", systemImage: "waveform.path.ecg") {
            ForEach(Array(summary.objectiveFacts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metricTitle(fact.metric))
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(objectiveStatus(fact))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(objectiveStatusColor(fact))
                    }
                    if let value = fact.currentMedianValue {
                        Text("7 天中位数：\(format(value, unit: fact.unit))")
                    }
                    if let current = fact.currentValidDayCount,
                       let currentExpected = fact.currentExpectedDayCount,
                       let baseline = fact.baselineValidDayCount,
                       let baselineExpected = fact.baselineExpectedDayCount {
                        Text("有效日：近 7 天 \(current)/\(currentExpected) · 基线 \(baseline)/\(baselineExpected)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let change = fact.relativeChange {
                        Text("相较个人基线：\(signedPercent(change))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("来源：\(fact.sourceNames.isEmpty ? "暂无可用来源" : fact.sourceNames.joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func subjectiveCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "主观感受", systemImage: "person.crop.circle") {
            switch summary.subjectiveState {
            case .available(let values):
                Text("近 7 天有 \(values.recordedDayCount)/\(values.expectedDayCount) 天记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("精力中位数", value: rating(values.energyMedian))
                LabeledContent("压力中位数", value: rating(values.stressMedian))
                LabeledContent("身体感受中位数", value: rating(values.bodyFeelingMedian))
                Text("三项分别汇总，不计算综合健康分。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notRecorded:
                Text("这 7 天还没有已保存的感受记录。未记录不代表没有感受。")
                    .foregroundStyle(.secondary)
            case .demoMode:
                Text("演示模式不读取或展示你的真实感受记录。")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("主观记录暂时无法读取，不会用部分结果拼接摘要。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func contextCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "生活情境", systemImage: "tag") {
            switch summary.contextState {
            case .available(let events):
                ForEach(events) { event in
                    LabeledContent(event.kind.title, value: "\(event.count) 次")
                }
                Text("这里只汇总结构化类型和次数；同期出现不代表它导致了指标变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notRecorded:
                Text("这 7 天没有已保存的生活事件。未记录不等于没有相关情境。")
                    .foregroundStyle(.secondary)
            case .demoMode:
                Text("演示模式不读取或展示你的真实生活事件。")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("生活事件暂时无法读取，不会把读取失败写成没有事件。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recommendationCard(_ summary: SevenDayHealthSummary) -> some View {
        summaryCard(title: "下一步", systemImage: "leaf") {
            Text(summary.recommendation.text)
            Text(summary.recommendation.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("建议不会自动创建微计划；如需行动，仍由你主动确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func exportCard() -> some View {
        summaryCard(title: "导出与分享", systemImage: "square.and.arrow.up") {
            Text("生成前会先说明报告包含的聚合健康信息；取消确认不会创建文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                exportGate.begin()
                isShowingExportPrivacy = true
            } label: {
                HStack {
                    if isPreparingExport {
                        ProgressView()
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text(isPreparingExport ? "正在生成 PDF…" : "导出 PDF 并分享")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(summary == nil || isPreparingExport || activeExport != nil)
            .accessibilityHint("先显示隐私确认，确认后才生成临时 PDF 并打开系统分享")
        }
    }

    private func prepareConfirmedExport() {
        guard let options = exportGate.consumeConfirmedOptions() else { return }
        guard let summary, !isPreparingExport, activeExport == nil else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            let pdfData = try SevenDayHealthReportPDFRenderer.render(
                summary: summary,
                options: options
            )
            activeExport = try SevenDayHealthReportTemporaryFileStore.create(
                pdfData: pdfData
            )
            exportErrorMessage = nil
        } catch {
            cleanupActiveExport()
            exportErrorMessage = "没有保留不完整的临时报告。请返回摘要确认内容后再试。"
        }
    }

    private func cleanupActiveExport() {
        guard let activeExport else { return }
        SevenDayHealthReportTemporaryFileStore.cleanup(activeExport)
        self.activeExport = nil
    }

    private func cancelUnconfirmedExport() {
        if exportGate.isAwaitingConfirmation {
            exportGate.cancel()
        }
    }

    private func summaryCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.teal)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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

    private func objectiveStatus(_ fact: SevenDayHealthSummary.ObjectiveFact) -> String {
        if let reason = fact.unavailableReason { return unavailableText(reason) }
        switch fact.trendState {
        case .currentWindowInsufficient: return "近 7 天数据不足"
        case .baselineInsufficient: return "个人基线不足"
        case .sourceChanged: return "来源发生变化"
        case .trend(.noClearChange): return "未见明确变化"
        case .trend(.worthObserving): return "值得继续观察"
        case .trend(.sustainedChange): return "存在持续变化"
        case nil: return "暂时无法分析"
        }
    }

    private func objectiveStatusColor(_ fact: SevenDayHealthSummary.ObjectiveFact) -> Color {
        guard case .trend(.sustainedChange) = fact.trendState else { return .secondary }
        return .teal
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
        "\(value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))) / 5"
    }

    private func dateRange(_ interval: DateInterval, timeZoneIdentifier: String) -> String {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return "时间范围不可用" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(formatter.string(from: interval.start))—\(formatter.string(from: end))"
    }
}

@MainActor
private struct SevenDayHealthReportPrivacySheet: View {
    let onCancel: () -> Void
    let onConfirm: (SevenDayHealthReportExportOptions) -> Void

    @State private var includeDisplayName = false
    @State private var displayName = ""

    private var exportOptions: SevenDayHealthReportExportOptions? {
        if !includeDisplayName { return .anonymous }
        return try? .includingDisplayName(displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("这份 PDF 会离开知衡，请先确认包含范围和外部副本风险。")
                        .font(.body.weight(.semibold))
                }

                Section("报告将包含") {
                    ForEach(SevenDayHealthReportPrivacyPolicy.includedItems, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                    }
                }

                Section("默认不会包含") {
                    ForEach(SevenDayHealthReportPrivacyPolicy.excludedItems, id: \.self) { item in
                        Label(item, systemImage: "minus.circle")
                    }
                }

                Section("可选身份信息") {
                    Toggle("在本次 PDF 中加入姓名", isOn: $includeDisplayName)
                    if includeDisplayName {
                        TextField("姓名", text: $displayName)
                            .textContentType(.name)
                        Text("姓名只写入本次 PDF，不保存到知衡。最多 \(SevenDayHealthReportPrivacyPolicy.maximumDisplayNameLength) 个字符。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if exportOptions == nil {
                            Text("请输入有效姓名，且不要超过长度限制。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Label(
                        SevenDayHealthReportPrivacyPolicy.externalHandlingNotice,
                        systemImage: "hand.raised.fill"
                    )
                    .foregroundStyle(.orange)
                    Text("确认后才会在本机临时生成 PDF。分享完成、取消或页面离开后，知衡会清理本次临时文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("确认并继续") {
                        if let exportOptions {
                            onConfirm(exportOptions)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(exportOptions == nil)

                    Button("取消", role: .cancel, action: onCancel)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("导出前请确认")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
