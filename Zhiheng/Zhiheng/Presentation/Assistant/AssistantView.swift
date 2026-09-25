import SwiftUI

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [AssistantChatMessage]
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var streamingMessageID: UUID?
    @Published private(set) var streamingRevision = 0

    let suggestedQuestions = [
        "结合我的记录，最近睡眠怎么样？",
        "最近活动量和我的平时相比如何？",
        "我的 HRV 记录能说明什么？",
        "根据近期状态，我适合尝试什么微计划？"
    ]

    private let service: any AIService
    private let conversationStore: AssistantConversationStore
    private var activeTask: Task<Void, Never>?
    private var lastFailedQuestion: String?

    init(
        service: any AIService,
        conversationStore: AssistantConversationStore = AssistantConversationStore()
    ) {
        self.service = service
        self.conversationStore = conversationStore
        do {
            messages = try conversationStore.load()
            errorMessage = nil
        } catch {
            messages = []
            errorMessage = "无法恢复之前的对话，本次对话仍可继续。"
        }
#if DEBUG
        if (ProcessInfo.processInfo.arguments.contains("--assistant-seed-plan-preview")
            || ProcessInfo.processInfo.arguments.contains("--demo-showcase-recording")),
           messages.isEmpty {
            messages = Self.planCandidatePreviewMessages
        }
#endif
    }

#if DEBUG
    private static let planCandidatePreviewMessages = [
        AssistantChatMessage(
            role: .user,
            text: "结合我最近的记录，给我一个容易开始的微计划。"
        ),
        AssistantChatMessage(
            role: .assistant,
            text: "最近几天你的睡眠时长比个人基线略短，可以先从一个负担较小的作息调整开始。",
            response: HealthAIResponse(
                summary: "最近几天你的睡眠时长比个人基线略短，可以先从一个负担较小的作息调整开始。",
                observedFacts: ["近期睡眠时长低于个人基线"],
                possibleFactors: [],
                uncertainty: "",
                followUpQuestion: nil,
                suggestedAction: HealthAISuggestedAction(
                    templateID: .earlierBedtime,
                    rationale: "这个计划只要求每天比平时提前 30 分钟上床，连续观察 5 天，行动明确，也不会一下子改变太多生活安排。完成后可以结合睡眠时长、第二天的精力感受和实际完成情况，再看看它是否适合你当前的节奏。"
                ),
                safetyLevel: .normal,
                usedMetrics: [],
                supportiveClosing: "不用追求一次做到完美，先完成今晚这一个小动作就很好。"
            )
        ),
    ]

    func runInteractiveShowcase() {
        Task { @MainActor in
            messages.removeAll()
            draft = ""
            try? await Task.sleep(for: .seconds(1))
            let textToType = "结合我最近的记录，给我一个容易开始的微计划。"
            for char in textToType {
                draft.append(char)
                try? await Task.sleep(for: .milliseconds(75))
            }
            try? await Task.sleep(for: .milliseconds(900))
            let userMessage = AssistantChatMessage(
                role: .user,
                text: textToType
            )
            messages.append(userMessage)
            draft = ""
            isSending = true
            try? await Task.sleep(for: .seconds(2))
            isSending = false
            let firstAIResponse = AssistantChatMessage(
                role: .assistant,
                text: "根据近 7 天的数据，你的 HRV 较 28 天个人基线偏低 15%，同时今天记录了较高的主观压力和加班情境。这说明身体处于持续消耗状态，恢复窗口不足。",
                response: HealthAIResponse(
                    summary: "根据近 7 天的数据，你的 HRV 较 28 天个人基线偏低 15%，同时今天记录了较高的主观压力和加班情境。这说明身体处于持续消耗状态，恢复窗口不足。",
                    observedFacts: ["近7天HRV低于个人稳健基线15%", "今日记录压力偏高(4/5)", "生活事件：加班到深夜"],
                    possibleFactors: ["连续高压加班", "深度睡眠窗口压缩"],
                    uncertainty: "短期指标波动需结合实际休息情况综合观察",
                    followUpQuestion: "想再了解一下：我注意到你最近有连续加班记录，昨晚的入睡时间是否比平时推迟了？",
                    suggestedAction: nil,
                    safetyLevel: .normal,
                    usedMetrics: [.heartRateVariability, .restingHeartRate],
                    supportiveClosing: "请在下方告诉我你昨晚的入睡情况。"
                )
            )
            messages.append(firstAIResponse)
            try? await Task.sleep(for: .seconds(8))
            let userFollowUpAnswer = AssistantChatMessage(
                role: .user,
                text: "确实比平时晚睡了差不多一个小时，早上起来感觉头很沉。"
            )
            messages.append(userFollowUpAnswer)
            isSending = true
            try? await Task.sleep(for: .seconds(2))
            isSending = false
            let finalAIResponse = AssistantChatMessage(
                role: .assistant,
                text: "入睡推迟会直接影响深度睡眠阶段的心率恢复与自主神经调节。本地安全校验已通过（非医疗诊断）。建议先从一个负担较小的作息微调开始，观察身体状态是否逐步好转。",
                response: HealthAIResponse(
                    summary: "入睡推迟会直接影响深度睡眠阶段的心率恢复与自主神经调节。建议先从一个负担较小的作息微调开始，观察身体状态是否逐步好转。",
                    observedFacts: ["昨晚入睡推迟约1小时", "晨起主观精力偏低"],
                    possibleFactors: ["晚睡导致慢波睡眠减少"],
                    uncertainty: "单次作息微调主要观察反应，不作治疗承诺",
                    followUpQuestion: nil,
                    suggestedAction: HealthAISuggestedAction(
                        templateID: .earlierBedtime,
                        rationale: "每天比平时提前 30 分钟上床准备，连续观察 5 天，行动明确且负担轻。完成后结合睡眠时长、第二天的精力感受和完成率，评估是否适合你的节奏。"
                    ),
                    safetyLevel: .normal,
                    usedMetrics: [.heartRateVariability, .sleepDuration],
                    supportiveClosing: "不用追求一次做到完美，先尝试今晚提前放下手机、放松躺下。"
                )
            )
            messages.append(finalAIResponse)
        }
    }
