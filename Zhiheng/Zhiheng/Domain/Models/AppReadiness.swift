enum HealthAccessState: Equatable, Sendable {
    case notRequested
    case unavailable
    case requestCompleted
}

struct AppReadiness: Equatable, Sendable {
    let healthAccess: HealthAccessState

    var canQueryHealthData: Bool {
        healthAccess == .requestCompleted
    }

    var shouldOfferHealthConnection: Bool {
        healthAccess == .notRequested
    }

    var systemImage: String {
        switch healthAccess {
        case .notRequested, .unavailable:
            "heart.slash"
        case .requestCompleted:
            "checkmark.circle.fill"
        }
    }

    var title: String {
        switch healthAccess {
        case .notRequested:
            "尚未连接 Apple Health"
        case .unavailable:
            "此设备暂不支持健康数据"
        case .requestCompleted:
            "Apple Health 已连接"
        }
    }

    var detail: String {
        switch healthAccess {
        case .notRequested:
            "完成引导后，你可以逐项选择愿意分享的数据。"
        case .unavailable:
            "仍可使用主观记录和模拟数据体验核心功能。"
        case .requestCompleted:
            "已完成数据选择，知衡会读取当前可见的数据；某项没有样本不等于数值为零。"
        }
    }
}
