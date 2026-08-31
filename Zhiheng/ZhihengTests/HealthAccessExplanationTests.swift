import XCTest
@testable import Zhiheng

final class HealthAccessExplanationTests: XCTestCase {
    func testExplanationCoversTheDashboardHealthCategories() {
        XCTAssertEqual(
            HealthAccessPurpose.allCases,
            [.activity, .sleep, .heart, .vitals]
        )
    }

    func testEveryPurposeHasDistinctUserFacingContent() {
        let purposes = HealthAccessPurpose.allCases

        XCTAssertEqual(Set(purposes.map(\.title)).count, purposes.count)
        XCTAssertEqual(Set(purposes.map(\.detail)).count, purposes.count)
        XCTAssertEqual(Set(purposes.map(\.systemImage)).count, purposes.count)
    }

    func testHeartPurposeStatesTheNonDiagnosticBoundary() {
        XCTAssertTrue(HealthAccessPurpose.heart.detail.contains("不用于诊断疾病"))
    }
}
