import XCTest
@testable import Zhiheng

final class AppReadinessTests: XCTestCase {
    func testHealthDataRemainsUnavailableBeforeAuthorization() {
        let readiness = AppReadiness(healthAccess: .notRequested)

        XCTAssertFalse(readiness.canQueryHealthData)
        XCTAssertTrue(readiness.shouldOfferHealthConnection)
        XCTAssertEqual(readiness.title, "尚未连接 Apple Health")
        XCTAssertEqual(readiness.systemImage, "heart.slash")
    }

    func testCompletedRequestDoesNotClaimEveryMetricWasAuthorized() {
        let readiness = AppReadiness(healthAccess: .requestCompleted)

        XCTAssertTrue(readiness.canQueryHealthData)
        XCTAssertFalse(readiness.shouldOfferHealthConnection)
        XCTAssertEqual(readiness.title, "Apple Health 已连接")
        XCTAssertEqual(readiness.systemImage, "checkmark.circle.fill")
        XCTAssertTrue(readiness.detail.contains("没有样本不等于数值为零"))
        XCTAssertFalse(readiness.detail.contains("全部"))
    }

    func testUnavailableDeviceDoesNotOfferConnectionAction() {
        let readiness = AppReadiness(healthAccess: .unavailable)

        XCTAssertFalse(readiness.canQueryHealthData)
        XCTAssertFalse(readiness.shouldOfferHealthConnection)
        XCTAssertEqual(readiness.systemImage, "heart.slash")
    }
}
