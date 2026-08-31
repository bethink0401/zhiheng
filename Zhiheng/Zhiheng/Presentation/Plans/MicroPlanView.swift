import Charts
import SwiftUI

struct MicroPlanHistoryEntry: Identifiable {
    let plan: MicroPlan
    let progress: MicroPlanProgress

    var id: CarePlanID { plan.draft.id }
}

@MainActor
final class MicroPlanSession: ObservableObject {
    @Published private(set) var activePlan: MicroPlan?
    @Published private(set) var mostRecentPlan: MicroPlan?
    @Published private(set) var progress: MicroPlanProgress?
    @Published private(set) var todayOutcomeState: PlanOutcomeState?
    @Published private(set) var history = [MicroPlanHistoryEntry]()
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var showsError = false

    private let service: any CarePlanService

    var displayedPlan: MicroPlan? { activePlan ?? mostRecentPlan }

    init(service: any CarePlanService) {
        self.service = service
    }

    func refresh(referenceDate: Date = Date()) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await loadState(referenceDate: referenceDate)
        } catch {
            present(error)
        }
    }

    func start(
        from action: HealthAISuggestedAction,
        referenceDate: Date = Date()
    ) async -> Bool {
        guard !isBusy else { return false }
        guard let template = MicroPlanTemplateLibrary.template(
            for: action.templateID
        ) else {
            present(CarePlanModelError.invalidPlanDateRange)
            return false
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let draft = try template.makeDraft(referenceDate: referenceDate)
            _ = try await service.createPlan(from: draft)
            try await loadState(referenceDate: referenceDate)
            message = "微计划已经开始，今天完成后记得回来打卡。"
            showsError = false
            return true
        } catch {
            present(error)
            return false
        }
    }

    func recordToday(
        _ state: PlanOutcomeState,
        referenceDate: Date = Date()
    ) async {
        guard !isBusy, let plan = activePlan,
              let occurrenceIndex = Self.occurrenceIndex(
                for: referenceDate,
                in: plan
              ) else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            try await service.recordOutcome(PlanOutcomeInput(
                taskID: plan.draft.taskID,
                occurrenceIndex: occurrenceIndex,
                state: state,
                recordedAt: referenceDate,
                difficulty: nil
            ))
            try await loadState(referenceDate: referenceDate)
            message = state == .completed
                ? "今天这一步已经记下来了，做到了就很值得肯定。"
                : "今天已记为跳过。一次没完成不会否定整个计划。"
            showsError = false
        } catch {
            present(error)
        }
    }

    func endEarly(referenceDate: Date = Date()) async {
        guard !isBusy, let plan = activePlan else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.endPlan(plan.draft.id, at: referenceDate)
            try await loadState(referenceDate: referenceDate)
            message = "计划已提前结束，已经完成的记录会继续保留。"
            showsError = false
        } catch {
            present(error)
        }
    }

    private func loadState(referenceDate: Date) async throws {
        let plan = try await service.activePlan()
        let plans = try await service.planHistory()
        activePlan = plan
        mostRecentPlan = plans.first
        var loadedHistory = [MicroPlanHistoryEntry]()
        for historicalPlan in plans where historicalPlan.status != .active {
            loadedHistory.append(MicroPlanHistoryEntry(
                plan: historicalPlan,
                progress: try await service.progress(for: historicalPlan.draft.id)
            ))
        }
        history = loadedHistory
        guard let displayedPlan else {
            progress = nil
            todayOutcomeState = nil
            return
        }
        progress = try await service.progress(for: displayedPlan.draft.id)
        guard let plan else {
            todayOutcomeState = nil
            return
        }
        guard let index = Self.occurrenceIndex(for: referenceDate, in: plan) else {
            todayOutcomeState = nil
            return
        }
        todayOutcomeState = try await service.outcomeState(
            for: plan.draft.taskID,
            occurrenceIndex: index
        )
    }

    private func present(_ error: Error) {
        showsError = true
        switch error as? CarePlanServiceError {
        case .activePlanExists:
            message = "你已经有一个进行中的微计划。先完成或结束它，再开始新的计划。"
        case .outcomeConflict:
            message = "今天已经记录过了，不需要重复打卡。"
        case .planNotFound, .taskNotFound:
            message = "没有找到这项微计划，请刷新后再试。"
        case .persistenceFailed, .none:
            message = "微计划暂时无法保存，请稍后再试。"
        }
    }

    private static func occurrenceIndex(
        for date: Date,
        in plan: MicroPlan,
        calendar: Calendar = .current
    ) -> Int? {
        let start = calendar.startOfDay(for: plan.draft.startDate)
        let day = calendar.startOfDay(for: date)
        guard day >= start, day < plan.draft.endDateExclusive else { return nil }
        return calendar.dateComponents([.day], from: start, to: day).day
    }
}

