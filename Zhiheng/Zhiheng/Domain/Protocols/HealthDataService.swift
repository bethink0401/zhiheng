import Foundation

enum HealthDataServiceError: Error, Equatable, Sendable {
    case healthDataUnavailable
    case authorizationRequestFailed
    case invalidInterval
    case queryFailed
}

enum HealthDataMode: String, Codable, Equatable, Sendable {
    case live
    case demo
}

enum HealthMetricReadState: Equatable, Sendable {
    case accessNotRequested
    case healthDataUnavailable
    case noVisibleData
    case available([HealthMetricSample])
    case failed(HealthDataServiceError)
}

struct HealthDataSnapshot: Equatable, Sendable {
    let states: [HealthMetricType: HealthMetricReadState]

    subscript(metric: HealthMetricType) -> HealthMetricReadState? {
        states[metric]
    }

    /// HealthKit intentionally does not reveal read denial for an individual
    /// type. A mix of visible and non-visible metrics is therefore expressed
    /// as partial visibility, not claimed as partial authorization.
    var hasPartialVisibility: Bool {
        let visibleCount = states.values.filter { state in
            if case .available = state {
                return true
            }
            return false
        }.count
        return visibleCount > 0 && visibleCount < states.count
    }
}

protocol HealthAccessService: Sendable {
    func accessState() async -> HealthAccessState

    /// 请求读取所列指标。完成系统弹窗不代表用户同意了每一项；
    /// 后续必须根据各指标查询结果和覆盖率表达可用性。
    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws
}

protocol HealthDataService: HealthAccessService {
    var dataMode: HealthDataMode { get async }

    /// 空数组表示查询成功但时间范围内没有可见样本；失败必须抛出错误。
    /// 调用方不得用单个数值 0 替代空数组。
    func fetchSamples(
        for metric: HealthMetricType,
        interval: DateInterval
    ) async throws -> [HealthMetricSample]
}

extension HealthDataService {
    var dataMode: HealthDataMode {
        get async { .live }
    }

    func loadSnapshot(
        for metrics: Set<HealthMetricType>,
        interval: DateInterval
    ) async -> HealthDataSnapshot {
        let access = await accessState()
        switch access {
        case .notRequested:
            return HealthDataSnapshot(states: Dictionary(
                uniqueKeysWithValues: metrics.map { ($0, .accessNotRequested) }
            ))
        case .unavailable:
            return HealthDataSnapshot(states: Dictionary(
                uniqueKeysWithValues: metrics.map { ($0, .healthDataUnavailable) }
            ))
        case .requestCompleted:
            break
        }

        var states = [HealthMetricType: HealthMetricReadState]()
        for metric in metrics {
            do {
                let samples = try await fetchSamples(
                    for: metric,
                    interval: interval
                )
                states[metric] = samples.isEmpty
                    ? .noVisibleData
                    : .available(samples)
            } catch let error as HealthDataServiceError {
                states[metric] = .failed(error)
            } catch {
                states[metric] = .failed(.queryFailed)
            }
        }
        return HealthDataSnapshot(states: states)
    }
}
