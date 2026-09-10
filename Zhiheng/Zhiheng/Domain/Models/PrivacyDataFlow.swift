import Foundation

enum PrivacyDataBoundary: String, CaseIterable, Sendable {
    case appleSystem
    case onDevice
    case secureNetwork
    case externalDestination

    var title: String {
        switch self {
        case .appleSystem: "Apple 系统"
        case .onDevice: "知衡本机"
        case .secureNetwork: "加密网络"
        case .externalDestination: "外部接收方"
        }
    }
}

enum PrivacyDataExitKind: String, Sendable {
    case none
    case userInitiatedNetwork
    case userConfirmedShare

    var title: String {
        switch self {
        case .none: "不离开本机"
        case .userInitiatedNetwork: "发送问题时联网"
        case .userConfirmedShare: "确认分享后交给所选应用"
        }
    }
}

struct PrivacyDataFlowStep: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let boundary: PrivacyDataBoundary
}

struct PrivacyDataFlowRoute: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let exitKind: PrivacyDataExitKind
    let steps: [PrivacyDataFlowStep]
    let sharedData: [String]
    let excludedData: [String]
}

struct PrivacyUserControl: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

enum PrivacyDataFlowCatalog {
    static let version = "s14-privacy-data-flow-v1"

    static let headline = "你的数据先在 iPhone 上处理"
    static let introduction =
        "知衡只读取你允许的 Apple Health 数据。趋势、数据质量、个人基线和本地洞察先在设备上计算；只有你主动发送 AI 问题或确认分享报告时，相关的最小内容才会离开知衡。"

    static let commitments = [
        "不使用健康数据投放广告或出售用户画像。",
        "不使用健康数据训练基础模型。",
        "当前版本没有账号、健康数据云同步或后台持续医疗监护。",
        "知衡是健康管理与生活方式改善工具，不提供疾病诊断、处方或急救监护。"
    ]

