import Charts
import SwiftUI

struct InsightsView: View {
    @ObservedObject private var healthSession: HealthDataSession
    private let debugSectionFromArguments: String?

    @AppStorage("insightsDashboardLayoutV2") private var storedLayout = Data()
    @State private var layout = InsightsDashboardLayout.standard
    @State private var showsHRVInfo = false
    @State private var showsTrendDetails = false
    @State private var showsMetricEditor = false
    @State private var debugScrollTarget: String?

    init(healthSession: HealthDataSession) {
        self.healthSession = healthSession
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--insights-section=expanded") {
            debugSectionFromArguments = "insightsMetric-walkingRunningDistance"
        } else if ProcessInfo.processInfo.arguments.contains("--insights-section=body") {
            debugSectionFromArguments = "insightsBody"
        } else if ProcessInfo.processInfo.arguments.contains("--insights-section=chart") {
            debugSectionFromArguments = "insightsChart"
        } else {
            debugSectionFromArguments = nil
        }
#else
        debugSectionFromArguments = nil
#endif
    }

    private var readiness: AppReadiness {
        AppReadiness(healthAccess: healthSession.accessState)
    }

    private var healthSnapshot: HealthDataSnapshot? { healthSession.snapshot }
    private var isLoading: Bool { healthSession.isLoading }
    private var dataMode: HealthDataMode { healthSession.dataMode }

    private var dashboard: InsightsDashboardPresentation? {
        healthSnapshot.map {
            InsightsDashboardPresentationFactory.make(
                snapshot: $0,
                referenceDate: Date()
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    insightsHeader
                    if dataMode == .demo { demoModeBanner }
                    if let dashboard {
                        hrvOverview(dashboard)
                        bodyMetrics(dashboard)
                            .id("insightsBody")
                        referenceNote
                        wearableReminder
                    } else if isLoading {
                        ProgressView("正在整理健康数据…")
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else if !readiness.canQueryHealthData {
                        ContentUnavailableView(
                            "还没有可分析的数据",
                            systemImage: "chart.xyaxis.line",
                            description: Text("请先到“我的”页面查看健康数据状态并连接 Apple Health。")
                        )
                        .frame(minHeight: 360)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 96)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $debugScrollTarget, anchor: .top)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadHealthData() }
            .task {
                restoreLayout()
                if let debugSectionFromArguments {
                    try? await Task.sleep(for: .milliseconds(250))
                    debugScrollTarget = debugSectionFromArguments
                }
            }
            .onChange(of: dashboard != nil) { _, isAvailable in
#if DEBUG
                guard isAvailable, let debugSectionFromArguments else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    debugScrollTarget = debugSectionFromArguments
                }
#endif
            }
            .onChange(of: layout) { _, newValue in
                storedLayout = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        }
        .sheet(isPresented: $showsHRVInfo) {
            HRVReferenceExplanationView()
        }
        .sheet(isPresented: $showsTrendDetails) {
            if let healthSnapshot {
                InsightsTrendDetailView(snapshot: healthSnapshot)
            }
        }
        .sheet(isPresented: $showsMetricEditor) {
            InsightsMetricEditorView(layout: $layout)
        }
    }

    private var insightsHeader: some View {
        Text("洞悉")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(InsightsPalette.ink)
    }

    private func hrvOverview(_ dashboard: InsightsDashboardPresentation) -> some View {
        VStack(spacing: 0) {
            hrvHero(dashboard.hrv)
            hrvChart(
                dashboard.hrv,
                chart: dashboard.hrvIntradayChart
            )
            .id("insightsChart")
            detailsButton
                .padding(.top, 16)
        }
    }

    private func hrvHero(_ presentation: InsightsHRVPresentation) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                InsightsHRVGauge(presentation: presentation)
                    .frame(height: 286)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("HRV 个人参考仪表")
                    .accessibilityValue(gaugeAccessibilityValue(presentation))

                HStack {
                    Button { showsHRVInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 26, weight: .medium))
                            .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel("查看 HRV 详情说明")
                    Spacer()
                    ShareLink(item: shareText(presentation)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 26, weight: .medium))
                            .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel("分享 HRV 状态摘要")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 108)
            }

            VStack(spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(heroColor(presentation))

                Text(latestHRVText(presentation))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(presentation.explanation)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(InsightsPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .multilineTextAlignment(.center)
            .padding(.top, -2)
            .padding(.bottom, 12)
        }
        .background {
            InsightsCloudBackdrop()
                .padding(.horizontal, -18)
        }
    }

    private func hrvChart(
        _ presentation: InsightsHRVPresentation,
        chart: InsightsHRVIntradayChartPresentation
    ) -> some View {
        InsightsHRVReferenceChart(
            presentation: presentation,
            intraday: chart
        )
            .padding(.horizontal, -18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今天 HRV 与个人参考范围")
            .accessibilityValue(hrvChartAccessibilityValue(chart))
    }

    private var detailsButton: some View {
        Button { showsTrendDetails = true } label: {
            HStack {
                Text("HRV 详情")
                Spacer()
                HStack(spacing: 3) {
                    Text("查看更多")
                    Image(systemName: "chevron.right")
                }
                    .foregroundStyle(.blue)
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开 7 天和 28 天趋势详情")
    }

    private func bodyMetrics(_ dashboard: InsightsDashboardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("身体指标")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(InsightsPalette.ink)
                Spacer()
                Button("编辑") { showsMetricEditor = true }
                    .font(.headline)
            }
            ForEach(layout.visibleMetrics) { kind in
                if let item = dashboard.bodyMetrics.first(where: { $0.kind == kind }) {
                    NavigationLink {
                        HealthMetricDetailView(
                            metric: item.kind.metric,
                            state: healthSnapshot?[item.kind.metric] ?? .noVisibleData
                        )
                    } label: {
                        InsightsBodyMetricCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开\(item.kind.title)详情")
                    .id("insightsMetric-\(kind.rawValue)")
                }
            }
        }
    }

    private var referenceNote: some View {
        Text("各项身体指标的个人参考范围基于最近 28 天、至少 14 个有效日的数据计算，缺失记录不会补成 0。它用于和过去的自己比较，不代表医学正常范围。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var wearableReminder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("温馨提醒")
                .font(.headline)
            Text("睡眠相关指标需要 Apple Watch 在夜间产生相应记录。所有结果仅用于生活方式观察；如果出现明显不适或症状持续，请咨询专业人士。")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .overlay(alignment: .top) { Divider() }
    }

    private var demoModeBanner: some View {
        Label("演示数据 · 不是你的真实健康记录", systemImage: "theatermasks")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func heroColor(_ presentation: InsightsHRVPresentation) -> Color {
        switch presentation {
        case let .available(_, _, level, _, _):
            switch level {
            case .nearPersonalRange: .blue
            case .belowPersonalRange: .orange
            case .abovePersonalRange: .teal
            }
        case .learning, .unavailable:
            .secondary
        }
    }

    private func latestHRVText(_ presentation: InsightsHRVPresentation) -> String {
        guard let current = presentation.current else { return "最新 HRV · 暂无记录" }
        return "最新 HRV · \(Int(current.value.rounded())) ms · \(current.date.formatted(.relative(presentation: .named)))"
    }

    private func shareText(_ presentation: InsightsHRVPresentation) -> String {
        guard let current = presentation.current else {
            return "知衡：当前暂无可见的 HRV 记录。"
        }
        return "知衡 HRV 状态：\(presentation.title)，最新记录 \(Int(current.value.rounded())) ms。该结果只用于个人近期数据对照，不代表医学诊断。"
    }

    private func gaugeAccessibilityValue(_ presentation: InsightsHRVPresentation) -> String {
        guard let current = presentation.current else { return presentation.title }
        return "\(presentation.title)，最新 HRV \(Int(current.value.rounded())) 毫秒"
    }

    private func hrvChartAccessibilityValue(
        _ chart: InsightsHRVIntradayChartPresentation
    ) -> String {
        guard !chart.points.isEmpty else { return "今天没有可绘制的 HRV 记录" }
        let values = chart.points.map(\.value)
        return "今天 \(chart.points.count) 次记录，范围 \(Int((values.min() ?? 0).rounded())) 到 \(Int((values.max() ?? 0).rounded())) 毫秒"
    }

    private func restoreLayout() {
        guard
            let decoded = try? JSONDecoder().decode(
                InsightsDashboardLayout.self,
                from: storedLayout
            )
        else { return }
        layout = decoded
    }

    @MainActor
    private func loadHealthData() async {
        await healthSession.refresh()
    }
}

private enum InsightsPalette {
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.36)
    static let blue = Color(red: 0.30, green: 0.64, blue: 0.94)
    static let green = Color(red: 0.05, green: 0.74, blue: 0.35)
    static let chartBackground = Color(red: 0.94, green: 0.94, blue: 0.97)
    static let referenceBand = Color(red: 0.93, green: 0.58, blue: 0.58).opacity(0.12)
}

private struct InsightsCloudBackdrop: View {
    var body: some View {
        ZStack {
            InsightsCloudLowerArcFillShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.50),
                            Color.white.opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            InsightsCloudLowerArcEdgeShape()
                .stroke(
                    Color.white.opacity(0.84),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum InsightsCloudLowerArcGeometry {
    static func edgePath(in rect: CGRect) -> Path {
        var path = Path()
        let lobeCount = 7
        let lobeLiftFactors: [CGFloat] = [0.18, 0.13, 0.085, 0.06, 0.085, 0.13, 0.18]
        path.move(to: point(fraction: 0, in: rect))

        for index in 0..<lobeCount {
            let endFraction = CGFloat(index + 1) / CGFloat(lobeCount)
            let middleFraction = (CGFloat(index) + 0.5) / CGFloat(lobeCount)
            let lobeLift = rect.height * lobeLiftFactors[index]
            let control = CGPoint(
                x: rect.minX + rect.width * middleFraction,
                y: baseY(fraction: middleFraction, in: rect) - lobeLift
            )
            path.addQuadCurve(
                to: point(fraction: endFraction, in: rect),
                control: control
            )
        }
        return path
    }

    private static func point(fraction: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * fraction,
            y: baseY(fraction: fraction, in: rect)
        )
    }

    private static func baseY(fraction: CGFloat, in rect: CGRect) -> CGFloat {
        let sideY = rect.height * 0.24
        let bottomY = rect.height * 0.70
        let sine = sin(Double.pi * Double(fraction))
        let uShape = CGFloat(pow(max(0, sine), 0.86))
        return sideY + (bottomY - sideY) * uShape
    }
}

private struct InsightsCloudLowerArcFillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = InsightsCloudLowerArcGeometry.edgePath(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct InsightsCloudLowerArcEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        InsightsCloudLowerArcGeometry.edgePath(in: rect)
    }
}

private struct InsightsHRVGauge: View {
    let presentation: InsightsHRVPresentation

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.44)
            let radius = min(size * 0.41, 112)
            ZStack {
                InsightsGaugeArc()
                    .stroke(
                        AngularGradient(
                            colors: [.red, .purple, .blue, .cyan, .yellow],
                            center: .center,
                            startAngle: .degrees(135),
                            endAngle: .degrees(405)
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                ForEach(0..<31, id: \.self) { index in
                    let angle = 135 + Double(index) / 30 * 270
                    let outerRadius = radius - 15
                    let tickLength: CGFloat = index.isMultiple(of: 5) ? 11 : 7
                    Path { path in
                        path.move(to: gaugePoint(
                            center: center,
                            radius: outerRadius - tickLength,
                            angleDegrees: angle
                        ))
                        path.addLine(to: gaugePoint(
                            center: center,
                            radius: outerRadius,
                            angleDegrees: angle
                        ))
                    }
                    .stroke(
                        Color.secondary.opacity(index.isMultiple(of: 5) ? 0.30 : 0.19),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }

                HRVStatusFace(
                    state: presentation.visualState,
                    size: 124
                )
                    .position(x: center.x, y: center.y - 2)

                Text(presentation.current.map {
                    String(Int($0.value.rounded()))
                } ?? "--")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(InsightsPalette.ink)
                    .position(x: center.x, y: center.y + radius - 3)

                if let position = presentation.gaugePosition {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.blue.opacity(0.55), lineWidth: 4))
                        .shadow(color: .blue.opacity(0.25), radius: 5)
                        .position(gaugePoint(center: center, radius: radius, position: position))
                }
            }
        }
    }

    private func gaugePoint(
        center: CGPoint,
        radius: CGFloat,
        position: Double
    ) -> CGPoint {
        let radians = (135 + min(max(position, 0), 1) * 270) * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private func gaugePoint(
        center: CGPoint,
        radius: CGFloat,
        angleDegrees: Double
    ) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

private struct InsightsGaugeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(135),
            endAngle: .degrees(405),
            clockwise: false
        )
        return path
    }
}

