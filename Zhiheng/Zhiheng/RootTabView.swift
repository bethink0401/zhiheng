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
        )
        let startsOnProfile = ProcessInfo.processInfo.arguments.contains(
            "--profile-preview"
        )
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
        let baselineStore: any PlanBaselineStore
        do {
            baselineStore = try SwiftDataPlanBaselineStore()
        } catch {
            baselineStore = UnavailablePlanBaselineStore()
        }
        _microPlanSession = StateObject(
            wrappedValue: MicroPlanSession(
                service: CareKitPlanStore(onDiskStoreNamed: planStoreName),
                baselineStore: baselineStore
            )
        )
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
        .task(id: healthDataMode) {
            await activeHealthSession.refreshOnceForCurrentAppEntry()
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
                await microPlanSession.refresh()
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
                    await microPlanSession.refresh()
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
                Task {
                    await activeHealthSession.refreshOnceForCurrentAppEntry()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            if healthDataMode == .demo, isDemoAvailable {
                TodayView(healthSession: demoHealthSession)
                    .id(HealthDataMode.demo.rawValue)
            } else {
                TodayView(healthSession: liveHealthSession)
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
                healthDataModeRaw: $healthDataModeRaw,
                isDemoAvailable: isDemoAvailable,
                healthSession: activeHealthSession
            )
        }
    }
}

struct ProfileSettingsView: View {
    @Binding var healthDataModeRaw: String
    let isDemoAvailable: Bool
    @ObservedObject var healthSession: HealthDataSession
    @State private var showsHealthAccessExplanation = false
    @State private var isRequestingHealthAccess = false
    @State private var healthAccessErrorMessage: String?
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

    var body: some View {
        NavigationStack {
            Form {
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

                Section("隐私与安全") {
                    Label("Apple Health 始终为只读访问", systemImage: "heart.text.square")
                    Label("原始健康样本不会直接发送给 AI", systemImage: "lock.shield")
                    Label("AI 只使用回答所需的聚合事实", systemImage: "checkmark.shield")
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
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showsHealthAccessExplanation) {
                HealthAccessExplanationView(
                    isRequesting: isRequestingHealthAccess,
                    requestErrorMessage: healthAccessErrorMessage
                ) { requestHealthAccess() }
            }
#if DEBUG
            .onAppear {
                hasDeepSeekKey = deepSeekKeyStore.load() != nil
            }
#endif
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