struct MicroPlanView: View {
    @ObservedObject var session: MicroPlanSession
    @ObservedObject var healthSession: HealthDataSession
    let onOpenAssistant: () -> Void
    @State private var confirmsEarlyEnd = false
    @State private var debugScrollTarget: String?

    private var trendCards: [MicroPlanTrendPresentation] {
        guard let plan = session.displayedPlan else { return [] }
        return MicroPlanTrendPresentationFactory.make(
            plan: plan,
            snapshot: healthSession.snapshot
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader

                    if let message = session.message, session.showsError {
                        statusCard(message, isError: session.showsError)
                    }

                    if let plan = session.displayedPlan {
                        progressHero(plan)
                        planCard(plan)
                        trendSection(plan)
                    } else if session.isBusy {
                        loadingCard
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 110)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $debugScrollTarget, anchor: .top)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await healthSession.refresh()
                await session.refresh()
            }
            .task {
                await session.refresh()
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--plans-trends-preview") {
                    try? await Task.sleep(for: .milliseconds(350))
                    debugScrollTarget = "planTrends"
                }
#endif
            }
            .confirmationDialog(
                "提前结束这个微计划？",
                isPresented: $confirmsEarlyEnd,
                titleVisibility: .visible
            ) {
                Button("提前结束", role: .destructive) {
                    Task { await session.endEarly() }
                }
                Button("继续计划", role: .cancel) {}
            } message: {
                Text("已完成的打卡会保留，未来日程将停止。")
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("微计划")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Spacer(minLength: 0)
            NavigationLink {
                MicroPlanHistoryView(entries: session.history)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(MicroPlanHistoryGlassModifier())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("历史微计划")
        }
    }

    private func progressHero(_ plan: MicroPlan) -> some View {
        let progress = session.progress
        let percentage = Int(((progress?.completionFraction ?? 0) * 100).rounded())
        return VStack(spacing: 14) {
            MicroPlanProgressGauge(
                ratio: progress?.completionFraction ?? 0,
                percentage: percentage,
                completedCount: progress?.completedCount ?? 0,
                scheduledCount: progress?.scheduledCount ?? durationDays(for: plan)
            )
            .frame(width: 238, height: 238)
            .dynamicTypeSize(.small ... .xLarge)

            Text(progressTitle(for: plan))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(encouragementText(for: plan))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func planCard(_ plan: MicroPlan) -> some View {
        let isActive = session.activePlan?.draft.id == plan.draft.id
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(planStatusTitle(plan), systemImage: planStatusIcon(plan))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plan.status == .endedEarly ? .orange : .teal)
                    Text(plan.draft.title)
                        .font(.title2.bold())
                    Text(plan.draft.taskTitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "figure.mind.and.body")
                    .font(.title2)
                    .foregroundStyle(.teal)
                    .frame(width: 48, height: 48)
                    .background(.teal.opacity(0.1), in: Circle())
            }

            planFacts(plan)

            if isActive {
                todayActions
                Button("提前结束计划", role: .destructive) {
                    confirmsEarlyEnd = true
                }
                .font(.subheadline.weight(.semibold))
                .disabled(session.isBusy)
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
    }

    private func trendSection(_ plan: MicroPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("计划期间的变化")
                    .font(.title2.weight(.bold))
                Text("根据这项任务显示相关指标；计划开始线用于对照，不代表计划造成了变化。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if healthSession.dataMode == .demo {
                Label("当前趋势使用演示数据", systemImage: "theatermasks")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }

            ForEach(trendCards) { trend in
                MicroPlanTrendCard(trend: trend)
            }
        }
        .id("planTrends")
    }

    private func planFacts(_ plan: MicroPlan) -> some View {
        HStack(spacing: 12) {
            factPill("\(durationDays(for: plan)) 天", systemImage: "calendar")
            factPill(formattedTime(plan.draft.scheduledTime), systemImage: "clock")
        }
    }

    @ViewBuilder
    private var todayActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今天")
                .font(.headline)
            if let state = session.todayOutcomeState {
                Label(
                    state == .completed ? "今天已完成" : "今天已跳过",
                    systemImage: state == .completed
                        ? "checkmark.circle.fill"
                        : "forward.circle.fill"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(state == .completed ? .teal : .secondary)
            } else {
                HStack(spacing: 12) {
                    Button {
                        Task { await session.recordToday(.completed) }
                    } label: {
                        Label("完成", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                Color.teal,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await session.recordToday(.skipped) }
                    } label: {
                        Text("今天跳过")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.teal)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                Color.teal.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.teal.opacity(0.28), lineWidth: 1)
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .disabled(session.isBusy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.teal)
            Text("从一个真正做得到的小行动开始")
                .font(.title2.bold())
            Text("在 AI 助手里聊聊你最近的状态。出现微计划候选后，由你确认，计划才会写入 CareKitStore。一次只进行一个 5 天计划。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("去 AI 助手选择计划") {
                onOpenAssistant()
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("正在读取微计划…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func statusCard(_ text: String, isError: Bool) -> some View {
        Label(
            text,
            systemImage: isError ? "exclamationmark.circle" : "checkmark.circle"
        )
        .font(.subheadline)
        .foregroundStyle(isError ? .orange : .teal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            (isError ? Color.orange : Color.teal).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func progressTitle(for plan: MicroPlan) -> String {
        switch plan.status {
        case .completed: "这次计划已经走完"
        case .endedEarly: "这次计划已提前结束"
        case .paused: "计划已暂停"
        case .draft: "计划准备中"
        case .active:
            (session.progress?.completedCount ?? 0) == 0
                ? "从今天这一小步开始"
                : "你正在稳稳推进"
        }
    }

    private func encouragementText(for plan: MicroPlan) -> String {
        if let message = session.message, !session.showsError {
            return message
        }
        guard let progress = session.progress else { return "正在读取完成记录。" }
        if plan.status == .completed {
            return "这段坚持已经完整记下来了，下面可以看看相关指标如何变化。"
        }
        if plan.status == .endedEarly {
            return "停下来也是照顾自己的选择，已经做过的努力都会保留。"
        }
        if progress.skippedCount > 0 {
            return "偶尔跳过不会否定整个计划，按自己的节奏继续就好。"
        }
        if progress.completedCount > 0 {
            return "你已经把行动真正做起来了，继续保持现在的节奏。"
        }
        return "先完成今天这一小步，不用追求一次做到完美。"
    }

    private func planStatusTitle(_ plan: MicroPlan) -> String {
        switch plan.status {
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .endedEarly: "已提前结束"
        case .draft: "准备中"
        }
    }

    private func planStatusIcon(_ plan: MicroPlan) -> String {
        switch plan.status {
        case .active: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.seal.fill"
        case .endedEarly: "stop.circle.fill"
        case .draft: "clock.fill"
        }
    }

    private func factPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .teal.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
    }

    private func durationDays(for plan: MicroPlan) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: plan.draft.startDate,
            to: plan.draft.endDateExclusive
        ).day ?? 0
    }

    private func formattedTime(_ time: ScheduledLocalTime) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }
}

