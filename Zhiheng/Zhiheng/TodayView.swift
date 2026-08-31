import Charts
import SwiftUI

struct TodayView: View {
    @ObservedObject private var healthSession: HealthDataSession
    private let debugScrollSection: TodayDashboardSection?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("todayDashboardGoals") private var storedGoals = Data()
    @AppStorage("todayDashboardLayout") private var storedLayout = Data()
    @State private var goals = TodayDashboardGoals.standard
    @State private var layout = TodayDashboardLayout.standard
    @State private var selectedDate: Date
    @State private var dateWindowEnd: Date
    @State private var dateWindowShiftDirection = 0
    @State private var showsGoalSettings = false
    @State private var editedSection: TodayDashboardSection?
    @State private var showsProgressInfo = false

    init(healthSession: HealthDataSession) {
        self.healthSession = healthSession
        debugScrollSection = Self.debugSectionFromArguments
        let today = Calendar.current.startOfDay(for: Date())
        _selectedDate = State(initialValue: today)
        _dateWindowEnd = State(initialValue: today)
    }

    private static var debugSectionFromArguments: TodayDashboardSection? {
#if DEBUG
        let prefix = "--today-section="
        guard let value = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix(prefix)
        })?.dropFirst(prefix.count) else { return nil }
        return TodayDashboardSection(rawValue: String(value))
#else
        return nil
