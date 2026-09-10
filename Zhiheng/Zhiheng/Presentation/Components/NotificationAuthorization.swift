import Combine
import SwiftUI
import UserNotifications

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var isEnabled: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unknown:
            false
        }
    }
}

enum NotificationPermissionViewState: Equatable, Sendable {
    case loading
    case notRequested
    case denied
    case authorized
    case provisional
    case ephemeral
    case unavailable

    init(status: NotificationAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notRequested
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        case .unknown: self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .loading: "正在读取通知状态…"
        case .notRequested: "通知尚未开启"
        case .denied: "通知已在系统中关闭"
        case .authorized: "通知已开启"
        case .provisional: "通知将安静送达"
        case .ephemeral: "通知已临时开启"
        case .unavailable: "暂时无法确认通知状态"
        }
    }

    var detail: String {
        switch self {
        case .loading:
            "知衡不会在读取状态时请求权限。"
        case .notRequested:
            "先查看提醒用途，再由你决定是否显示系统授权选项。"
        case .denied:
            "知衡不会反复请求。需要时可在 iPhone 系统设置中重新开启。"
        case .authorized:
            "系统允许知衡发送通知；只有你开启的具体提醒才会安排，可在应用内或 iPhone 系统设置中关闭。"
        case .provisional:
            "提醒会先以安静方式进入通知中心，不播放声音。"
        case .ephemeral:
            "系统只提供了临时通知权限，之后可能需要重新确认。"
        case .unavailable:
            "不会在状态未知时发送或假装已开启提醒，请稍后重试。"
        }
    }

    var systemImage: String {
        switch self {
        case .loading: "bell"
        case .notRequested: "bell.badge"
        case .denied: "bell.slash"
        case .authorized: "bell.fill"
        case .provisional: "bell.and.waves.left.and.right"
        case .ephemeral: "bell.badge.fill"
        case .unavailable: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }

    var canPresentExplanation: Bool { self == .notRequested }
    var canRetryStatus: Bool { self == .unavailable }
}

enum NotificationReminderPurpose: String, CaseIterable, Identifiable, Sendable {
    case dailyCheckIn
    case microPlan
    case lowFrequencyTrend

    var id: Self { self }

    var title: String {
        switch self {
        case .dailyCheckIn: "每日感受"
        case .microPlan: "微计划"
        case .lowFrequencyTrend: "低频趋势"
        }
    }

    var detail: String {
        switch self {
        case .dailyCheckIn:
            "在你选择的时间提醒记录精力、压力和身体感受。"
        case .microPlan:
            "提醒完成或跳过当前微计划中的当天行动。"
        case .lowFrequencyTrend:
            "仅在数据质量足够且有值得查看的近期变化时提醒，不把缺失数据当作异常。"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyCheckIn: "checkmark.circle"
        case .microPlan: "checklist"
        case .lowFrequencyTrend: "chart.line.uptrend.xyaxis"
        }
    }
}

enum NotificationPermissionCopy {
    static let introduction =
        "知衡只会发送你选择开启的提醒。授权本身不会读取新的健康数据，也不会立即安排任何提醒。"
    static let lockScreenPrivacy =
        "锁屏默认只显示“知衡提醒 / 打开知衡查看”，不显示提醒类型、健康数值、症状、计划反馈或其他敏感细节。"
    static let frequency =
        "常规提醒默认每天最多一条，并会遵守你之后设置的安静时间和频率。"
    static let safetyBoundary =
        "知衡不是急救或持续医疗监护工具，通知不能替代紧急求助和专业医疗建议。"
    static let control =
        "你可以暂不开启，也可以稍后在 iPhone 系统设置中关闭通知。知衡内的提醒开关会在相应功能启用时提供。"
}

protocol NotificationAuthorizationClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async throws -> NotificationAuthorizationStatus
}

actor SystemNotificationAuthorizationClient: NotificationAuthorizationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(
                    returning: Self.map(settings.authorizationStatus)
                )
            }
        }
    }

    func requestAuthorization() async throws -> NotificationAuthorizationStatus {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return await authorizationStatus()
    }

    private nonisolated static func map(
        _ status: UNAuthorizationStatus
    ) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unknown
        }
    }
}

@MainActor
final class NotificationAuthorizationSession: ObservableObject {
    @Published private(set) var state = NotificationPermissionViewState.loading
    @Published private(set) var authorizationStatus = NotificationAuthorizationStatus.unknown
    @Published private(set) var showsExplanation = false
    @Published private(set) var isRequesting = false
    @Published private(set) var requestErrorMessage: String?

    private let client: any NotificationAuthorizationClient

    init(
        client: any NotificationAuthorizationClient =
            SystemNotificationAuthorizationClient()
    ) {
        self.client = client
    }

    func refresh() async {
        guard !isRequesting else { return }
        let status = await client.authorizationStatus()
        authorizationStatus = status
        state = NotificationPermissionViewState(status: status)
    }

    func beginRequest() {
        guard state.canPresentExplanation, !isRequesting else { return }
        requestErrorMessage = nil
        showsExplanation = true
    }

    func cancelExplanation() {
        guard !isRequesting else { return }
        requestErrorMessage = nil
        showsExplanation = false
    }

    func confirmExplanation() async {
        guard showsExplanation, state.canPresentExplanation, !isRequesting else {
            return
        }
        isRequesting = true
        requestErrorMessage = nil
        defer { isRequesting = false }

        do {
            let status = try await client.requestAuthorization()
            guard status != .notDetermined, status != .unknown else {
                requestErrorMessage = "系统暂时没有返回明确的通知权限状态，请稍后重试。"
                return
            }
            authorizationStatus = status
            state = NotificationPermissionViewState(status: status)
            showsExplanation = false
        } catch {
            requestErrorMessage = "暂时无法请求通知权限，请稍后重试。"
        }
    }
}

struct NotificationPermissionExplanationView: View {
    let isRequesting: Bool
    let requestErrorMessage: String?
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    purposeList
                    privacyCard
                    Text(NotificationPermissionCopy.control)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .padding(.bottom, 96)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("开启知衡提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不开启", action: onCancel)
                        .disabled(isRequesting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
            }
            .interactiveDismissDisabled(isRequesting)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 42))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            Text("先了解用途，再决定是否授权")
                .font(.title2.weight(.bold))
            Text(NotificationPermissionCopy.introduction)
                .foregroundStyle(.secondary)
        }
    }

    private var purposeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通知可用于")
                .font(.headline)
            ForEach(NotificationReminderPurpose.allCases) { purpose in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: purpose.systemImage)
                        .frame(width: 28, height: 28)
                        .font(.title3)
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(purpose.title)
                            .font(.subheadline.weight(.semibold))
                        Text(purpose.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("频率、隐私与安全", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(.teal)
            commitment(NotificationPermissionCopy.lockScreenPrivacy)
            commitment(NotificationPermissionCopy.frequency)
            commitment(NotificationPermissionCopy.safetyBoundary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color.teal.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func commitment(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.primary)
    }

    private var continueButton: some View {
        VStack(spacing: 8) {
            if let requestErrorMessage {
                Label(requestErrorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onContinue) {
                if isRequesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("允许知衡发送通知")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
            .disabled(isRequesting)
            Text("点击后才会显示 iPhone 的系统授权选项。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    NotificationPermissionExplanationView(
        isRequesting: false,
        requestErrorMessage: nil,
        onCancel: {},
        onContinue: {}
    )
}
