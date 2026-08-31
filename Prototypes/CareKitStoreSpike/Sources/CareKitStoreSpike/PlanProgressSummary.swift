import CareKitStore

/// S02 技术样例：把 CareKit 的每日进度映射成知衡可测试的计划摘要。
///
/// 正式产品还需要区分跳过、提前结束和数据质量；本样例只验证
/// CareKit 4.1 当前 API 与知衡适配层的边界。
public struct PlanProgressSummary: Equatable, Sendable {
    public let scheduledDayCount: Int
    public let completedFraction: Double?
    public let missingEventDayCount: Int

    public init(adherence: [OCKAdherence]) {
        var progressValues: [Double] = []
        var missingEventDayCount = 0

        for value in adherence {
            switch value {
            case .progress(let fraction):
                progressValues.append(fraction)
            case .noEvents:
                missingEventDayCount += 1
            case .noTasks:
                continue
            }
        }

        scheduledDayCount = progressValues.count + missingEventDayCount
        self.missingEventDayCount = missingEventDayCount
        completedFraction = progressValues.isEmpty
            ? nil
            : progressValues.reduce(0, +) / Double(progressValues.count)
    }
}