#endif

    func submit(
        snapshot: HealthDataSnapshot?,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        supplementalFacts: HealthFactSupplementalFacts? = nil
    ) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        draft = ""
        send(
            question: question,
            snapshot: snapshot,
            dataMode: dataMode,
            referenceDate: referenceDate,
            supplementalFacts: supplementalFacts
        )
    }

    func askSuggestedQuestion(
        _ question: String,
        snapshot: HealthDataSnapshot?,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        supplementalFacts: HealthFactSupplementalFacts? = nil
    ) {
        guard !isSending else { return }
        send(
            question: question,
            snapshot: snapshot,
            dataMode: dataMode,
            referenceDate: referenceDate,
            supplementalFacts: supplementalFacts
        )
    }

    func retry(
        snapshot: HealthDataSnapshot?,
        dataMode: HealthDataMode,
        referenceDate: Date = Date(),
        supplementalFacts: HealthFactSupplementalFacts? = nil
    ) {
        guard let question = lastFailedQuestion, !isSending else { return }
        send(
            question: question,
            snapshot: snapshot,
            dataMode: dataMode,
            referenceDate: referenceDate,
            supplementalFacts: supplementalFacts,
            appendsUserMessage: false
        )
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        discardStreamingMessage()
        isSending = false
        errorMessage = "已停止本次回答。"
    }

    func clearConversation() {
        activeTask?.cancel()
        activeTask = nil
        messages.removeAll()
        draft = ""
        isSending = false
        streamingMessageID = nil
        streamingRevision = 0
        errorMessage = nil
        lastFailedQuestion = nil
        do {
            try conversationStore.delete()
        } catch {
            errorMessage = "本地对话删除失败，请稍后重试。"
        }
    }

    private func send(
        question: String,
        snapshot: HealthDataSnapshot?,
        dataMode: HealthDataMode,
        referenceDate: Date,
        supplementalFacts: HealthFactSupplementalFacts?,
        appendsUserMessage: Bool = true
    ) {
        errorMessage = nil
        lastFailedQuestion = nil
        guard question.count <= 2_000 else {
            errorMessage = "问题最多 2000 个字符，请缩短后再发送。"
            return
        }
        if appendsUserMessage {
            append(.init(role: .user, text: question))
        }

        switch HealthAISafetyRuleEngine.evaluate(question) {
        case let .respondLocally(response):
            append(.init(
                role: .assistant,
                text: response.summary,
                response: response
            ))
            return
        case .allowModelRequest:
            break
        }

        let factPack = snapshot.map {
            HealthFactPackBuilder.build(
                snapshot: $0,
                dataMode: dataMode,
                referenceDate: referenceDate,
                supplementalFacts: supplementalFacts
            )
        } ?? HealthFactPackBuilder.empty(
            dataMode: dataMode,
            referenceDate: referenceDate,
            supplementalFacts: supplementalFacts
        )
        let request = HealthAIRequest(
            question: question,
            factPack: factPack,
            recentConversation: recentConversation(excluding: question)
        )

        isSending = true
        activeTask = Task { [weak self, service] in
            do {
                var didComplete = false
                for try await event in service.streamResponse(to: request) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case let .textDelta(delta):
                        self?.appendStreamingDelta(delta)
                    case let .completed(response):
                        self?.completeStreamingResponse(response)
                        didComplete = true
                    }
                }
                guard didComplete else {
                    throw HealthAIServiceError.invalidResponse
                }
                self?.isSending = false
                self?.activeTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.discardStreamingMessage()
                let fallback = HealthAILocalFallbackBuilder.makeResponse(
                    from: request.factPack
                )
                self?.append(.init(
                    role: .assistant,
                    text: fallback.summary,
                    response: fallback
                ))
                self?.lastFailedQuestion = question
                self?.errorMessage = Self.userMessage(for: error)
                self?.isSending = false
                self?.activeTask = nil
            }
        }
    }

    private func recentConversation(excluding question: String) -> [HealthAIConversationTurn] {
        var history = messages
        if history.last?.role == .user, history.last?.text == question {
            history.removeLast()
        }
        return history.suffix(10).map { message in
            HealthAIConversationTurn(
                role: message.role == .user ? .user : .assistant,
                content: message.text
            )
        }
    }

    private func append(_ message: AssistantChatMessage) {
        messages.append(message)
        do {
            try conversationStore.save(messages)
        } catch {
            errorMessage = "回答已显示，但这次对话无法保存在本机。"
        }
    }

    private func appendStreamingDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let streamingMessageID,
           let index = messages.firstIndex(where: { $0.id == streamingMessageID }) {
            let current = messages[index]
            messages[index] = AssistantChatMessage(
                id: current.id,
                role: .assistant,
                text: current.text + delta
            )
        } else {
            let message = AssistantChatMessage(role: .assistant, text: delta)
            streamingMessageID = message.id
            messages.append(message)
        }
        streamingRevision += 1
    }

    private func completeStreamingResponse(_ response: HealthAIResponse) {
        if let streamingMessageID,
           let index = messages.firstIndex(where: { $0.id == streamingMessageID }) {
            messages[index] = AssistantChatMessage(
                id: streamingMessageID,
                role: .assistant,
                text: response.summary,
                response: response
            )
        } else {
            messages.append(AssistantChatMessage(
                role: .assistant,
                text: response.summary,
                response: response
            ))
        }
        streamingMessageID = nil
        streamingRevision += 1
        do {
            try conversationStore.save(messages)
        } catch {
            errorMessage = "回答已显示，但这次对话无法保存在本机。"
        }
    }

    private func discardStreamingMessage() {
        guard let streamingMessageID else { return }
        messages.removeAll { $0.id == streamingMessageID }
        self.streamingMessageID = nil
        streamingRevision += 1
        try? conversationStore.save(messages)
    }

    private static func userMessage(for error: Error) -> String {
        switch error as? HealthAIServiceError {
        case .notConfigured:
            "AI 服务尚未配置。个人调试请从“今日”右上角的设置保存 DeepSeek 密钥。"
        case .timedOut:
            "AI 回答超时了，你可以稍后重试。"
        case .cancelled:
            "已停止本次回答。"
        case .invalidRequest, .invalidResponse:
            "AI 返回的内容未通过安全校验，已停止展示。"
        case let .serviceRejected(statusCode):
            "AI 服务暂时无法完成请求（状态码 \(statusCode)）。"
        case .networkUnavailable, .none:
            "暂时无法连接 AI 服务。请检查网络后重试。"
        }
    }
}