private struct InsightsHRVReferenceChart: View {
    let presentation: InsightsHRVPresentation
    let intraday: InsightsHRVIntradayChartPresentation

    var body: some View {
        if intraday.points.isEmpty {
            ContentUnavailableView(
                "今天暂无 HRV 记录",
                systemImage: "waveform.path.ecg",
                description: Text("缺失数据不会补成 0。")
            )
            .frame(height: 176)
            .background(InsightsPalette.chartBackground)
        } else {
            Chart {
                if let range = presentation.baselineRange {
                    RectangleMark(
                        xStart: .value("当天开始", intraday.interval.start),
                        xEnd: .value("当天结束", intraday.interval.end),
                        yStart: .value("参考下界", range.lowerBound),
                        yEnd: .value("参考上界", range.upperBound)
                    )
                    .foregroundStyle(InsightsPalette.referenceBand)
                }
                ForEach(intraday.points) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [InsightsPalette.green, .cyan, .blue, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("时间", point.date),
                        y: .value("HRV", point.value)
                    )
                    .symbolSize(54)
                    .foregroundStyle(.white)
                    .annotation(position: .overlay) {
                        Circle()
                            .stroke(pointColor(point), lineWidth: 2.2)
                            .frame(width: 9, height: 9)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(hourLabel(date))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                if let range = presentation.baselineRange {
                    AxisMarks(position: .trailing, values: [range.lowerBound, range.upperBound]) { value in
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(Int(number.rounded())))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.12))
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(
                domain: intraday.interval.start...intraday.interval.end,
                range: .plotDimension(startPadding: 18, endPadding: 18)
            )
            .chartPlotStyle { plotArea in
                plotArea.background(InsightsPalette.chartBackground)
            }
            .frame(height: 176)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .background(InsightsPalette.chartBackground)
        }
    }

    private var xAxisDates: [Date] {
        [0, 6, 12, 18].compactMap {
            Calendar.current.date(
                byAdding: .hour,
                value: $0,
                to: intraday.interval.start
            )
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return String(format: "%02d时", hour)
    }

    private func pointColor(_ point: InsightsHRVChartPoint) -> Color {
        guard let range = presentation.baselineRange else { return InsightsPalette.blue }
        if point.value < range.lowerBound { return .orange }
        if point.value > range.upperBound { return InsightsPalette.green }
        return .cyan
    }

    private var yDomain: ClosedRange<Double> {
        let rangeValues = presentation.baselineRange.map { [$0.lowerBound, $0.upperBound] } ?? []
        let values = intraday.points.map(\.value) + rangeValues
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.18, maximum * 0.05, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}

private struct InsightsBodyMetricCard: View {
    let item: InsightsBodyMetricPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(item.kind.title)
                    .font(.headline)
                    .foregroundStyle(InsightsPalette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(valueText)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(InsightsPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Label(item.referenceState.title, systemImage: statusIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    Text(changeText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InsightsSparkline(points: item.points, color: color)
                    .frame(width: 145, height: 70)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch item.kind {
        case .restingHeartRate: "heart.text.clipboard.fill"
        case .sleepingHeartRate: "heart.fill"
        case .respiratoryRate: "lungs.fill"
        case .oxygenSaturation: "drop.fill"
        case .wristTemperature: "thermometer.medium"
        case .walkingRunningDistance: "figure.walk"
        case .flightsClimbed: "stairs"
        case .walkingSpeed: "speedometer"
        case .walkingStepLength: "ruler.fill"
        case .vo2Max: "lungs.fill"
        }
    }

    private var color: Color {
        switch item.kind {
        case .restingHeartRate, .sleepingHeartRate: .pink
        case .respiratoryRate: .blue
        case .oxygenSaturation: .purple
        case .wristTemperature: .indigo
        case .walkingRunningDistance: .teal
        case .flightsClimbed: .orange
        case .walkingSpeed: .blue
        case .walkingStepLength: .cyan
        case .vo2Max: .mint
        }
    }

    private var statusIcon: String {
        switch item.referenceState {
        case .nearPersonalRange: "checkmark.circle.fill"
        case .belowPersonalRange: "arrow.down.circle.fill"
        case .abovePersonalRange: "arrow.up.circle.fill"
        case .learning: "clock.fill"
        case .unavailable: "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.referenceState {
        case .nearPersonalRange: InsightsPalette.green
        case .belowPersonalRange, .abovePersonalRange: .orange
        case .learning, .unavailable: .secondary
        }
    }

    private var valueText: String {
        guard let value = item.currentValue else { return "暂无数据" }
        return switch item.unit {
        case .beatsPerMinute: "\(Int(value.rounded())) BPM"
        case .breathsPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(1)))) 次/分"
        case .percentage:
            "\(value.formatted(.number.precision(.fractionLength(1))))%"
        case .degreesCelsius:
            "\(value.formatted(.number.precision(.fractionLength(1))))℃"
        case .kilometers:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        case .floors:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 层"
        case .metersPerSecond:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 米/秒"
        case .meters:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 米"
        case .millilitersPerKilogramPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(1)))) ml/kg·min"
        case .count:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 步"
        case .hours:
            "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .milliseconds:
            "\(value.formatted(.number.precision(.fractionLength(0)))) ms"
        case .kilocalories:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 千卡"
        case .minutes:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 分钟"
        }
    }

