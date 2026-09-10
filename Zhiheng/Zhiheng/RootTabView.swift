import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case insights
    case assistant
    case plans
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .insights: "洞察"
        case .assistant: "AI 助手"
        case .plans: "微计划"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "heart.text.square"
        case .insights: "chart.xyaxis.line"
        case .assistant: "bubble.left.and.text.bubble.right"
        case .plans: "checklist"
        case .profile: "person.crop.circle"
        }
    }
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab
    @AppStorage("healthDataMode") private var healthDataModeRaw = HealthDataMode.live.rawValue
    @StateObject private var liveHealthSession: HealthDataSession
    @StateObject private var demoHealthSession: HealthDataSession
    @StateObject private var microPlanSession: MicroPlanSession
    @StateObject private var checkInCoordinator: DailyCheckInCoordinator
    @StateObject private var notificationAuthorizationSession: NotificationAuthorizationSession
    @StateObject private var dailyCheckInReminderSession: DailyCheckInReminderSession
    @StateObject private var microPlanReminderSession: MicroPlanReminderSession
    @StateObject private var lowFrequencyTrendReminderSession: LowFrequencyTrendReminderSession
    @StateObject private var notificationDeliverySettingsSession:
        NotificationDeliverySettingsSession
    private let insightContextLoader: InsightContextLoader
    private let insightInteractionStore: any InsightInteractionStore
    private let isDemoAvailable: Bool

    init(referenceDate: Date = Date()) {
#if DEBUG
        let startsOnInsights = ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("--insights-section=")
        }
        let startsOnAssistant = ProcessInfo.processInfo.arguments.contains(
            "--assistant-preview"
        )
        let startsOnPlans = ProcessInfo.processInfo.arguments.contains(
            "--plans-preview"
        ) || ProcessInfo.processInfo.arguments.contains(
            "--plans-feedback-preview"
        ) || ProcessInfo.processInfo.arguments.contains(
            "--plans-evaluation-preview"
        )
        let startsOnProfile = ProcessInfo.processInfo.arguments.contains(
            "--profile-preview"
        ) || ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("--privacy-flow-preview=")
        }
        _selection = State(initialValue: startsOnProfile
            ? .profile
            : (startsOnPlans
                ? .plans
                : (startsOnAssistant
                    ? .assistant
                    : (startsOnInsights ? .insights : .today))))
#else
        _selection = State(initialValue: .today)
#endif
        let liveService = HealthKitDataService()
        let demoService = try? DemoHealthScenarioFactory.dashboard(
            endingAt: referenceDate
        )
        _liveHealthSession = StateObject(
            wrappedValue: HealthDataSession(service: liveService)
        )
        _demoHealthSession = StateObject(
            wrappedValue: HealthDataSession(service: demoService ?? liveService)
        )
        let planStoreName: String
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--plans-evaluation-preview") {
            planStoreName = "ZhihengCarePlansEvaluationPreview"
        } else if ProcessInfo.processInfo.arguments.contains("--plans-feedback-preview") {
            planStoreName = "ZhihengCarePlansFeedbackPreview"
        } else {
            planStoreName = "ZhihengCarePlans"
        }
#else
        planStoreName = "ZhihengCarePlans"