    static let routes: [PrivacyDataFlowRoute] = [
        PrivacyDataFlowRoute(
            id: "health-analysis",
            title: "Apple Health 到健康洞察",
            summary: "原始健康记录只在读取和本机计算过程中使用，不作为健康事实包上传。",
            systemImage: "heart.text.square",
            exitKind: .none,
            steps: [
                .init(
                    id: "health-apple-health",
                    title: "Apple Health",
                    detail: "保存 Apple Watch 与 iPhone 写入的记录；你决定允许知衡读取哪些类型。",
                    systemImage: "heart.fill",
                    boundary: .appleSystem
                ),
                .init(
                    id: "health-read-only",
                    title: "只读 HealthKit 边界",
                    detail: "按当前功能需要读取，不修改或删除 Apple Health 中的数据。",
                    systemImage: "lock.open.display",
                    boundary: .onDevice
                ),
                .init(
                    id: "health-normalize",
                    title: "本机清洗与质量判断",
                    detail: "在内存中处理单位、时区、来源、缺失和重复，再计算有效日与覆盖率。",
                    systemImage: "slider.horizontal.3",
                    boundary: .onDevice
                ),
                .init(
                    id: "health-insight",
                    title: "个人基线、趋势与页面",
                    detail: "本机程序生成可追溯的聚合结果，供今日、洞悉、计划评估和摘要使用。",
                    systemImage: "chart.line.uptrend.xyaxis",
                    boundary: .onDevice
                )
            ],
            sharedData: [],
            excludedData: ["不会把原始 HealthKit 样本作为健康事实包发送给 AI"]
        ),
        PrivacyDataFlowRoute(
            id: "local-records",
            title: "感受、生活情境与微计划",
            summary: "三类记录各有明确的本机事实来源，不建立云端副本，也不把计划完成状态重复保存。",
            systemImage: "iphone.gen3",
            exitKind: .none,
            steps: [
                .init(
                    id: "local-user-input",
                    title: "你主动填写或执行",
                    detail: "今日感受、生活情境、计划完成或跳过都由你主动记录。",
                    systemImage: "hand.tap",
                    boundary: .onDevice
                ),
                .init(
                    id: "local-stores",
                    title: "分开保存在本机",
                    detail: "感受与情境进入本机记录库；计划、日程和执行结果由 CareKitStore 保存。",
                    systemImage: "externaldrive.fill",
                    boundary: .onDevice
                ),
                .init(
                    id: "local-compare",
                    title: "本机对照与评估",
                    detail: "规则把客观聚合、主观感受与执行事实并列比较，不把同期变化写成因果。",
                    systemImage: "scale.3d",
                    boundary: .onDevice
                )
            ],
            sharedData: [],
            excludedData: ["默认不上传签到备注、自定义事件名称、CareKit 反馈或底层记录 ID"]
        ),
        PrivacyDataFlowRoute(
            id: "ai-conversation",
            title: "AI 对话",
            summary: "只有你点击发送后才联网；危险问题会先由本机安全规则处理。",
            systemImage: "bubble.left.and.text.bubble.right",
            exitKind: .userInitiatedNetwork,
            steps: [
                .init(
                    id: "ai-user-send",
                    title: "你主动发送问题",
                    detail: "发送前不会因打开页面而自动发起 AI 请求。",
                    systemImage: "paperplane.fill",
                    boundary: .onDevice
                ),
                .init(
                    id: "ai-fact-pack",
                    title: "本机构建最小事实包",
                    detail: "只整理回答所需的当前值、时间范围、数据质量与个人基线等聚合事实。",
                    systemImage: "shippingbox.fill",
                    boundary: .onDevice
                ),
                .init(
                    id: "ai-service",
                    title: "经 HTTPS 请求 AI 服务",
                    detail: "正式版本经知衡代理转发；个人 Debug 模式可选择用本机 Keychain 密钥直连。",
                    systemImage: "network",
                    boundary: .secureNetwork
                ),
                .init(
                    id: "ai-validated-response",
                    title: "校验后显示并保存在本机",
                    detail: "完整回答通过结构、事实引用和安全检查后，才进入受系统文件保护的当前对话。",
                    systemImage: "checkmark.shield.fill",
                    boundary: .onDevice
                )
            ],
            sharedData: [
                "本次问题和最近最多 10 条对话消息",
                "回答所需的聚合健康事实与数据不足状态",
                "主动请求计划 AI 解读时的聚合评估和受限反馈"
            ],
            excludedData: [
                "原始 HealthKit 样本数组",
                "真实姓名、联系方式、精确地址和底层记录 ID",
                "生活事件备注与自定义名称"
            ]
        ),
        PrivacyDataFlowRoute(
            id: "local-notifications",
            title: "本地提醒",
            summary: "提醒选择和调度都在设备上完成，AI 不参与；三类锁屏内容完全相同。",
            systemImage: "bell.badge",
            exitKind: .none,
            steps: [
                .init(
                    id: "notification-local-rules",
                    title: "本机规则选择是否提醒",
                    detail: "只读取所需的本地授权、偏好和聚合状态，并遵守安静时间与频率。",
                    systemImage: "switch.2",
                    boundary: .onDevice
                ),
                .init(
                    id: "notification-system",
                    title: "iOS 安排本地通知",
                    detail: "锁屏统一显示“知衡提醒 / 打开知衡查看”，不携带健康详情或自由文本。",
                    systemImage: "lock.iphone",
                    boundary: .appleSystem
                )
            ],
            sharedData: [],
            excludedData: ["通知负载不包含健康详情、提醒类别、指标、数值、症状、评分、计划行动或反馈"]
        ),
        PrivacyDataFlowRoute(
            id: "report-sharing",
            title: "7 天摘要与系统分享",
            summary: "预览留在内存；只有你确认后才生成临时 PDF，并交给你选择的接收应用。",
            systemImage: "square.and.arrow.up",
            exitKind: .userConfirmedShare,
            steps: [
                .init(
                    id: "report-memory-summary",
                    title: "本机内存摘要",
                    detail: "复用四项客观聚合、三项主观汇总、结构化情境和一个本地建议。",
                    systemImage: "doc.text.magnifyingglass",
                    boundary: .onDevice
                ),
                .init(
                    id: "report-confirmation",
                    title: "你查看并确认隐私提示",
                    detail: "取消不会生成文件；可选姓名默认关闭且只用于本次导出。",
                    systemImage: "checkmark.circle",
                    boundary: .onDevice
                ),
                .init(
                    id: "report-temporary-file",
                    title: "受保护的临时 PDF",
                    detail: "文件位于独立临时目录、排除备份，分享结束、取消或离开页面后清理。",
                    systemImage: "doc.badge.clock",
                    boundary: .onDevice
                ),
                .init(
                    id: "report-external-copy",
                    title: "系统分享与外部副本",
                    detail: "你选择的应用接收副本后，由该应用和你负责保存、转发与删除。",
                    systemImage: "arrow.up.right.square",
                    boundary: .externalDestination
                )
            ],
            sharedData: ["你确认导出的聚合健康摘要 PDF", "本次主动选择时才会加入的姓名"],
            excludedData: [
                "手机号、身份证、备注、自定义事件名称和底层记录 ID",
                "原始健康样本、CareKit 反馈和 AI 对话"
            ]
        )
    ]

    static let userControls: [PrivacyUserControl] = [
        .init(
            id: "permissions",
            title: "权限由你控制",
            detail: "可在 iPhone 系统设置中调整 Apple Health 与通知权限；知衡不会用提示代替系统选择。",
            systemImage: "person.badge.key"
        ),
        .init(
            id: "subjective-history",
            title: "修改或删除个人记录",
            detail: "今日状态历史支持修改和逐条删除感受与生活情境。",
            systemImage: "pencil.and.list.clipboard"
        ),
        .init(
            id: "plan-history",
            title: "删除单个计划历史",
            detail: "微计划历史可删除对应 Care Plan、任务、执行结果和本地分析基线。",
            systemImage: "checklist"
        ),
        .init(
            id: "conversation",
            title: "清空本机 AI 对话",
            detail: "AI 助手中的“开始新对话”会删除当前模式保存在本机的会话文件。",
            systemImage: "bubble.left.and.exclamationmark.bubble.right"
        ),
        .init(
            id: "external-copy",
            title: "留意外部副本",
            detail: "报告交给其他应用后，知衡无法替你删除接收方保存或转发的副本。",
            systemImage: "exclamationmark.shield"
        )
    ]
}