    private var changeText: String {
        guard let change = item.changeFromPrevious else { return "等待前一有效日记录" }
        let symbol = change > 0 ? "↑" : change < 0 ? "↓" : "＝"
        let value = abs(change)
        let formatted: String
        switch item.unit {
        case .beatsPerMinute: formatted = "\(Int(value.rounded())) BPM"
        case .breathsPerMinute: formatted = value.formatted(.number.precision(.fractionLength(1)))
        case .percentage: formatted = "\(value.formatted(.number.precision(.fractionLength(1))))%"
        case .degreesCelsius: formatted = "\(value.formatted(.number.precision(.fractionLength(1))))℃"
        case .kilometers: formatted = "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        case .floors: formatted = "\(value.formatted(.number.precision(.fractionLength(0)))) 层"
        case .metersPerSecond: formatted = "\(value.formatted(.number.precision(.fractionLength(2)))) 米/秒"
        case .meters: formatted = "\(value.formatted(.number.precision(.fractionLength(2)))) 米"
        case .millilitersPerKilogramPerMinute:
            formatted = "\(value.formatted(.number.precision(.fractionLength(1)))) ml/kg·min"
        case .count: formatted = "\(value.formatted(.number.precision(.fractionLength(0)))) 步"
        case .hours: formatted = "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .milliseconds: formatted = "\(value.formatted(.number.precision(.fractionLength(0)))) ms"
        case .kilocalories: formatted = "\(value.formatted(.number.precision(.fractionLength(0)))) 千卡"
        case .minutes: formatted = "\(value.formatted(.number.precision(.fractionLength(0)))) 分钟"
        }
        return change == 0 ? "＝ 与前一有效日无变化" : "\(symbol) \(formatted) 较前一有效日"
    }
}