#endif
    }

    private var readiness: AppReadiness {
        AppReadiness(healthAccess: healthSession.accessState)
    }

    private var healthSnapshot: HealthDataSnapshot? { healthSession.snapshot }
    private var isLoadingHealthData: Bool { healthSession.isLoading }
    private var dataMode: HealthDataMode { healthSession.dataMode }

    private var dashboard: TodayDashboardPresentation? {
        healthSnapshot.map {
            TodayDashboardPresentationFactory.make(
                snapshot: $0,
                selectedDate: selectedDate,
                today: Date(),
                dateWindowEnd: dateWindowEnd,
                goals: goals
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if dataMode == .demo { demoModeBanner }
                        dateStrip
                        if let dashboard {
                            progressHero(dashboard)
                            dashboardSection(.body) { bodyGrid(dashboard) }
                            dashboardSection(.daily) { dailyGrid(dashboard) }
                            dashboardSection(.nightlyVitals) { nightlyVitals(dashboard) }
                        } else if isLoadingHealthData {
                            ProgressView("正在整理健康数据…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 80)
                        }
                        privacyNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .refreshable { await loadHealthData() }
                .task {
                    restorePreferences()
                    if let debugScrollSection {
                        try? await Task.sleep(for: .milliseconds(250))
                        proxy.scrollTo(debugScrollSection, anchor: .top)
                    }
                }
                .onChange(of: goals) { _, newValue in storedGoals = encode(newValue) }
                .onChange(of: layout) { _, newValue in storedLayout = encode(newValue) }
            }
        }
        .sheet(isPresented: $showsGoalSettings) {
            TodayGoalSettingsView(goals: $goals)
        }
        .sheet(item: $editedSection) { section in
            TodayModuleEditorView(section: section, layout: $layout)
        }
        .sheet(isPresented: $showsProgressInfo) {
            TodayProgressExplanationView(dashboard: dashboard)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Calendar.current.isDateInToday(selectedDate) ? "今天" : selectedDate.formatted(.dateTime.month().day()))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(todayInk)
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingHealthData {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await loadHealthData() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("更新健康数据")
            }
            Button { showsGoalSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置健康目标")
        }
    }

    private var dateStrip: some View {
        let statuses = dashboard?.dateStatuses ?? TodayDashboardDateWindow.sevenDays(endingAt: Date()).map {
            TodayDashboardDateStatus(
                date: $0,
                goalPercentage: nil,
                activityRings: .unavailable
            )
        }
        return ZStack {
            HStack(spacing: 4) {
                ForEach(statuses) { status in
                    Button {
                        withAnimation(.snappy) { selectedDate = status.date }
                    } label: {
                        VStack(spacing: 9) {
                            Text(String(Calendar.current.component(.day, from: status.date)))
                                .font(.headline)
                                .foregroundStyle(Calendar.current.isDate(status.date, inSameDayAs: selectedDate) ? .white : .primary)
                                .frame(width: 38, height: 30)
                                .background(
                                    Calendar.current.isDate(status.date, inSameDayAs: selectedDate)
                                        ? Color.blue.opacity(0.72) : Color.clear,
                                    in: Capsule()
                                )
                            DateProgressGlyph(
                                rings: status.activityRings,
                                overallPercentage: status.goalPercentage
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status.date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(status.goalPercentage.map { "目标完成度 \($0)%" } ?? "暂无目标数据")
                }
            }
            .id(Calendar.current.startOfDay(for: dateWindowEnd))
            .transition(
                .asymmetric(
                    insertion: .move(edge: dateWindowShiftDirection > 0 ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .move(edge: dateWindowShiftDirection > 0 ? .leading : .trailing)
                        .combined(with: .opacity)
                )
            )
        }
        .dynamicTypeSize(.small ... .xLarge)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 42 else { return }
                    shiftDateWindow(by: value.translation.width < 0 ? 7 : -7)
                }
        )
        .accessibilityHint("左右轻扫切换一组 7 天")
    }

    private func progressHero(_ dashboard: TodayDashboardPresentation) -> some View {
        let percentage: Int?
        let ratio: Double
        let usedCount: Int
        if case let .available(progress) = dashboard.goalProgress {
            percentage = progress.percentage
            ratio = progress.overallRatio
            usedCount = progress.items.count
        } else {
            percentage = nil
            ratio = 0
            usedCount = 0
        }
        return VStack(spacing: 18) {
            HStack {
                Button { showsProgressInfo = true } label: {
                    Image(systemName: "info.circle").font(.title2)
                }
                Spacer()
                GoalArcGauge(ratio: ratio, percentage: percentage, usedCount: usedCount)
                    .frame(width: 230, height: 230)
                    .dynamicTypeSize(.small ... .xLarge)
                Spacer()
                ShareLink(item: shareText(dashboard)) {
                    Image(systemName: "square.and.arrow.up").font(.title2)
                }
                .accessibilityLabel("分享目标完成情况")
            }
            VStack(spacing: 6) {
                Text(dashboard.encouragement.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(dashboard.encouragement.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(todayInk)
    }

    private func dashboardSection<Content: View>(
        _ section: TodayDashboardSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(sectionTitle(section))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(todayInk)
                if section == .nightlyVitals {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("编辑") { editedSection = section }
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .id(section)
    }

    @ViewBuilder
    private func bodyGrid(_ dashboard: TodayDashboardPresentation) -> some View {
        let modules = layout.modules(in: .body)
        if modules.isEmpty {
            emptySection("身体模块已隐藏，可点击编辑恢复。")
        } else {
            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                ForEach(modules) { module in
                    switch module {
                    case .loadReference: loadCard(dashboard.loadReference)
                    case .trainingReadiness: trainingReadinessCard(dashboard.trainingReadiness)
                    default: EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dailyGrid(_ dashboard: TodayDashboardPresentation) -> some View {
        let modules = layout.modules(in: .daily)
        if modules.isEmpty {
            emptySection("日常模块已隐藏，可点击编辑恢复。")
        } else {
            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                ForEach(modules) { module in
                    Group {
                        switch module {
                        case .walking:
                            metricNavigationCard(metric: .stepCount) {
                                DailyMetricCard(
                                    title: module.title,
                                    icon: "shoeprints.fill",
                                    color: .green,
                                    value: dashboard.values[.stepCount],
                                    goal: goals.steps,
                                    goalUnit: .count,
                                    bars: dashboard.stepHourlyBars
                                )
                            }
                        case .sleep:
                            metricNavigationCard(metric: .sleepDuration) {
                                SleepDailyCard(
                                    value: dashboard.values[.sleepDuration],
                                    goalHours: goals.sleepHours,
                                    segments: dashboard.sleepSegments,
                                    sleepingHeartRate: dashboard.nightVitals.first {
                                        $0.metric == .heartRate
                                    }?.value
                                )
                            }
                        case .activity:
                            ActivityRingsCard(dashboard: dashboard, goals: goals)
                        case .energy:
                            metricNavigationCard(metric: .activeEnergy) {
                                DailyMetricCard(
                                    title: module.title,
                                    icon: "flame.fill",
                                    color: .red,
                                    value: dashboard.values[.activeEnergy],
                                    goal: goals.activeEnergyKilocalories,
                                    goalUnit: .kilocalories,
                                    bars: dashboard.energyHourlyBars
                                )
                            }
                        default: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func nightlyVitals(_ dashboard: TodayDashboardPresentation) -> some View {
        let modules = layout.modules(in: .nightlyVitals)
        if modules.isEmpty {
            emptySection("昨晚生命体征模块已隐藏，可点击编辑恢复。")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(modules) { module in
                        let metric = metric(for: module)
                        metricNavigationCard(metric: metric) {
                            NightVitalCard(
                                title: module.title,
                                metric: metric,
                                vital: dashboard.nightVitals.first { $0.metric == metric }
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -18)
            Label(dashboard.nightSummary.title, systemImage: "heart.circle.fill")
                .font(.headline)
                .foregroundStyle(.mint)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.08), in: Capsule())
                .accessibilityHint(dashboard.nightSummary.detail)
        }
    }

    private var adaptiveColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func metricNavigationCard<Content: View>(
        metric: HealthMetricType,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationLink {
            HealthMetricDetailView(
                metric: metric,
                state: healthSnapshot?[metric] ?? .noVisibleData,
                referenceDate: selectedDate
            )
        } label: { content() }
            .buttonStyle(.plain)
            .accessibilityHint("打开详情")
    }

    private func loadCard(_ reference: TodayLoadReference) -> some View {
        let title: String
        let detail: String
        let hrv: TodayDashboardMetricValue?
        switch reference {
        case let .insufficient(current):
            title = current == nil ? "暂无 HRV" : "等待个人基线"
            detail = "暂不判断"
            hrv = current
        case let .available(current, _, difference, level):
            hrv = current
            switch level {
            case .belowPersonalRange: title = "状态偏低"
            case .nearPersonalRange: title = "状态正常"
            case .abovePersonalRange: title = "状态较好"
            }
            detail = "根据 HRV 与个人近期参考对照；相对近期 \(Int((difference * 100).rounded()))%"
        }
        let position: Double?
        if case let .available(_, _, difference, _) = reference {
            position = min(max(0.5 + difference / 0.6, 0), 1)
        } else {
            position = nil
        }
        return VStack(alignment: .leading, spacing: 9) {
            HRVStatusFace(state: reference.visualState, size: 46)
                .frame(width: 46, height: 46, alignment: .topLeading)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(reference.visualState.accentColor)
            Text(hrv.map {
                "♥︎ \(format($0.value, unit: $0.unit)) · \($0.date.formatted(.dateTime.hour().minute()))"
            } ?? "暂无数据")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            LoadRangeBar(gradient: loadGradient, position: position)
        }
        .dashboardSquareCard()
        .accessibilityHint(detail)
    }

    private func trainingReadinessCard(_ readiness: TodayTrainingReadiness) -> some View {
        let score: Int?
        let title: String
        let detail: String
        switch readiness {
        case let .insufficient(count, required):
            score = nil
            title = "等待更多恢复数据"
            detail = "已有 \(count)/\(required) 个必要组件。"
        case let .available(value, components, advice):
            score = value
            title = value >= 80 ? "适合按计划活动" : value >= 60 ? "适合轻中强度" : "优先轻松活动"
            detail = "使用 \(components.count)/7 个组件。\(advice)"
        }
        return VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.blue)
                .frame(width: 46, height: 46, alignment: .topLeading)
            Text(title).font(.title3.weight(.bold))
            Text(score.map { "\($0)% · 训练准备参考" } ?? "暂不计算百分比")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            UniformProgressBar(value: Double(score ?? 0) / 100, color: .blue)
        }
        .dashboardSquareCard()
        .accessibilityHint(detail)
    }

    private var loadGradient: LinearGradient {
        LinearGradient(
            colors: [.red.opacity(0.75), .purple.opacity(0.55), .blue.opacity(0.55), .yellow.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func emptySection(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var demoModeBanner: some View {
        Label("演示数据 · 不是你的真实健康记录", systemImage: "theatermasks")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var privacyNote: some View {
        Label(
            dataMode == .demo
                ? "当前内容为本地演示数据，不会读取 Apple Health。"
                : "只读取你选择分享的数据；目标和模块布局仅保存在本机。",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func sectionTitle(_ section: TodayDashboardSection) -> String {
        switch section {
        case .body: "身体"
        case .daily: "日常"
        case .nightlyVitals: "昨晚生命体征"
        }
    }

    private func metric(for module: TodayDashboardModule) -> HealthMetricType {
        switch module {
        case .sleepDuration: .sleepDuration
        case .sleepingHeartRate: .heartRate
        case .wristTemperature: .wristTemperature
        case .respiratoryRate: .respiratoryRate
        case .oxygenSaturation: .oxygenSaturation
        case .walking: .stepCount
        case .sleep: .sleepDuration
        case .energy: .activeEnergy
        case .activity: .exerciseDuration
        case .loadReference: .heartRateVariability
        case .trainingReadiness: .restingHeartRate
        }
    }

    private func shareText(_ dashboard: TodayDashboardPresentation) -> String {
        let percentage: String
        if case let .available(progress) = dashboard.goalProgress {
            percentage = "\(progress.percentage)%"
        } else {
            percentage = "数据不足"
        }
        return "知衡 · \(selectedDate.formatted(date: .abbreviated, time: .omitted))目标完成度：\(percentage)。数据仅供个人健康管理参考。"
    }

    private func format(_ value: Double, unit: HealthMetricUnit) -> String {
        HealthValueFormatter.text(value: value, unit: unit)
    }

    private var todayInk: Color {
        Color(red: 0.08, green: 0.17, blue: 0.36)
    }

    private func shiftDateWindow(by days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let earliestEnd = calendar.date(byAdding: .day, value: -83, to: today),
              let proposed = calendar.date(byAdding: .day, value: days, to: dateWindowEnd)
        else { return }
        let newEnd = min(max(proposed, earliestEnd), today)
        guard !calendar.isDate(newEnd, inSameDayAs: dateWindowEnd) else { return }
        dateWindowShiftDirection = days > 0 ? 1 : -1
        withAnimation(.smooth(duration: 0.34)) {
            dateWindowEnd = newEnd
            selectedDate = newEnd
        }
    }

    private func restorePreferences() {
        if let decoded: TodayDashboardGoals = decode(storedGoals) { goals = decoded }
        if let decoded: TodayDashboardLayout = decode(storedLayout) { layout = decoded }
    }

    private func decode<T: Decodable>(_ data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    @MainActor
    private func loadHealthData() async {
        await healthSession.refresh()
    }
}

private struct DateProgressGlyph: View {
    let rings: TodayActivityRingProgress
    let overallPercentage: Int?

    var body: some View {
        SystemActivityRingView(progress: rings)
            .background(.black)
            .clipShape(Circle())
        .frame(width: 38, height: 38)
        .opacity(overallPercentage == nil ? 0.35 : 1)
    }
}

private struct MetricProgressRing: View {
    let icon: String
    let color: Color
    let value: Double?
    let goal: Double

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 7)
            if let value, goal > 0 {
                Circle()
                    .trim(from: 0, to: min(max(value / goal, 0), 1))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

private struct LoadRangeBar: View {
    let gradient: LinearGradient
    let position: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(gradient).frame(height: 11)
                if let position {
                    Circle()
                        .fill(.white)
                        .stroke(.blue.opacity(0.75), lineWidth: 3)
                        .frame(width: 17, height: 17)
                        .offset(x: max(0, geometry.size.width - 17) * position)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
        .accessibilityLabel("HRV 相对个人近期参考位置")
    }
}

private struct UniformProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 11)
                Capsule()
                    .fill(color.gradient)
                    .frame(
                        width: geometry.size.width * min(max(value, 0), 1),
                        height: 11
                    )
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
    }
}

private struct GoalArcGauge: View {
    let ratio: Double
    let percentage: Int?
    let usedCount: Int

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                .shadow(color: .white, radius: 8)
            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * min(max(ratio, 0), 1))
                .stroke(
                    AngularGradient(colors: [.orange, .yellow, .pink], center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .shadow(color: .orange.opacity(0.35), radius: 8)
            Color.secondary.opacity(0.16)
                .mask {
                    gaugeTickMask(completedOnly: false)
                }
            AngularGradient(colors: [.orange, .yellow, .pink], center: .center)
                .mask {
                    gaugeTickMask(completedOnly: true)
                }
            VStack(spacing: 6) {
                Text(percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                Text("目标完成度").font(.headline).foregroundStyle(.secondary)
                Text("Perfect Day").font(.caption).foregroundStyle(.tertiary)
            }
            .rotationEffect(.degrees(-90))
        }
        .rotationEffect(.degrees(90))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("目标完成度")
        .accessibilityValue(percentage.map { "\($0)%，使用 \(usedCount) 项数据" } ?? "数据不足")
    }

    @ViewBuilder
    private func gaugeTickMask(completedOnly: Bool) -> some View {
        ZStack {
            ForEach(0..<25, id: \.self) { index in
                let tickProgress = Double(index + 1) / 25
                if !completedOnly || tickProgress <= min(max(ratio, 0), 1) {
                    Capsule()
                        .frame(
                            width: index.isMultiple(of: 4) ? 3 : 2,
                            height: index.isMultiple(of: 4) ? 10 : 6
                        )
                        .offset(y: -92)
                        .rotationEffect(.degrees(43.2 + Double(index) * 11.4))
                }
            }
        }
        .rotationEffect(.degrees(90))
    }
}

private struct DailyMetricCard: View {
    let title: String
    let icon: String
    let color: Color
    let value: TodayDashboardMetricValue?
    let goal: Double
    let goalUnit: HealthMetricUnit
    let bars: [TodayHourlyBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MetricProgressRing(icon: icon, color: color, value: value?.value, goal: goal)
            Text(value.map { HealthValueFormatter.text(value: $0.value, unit: $0.unit) } ?? "暂无数据")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("\(title) · 目标 \(HealthValueFormatter.text(value: goal, unit: goalUnit))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HourlyBarChart(bars: bars, color: color).frame(height: 54)
        }
        .dashboardSquareCard()
    }
}

private struct HourlyBarChart: View {
    let bars: [TodayHourlyBar]
    let color: Color

    var body: some View {
        if bars.isEmpty {
            Text("暂无 24 小时分时记录")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let maximum = bars.map(\.value).max() ?? 0
            let upperBound = max(maximum * 1.12, 1)
            Chart(bars) { bar in
                if bar.value > 0 {
                    BarMark(
                        x: .value("小时", bar.hour),
                        yStart: .value("起点", 0),
                        yEnd: .value("数值", bar.value),
                        width: .fixed(3)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(2)
                } else {
                    BarMark(
                        x: .value("小时", bar.hour),
                        yStart: .value("起点", 0),
                        yEnd: .value("空值标记", upperBound * 0.025),
                        width: .fixed(3)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .cornerRadius(2)
                }
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...upperBound)
            .chartXAxis {
                AxisMarks(values: [0, 12, 23]) { value in
                    AxisValueLabel {
                        let hour = value.as(Int.self) ?? 0
                        Text(hour == 23 ? "24:00" : "\(hour):00")
                    }
                    AxisTick().foregroundStyle(.clear)
                    AxisGridLine().foregroundStyle(.clear)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.padding(.horizontal, 2)
            }
            .accessibilityLabel("24 小时柱状图")
        }
    }
}

private struct SleepDailyCard: View {
    let value: TodayDashboardMetricValue?
    let goalHours: Double
    let segments: [TodaySleepSegment]
    let sleepingHeartRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                MetricProgressRing(
                    icon: "bed.double.fill",
                    color: .purple,
                    value: value?.value,
                    goal: goalHours
                )
                Spacer()
                if let sleepingHeartRate {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(sleepingHeartRate.rounded())) BPM")
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                            Text("平均")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.map { HealthValueFormatter.text(value: $0.value, unit: $0.unit) } ?? "暂无数据")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let value, goalHours > 0 {
                    Text("· \(Int(min(value.value / goalHours, 1) * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if segments.isEmpty {
                Text("暂无睡眠阶段记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                SleepStageChart(segments: segments).frame(height: 76)
            }
        }
        .dashboardSquareCard()
    }
}

private struct ActivityRingsCard: View {
    let dashboard: TodayDashboardPresentation
    let goals: TodayDashboardGoals

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                Circle().fill(.black)
                SystemActivityRingView(
                    progress: TodayActivityRingProgress(
                        activeEnergy: ratio(dashboard.values[.activeEnergy]?.value, goals.activeEnergyKilocalories),
                        exercise: ratio(dashboard.values[.exerciseDuration]?.value, goals.exerciseMinutes),
                        stand: ratio(dashboard.values[.standHours]?.value, goals.standHours)
                    )
                )
                .frame(width: 40, height: 40)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .accessibilityHidden(true)
            Spacer().frame(height: 1)
            activityLine(value: dashboard.values[.activeEnergy]?.value, goal: goals.activeEnergyKilocalories, unit: .kilocalories, color: .red)
            activityLine(value: dashboard.values[.exerciseDuration]?.value, goal: goals.exerciseMinutes, unit: .minutes, color: .green)
            activityLine(value: dashboard.values[.standHours]?.value, goal: goals.standHours, unit: .hours, color: .cyan)
            Text("合上活动圆环")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .dashboardSquareCard()
    }

    private func activityLine(value: Double?, goal: Double, unit: HealthMetricUnit, color: Color) -> some View {
        (
            Text("\(value.map { compactNumber($0) } ?? "---")/\(compactNumber(goal))")
                .foregroundColor(color)
            + Text(" \(unitLabel(unit))")
                .foregroundColor(.secondary)
        )
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func ratio(_ value: Double?, _ goal: Double) -> Double? {
        guard let value, goal > 0 else { return nil }
        return min(max(value / goal, 0), 1)
    }

    private func compactNumber(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func unitLabel(_ unit: HealthMetricUnit) -> String {
        switch unit {
        case .kilocalories: "千卡"
        case .minutes: "分钟"
        case .hours: "小时"
        default: ""
        }
    }
}

private struct SleepStageChart: View {
    let segments: [TodaySleepSegment]

    var body: some View {
        let detailed = segments.filter { $0.stage != .asleepUnspecified }
        GeometryReader { geometry in
            if let start = detailed.map(\.startDate).min(),
               let end = detailed.map(\.endDate).max(), end > start {
                let interval = DateInterval(start: start, end: end)
                let plotSize = CGSize(
                    width: max(geometry.size.width, 1),
                    height: max(geometry.size.height - 14, 1)
                )
                ZStack(alignment: .topLeading) {
                    ForEach(Array(detailed.indices.dropLast()), id: \.self) { index in
                        let current = detailed[index]
                        let next = detailed[index + 1]
                        if abs(next.startDate.timeIntervalSince(current.endDate)) <= 5 * 60 {
                            let fromY = yPosition(for: current.stage, height: plotSize.height)
                            let toY = yPosition(for: next.stage, height: plotSize.height)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            color(for: current.stage).opacity(0.16),
                                            color(for: next.stage).opacity(0.16)
                                        ],
                                        startPoint: fromY <= toY ? .top : .bottom,
                                        endPoint: fromY <= toY ? .bottom : .top
                                    )
                                )
                                .frame(width: 3, height: abs(toY - fromY) + 10)
                                .offset(
                                    x: xPosition(current.endDate, interval: interval, width: plotSize.width) - 1.5,
                                    y: min(fromY, toY) - 5
                                )
                        }
                    }

                    ForEach(detailed) { segment in
                        let startX = xPosition(segment.startDate, interval: interval, width: plotSize.width)
                        let endX = xPosition(segment.endDate, interval: interval, width: plotSize.width)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(for: segment.stage).gradient)
                            .frame(width: max(endX - startX, 3), height: 10)
                            .offset(
                                x: startX,
                                y: yPosition(for: segment.stage, height: plotSize.height) - 5
                            )
                    }

                    HStack {
                        Text(start.formatted(.dateTime.hour().minute()))
                        Spacer()
                        Text(end.formatted(.dateTime.hour().minute()))
                    }
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(y: geometry.size.height - 10)
                }
            } else {
                Text("暂无详细睡眠阶段")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("睡眠阶段时间轴，包含深睡、核心、快速眼动和清醒")
    }

    private func xPosition(_ date: Date, interval: DateInterval, width: CGFloat) -> CGFloat {
        width * CGFloat(date.timeIntervalSince(interval.start) / interval.duration)
    }

    private func yPosition(for stage: HealthSleepStage, height: CGFloat) -> CGFloat {
        let index = HealthSleepStage.displayedStages.firstIndex(of: stage) ?? 2
        return 5 + CGFloat(index) * max(height - 10, 0) / 3
    }

    private func color(for stage: HealthSleepStage) -> Color {
        switch stage {
        case .deep: Color(red: 0.18, green: 0.28, blue: 0.78)
        case .core: Color(red: 0.18, green: 0.48, blue: 0.96)
        case .rem: Color(red: 0.20, green: 0.72, blue: 0.78)
        case .awake: Color(red: 0.92, green: 0.40, blue: 0.24)
        case .asleepUnspecified: .blue
        }
    }
}

private struct NightVitalCard: View {
    let title: String
    let metric: HealthMetricType
    let vital: TodayNightVital?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24, alignment: .topLeading)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(height: 20, alignment: .topLeading)
                .padding(.top, 4)
            valueRow
                .padding(.top, 6)
            Label(
                vital?.value == nil ? "暂无记录" : "正常",
                systemImage: vital?.value == nil ? "minus.circle" : "checkmark.circle.fill"
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(vital?.value == nil ? Color.secondary : Color.green)
                .padding(.top, 2)
                .accessibilityHint(
                    vital?.value == nil
                        ? "昨晚没有可读取的数据"
                        : "只表示数据已成功读取，不代表医学正常或异常"
                )
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 136, height: 136, alignment: .topLeading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    @ViewBuilder
    private var valueRow: some View {
        if let value = vital?.value {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formattedNumber(value))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .layoutPriority(1)
                Text(unitLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else {
            Text("暂无数据")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        switch vital?.unit ?? metric.expectedUnit {
        case .hours, .breathsPerMinute, .percentage, .degreesCelsius:
            value.formatted(.number.precision(.fractionLength(1)))
        default:
            value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    private var unitLabel: String {
        switch vital?.unit ?? metric.expectedUnit {
        case .hours: "小时"
        case .beatsPerMinute, .breathsPerMinute: "次/分"
        case .percentage: "%"
        case .degreesCelsius: "℃"
        default: ""
        }
    }

    private var icon: String {
        switch metric {
        case .sleepDuration: "bed.double.fill"
        case .heartRate: "heart.fill"
        case .wristTemperature: "thermometer.medium"
        case .respiratoryRate: "lungs.fill"
        case .oxygenSaturation: "drop.fill"
        default: "waveform.path.ecg"
        }
    }

    private var color: Color {
        switch metric {
        case .sleepDuration: .cyan
        case .heartRate: .pink
        case .wristTemperature: .blue
        case .respiratoryRate: .indigo
        case .oxygenSaturation: .teal
        default: .blue
        }
    }
}

private struct TodayGoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goals: TodayDashboardGoals

    var body: some View {
        NavigationStack {
            Form {
                goalRow("步数", value: $goals.steps, range: 1_000...30_000, step: 500, unit: "步")
                goalRow("睡眠", value: $goals.sleepHours, range: 4...12, step: 0.5, unit: "小时")
                goalRow("活动能量", value: $goals.activeEnergyKilocalories, range: 100...2_000, step: 50, unit: "千卡")
                goalRow("运动分钟", value: $goals.exerciseMinutes, range: 5...180, step: 5, unit: "分钟")
                goalRow("站立小时", value: $goals.standHours, range: 4...16, step: 1, unit: "小时")
                Section {
                    Button("恢复默认目标") { goals = .standard }
                } footer: {
                    Text("目标只用于计算行动完成度，不是医学建议或综合健康评分。")
                }
            }
            .navigationTitle("目标设置")
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func goalRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        Section(title) {
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0)))) \(unit)")
            }
        }
    }
}

private struct TodayModuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let section: TodayDashboardSection
    @Binding var layout: TodayDashboardLayout

    private var allModules: [TodayDashboardModule] {
        TodayDashboardModule.allCases.filter { $0.section == section }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allModules) { module in
                    Toggle(module.title, isOn: Binding(
                        get: { layout.modules(in: section).contains(module) },
                        set: { layout.setVisible($0, module: module) }
                    ))
                }
                Section("当前顺序") {
                    ForEach(layout.modules(in: section)) { module in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(module.title)
                        }
                    }
                    .onMove { source, destination in
                        var modules = layout.modules(in: section)
                        modules.move(fromOffsets: source, toOffset: destination)
                        layout = TodayDashboardLayout(modulesBySection: Dictionary(
                            uniqueKeysWithValues: TodayDashboardSection.allCases.map {
                                ($0, $0 == section ? modules : layout.modules(in: $0))
                            }
                        ))
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("编辑模块")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

private struct TodayProgressExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    let dashboard: TodayDashboardPresentation?

    var body: some View {
        NavigationStack {
            List {
                Section("计算方式") {
                    Text("步数、睡眠、活动能量、运动分钟和站立小时分别与个人目标比较，再对有可见数据的项目等权平均。每项最多按 100% 计入。")
                    Text("缺失数据不按 0 处理；这个百分比只表示行动目标完成度，不代表整体健康优劣。")
                }
                if let dashboard, case let .available(progress) = dashboard.goalProgress {
                    Section("所选日期") {
                        ForEach(progress.items) { item in
                            HStack {
                                Text(item.kind.title)
                                Spacer()
                                Text("\(Int((item.ratio * 100).rounded()))%")
                            }
                        }
                    }
                }
            }
            .navigationTitle("目标完成度")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

private enum HealthValueFormatter {
    static func text(value: Double, unit: HealthMetricUnit) -> String {
        switch unit {
        case .count: "\(value.formatted(.number.precision(.fractionLength(0)))) 步"
        case .hours: "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .beatsPerMinute: "\(value.formatted(.number.precision(.fractionLength(0)))) 次/分"
        case .milliseconds: "\(value.formatted(.number.precision(.fractionLength(0)))) ms"
        case .kilocalories: "\(value.formatted(.number.precision(.fractionLength(0)))) 千卡"
        case .minutes: "\(value.formatted(.number.precision(.fractionLength(0)))) 分钟"
        case .breathsPerMinute: "\(value.formatted(.number.precision(.fractionLength(1)))) 次/分"
        case .percentage: "\(value.formatted(.number.precision(.fractionLength(1))))%"
        case .degreesCelsius: "\(value.formatted(.number.precision(.fractionLength(1))))℃"
        case .kilometers: "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        case .floors: "\(value.formatted(.number.precision(.fractionLength(0)))) 层"
        case .metersPerSecond: "\(value.formatted(.number.precision(.fractionLength(2)))) 米/秒"
        case .meters: "\(value.formatted(.number.precision(.fractionLength(2)))) 米"
        case .millilitersPerKilogramPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(1)))) ml/kg·min"
        }
    }
}

private extension View {
    func dashboardSquareCard() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .aspectRatio(1, contentMode: .fit)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 26)
            )
            .shadow(color: .black.opacity(0.045), radius: 16, y: 8)
    }

    func dashboardCard(minHeight: CGFloat?) -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.045), radius: 16, y: 8)
    }
}

#Preview {
    TodayView(healthSession: HealthDataSession(
        service: try! DemoHealthScenarioFactory.dashboard(endingAt: Date())
    ))
}