#endif
        let subjectiveRecordStore: any SubjectiveRecordStore
        do {
            subjectiveRecordStore = try SwiftDataSubjectiveRecordStore()
        } catch {
            subjectiveRecordStore = UnavailableSubjectiveRecordStore()
        }
        let baselineStore: any PlanBaselineStore
        do {
            baselineStore = try SwiftDataPlanBaselineStore()
        } catch {
            baselineStore = UnavailablePlanBaselineStore()
        }
        let effectiveMethodVisibilityStore: any EffectiveMethodVisibilityStore
        do {
            effectiveMethodVisibilityStore = try SwiftDataEffectiveMethodVisibilityStore()
        } catch {
            effectiveMethodVisibilityStore = UnavailableEffectiveMethodVisibilityStore()
        }
        let planService = CareKitPlanStore(onDiskStoreNamed: planStoreName)
        _microPlanSession = StateObject(
            wrappedValue: MicroPlanSession(
                service: planService,
                baselineStore: baselineStore,
                subjectiveRecordStore: subjectiveRecordStore,
                effectiveMethodVisibilityStore: effectiveMethodVisibilityStore
            )
        )
        let notificationAuthorizationSession = NotificationAuthorizationSession()
        let notificationPreferences = UserDefaults.standard
        let notificationDeliverySettingsStore = NotificationDeliverySettingsStore(
            preferences: notificationPreferences
        )
        let notificationDeliverySettingsSession = NotificationDeliverySettingsSession(
            store: notificationDeliverySettingsStore,
            initialSettings: NotificationDeliverySettingsStore.load(
                from: notificationPreferences
            )
        )
        let reminderScheduler = SystemNotificationReminderScheduler(
            deliverySettingsStore: notificationDeliverySettingsStore
        )
        let insightInteractionStore: any InsightInteractionStore
        do {
            insightInteractionStore = try SwiftDataInsightInteractionStore()
        } catch {
            insightInteractionStore = UnavailableInsightInteractionStore()
        }
        let dailyCheckInReminderSession = DailyCheckInReminderSession(
            store: subjectiveRecordStore,
            authorizationSession: notificationAuthorizationSession,
            scheduler: reminderScheduler
        )
        let lowFrequencyTrendReminderSession = LowFrequencyTrendReminderSession(
            interactionStore: insightInteractionStore,
            authorizationSession: notificationAuthorizationSession,
            scheduler: reminderScheduler
        )
        let microPlanReminderSession = MicroPlanReminderSession(
            service: planService,
            authorizationSession: notificationAuthorizationSession,
            scheduler: reminderScheduler
        )
        let checkInCoordinator = DailyCheckInCoordinator(store: subjectiveRecordStore)
        checkInCoordinator.onCurrentCheckInChanged = {
            Task { @MainActor in
                await microPlanReminderSession.synchronize(isLiveMode: true)
                await dailyCheckInReminderSession.synchronize(isLiveMode: true)
            }
        }
        _checkInCoordinator = StateObject(wrappedValue: checkInCoordinator)
        _notificationAuthorizationSession = StateObject(
            wrappedValue: notificationAuthorizationSession
        )
        _dailyCheckInReminderSession = StateObject(
            wrappedValue: dailyCheckInReminderSession
        )
        _microPlanReminderSession = StateObject(
            wrappedValue: microPlanReminderSession
        )
        _lowFrequencyTrendReminderSession = StateObject(
            wrappedValue: lowFrequencyTrendReminderSession
        )
        _notificationDeliverySettingsSession = StateObject(
            wrappedValue: notificationDeliverySettingsSession
        )
        insightContextLoader = InsightContextLoader(store: subjectiveRecordStore)
        self.insightInteractionStore = insightInteractionStore
        isDemoAvailable = demoService != nil
    }

    private var healthDataMode: HealthDataMode {
        HealthDataMode(rawValue: healthDataModeRaw) ?? .live
    }

    private var activeHealthSession: HealthDataSession {
        healthDataMode == .demo ? demoHealthSession : liveHealthSession
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                content(for: tab)
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        .tint(.teal)
        .sheet(isPresented: $checkInCoordinator.isPresented) {
            DailyFeelingSheet(coordinator: checkInCoordinator)
        }
        .task(id: healthDataMode) {
            checkInCoordinator.enterApp(dataMode: healthDataMode)
            await notificationAuthorizationSession.refresh()
            await activeHealthSession.refreshOnceForCurrentAppEntry()
            await synchronizeReminders()
#if DEBUG
            let seedsProgressPreview = ProcessInfo.processInfo.arguments.contains(
                "--plans-seed-preview"
            )
            let seedsActionsPreview = ProcessInfo.processInfo.arguments.contains(
                "--plans-actions-preview"
            ) || ProcessInfo.processInfo.arguments.contains(
                "--plans-feedback-preview"
            )
            let seedsEvaluationPreview = ProcessInfo.processInfo.arguments.contains(
                "--plans-evaluation-preview"
            )
            if seedsProgressPreview || seedsActionsPreview || seedsEvaluationPreview {
                for _ in 0..<20 where microPlanSession.isBusy {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await microPlanSession.refresh(dataMode: activeHealthSession.dataMode)
            }
            if seedsProgressPreview || seedsActionsPreview || seedsEvaluationPreview,
               microPlanSession.activePlan == nil,
               !microPlanSession.isBusy {
                let calendar = Calendar.current
                let previewStart = seedsActionsPreview
                    ? Date()
                    : (calendar.date(
                        byAdding: .day,
                        value: -4,
                        to: Date()
                    ) ?? Date())
                let didStart = await microPlanSession.start(
                    from: HealthAISuggestedAction(
                        templateID: .earlierBedtime,
                        rationale: "用一个短而明确的行动观察作息变化。"
                    ),
                    healthSnapshot: activeHealthSession.snapshot,
                    dataMode: activeHealthSession.dataMode,
                    referenceDate: previewStart
                )
                if didStart, seedsProgressPreview || seedsEvaluationPreview {
                    for dayOffset in 0..<4 {
                        let day = calendar.date(
                            byAdding: .day,
                            value: dayOffset,
                            to: previewStart
                        ) ?? previewStart
                        await microPlanSession.recordToday(
                            .completed,
                            feedback: seedsEvaluationPreview
                                ? (dayOffset.isMultiple(of: 2)
                                    ? "今天更容易开始，结束后感觉比较轻松。"
                                    : nil)
                                : nil,
                            referenceDate: day
                        )
                    }
                    if seedsEvaluationPreview {
                        await microPlanSession.endEarly()
                    }
                    await microPlanSession.refresh(dataMode: activeHealthSession.dataMode)
                }
            }
#endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                liveHealthSession.markAppAsExited()
                demoHealthSession.markAppAsExited()
            case .active:
                checkInCoordinator.enterApp(dataMode: healthDataMode)
                Task {
                    await notificationAuthorizationSession.refresh()
                    await activeHealthSession.refreshOnceForCurrentAppEntry()
                    await synchronizeReminders()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: microPlanSession.activePlan) {
            Task { await synchronizeReminders() }
        }
        .onChange(of: microPlanSession.todayOutcomeState) {
            Task { await synchronizeReminders() }
        }
        .onChange(of: activeHealthSession.snapshot) {
            Task { await synchronizeReminders() }
        }
    }

    private func synchronizeReminders() async {
        let isLiveMode = healthDataMode == .live
        await microPlanReminderSession.synchronize(isLiveMode: isLiveMode)
        await lowFrequencyTrendReminderSession.synchronize(
            snapshot: activeHealthSession.snapshot,
            loadedInterval: activeHealthSession.snapshotInterval,
            access: activeHealthSession.accessState,
            dataMode: healthDataMode
        )
        await dailyCheckInReminderSession.synchronize(isLiveMode: isLiveMode)
    }

    private func settingsView(goals: Binding<TodayDashboardGoals>) -> some View {
        ProfileSettingsView(
            contentMode: .settings,
            goals: goals,
            healthDataModeRaw: $healthDataModeRaw,
            isDemoAvailable: isDemoAvailable,
            healthSession: activeHealthSession,
            planSession: microPlanSession,
            notificationSession: notificationAuthorizationSession,
            dailyReminderSession: dailyCheckInReminderSession,
            microPlanReminderSession: microPlanReminderSession,
            lowFrequencyTrendReminderSession: lowFrequencyTrendReminderSession,
            notificationDeliverySettingsSession: notificationDeliverySettingsSession,
            insightContextLoader: insightContextLoader,
            onPlanStarted: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    selection = .plans
                }
            }
        )
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            if healthDataMode == .demo, isDemoAvailable {
                TodayView(
                    healthSession: demoHealthSession,
                    checkInCoordinator: checkInCoordinator,
                    settingsDestination: { goals in
                        AnyView(settingsView(goals: goals))
                    }
                )
                    .id(HealthDataMode.demo.rawValue)
            } else {
                TodayView(
                    healthSession: liveHealthSession,
                    checkInCoordinator: checkInCoordinator,
                    settingsDestination: { goals in
                        AnyView(settingsView(goals: goals))
                    }
                )
                    .id(HealthDataMode.live.rawValue)
            }
        case .insights:
            if healthDataMode == .demo, isDemoAvailable {
                InsightsView(healthSession: demoHealthSession)
                    .id("insights-\(HealthDataMode.demo.rawValue)")
            } else {
                InsightsView(healthSession: liveHealthSession)
                    .id("insights-\(HealthDataMode.live.rawValue)")
            }
        case .assistant:
            if healthDataMode == .demo, isDemoAvailable {
                AssistantView(
                    healthSession: demoHealthSession,
                    planSession: microPlanSession,
                    onPlanStarted: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = .plans
                        }
                    },
                    conversationScope: .demo
                )
                    .id("assistant-\(HealthDataMode.demo.rawValue)")
            } else {
                AssistantView(
                    healthSession: liveHealthSession,
                    planSession: microPlanSession,
                    onPlanStarted: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = .plans
                        }
                    },
                    conversationScope: .live
                )
                    .id("assistant-\(HealthDataMode.live.rawValue)")
            }
        case .plans:
            MicroPlanView(
                session: microPlanSession,
                healthSession: activeHealthSession,
                onOpenAssistant: { selection = .assistant }
            )
        case .profile:
            ProfileSettingsView(
                contentMode: .effectiveMethods,
                goals: nil,
                healthDataModeRaw: $healthDataModeRaw,
                isDemoAvailable: isDemoAvailable,
                healthSession: activeHealthSession,
                planSession: microPlanSession,
                notificationSession: notificationAuthorizationSession,
                dailyReminderSession: dailyCheckInReminderSession,
                microPlanReminderSession: microPlanReminderSession,
                lowFrequencyTrendReminderSession: lowFrequencyTrendReminderSession,
                notificationDeliverySettingsSession: notificationDeliverySettingsSession,
                insightContextLoader: insightContextLoader,
                onPlanStarted: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection = .plans
                    }
                }
            )
        }
    }
}

