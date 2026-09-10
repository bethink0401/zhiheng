import Foundation
import XCTest
@testable import Zhiheng

@MainActor
final class HealthDataSessionTests: XCTestCase {
    func testAutomaticRefreshRunsOnlyOnceDuringOneAppEntry() async {
        let service = HealthDataSessionServiceSpy()
        let session = HealthDataSession(service: service)

        await session.refreshOnceForCurrentAppEntry()
        await session.refreshOnceForCurrentAppEntry()

        let fetchCount = await service.fetchCount(for: .stepCount)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNotNil(session.snapshotInterval)
        XCTAssertNotNil(session.snapshot)
    }

    func testNextAppEntryCanAutomaticallyRefreshAgain() async {
        let service = HealthDataSessionServiceSpy()
        let session = HealthDataSession(service: service)

        await session.refreshOnceForCurrentAppEntry()
        session.markAppAsExited()
        await session.refreshOnceForCurrentAppEntry()

        let fetchCount = await service.fetchCount(for: .stepCount)
        XCTAssertEqual(fetchCount, 2)
    }

    func testManualRefreshCanUpdateWithinTheSameAppEntry() async {
        let service = HealthDataSessionServiceSpy()
        let session = HealthDataSession(service: service)

        await session.refreshOnceForCurrentAppEntry()
        await session.refresh()

        let fetchCount = await service.fetchCount(for: .stepCount)
        XCTAssertEqual(fetchCount, 2)
    }

    func testSnapshotAndItsWindowAreClearedTogetherWhenAccessUnavailable() async {
        let service = HealthDataSessionServiceSpy()
        let session = HealthDataSession(service: service)
        await session.refresh()
        XCTAssertNotNil(session.snapshotInterval)
        await service.setAccess(.unavailable)
        await session.refresh()
        XCTAssertNil(session.snapshot)
        XCTAssertNil(session.snapshotInterval)
    }
}

private actor HealthDataSessionServiceSpy: HealthDataService {
    private var fetchCounts = [HealthMetricType: Int]()
    private var access = HealthAccessState.requestCompleted

    var dataMode: HealthDataMode { .live }

    func accessState() async -> HealthAccessState { access }
    func setAccess(_ value: HealthAccessState) { access = value }

    func requestReadAccess(for metrics: Set<HealthMetricType>) async throws {}

    func fetchSamples(
        for metric: HealthMetricType,
        interval: DateInterval
    ) async throws -> [HealthMetricSample] {
        fetchCounts[metric, default: 0] += 1
        return []
    }

    func fetchCount(for metric: HealthMetricType) -> Int {
        fetchCounts[metric, default: 0]
    }
}
