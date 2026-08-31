import XCTest
@testable import Zhiheng

final class NavigationModelTests: XCTestCase {
    func testFirstVersionHasExactlyFiveDistinctTabs() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertEqual(Set(AppTab.allCases.map(\.title)).count, 5)
        XCTAssertEqual(Set(AppTab.allCases.map(\.systemImage)).count, 5)
    }

    func testCoreJourneyTabOrderRemainsStable() {
        XCTAssertEqual(
            AppTab.allCases,
            [.today, .insights, .assistant, .plans, .profile]
        )
    }

    func testHealthDataModeHasStablePersistedValues() {
        XCTAssertEqual(HealthDataMode.live.rawValue, "live")
        XCTAssertEqual(HealthDataMode.demo.rawValue, "demo")
        XCTAssertEqual(HealthDataMode(rawValue: "demo"), .demo)
    }
}
