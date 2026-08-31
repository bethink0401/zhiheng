import Combine
import Foundation

@MainActor
final class HealthDataSession: ObservableObject {
    @Published private(set) var accessState = HealthAccessState.notRequested
    @Published private(set) var snapshot: HealthDataSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var dataMode = HealthDataMode.live

    private let service: any HealthDataService
    private var hasLoadedCurrentAppEntry = false

    init(service: any HealthDataService) {
        self.service = service
    }

    func refreshOnceForCurrentAppEntry() async {
        guard !hasLoadedCurrentAppEntry else { return }
        hasLoadedCurrentAppEntry = true
        await refresh()
    }

    func markAppAsExited() {
        hasLoadedCurrentAppEntry = false
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        dataMode = await service.dataMode
        accessState = await service.accessState()
        guard AppReadiness(healthAccess: accessState).canQueryHealthData else {
            snapshot = nil
            return
        }
        guard let interval = HealthHistoryWindow.last90Days(endingAt: Date()) else {
            return
        }
        snapshot = await service.loadSnapshot(
            for: Set(HealthMetricType.allCases),
            interval: interval
        )
    }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {
        try await service.requestReadAccess(for: metrics)
        await refresh()
    }
}