private struct InsightsSparkline: View {
    let points: [HealthMetricDailyPoint]
    let color: Color

    var body: some View {
        if points.isEmpty {
            Text("暂无趋势")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Chart(points) { point in
                AreaMark(
                    x: .value("日期", point.date, unit: .day),
                    yStart: .value("起点", yDomain.lowerBound),
                    yEnd: .value("数值", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.linear)
                PointMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("数值", point.value)
                )
                .symbolSize(point.id == points.last?.id ? 44 : 26)
                .foregroundStyle(point.id == points.last?.id ? color : .white)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 8))
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
        }
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = points.map(\.value).min(),
              let maximum = points.map(\.value).max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.35, maximum * 0.04, 0.1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}

private struct HRVReferenceExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("仪表代表什么") {
                    Text("中间数字是最新 HRV 记录，不是健康总分。圆点表示它在个人近期参考范围中的相对位置。")
                    Text("参考范围来自此前 28 天，并且至少需要 14 个有效日。")
                }
                Section("如何理解") {
                    Text("HRV 会受到睡眠、训练负荷、饮酒、感染、情绪和测量时间等多种因素影响。知衡只做个人数据对照，不把单项 HRV 直接解释为压力、疾病或恢复能力。")
                }
            }
            .navigationTitle("HRV 状态说明")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