enum ProfileContentMode {
    case effectiveMethods
    case settings
}

private struct EffectiveMethodsRefreshRequest: Hashable {
    let dataMode: String
    let snapshotIntervalEnd: Date?
    let planID: String?
    let planStatus: String?
    let scheduledCount: Int?
    let completedCount: Int?
    let skippedCount: Int?
    let outcomeCount: Int
}

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let contentMode: ProfileContentMode
    let goals: Binding<TodayDashboardGoals>?
    @Binding var healthDataModeRaw: String
    let isDemoAvailable: Bool
    @ObservedObject var healthSession: HealthDataSession
    @ObservedObject var planSession: MicroPlanSession
    @ObservedObject var notificationSession: NotificationAuthorizationSession
    @ObservedObject var dailyReminderSession: DailyCheckInReminderSession
    @ObservedObject var microPlanReminderSession: MicroPlanReminderSession
    @ObservedObject var lowFrequencyTrendReminderSession: LowFrequencyTrendReminderSession
    @ObservedObject var notificationDeliverySettingsSession:
        NotificationDeliverySettingsSession
    let insightContextLoader: InsightContextLoader
    let onPlanStarted: () -> Void
    @State private var showsHealthAccessExplanation = false
    @State private var isRequestingHealthAccess = false
    @State private var healthAccessErrorMessage: String?
    @State private var pendingMethodRestart: EffectiveMethodCardPresentation?
    @State private var pendingMethodHide: EffectiveMethodCardPresentation?
    @State private var effectiveMethodFilter = EffectiveMethodEvidenceFilter.all
    @State private var showsPrivacyDataFlow = false
    @State private var displayedEffectiveMethodsRequest: EffectiveMethodsRefreshRequest?
    @State private var didPrepareSettings = false
#if DEBUG
    @State private var deepSeekKeyDraft = ""
    @State private var hasDeepSeekKey = false
    @State private var deepSeekKeyMessage: String?
    private let deepSeekKeyStore = DeepSeekAPIKeyStore()