private struct MicroPlanHistoryGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.55), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
        }
    }
}

private struct MicroPlanProgressGauge: View {
    let ratio: Double
    let percentage: Int
    let completedCount: Int
    let scheduledCount: Int

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                .shadow(color: .white, radius: 8)
            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * min(max(ratio, 0), 1))
                .stroke(
                    AngularGradient(colors: [.teal, .cyan, .blue], center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .shadow(color: .teal.opacity(0.30), radius: 8)
            Color.secondary.opacity(0.15)
                .mask { tickMask(completedOnly: false) }
            AngularGradient(colors: [.teal, .cyan, .blue], center: .center)
                .mask { tickMask(completedOnly: true) }
            VStack(spacing: 6) {
                Text("\(percentage)%")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                Text("微计划进度")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(completedCount) / \(scheduledCount) 次")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .rotationEffect(.degrees(-90))
        }
        .rotationEffect(.degrees(90))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("微计划进度")
        .accessibilityValue("\(percentage)%，完成 \(completedCount) 次，共 \(scheduledCount) 次")
    }

    @ViewBuilder
    private func tickMask(completedOnly: Bool) -> some View {
        ZStack {
            ForEach(0..<25, id: \.self) { index in
                let tickProgress = Double(index + 1) / 25
                if !completedOnly || tickProgress <= min(max(ratio, 0), 1) {
                    Capsule()
                        .frame(
                            width: index.isMultiple(of: 4) ? 3 : 2,
                            height: index.isMultiple(of: 4) ? 10 : 6
                        )
                        .offset(y: -96)
                        .rotationEffect(.degrees(43.2 + Double(index) * 11.4))
                }
            }
        }
        .rotationEffect(.degrees(90))
    }
}

