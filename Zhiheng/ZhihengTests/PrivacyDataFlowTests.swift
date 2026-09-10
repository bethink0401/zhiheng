import XCTest
@testable import Zhiheng

final class PrivacyDataFlowTests: XCTestCase {
    private var routes: [PrivacyDataFlowRoute] {
        PrivacyDataFlowCatalog.routes
    }

    private func route(_ id: String) throws -> PrivacyDataFlowRoute {
        try XCTUnwrap(routes.first { $0.id == id })
    }

    func testCatalogHasVersionedStableRouteOrderAndUniqueStepIDs() {
        XCTAssertEqual(PrivacyDataFlowCatalog.version, "s14-privacy-data-flow-v1")
        XCTAssertEqual(routes.map(\.id), [
            "health-analysis",
            "local-records",
            "ai-conversation",
            "local-notifications",
            "report-sharing"
        ])

        let stepIDs = routes.flatMap { $0.steps.map(\.id) }
        XCTAssertEqual(Set(stepIDs).count, stepIDs.count)
        XCTAssertFalse(routes.contains { $0.steps.isEmpty })
    }

    func testHealthAnalysisStaysInsideAppleAndOnDeviceBoundaries() throws {
        let health = try route("health-analysis")

        XCTAssertEqual(health.exitKind, .none)
        XCTAssertEqual(Set(health.steps.map(\.boundary)), [.appleSystem, .onDevice])
        XCTAssertTrue(health.sharedData.isEmpty)
        XCTAssertTrue(health.excludedData.joined().contains("原始 HealthKit 样本"))
    }

    func testLocalRecordsKeepSubjectiveAndCareKitFactsSeparatedOnDevice() throws {
        let local = try route("local-records")
        let text = local.steps.map { $0.title + $0.detail }.joined()

        XCTAssertEqual(local.exitKind, .none)
        XCTAssertEqual(Set(local.steps.map(\.boundary)), [.onDevice])
        XCTAssertTrue(text.contains("本机记录库"))
        XCTAssertTrue(text.contains("CareKitStore"))
        XCTAssertTrue(local.excludedData.joined().contains("底层记录 ID"))
    }

    func testAIFlowRequiresUserSendAndNamesExactOutboundCategories() throws {
        let ai = try route("ai-conversation")
        let shared = ai.sharedData.joined()

        XCTAssertEqual(ai.exitKind, .userInitiatedNetwork)
        XCTAssertEqual(ai.steps.first?.id, "ai-user-send")
        XCTAssertTrue(ai.steps.contains { $0.boundary == .secureNetwork })
        XCTAssertTrue(ai.steps.contains { ($0.title + $0.detail).contains("HTTPS") })
        XCTAssertTrue(shared.contains("本次问题"))
        XCTAssertTrue(shared.contains("最多 10 条"))
        XCTAssertTrue(shared.contains("聚合健康事实"))
    }

    func testAIFlowExplicitlyExcludesRawSamplesIdentityAndContextFreeText() throws {
        let excluded = try route("ai-conversation").excludedData.joined()

        XCTAssertTrue(excluded.contains("原始 HealthKit 样本数组"))
        XCTAssertTrue(excluded.contains("真实姓名"))
        XCTAssertTrue(excluded.contains("联系方式"))
        XCTAssertTrue(excluded.contains("底层记录 ID"))
        XCTAssertTrue(excluded.contains("生活事件备注"))
        XCTAssertTrue(excluded.contains("自定义名称"))
    }

    func testNotificationsAreLocalAndExposeOnlyTheNeutralPreview() throws {
        let notifications = try route("local-notifications")
        let visibleText = notifications.steps.map { $0.title + $0.detail }.joined()

        XCTAssertEqual(notifications.exitKind, .none)
        XCTAssertFalse(notifications.steps.contains { $0.boundary == .secureNetwork })
        XCTAssertTrue(visibleText.contains("知衡提醒 / 打开知衡查看"))
        XCTAssertTrue(notifications.excludedData.joined().contains("健康详情"))
    }

    func testReportFlowRequiresConfirmationAndEndsAtExternalDestination() throws {
        let report = try route("report-sharing")

        XCTAssertEqual(report.exitKind, .userConfirmedShare)
        XCTAssertTrue(report.steps.contains { $0.id == "report-confirmation" })
        XCTAssertEqual(report.steps.last?.boundary, .externalDestination)
        XCTAssertTrue(report.steps.contains { $0.detail.contains("排除备份") })
        XCTAssertTrue(report.steps.contains { $0.detail.contains("清理") })
        XCTAssertTrue(report.steps.last?.detail.contains("由该应用和你负责") == true)
    }

    func testReportFlowKeepsIdentityOptionalAndExcludesSensitiveSources() throws {
        let report = try route("report-sharing")
        let shared = report.sharedData.joined()
        let excluded = report.excludedData.joined()

        XCTAssertTrue(shared.contains("主动选择"))
        XCTAssertTrue(excluded.contains("手机号"))
        XCTAssertTrue(excluded.contains("身份证"))
        XCTAssertTrue(excluded.contains("原始健康样本"))
        XCTAssertTrue(excluded.contains("CareKit 反馈"))
        XCTAssertTrue(excluded.contains("AI 对话"))
    }

    func testUserControlsCoverPermissionsAndEveryLocalDeletionPath() {
        let ids = Set(PrivacyDataFlowCatalog.userControls.map(\.id))

        XCTAssertTrue(ids.isSuperset(of: [
            "permissions",
            "subjective-history",
            "plan-history",
            "conversation",
            "external-copy"
        ]))
    }

    func testPrivacyCopyIncludesBusinessAndMedicalBoundariesWithoutAbsoluteClaims() {
        let visibleText = ([
            PrivacyDataFlowCatalog.headline,
            PrivacyDataFlowCatalog.introduction
        ] + PrivacyDataFlowCatalog.commitments
            + routes.flatMap { route in
                [route.title, route.summary]
                    + route.steps.flatMap { [$0.title, $0.detail] }
                    + route.sharedData
                    + route.excludedData
            }
            + PrivacyDataFlowCatalog.userControls.flatMap { [$0.title, $0.detail] })
            .joined(separator: " ")

        XCTAssertTrue(visibleText.contains("不使用健康数据投放广告"))
        XCTAssertTrue(visibleText.contains("不使用健康数据训练基础模型"))
        XCTAssertTrue(visibleText.contains("不提供疾病诊断、处方或急救监护"))
        for forbiddenClaim in ["绝对安全", "永不泄露", "百分之百安全"] {
            XCTAssertFalse(visibleText.contains(forbiddenClaim))
        }
    }
}