#endif

    private var isDemoMode: Binding<Bool> {
        Binding(
            get: { healthDataModeRaw == HealthDataMode.demo.rawValue },
            set: { enabled in
                healthDataModeRaw = enabled
                    ? HealthDataMode.demo.rawValue
                    : HealthDataMode.live.rawValue
            }
        )
    }

    private var readiness: AppReadiness {
        AppReadiness(healthAccess: healthSession.accessState)
    }

    private var healthDataMode: HealthDataMode {
        HealthDataMode(rawValue: healthDataModeRaw) ?? .live
    }

    private var effectiveMethodsRefreshRequest: EffectiveMethodsRefreshRequest {
        EffectiveMethodsRefreshRequest(
            dataMode: healthDataModeRaw,
            snapshotIntervalEnd: healthSession.snapshotInterval?.end,
            planID: planSession.mostRecentPlan?.draft.id.rawValue,
            planStatus: planSession.mostRecentPlan?.status.rawValue,
            scheduledCount: planSession.progress?.scheduledCount,
            completedCount: planSession.progress?.completedCount,
            skippedCount: planSession.progress?.skippedCount,
            outcomeCount: planSession.outcomeRecords.count
        )
    }

    var body: some View {
        NavigationStack {
            AnyView(Group {
                if contentMode == .effectiveMethods {
                    AnyView(effectiveMethodsPage)
                } else {
                    AnyView(Form {
                    if let goals {
                        Section("今日") {
                            NavigationLink {
                                TodayGoalSettingsView(goals: goals)
                            } label: {
                                Label("健康目标", systemImage: "target")
                            }
                        }
                    }

                    Section("健康摘要") {
                    NavigationLink {
                        SevenDayHealthSummaryView(
                            healthSession: healthSession,
                            contextLoader: insightContextLoader,
                            dataMode: healthDataMode
                        )
                    } label: {
                        Label("查看 7 天健康摘要", systemImage: "doc.text.magnifyingglass")
                    }
                    Text("汇总最近 7 个完整日的客观记录、已保存感受、生活情境和一个本地建议；不会调用 AI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("健康数据状态") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: healthDataModeRaw == HealthDataMode.demo.rawValue
                              ? "theatermasks.fill"
                              : readiness.systemImage)
                            .font(.title3)
                            .foregroundStyle(dataStatusColor)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(dataStatusTitle)
                                .font(.body.weight(.semibold))
                            Text(dataStatusDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    if healthDataModeRaw != HealthDataMode.demo.rawValue {
                        Button {
                            showsHealthAccessExplanation = true
                        } label: {
                            Label(
                                readiness.shouldOfferHealthConnection
                                    ? "了解并连接 Apple Health"
                                    : "查看健康数据权限与用途",
                                systemImage: "heart.text.square"
                            )
                        }

                        Button {
                            Task { await healthSession.refresh() }
                        } label: {
                            if healthSession.isLoading {
                                Label("正在刷新…", systemImage: "arrow.clockwise")
                            } else {
                                Label("刷新健康数据", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(healthSession.isLoading || !readiness.canQueryHealthData)
                    }
                }

                Section("数据来源") {
                    Toggle("使用演示数据", isOn: isDemoMode)
                        .disabled(!isDemoAvailable)
                    Text(isDemoMode.wrappedValue
                         ? "当前显示知衡生成的模拟场景，不是你的真实健康数据。"
                         : "当前使用你主动选择分享的 Apple Health 数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("提醒") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notificationSession.state.systemImage)
                            .font(.title3)
                            .foregroundStyle(notificationStatusColor)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notificationSession.state.title)
                                .font(.body.weight(.semibold))
                            Text(notificationSession.state.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    if notificationSession.state.canPresentExplanation {
                        Button {
                            notificationSession.beginRequest()
                        } label: {
                            Label("了解并开启通知", systemImage: "bell.badge")
                        }
                    } else if notificationSession.state.canRetryStatus {
                        Button {
                            Task {
                                await notificationSession.refresh()
                                await synchronizeReminders()
                            }
                        } label: {
                            Label("重新读取通知状态", systemImage: "arrow.clockwise")
                        }
                    }

                    Toggle(
                        isOn: Binding(
                            get: {
                                notificationDeliverySettingsSession.settings.isEnabled
                            },
                            set: { isEnabled in
                                Task {
                                    await notificationDeliverySettingsSession
                                        .setEnabled(isEnabled)
                                    await synchronizeReminders()
                                }
                            }
                        )
                    ) {
                        Label("全部提醒", systemImage: "bell")
                    }

                    if notificationDeliverySettingsSession.settings.isEnabled {
                        Picker(
                            "提醒频率",
                            selection: Binding(
                                get: {
                                    notificationDeliverySettingsSession.settings.frequency
                                },
                                set: { frequency in
                                    Task {
                                        await notificationDeliverySettingsSession
                                            .setFrequency(frequency)
                                        await synchronizeReminders()
                                    }
                                }
                            )
                        ) {
                            ForEach(NotificationReminderFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }

                        Toggle(
                            "安静时间",
                            isOn: Binding(
                                get: {
                                    notificationDeliverySettingsSession.settings
                                        .quietHours.isEnabled
                                },
                                set: { isEnabled in
                                    Task {
                                        await notificationDeliverySettingsSession
                                            .setQuietHoursEnabled(isEnabled)
                                        await synchronizeReminders()
                                    }
                                }
                            )
                        )

                        if notificationDeliverySettingsSession.settings.quietHours.isEnabled {
                            DatePicker(
                                "开始",
                                selection: Binding(
                                    get: {
                                        notificationDeliverySettingsSession.quietStartTime
                                    },
                                    set: { time in
                                        Task {
                                            await notificationDeliverySettingsSession
                                                .updateQuietStart(from: time)
                                            await synchronizeReminders()
                                        }
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            DatePicker(
                                "结束",
                                selection: Binding(
                                    get: {
                                        notificationDeliverySettingsSession.quietEndTime
                                    },
                                    set: { time in
                                        Task {
                                            await notificationDeliverySettingsSession
                                                .updateQuietEnd(from: time)
                                            await synchronizeReminders()
                                        }
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                        }
                    } else {
                        Text("已清除三类待发送提醒；各类型选择与趋势去重记录仍保留。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { dailyReminderSession.settings.isEnabled },
                            set: { isEnabled in
                                Task {
                                    await dailyReminderSession.setEnabled(
                                        isEnabled,
                                        isLiveMode: healthDataModeRaw == HealthDataMode.live.rawValue
                                    )
                                    await synchronizeReminders()
                                }
                            }
                        )
                    ) {
                        Label("每日感受提醒", systemImage: "checkmark.circle")
                    }
                    .disabled(
                        !notificationDeliverySettingsSession.settings.isEnabled
                            || dailyReminderSession.isUpdating
                            || (!notificationSession.authorizationStatus.isEnabled
                                && !dailyReminderSession.settings.isEnabled)
                    )

                    if dailyReminderSession.settings.isEnabled {
                        DatePicker(
                            "提醒时间",
                            selection: Binding(
                                get: { dailyReminderSession.selectedTime },
                                set: { time in
                                    Task {
                                        await dailyReminderSession.updateTime(
                                            from: time,
                                            isLiveMode: healthDataModeRaw == HealthDataMode.live.rawValue
                                        )
                                        await synchronizeReminders()
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .disabled(
                            !notificationDeliverySettingsSession.settings.isEnabled
                                || dailyReminderSession.isUpdating
                                || !notificationSession.authorizationStatus.isEnabled
                        )
                    }

                    if let errorMessage = dailyReminderSession.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(dailyReminderSession.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { microPlanReminderSession.settings.isEnabled },
                            set: { isEnabled in
                                Task {
                                    await microPlanReminderSession.setEnabled(
                                        isEnabled,
                                        isLiveMode: healthDataModeRaw == HealthDataMode.live.rawValue
                                    )
                                    await synchronizeReminders()
                                }
                            }
                        )
                    ) {
                        Label("微计划提醒", systemImage: "checklist")
                    }
                    .disabled(
                        !notificationDeliverySettingsSession.settings.isEnabled
                            || microPlanReminderSession.isUpdating
                            || (!notificationSession.authorizationStatus.isEnabled
                                && !microPlanReminderSession.settings.isEnabled)
                    )

                    if let errorMessage = microPlanReminderSession.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(microPlanReminderSession.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { lowFrequencyTrendReminderSession.settings.isEnabled },
                            set: { isEnabled in
                                Task {
                                    await lowFrequencyTrendReminderSession.setEnabled(
                                        isEnabled,
                                        snapshot: healthSession.snapshot,
                                        loadedInterval: healthSession.snapshotInterval,
                                        access: healthSession.accessState,
                                        dataMode: healthDataMode
                                    )
                                    await synchronizeReminders()
                                }
                            }
                        )
                    ) {
                        Label("低频趋势提醒", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(
                        !notificationDeliverySettingsSession.settings.isEnabled
                            || lowFrequencyTrendReminderSession.isUpdating
                            || (!notificationSession.authorizationStatus.isEnabled
                                && !lowFrequencyTrendReminderSession.settings.isEnabled)
                    )

                    if let errorMessage = lowFrequencyTrendReminderSession.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(lowFrequencyTrendReminderSession.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("只有数据质量合格并达到持续变化时才会低频提醒；同一指标与方向不会重复发送，AI 不参与判断。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("同日优先级为微计划、低频趋势、每日感受，全部常规提醒合计每天最多一条。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("安静时间内的提醒会跳过，不会擅自移动计划时间；降低频率后，三类提醒共同遵守所选最小间隔。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("锁屏默认只显示“知衡提醒 / 打开知衡查看”，不透露感受、计划或趋势类别，也不包含症状、指标、数值、具体行动或反馈。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与安全") {
                    NavigationLink {
                        PrivacyDataFlowView()
                    } label: {
                        Label("查看隐私说明与数据流", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    Label("Apple Health 始终为只读访问", systemImage: "heart.text.square")
                    Label("只有主动发送 AI 问题或确认分享时才会外发", systemImage: "hand.tap")
                    Text("切换演示模式不会修改 Apple Health；演示内容仅用于体验，不会冒充你的真实记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

#if DEBUG
                Section("个人 AI · Debug") {
                    SecureField("输入 DeepSeek API Key", text: $deepSeekKeyDraft)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button(hasDeepSeekKey ? "更新密钥" : "保存密钥") {
                        saveDeepSeekKey()
                    }
                    .disabled(
                        deepSeekKeyDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )

                    if hasDeepSeekKey {
                        Label("已安全保存在这台 iPhone 的 Keychain", systemImage: "checkmark.shield.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                        Button("删除密钥", role: .destructive) {
                            deleteDeepSeekKey()
                        }
                    }

                    if let deepSeekKeyMessage {
                        Text(deepSeekKeyMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("保存后，个人 Debug 版本会通过 HTTPS 直接调用 DeepSeek。密钥不会显示、不会写入源码或日志；Release 版本仍使用后端代理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif

                Section("关于知衡") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("产品定位", value: "健康洞察与行动助手")
                    Text("知衡用于个人健康管理和生活方式改善，不提供疾病诊断、处方或持续急救监护。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                })
            }})
            .navigationTitle(contentMode == .settings ? "设置" : "")
            .toolbar(
                contentMode == .effectiveMethods ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbar {
                if contentMode == .settings {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
            .navigationDestination(isPresented: $showsPrivacyDataFlow) {
                PrivacyDataFlowView()
            }
            .task(id: healthDataModeRaw) {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains(where: {
                    $0.hasPrefix("--privacy-flow-preview=")
                }) {
                    showsPrivacyDataFlow = true
                }
#endif
            }
            .task(id: effectiveMethodsRefreshRequest) {
                guard contentMode == .effectiveMethods else { return }
                await refreshEffectiveMethods()
            }
            .task {
                guard contentMode == .settings, !didPrepareSettings else { return }
                didPrepareSettings = true
                await notificationSession.refresh()
                await synchronizeReminders()
            }
            .sheet(isPresented: $showsHealthAccessExplanation) {
                HealthAccessExplanationView(
                    isRequesting: isRequestingHealthAccess,
                    requestErrorMessage: healthAccessErrorMessage
                ) { requestHealthAccess() }
            }
            .sheet(
                isPresented: Binding(
                    get: { notificationSession.showsExplanation },
                    set: { isPresented in
                        if !isPresented {
                            notificationSession.cancelExplanation()
                        }
                    }
                )
            ) {
                NotificationPermissionExplanationView(
                    isRequesting: notificationSession.isRequesting,
                    requestErrorMessage: notificationSession.requestErrorMessage,
                    onCancel: {
                        notificationSession.cancelExplanation()
                    },
                    onContinue: {
                        Task {
                            await notificationSession.confirmExplanation()
                            await synchronizeReminders()
                        }
                    }
                )
            }
            .alert(
                "再次验证这个方法？",
                isPresented: Binding(
                    get: { pendingMethodRestart != nil },
                    set: { isPresented in
                        if !isPresented { pendingMethodRestart = nil }
                    }
                ),
                presenting: pendingMethodRestart
            ) { card in
                Button("开始 5 天计划") {
                    restartEffectiveMethod(card)
                }
                Button("取消", role: .cancel) {
                    pendingMethodRestart = nil
                }
            } message: { card in
                Text(restartConfirmationMessage(for: card))
            }
            .alert(
                "隐藏这个方法？",
                isPresented: Binding(
                    get: { pendingMethodHide != nil },
                    set: { isPresented in
                        if !isPresented { pendingMethodHide = nil }
                    }
                ),
                presenting: pendingMethodHide
            ) { card in
                Button("隐藏") {
                    pendingMethodHide = nil
                    planSession.setEffectiveMethodHidden(
                        true,
                        templateID: card.sourcePlanTemplateID
                    )
                }
                Button("取消", role: .cancel) {
                    pendingMethodHide = nil
                }
            } message: { card in
                Text("只会从“我的有效方法”默认列表隐藏“\(card.title)”。相关计划、打卡和评估历史仍会保留，可随时恢复显示。")
            }
#if DEBUG
            .onAppear {
                hasDeepSeekKey = deepSeekKeyStore.load() != nil
            }
#endif
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }

    private func synchronizeReminders() async {
        let isLiveMode = healthDataMode == .live
        await microPlanReminderSession.synchronize(isLiveMode: isLiveMode)
        await lowFrequencyTrendReminderSession.synchronize(
            snapshot: healthSession.snapshot,
            loadedInterval: healthSession.snapshotInterval,
            access: healthSession.accessState,
            dataMode: healthDataMode
        )
        await dailyReminderSession.synchronize(isLiveMode: isLiveMode)
    }

    private var effectiveMethodsPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                effectiveMethodsHeader
                effectiveMethodFilterControls
                effectiveMethodsContent
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var effectiveMethodsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("我的有效方法")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("已收录 \(effectiveMethodCount) 项")
                .font(.caption.weight(.medium))
                .foregroundStyle(.teal)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.teal.opacity(0.06), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.teal.opacity(0.22), lineWidth: 0.8)
                }
                .fixedSize()
                .accessibilityLabel("已收录 \(effectiveMethodCount) 项方法")
        }
    }

    private var effectiveMethodCount: Int {
        guard case .loaded(let cards) = planSession.effectiveMethodsState else {
            return 0
        }
        return cards.count + planSession.hiddenEffectiveMethods.count
    }

    @ViewBuilder
    private var effectiveMethodsContent: some View {
        if planSession.showsError, let message = planSession.message {
            effectiveMethodStatePanel {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        switch planSession.effectiveMethodsState {
        case .idle, .loading:
            effectiveMethodStatePanel {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在整理已结束的微计划…")
                        .foregroundStyle(.secondary)
                }
            }
        case .demoMode:
            effectiveMethodStatePanel {
                Label("演示模式不读取真实方法记录", systemImage: "theatermasks")
                Text("切换回真实数据后，知衡会从本机 CareKit 历史重新整理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .empty:
            effectiveMethodStatePanel {
                Label("还没有可整理的方法", systemImage: "leaf")
                Text("完成或提前结束一个微计划后，这里会显示真实执行次数、完成率和数据质量。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            effectiveMethodStatePanel {
                Label("方法记录暂时无法读取", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                Text("不会用不完整记录生成方法结论，你可以稍后重试。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await refreshEffectiveMethods(force: true) }
                } label: {
                    Text("重新读取")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        case .loaded(let cards):
            if cards.isEmpty {
                effectiveMethodStatePanel {
                    Label("当前方法均已隐藏", systemImage: "eye.slash")
                    Text("历史记录仍完整保留，可在下方恢复显示。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            let filteredCards = effectiveMethodFilter.apply(to: cards)
            if !cards.isEmpty, filteredCards.isEmpty {
                effectiveMethodStatePanel {
                    Label(
                        "当前没有符合“\(effectiveMethodFilter.title)”的可判断方法",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    Text("缺少相应对照不会被当作没有变化。你可以查看全部方法，或在积累更多记录后再筛选。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        effectiveMethodFilter = .all
                    } label: {
                        Text("查看全部")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }
            ForEach(filteredCards) { card in
                effectiveMethodCard(card)
            }
            if !planSession.hiddenEffectiveMethods.isEmpty {
                effectiveMethodStatePanel {
                    DisclosureGroup("已隐藏的方法（\(planSession.hiddenEffectiveMethods.count)）") {
                        ForEach(planSession.hiddenEffectiveMethods) { card in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(card.title)
                                    Text("计划与评估历史仍保留")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("恢复显示") {
                                    planSession.setEffectiveMethodHidden(
                                        false,
                                        templateID: card.sourcePlanTemplateID
                                    )
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle(radius: 12))
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    private var notificationStatusColor: Color {
        switch notificationSession.state {
        case .authorized, .provisional, .ephemeral:
            .teal
        case .denied, .notRequested, .loading, .unavailable:
            .secondary
        }
    }

    private var effectiveMethodFilterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EffectiveMethodEvidenceFilter.allCases) { filter in
                    let isSelected = effectiveMethodFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            effectiveMethodFilter = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(
                                isSelected
                                    ? Color.teal
                                    : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .overlay {
                                if !isSelected {
                                    Capsule()
                                        .stroke(
                                            Color(uiColor: .separator).opacity(0.45),
                                            lineWidth: 0.8
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("筛选：\(filter.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func effectiveMethodCard(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(methodAccentColor(card.sourcePlanTemplateID))
                    .frame(width: 11, height: 11)
                    .padding(6)
                    .background(
                        methodAccentColor(card.sourcePlanTemplateID).opacity(0.09),
                        in: Circle()
                    )
                    .accessibilityHidden(true)
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(card.confidence.level.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(confidenceColor(card.confidence.level))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        confidenceColor(card.confidence.level).opacity(0.1),
                        in: Capsule()
                    )
            }
            .padding(.bottom, 15)

            Divider()

            effectiveMethodStats(card)
                .padding(.vertical, 18)

            Divider()

            effectiveMethodChangesPanel(card)
                .padding(.top, 14)

            Button {
                pendingMethodRestart = card
            } label: {
                ZStack {
                    Text(restartButtonTitle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Spacer()
                        if planSession.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .padding(.trailing, 12)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.teal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.teal.opacity(0.16), radius: 8, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .disabled(
                planSession.effectiveMethodRestartAvailability != .available
                    || planSession.isBusy
            )
            .opacity(
                planSession.effectiveMethodRestartAvailability == .available
                    && !planSession.isBusy ? 1 : 0.55
            )

            Button {
                pendingMethodHide = card
            } label: {
                Label("隐藏此方法", systemImage: "eye.slash")
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.teal.opacity(0.065))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .disabled(planSession.isBusy)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.38), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private func effectiveMethodStats(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            effectiveMethodExecutionStat(card)
            effectiveMethodCompletionStat(card)
            effectiveMethodQualityStat(card)
        }
    }

    private func effectiveMethodExecutionStat(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        methodStatTile(title: "执行次数") {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(card.executionCount.formatted())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func effectiveMethodCompletionStat(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        methodStatTile(title: "完成率") {
            if let completionRate = card.completion.completionRate {
                Text(completionRate, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .systemGray4).opacity(0.45))
                        Capsule()
                            .fill(Color.teal)
                            .frame(
                                width: proxy.size.width
                                    * min(max(completionRate, 0), 1)
                            )
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            } else {
                Text("未知")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func effectiveMethodQualityStat(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        methodStatTile(
            title: "数据质量",
            background: dataQualityColor(card.dataQuality.level).opacity(0.055)
        ) {
            Text(card.dataQuality.level.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(dataQualityColor(card.dataQuality.level))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func methodStatTile<Content: View>(
        title: String,
        background: Color = Color(uiColor: .systemGray6).opacity(0.55),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .top)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func effectiveMethodChangesPanel(
        _ card: EffectiveMethodCardPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            effectiveMethodObjectiveChange(card.objectiveChange)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)

            Divider()
                .padding(.horizontal, 16)

            effectiveMethodSubjectiveChange(card.subjectiveChange)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGray6).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func effectiveMethodStatePanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.8)
        }
    }

    private func methodAccentColor(_ templateID: MicroPlanTemplateID) -> Color {
        switch templateID {
        case .afternoonCaffeineCutoff, .earlierBedtime, .bedtimeBreathing,
                .consistentWakeTime:
            .cyan
        case .afternoonWalk, .movementBreak, .morningDaylight, .afterMealWalk,
                .gentleMobility:
            .mint
        case .reducedTrainingLoad:
            .orange
        }
    }

    @ViewBuilder
    private func effectiveMethodObjectiveChange(
        _ change: EffectiveMethodObjectiveChangePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("客观变化", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
            if change.metrics.isEmpty {
                Text(change.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(change.metrics, id: \.metric) { metric in
                    LabeledContent(metric.metric.title) {
                        Text(objectiveChangeText(metric))
                            .multilineTextAlignment(.trailing)
                    }
                    Text("计划前 \(metric.beforeValidDayCount) 天 · 计划期 \(metric.planValidDayCount) 天有效记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(change.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func effectiveMethodSubjectiveChange(
        _ change: EffectiveMethodSubjectiveChangePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("主观变化", systemImage: "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            if change.metrics.isEmpty {
                Text(change.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(change.metrics, id: \.dimension) { metric in
                    LabeledContent(metric.dimension.title) {
                        Text(subjectiveChangeText(metric))
                    }
                }
                Text("计划前 \(change.beforeRecordedDayCount) 天 · 计划期 \(change.planRecordedDayCount) 天有记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(change.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func objectiveChangeText(
        _ metric: MicroPlanEvaluationMetricFact
    ) -> String {
        if metric.metric == .sleepOnset {
            let minutes = Int((abs(metric.changeFromBefore) * 60).rounded())
            if minutes == 0 { return "与计划前相近" }
            return metric.changeFromBefore < 0
                ? "较计划前提前 \(minutes) 分钟"
                : "较计划前推迟 \(minutes) 分钟"
        }
        if abs(metric.changeFromBefore) < 0.000_1 { return "与计划前相近" }
        let direction = metric.changeFromBefore > 0 ? "增加" : "减少"
        return "较计划前\(direction) \(objectiveMetricValue(abs(metric.changeFromBefore), metric: metric.metric))"
    }

    private func objectiveMetricValue(
        _ value: Double,
        metric: MicroPlanTrendMetric
    ) -> String {
        switch metric {
        case .sleepOnset:
            return "\(Int((value * 60).rounded())) 分钟"
        case .sleepDuration, .standHours:
            return "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .stepCount:
            return "\(Int(value.rounded()).formatted()) 步"
        case .activeEnergy:
            return "\(Int(value.rounded())) 千卡"
        case .exerciseDuration:
            return "\(Int(value.rounded())) 分钟"
        case .heartRateVariability:
            return "\(Int(value.rounded())) 毫秒"
        case .walkingRunningDistance:
            return "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        }
    }

    private func subjectiveChangeText(
        _ metric: EffectiveMethodSubjectiveMetricFact
    ) -> String {
        let before = metric.beforeMedian.formatted(
            .number.precision(.fractionLength(1))
        )
        let plan = metric.planMedian.formatted(
            .number.precision(.fractionLength(1))
        )
        let difference = abs(metric.changeFromBefore).formatted(
            .number.precision(.fractionLength(1))
        )
        guard abs(metric.changeFromBefore) >= 0.05 else {
            return "\(before) → \(plan)（相近）"
        }
        return "\(before) → \(plan)（\(metric.changeFromBefore > 0 ? "高" : "低") \(difference) 分）"
    }

    @MainActor
    private func refreshEffectiveMethods(force: Bool = false) async {
        let request = effectiveMethodsRefreshRequest
        guard force || displayedEffectiveMethodsRequest != request else { return }
        await planSession.refreshEffectiveMethods(
            snapshot: healthSession.snapshot,
            dataMode: HealthDataMode(rawValue: healthDataModeRaw) ?? .live
        )
        guard request == effectiveMethodsRefreshRequest else { return }
        displayedEffectiveMethodsRequest = request
    }

    private var restartButtonTitle: String {
        switch planSession.effectiveMethodRestartAvailability {
        case .available: "再次验证这个方法"
        case .activePlanExists: "已有进行中的计划"
        case .checking: "正在确认计划状态…"
        case .unavailable: "暂时无法确认计划状态"
        case .demoMode: "演示模式不创建真实计划"
        }
    }

    private func restartEffectiveMethod(_ card: EffectiveMethodCardPresentation) {
        pendingMethodRestart = nil
        Task {
            let didStart = await planSession.restartEffectiveMethod(
                templateID: card.sourcePlanTemplateID,
                healthSnapshot: healthSession.snapshot,
                dataMode: HealthDataMode(rawValue: healthDataModeRaw) ?? .live
            )
            if didStart { onPlanStarted() }
        }
    }

    private func restartConfirmationMessage(
        for card: EffectiveMethodCardPresentation
    ) -> String {
        guard let template = MicroPlanTemplateLibrary.template(
            for: card.sourcePlanTemplateID
        ) else {
            return "当前模板暂时不可用，不会创建计划。"
        }
        return "会从今天开始一条新的独立计划："
            + template.taskTitle
            + "。旧计划和评估记录不会被修改。"
    }

    private func confidenceColor(_ level: EffectiveMethodConfidenceLevel) -> Color {
        switch level {
        case .fairlyStable: .teal
        case .possiblySuitable: .blue
        case .preliminaryObservation: .orange
        case .unclear: .secondary
        }
    }

    private func dataQualityColor(_ level: EffectiveMethodDataQualityLevel) -> Color {
        switch level {
        case .sufficient: .teal
        case .partial: .orange
        case .insufficient, .unavailable: .secondary
        }
    }

    private var dataStatusTitle: String {
        healthDataModeRaw == HealthDataMode.demo.rawValue
            ? "正在使用知衡演示数据"
            : readiness.title
    }

    private var dataStatusDetail: String {
        healthDataModeRaw == HealthDataMode.demo.rawValue
            ? "这是本地生成的模拟场景，不会读取 Apple Health。"
            : readiness.detail
    }

    private var dataStatusColor: Color {
        if healthDataModeRaw == HealthDataMode.demo.rawValue { return .orange }
        return readiness.canQueryHealthData ? .teal : .orange
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version ?? "1.0"
    }

    private func requestHealthAccess() {
        Task { @MainActor in
            isRequestingHealthAccess = true
            healthAccessErrorMessage = nil
            defer { isRequestingHealthAccess = false }
            do {
                try await healthSession.requestReadAccess(
                    for: Set(HealthMetricType.allCases)
                )
                showsHealthAccessExplanation = false
            } catch {
                healthAccessErrorMessage = "暂时无法打开系统授权，请稍后重试。"
            }
        }
    }

#if DEBUG
    private func saveDeepSeekKey() {
        do {
            try deepSeekKeyStore.save(deepSeekKeyDraft)
            deepSeekKeyDraft = ""
            hasDeepSeekKey = true
            deepSeekKeyMessage = "密钥已保存，可以前往“AI 助手”直接使用。"
        } catch {
            deepSeekKeyMessage = "密钥保存失败，请稍后重试。"
        }
    }

    private func deleteDeepSeekKey() {
        do {
            try deepSeekKeyStore.delete()
            deepSeekKeyDraft = ""
            hasDeepSeekKey = false
            deepSeekKeyMessage = "密钥已从这台 iPhone 删除。"
        } catch {
            deepSeekKeyMessage = "密钥删除失败，请稍后重试。"
        }
    }
#endif
}

#Preview {
    RootTabView()
}