private struct MicroPlanTrendCard: View {
    let trend: MicroPlanTrendPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(trend.metric.title)
                    .font(.headline)
                Spacer()
                Text("计划相关")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.1), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text(valueText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Text(changeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(changeColor)
                    .multilineTextAlignment(.trailing)
            }

            if trend.points.isEmpty {
                Text("当前没有可见记录，缺失数据不会补成 0。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .center)
                    .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Chart {
                    ForEach(trend.points) { point in
                        AreaMark(
                            x: .value("日期", point.date, unit: .day),
                            yStart: .value("起点", yDomain.lowerBound),
                            yEnd: .value("数值", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.20), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("数值", point.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("数值", point.value)
                        )
                        .symbolSize(point.id == trend.points.last?.id ? 48 : 24)
                        .foregroundStyle(point.id == trend.points.last?.id ? color : .white)
                    }
                    RuleMark(x: .value("计划开始", trend.planStartDate, unit: .day))
                        .foregroundStyle(.teal.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                }
                .chartYScale(domain: yDomain)
                .chartXScale(
                    range: .plotDimension(startPadding: 18, endPadding: 18)
                )
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisTick().foregroundStyle(.clear)
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                if Calendar.current.isDate(
                                    date,
                                    inSameDayAs: trend.planStartDate
                                ) {
                                    VStack(spacing: 1) {
                                        Text("计划开始")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.teal)
                                        Text(date, format: .dateTime.month().day())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(date, format: .dateTime.month().day())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
                .background(color.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }

            Text("计划前 \(trend.beforeValidDayCount) 天 · 计划期 \(trend.planValidDayCount) 天有效记录")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.04), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch trend.metric {
        case .sleepOnset: "moon.stars.fill"
        case .sleepDuration: "bed.double.fill"
        case .stepCount: "figure.walk"
        case .activeEnergy: "flame.fill"
        case .standHours: "figure.stand"
        case .exerciseDuration: "figure.run"
        case .heartRateVariability: "waveform.path.ecg"
        case .walkingRunningDistance: "figure.walk.motion"
        }
    }

    private var color: Color {
        switch trend.metric {
        case .sleepOnset: .indigo
        case .sleepDuration: .blue
        case .stepCount: .teal
        case .activeEnergy: .orange
        case .standHours: .cyan
        case .exerciseDuration: .green
        case .heartRateVariability: .pink
        case .walkingRunningDistance: .teal
        }
    }

    private var valueText: String {
        guard let value = trend.latestValue else { return "暂无数据" }
        return format(value)
    }

    private var changeText: String {
        guard let change = trend.changeFromBefore else {
            return trend.points.isEmpty ? "等待健康记录" : "继续积累对照"
        }
        if trend.metric == .sleepOnset {
            let minutes = Int((abs(change) * 60).rounded())
            if minutes == 0 { return "与计划前相近" }
            return change < 0 ? "比计划前早 \(minutes) 分钟" : "比计划前晚 \(minutes) 分钟"
        }
        if abs(change) < 0.000_1 { return "与计划前相近" }
        return "较计划前 \(change > 0 ? "+" : "−")\(format(abs(change)))"
    }

    private var changeColor: Color {
        trend.changeFromBefore == nil ? .secondary : color
    }

    private func format(_ value: Double) -> String {
        switch trend.metric {
        case .sleepOnset:
            let totalMinutes = Int((value * 60).rounded()) % (24 * 60)
            return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
        case .sleepDuration:
            return "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .stepCount:
            return "\(Int(value.rounded()).formatted()) 步"
        case .activeEnergy:
            return "\(Int(value.rounded())) 千卡"
        case .standHours:
            return "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .exerciseDuration:
            return "\(Int(value.rounded())) 分钟"
        case .heartRateVariability:
            return "\(Int(value.rounded())) 毫秒"
        case .walkingRunningDistance:
            return "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        }
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = trend.points.map(\.value).min(),
              let maximum = trend.points.map(\.value).max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.30, 0.25)
        if trend.metric == .sleepOnset {
            return (minimum - padding)...(maximum + padding)
        }
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var axisDates: [Date] {
        let candidates = [
            trend.points.first?.date,
            trend.planStartDate,
            trend.points.last?.date
        ].compactMap { $0 }
        let calendar = Calendar.current
        return candidates.reduce(into: [Date]()) { result, date in
            guard !result.contains(where: { calendar.isDate($0, inSameDayAs: date) }) else {
                return
            }
            result.append(date)
        }
        .sorted()
    }
}

private struct MicroPlanHistoryView: View {
    let entries: [MicroPlanHistoryEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        historyCard(entry)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("历史微计划")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.teal)
            Text("还没有历史微计划")
                .font(.title3.bold())
            Text("完成或提前结束的计划会保存在这里，方便以后回看当时做了什么和完成进度。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func historyCard(_ entry: MicroPlanHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.plan.draft.title)
                        .font(.headline)
                    Text(entry.plan.draft.taskTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Text(statusTitle(entry.plan.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(entry.plan.status))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        statusColor(entry.plan.status).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
            }

            HStack(spacing: 10) {
                historyFact(
                    dateRange(entry.plan),
                    systemImage: "calendar"
                )
                historyFact(
                    formattedTime(entry.plan.draft.scheduledTime),
                    systemImage: "clock"
                )
            }

            ProgressView(value: entry.progress.completionFraction)
                .tint(.teal)
            Text("完成 \(entry.progress.completedCount) / \(entry.progress.scheduledCount) 次")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func historyFact(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color.teal.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    private func dateRange(_ plan: MicroPlan) -> String {
        let calendar = Calendar.current
        let endInclusive = calendar.date(
            byAdding: .day,
            value: -1,
            to: plan.draft.endDateExclusive
        ) ?? plan.draft.endDateExclusive
        return plan.draft.startDate.formatted(.dateTime.month().day())
            + "–"
            + endInclusive.formatted(.dateTime.month().day())
    }

    private func formattedTime(_ time: ScheduledLocalTime) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func statusTitle(_ status: MicroPlanStatus) -> String {
        switch status {
        case .completed: "已完成"
        case .endedEarly: "已提前结束"
        case .paused: "已暂停"
        case .active: "进行中"
        case .draft: "准备中"
        }
    }

    private func statusColor(_ status: MicroPlanStatus) -> Color {
        switch status {
        case .completed: .teal
        case .endedEarly: .orange
        case .paused, .draft: .secondary
        case .active: .blue
        }
    }
}
