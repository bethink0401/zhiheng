import XCTest
@testable import Zhiheng

final class AppContentStateTests: XCTestCase {
    func testEveryStateHasDistinctUserFacingIdentity() {
        let states = AppContentState.allCases

        XCTAssertEqual(states.count, 4)
        XCTAssertEqual(Set(states.map(\.title)).count, states.count)
        XCTAssertEqual(Set(states.map(\.systemImage)).count, states.count)
    }

    func testLoadingIsTheOnlyStateWithoutAnAction() {
        XCTAssertNil(AppContentState.loading.actionTitle)
        XCTAssertNotNil(AppContentState.healthAccessNotRequested.actionTitle)
        XCTAssertNotNil(AppContentState.noData.actionTitle)
        XCTAssertNotNil(AppContentState.failed.actionTitle)
    }

    func testFailureNeverMasqueradesAsAZeroMeasurement() {
        XCTAssertTrue(AppContentState.failed.message.contains("不表示数值为零"))
    }

    func testHealthAccessCopyRequiresActiveUserChoice() {
        XCTAssertTrue(AppContentState.healthAccessNotRequested.message.contains("主动授权"))
    }

    func testHealthMetricPresentationUsesLatestSampleSourceAndTime() throws {
        let earlier = try makeSample(
            endDate: Date(timeIntervalSince1970: 1_700_000_000),
            sourceName: "较早来源"
        )
        let latest = try makeSample(
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            sourceName: "最新来源"
        )
        let presentation = HealthMetricStatusPresentation(
            metric: .stepCount,
            state: .available([latest, earlier])
        )

        XCTAssertEqual(presentation.title, "步数")
        XCTAssertEqual(presentation.statusText, "已发现 2 条记录")
        XCTAssertEqual(presentation.latestSample, latest)
        XCTAssertEqual(presentation.latestSample?.source.sourceName, "最新来源")
    }

    func testNoVisibleDataExplainsPermissionAmbiguityWithoutShowingZero() {
        let presentation = HealthMetricStatusPresentation(
            metric: .sleepDuration,
            state: .noVisibleData
        )

        XCTAssertTrue(presentation.statusText.contains("没有可见数据"))
        XCTAssertTrue(presentation.fallbackDetail?.contains("未允许读取") == true)
        XCTAssertFalse(presentation.statusText.contains("数值为零"))
    }

    func testLiveTodayHierarchyKeepsDataStatusOutOfToday() {
        XCTAssertEqual(
            TodayInformationHierarchy.sections(
                dataMode: .live,
                canQueryHealthData: true
            ),
            [.keyMetrics, .productExplanation, .privacy]
        )
    }

    func testDemoNoticeIsFirstAndUnavailableDataDoesNotShowEmptyMetrics() {
        XCTAssertEqual(
            TodayInformationHierarchy.sections(
                dataMode: .demo,
                canQueryHealthData: false
            ),
            [.demoNotice, .productExplanation, .privacy]
        )
    }

    func testQualityCopyAllowsObservationAtFourOfSevenDays() {
        let presentation = HealthDataQualityPresentation(report: qualityReport(
            validDays: 4,
            longestGap: 2
        ))

        XCTAssertEqual(presentation.title, "数据覆盖可用于短期观察")
        XCTAssertTrue(presentation.detail.contains("有效 4 天"))
        XCTAssertTrue(presentation.detail.contains("57%"))
        XCTAssertTrue(presentation.detail.contains("最长断档 2 天"))
    }

    func testQualityCopyDoesNotCallInsufficientCoverageAHealthProblem() {
        let presentation = HealthDataQualityPresentation(report: qualityReport(
            validDays: 3,
            longestGap: 4
        ))

        XCTAssertEqual(presentation.title, "数据还不够连续，先继续记录")
        XCTAssertFalse(presentation.title.contains("异常"))
        XCTAssertFalse(presentation.detail.contains("未佩戴"))
    }

    func testQualityCopySurfacesSourceChangeAsDataContext() {
        let report = HealthDataQualityReport(
            metric: .stepCount,
            expectedDayCount: 7,
            validDayCount: 7,
            coverageRatio: 1,
            latestSampleDate: Date(),
            longestMissingDayStreak: 0,
            sourceNames: ["来源 A", "来源 B"]
        )

        XCTAssertTrue(
            HealthDataQualityPresentation(report: report)
                .detail.contains("数据来源有变化")
        )
    }

    func testNinetyDayCoverageCopyUsesEffectiveDaysWithoutHealthConclusion() {
        let report = HealthDataQualityReport(
            metric: .sleepDuration,
            expectedDayCount: 90,
            validDayCount: 63,
            coverageRatio: 0.7,
            latestSampleDate: nil,
            longestMissingDayStreak: 4,
            sourceNames: ["来源 A"]
        )

        let detail = HealthDataCoveragePresentation(report: report).detail

        XCTAssertEqual(detail, "近 90 天有效 63 天（70%）")
        XCTAssertFalse(detail.contains("健康"))
        XCTAssertFalse(detail.contains("异常"))
    }

    private func qualityReport(
        validDays: Int,
        longestGap: Int
    ) -> HealthDataQualityReport {
        HealthDataQualityReport(
            metric: .sleepDuration,
            expectedDayCount: 7,
            validDayCount: validDays,
            coverageRatio: Double(validDays) / 7,
            latestSampleDate: nil,
            longestMissingDayStreak: longestGap,
            sourceNames: ["来源 A"]
        )
    }

    private func makeSample(
        endDate: Date,
        sourceName: String
    ) throws -> HealthMetricSample {
        try HealthMetricSample(
            id: UUID(),
            metricType: .stepCount,
            startDate: endDate.addingTimeInterval(-60),
            endDate: endDate,
            value: 10,
            unit: .count,
            source: HealthMetricSource(
                sourceName: sourceName,
                bundleIdentifier: nil,
                deviceName: nil
            )
        )
    }
}