struct AssistantView: View {
    @ObservedObject var healthSession: HealthDataSession
    @ObservedObject var planSession: MicroPlanSession
    @ObservedObject var checkInCoordinator: DailyCheckInCoordinator
    @StateObject private var viewModel: AssistantViewModel
    let contextLoader: AssistantFactContextLoader
    let includesSyntheticDemoFacts: Bool
    let onPlanStarted: () -> Void
    @FocusState private var isComposerFocused: Bool
    @State private var didStartDebugSmokeQuestion = false

    init(
        healthSession: HealthDataSession,
        planSession: MicroPlanSession,
        checkInCoordinator: DailyCheckInCoordinator,
        contextLoader: AssistantFactContextLoader,
        includesSyntheticDemoFacts: Bool = false,
        onPlanStarted: @escaping () -> Void,
        service: any AIService = PersonalAIService(),
        conversationScope: HealthDataMode = .live
    ) {
        self.healthSession = healthSession
        self.planSession = planSession
        self.checkInCoordinator = checkInCoordinator
        self.contextLoader = contextLoader
        self.includesSyntheticDemoFacts = includesSyntheticDemoFacts
        self.onPlanStarted = onPlanStarted
        _viewModel = StateObject(
            wrappedValue: AssistantViewModel(
                service: service,
                conversationStore: AssistantConversationStore(
                    scope: conversationScope.rawValue
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        assistantHeader
                        if viewModel.messages.isEmpty {
                            welcome
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }
                        }
                        if viewModel.isSending,
                           viewModel.streamingMessageID == nil {
                            loadingBubble
                        }
                        if let errorMessage = viewModel.errorMessage {
                            errorCard(errorMessage)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.streamingRevision) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .onAppear {
                runDebugSmokeQuestionIfNeeded()
            }
            .onChange(of: healthSession.snapshot) { _, _ in
                runDebugSmokeQuestionIfNeeded()
            }
            .task {
                await planSession.refreshIfNeeded(
                    dataMode: healthSession.dataMode
                )
            }
        }
    }

    private var assistantHeader: some View {
        HStack(alignment: .center) {
            Text("AI 助手")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Spacer()
            if !viewModel.messages.isEmpty {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .foregroundStyle(.teal)
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
                .accessibilityLabel("开始新对话")
                .accessibilityHint("删除当前保存在本机的对话")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runDebugSmokeQuestionIfNeeded() {
#if DEBUG
        guard !didStartDebugSmokeQuestion,
              healthSession.snapshot != nil
        else { return }
        if ProcessInfo.processInfo.arguments.contains("--assistant-smoke-question") {
            didStartDebugSmokeQuestion = true
            sendSuggestedQuestion("我最近睡得怎么样？")
        } else if ProcessInfo.processInfo.arguments.contains("--demo-showcase-recording") {
            didStartDebugSmokeQuestion = true
            viewModel.runInteractiveShowcase()
        }
#endif
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "heart.text.sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.teal)
                Text("今天想了解什么？")
                    .font(.title.bold())
                Text("可以询问一般健康问题，也可以结合你授权的健康趋势、今日与近 7 天感受和生活事件（包括你填写的备注与自定义事件名称），以及当前或最近一次微计划记录继续聊。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(viewModel.suggestedQuestions, id: \.self) { question in
                Button {
                    sendSuggestedQuestion(question)
                } label: {
                    HStack {
                        Text(question)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up")
                            .font(.caption.bold())
                            .foregroundStyle(.teal)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func messageView(_ message: AssistantChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 44)
            }
            VStack(alignment: .leading, spacing: 14) {
                assistantText(
                    message.text,
                    parsesMarkdown: message.role == .assistant && message.response != nil
                )
                    .font(.body)
                    .lineSpacing(message.role == .assistant ? 4 : 0)
                    .textSelection(.enabled)
                if let response = message.response,
                   message.role == .assistant {
                    if let supportiveClosing = response.supportiveClosing?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ), !supportiveClosing.isEmpty {
                        Text(supportiveClosing)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    if let action = response.suggestedAction {
                        AssistantMicroPlanCandidateCard(
                            action: action,
                            hasActivePlan: planSession.activePlan != nil,
                            isBusy: planSession.isBusy
                        ) {
                            Task { @MainActor in
                                if await planSession.start(
                                    from: action,
                                    healthSnapshot: healthSession.snapshot,
                                    dataMode: healthSession.dataMode
                                ) {
                                    isComposerFocused = false
                                    onPlanStarted()
                                }
                            }
                        }
                    }
                    AssistantResponseDetailsView(response: response)
                    if let followUp = response.followUpQuestion {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(.teal)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("想再了解一下")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(followUp)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Text("可以在下方输入框里告诉我")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("请在下方输入框回答这个问题")
                    }
                }
            }
            .padding(14)
            .background(
                message.role == .user
                    ? Color.teal
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(
                color: message.role == .assistant ? .black.opacity(0.035) : .clear,
                radius: 8,
                y: 3
            )
            .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant {
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func assistantText(_ content: String, parsesMarkdown: Bool) -> Text {
        guard parsesMarkdown else { return Text(content) }

        let hasExplicitEmphasis = content.contains("**") || content.contains("__")
        if hasExplicitEmphasis,
           let attributed = try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            return Text(attributed)
        }

        guard let punctuationIndex = content.firstIndex(where: {
            "。！？!?\n".contains($0)
        }) else {
            return Text(content).bold()
        }
        let sentenceEnd = content.index(after: punctuationIndex)
        return Text(String(content[..<sentenceEnd])).bold()
            + Text(String(content[sentenceEnd...]))
    }

    private var loadingBubble: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在读取聚合事实并生成回答…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .accessibilityLabel("AI 正在生成回答")
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                Button("重试") {
                    retryLastQuestion()
                }
                .font(.subheadline.bold())
                .disabled(viewModel.isSending)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var composer: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                composerRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        } else {
            composerRow
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("询问你的近期健康记录", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .modifier(AssistantInputGlassModifier())
                .submitLabel(.send)
                .onSubmit {
                    submitDraft()
                }

            Button {
                if viewModel.isSending {
                    viewModel.stop()
                } else {
                    submitDraft()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: viewModel.isSending ? "stop.fill" : "arrow.up")
                        .font(.subheadline.bold())
                    Text(viewModel.isSending ? "停止" : "发送")
                        .font(.subheadline.bold())
                }
                .frame(minWidth: 86, minHeight: 52)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modifier(AssistantSendGlassModifier())
            .foregroundStyle(.white)
            .accessibilityLabel(viewModel.isSending ? "停止回答" : "发送问题")
            .disabled(!viewModel.isSending && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitDraft() {
        let referenceDate = Date()
        viewModel.submit(
            snapshot: healthSession.snapshot,
            dataMode: healthSession.dataMode,
            referenceDate: referenceDate,
            supplementalFacts: makeSupplementalFacts(referenceDate: referenceDate)
        )
    }

    private func sendSuggestedQuestion(_ question: String) {
        let referenceDate = Date()
        viewModel.askSuggestedQuestion(
            question,
            snapshot: healthSession.snapshot,
            dataMode: healthSession.dataMode,
            referenceDate: referenceDate,
            supplementalFacts: makeSupplementalFacts(referenceDate: referenceDate)
        )
    }

    private func retryLastQuestion() {
        let referenceDate = Date()
        viewModel.retry(
            snapshot: healthSession.snapshot,
            dataMode: healthSession.dataMode,
            referenceDate: referenceDate,
            supplementalFacts: makeSupplementalFacts(referenceDate: referenceDate)
        )
    }

    private func makeSupplementalFacts(
        referenceDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> HealthFactSupplementalFacts {
        let recentContextState: AssistantFactContextLoadState?
        do {
            let factSet = try InsightFactGenerator.generate(
                snapshot: healthSession.snapshot,
                loadedInterval: healthSession.snapshotInterval,
                access: healthSession.accessState,
                dataMode: healthSession.dataMode,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
            recentContextState = contextLoader.load(for: factSet)
        } catch {
            recentContextState = .failed(.invalidFactWindow)
        }
        return HealthFactSupplementalFactsBuilder.build(
            dataMode: healthSession.dataMode,
            referenceDate: referenceDate,
            timeZone: timeZone,
            todayCheckIn: checkInCoordinator.session.savedCheckIn,
            didLoadTodayCheckIn: checkInCoordinator.session.didLoadRecord,
            todayContextEvents: checkInCoordinator.contextEvents.events,
            didLoadTodayContextEvents: checkInCoordinator.contextEvents.didLoadRecords,
            recentContextState: recentContextState,
            plan: planSession.displayedPlan,
            progress: planSession.progress,
            todayOutcome: planSession.todayOutcomeState,
            outcomeRecords: planSession.outcomeRecords,
            didLoadPlan: planSession.hasLoadedStateForCurrentMode,
            includesSyntheticDemoFacts: includesSyntheticDemoFacts
        )
    }
}

private struct AssistantResponseDetailsView: View {
    let response: HealthAIResponse
    @State private var isExpanded = false

    private var hasDetails: Bool {
        !response.observedFacts.isEmpty
            || !response.possibleFactors.isEmpty
            || !response.usedMetrics.isEmpty
            || !(response.usedFactKinds ?? []).isEmpty
    }

    var body: some View {
        if hasDetails {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if !response.observedFacts.isEmpty {
                        detailSection("使用的事实", rows: response.observedFacts)
                    }
                    if !response.possibleFactors.isEmpty {
                        detailSection("可能因素", rows: response.possibleFactors)
                    }
                    if !response.usedMetrics.isEmpty {
                        Text("依据：" + response.usedMetrics.map(\.assistantDisplayName).joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let usedFactKinds = response.usedFactKinds,
                       !usedFactKinds.isEmpty {
                        Text("事实类别：" + usedFactKinds.map(\.displayName).joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)
            } label: {
                Label(
                    "使用的事实（\(response.observedFacts.count)）",
                    systemImage: "doc.text.magnifyingglass"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
            .accessibilityHint(isExpanded ? "收起回答依据" : "展开回答依据")
        }
    }

    private func detailSection(_ title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.self) { row in
                Text("• \(row)")
                    .font(.subheadline)
            }
        }
    }
}

private struct AssistantMicroPlanCandidateCard: View {
    let action: HealthAISuggestedAction
    let hasActivePlan: Bool
    let isBusy: Bool
    let onStart: () -> Void

    private var template: MicroPlanTemplate? {
        MicroPlanTemplateLibrary.template(for: action.templateID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("微计划候选", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
            Text(action.templateID.title)
                .font(.headline)

            if let template {
                Text(template.taskTitle)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    planFact(
                        "连续 \(template.durationDays) 天",
                        systemImage: "calendar"
                    )
                    planFact(
                        formattedTime(template.scheduledTime),
                        systemImage: "clock"
                    )
                }
            }

            Button(action: onStart) {
                HStack {
                    Text(hasActivePlan ? "已有进行中的计划" : "确认并开始 5 天计划")
                    Spacer()
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    hasActivePlan ? Color.secondary : Color.teal,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(hasActivePlan || isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.teal.opacity(0.18), lineWidth: 0.8)
        )
    }

    private func planFact(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.teal.opacity(0.1), in: Capsule())
    }

    private func formattedTime(_ time: ScheduledLocalTime) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

}

private struct AssistantInputGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.8))
        }
    }
}

private struct AssistantSendGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.teal).interactive(), in: Capsule())
        } else {
            content
                .background(.teal.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.8))
        }
    }
}