private struct InsightsMetricEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var layout: InsightsDashboardLayout

    var body: some View {
        NavigationStack {
            List {
                Section("显示指标") {
                    ForEach(InsightsBodyMetricKind.allCases) { metric in
                        Toggle(metric.title, isOn: Binding(
                            get: { layout.visibleMetrics.contains(metric) },
                            set: { layout.setVisible($0, metric: metric) }
                        ))
                    }
                }
                Section("当前顺序") {
                    ForEach(layout.visibleMetrics) { metric in
                        Label(metric.title, systemImage: "line.3.horizontal")
                    }
                    .onMove { source, destination in
                        var metrics = layout.visibleMetrics
                        metrics.move(fromOffsets: source, toOffset: destination)
                        layout = InsightsDashboardLayout(visibleMetrics: metrics)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("编辑身体指标")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

private struct InsightsTrendDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: HealthDataSnapshot
    @State private var selectedMetric = HealthMetricType.heartRateVariability
    @State private var selectedWindow = HealthTrendWindow.sevenDays

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("数据趋势")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Picker("指标", selection: $selectedMetric) {
                            ForEach(HealthMetricType.allCases, id: \.self) { metric in
                                Text(metricTitle(metric)).tag(metric)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Picker("时间范围", selection: $selectedWindow) {
                        ForEach(HealthTrendWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    detailChart
                    Text("图表只展示 HealthKit 中可安全汇总的每日记录。空缺不会补成 0，连线也不代表其间每天都有数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("趋势详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    @ViewBuilder
    private var detailChart: some View {
        if points.isEmpty {
            ContentUnavailableView(
                "暂无可绘制数据",
                systemImage: "chart.xyaxis.line",
                description: Text("当前时间范围没有可安全汇总的记录。")
            )
            .frame(height: 280)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                PointMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(.teal)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYScale(domain: HealthTrendChartPresentation(
                points: points,
                expectedDayCount: selectedWindow.rawValue
            ).yDomain)
            .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
            .frame(height: 280)
            .padding()
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
    }

    private var points: [HealthMetricDailyPoint] {
        guard case let .available(samples) = snapshot[selectedMetric] else { return [] }
        return HealthMetricDailySeriesCalculator.points(
            metric: selectedMetric,
            samples: samples,
            endingAt: Date(),
            window: selectedWindow
        )
    }

    private func metricTitle(_ metric: HealthMetricType) -> String {
        HealthMetricStatusPresentation(metric: metric, state: .noVisibleData).title
    }
}

#Preview {
    InsightsView(healthSession: HealthDataSession(
        service: try! DemoHealthScenarioFactory.dashboard(endingAt: Date())
    ))
}
