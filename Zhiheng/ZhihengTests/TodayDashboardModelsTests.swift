import Foundation
import XCTest
@testable import Zhiheng

final class TodayDashboardModelsTests: XCTestCase {
    func testDateWindowContainsSevenCalendarDaysEndingOnReferenceDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 15
        )))

        let days = TodayDashboardDateWindow.sevenDays(
            endingAt: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, calendar.startOfDay(for: referenceDate))
        XCTAssertEqual(
            calendar.dateComponents([.day], from: days[0], to: days[6]).day,
            6
        )
    }

    func testFiveGoalCompletionUsesEachGoalEqually() {
        let result = TodayGoalProgressCalculator.calculate(
            goals: .standard,
            actuals: TodayGoalActuals(values: [
                .steps: 4_000,
                .sleep: 4,
                .activeEnergy: 250,
                .exercise: 15,
                .stand: 6
            ])
        )

        guard case let .available(progress) = result else {
            return XCTFail("Expected progress")
        }
        XCTAssertEqual(progress.items.count, 5)
        XCTAssertEqual(progress.percentage, 50)
        XCTAssertEqual(progress.completedGoalCount, 0)
    }

    func testOverachievementCannotHideAnUnmetGoal() {
        let result = TodayGoalProgressCalculator.calculate(
            goals: .standard,
            actuals: TodayGoalActuals(values: [
                .steps: 80_000,
                .sleep: 0
            ])
        )

        guard case let .available(progress) = result else {
            return XCTFail("Expected progress")
        }
        XCTAssertEqual(progress.percentage, 50)
        XCTAssertEqual(progress.completedGoalCount, 1)
    }

    func testMissingMetricsAreExcludedInsteadOfBecomingZero() {
        let result = TodayGoalProgressCalculator.calculate(
            goals: .standard,
            actuals: TodayGoalActuals(values: [.steps: 8_000])
        )

        guard case let .available(progress) = result else {
            return XCTFail("Expected progress")
        }
        XCTAssertEqual(progress.items.map(\.kind), [.steps])
        XCTAssertEqual(progress.percentage, 100)
        XCTAssertEqual(
            TodayGoalProgressCalculator.calculate(
                goals: .standard,
                actuals: TodayGoalActuals()
            ),
            .unavailable
        )
    }

    func testEncouragementChangesDeterministicallyWithProgress() {
        let result = TodayGoalProgressCalculator.calculate(
            goals: .standard,
            actuals: TodayGoalActuals(values: [
                .steps: 4_000,
                .sleep: 4,
                .activeEnergy: 250,
                .exercise: 15,
                .stand: 6
            ])
        )

        XCTAssertEqual(
            TodayActivityEncouragementFactory.make(from: result, isToday: true).level,
            .progressing
        )
        XCTAssertEqual(
            TodayActivityEncouragementFactory.make(from: .unavailable, isToday: true).level,
            .unavailable
        )
    }

    func testLayoutCanHideRestoreAndReorderOnlyWithinASection() {
        var layout = TodayDashboardLayout.standard

        layout.setVisible(false, module: .sleep)
        XCTAssertFalse(layout.modules(in: .daily).contains(.sleep))
        layout.setVisible(true, module: .sleep)
        XCTAssertEqual(layout.modules(in: .daily).last, .sleep)

        layout.move(module: .sleep, before: .walking)
        XCTAssertEqual(layout.modules(in: .daily).first, .sleep)
        let bodyBefore = layout.modules(in: .body)
        layout.move(module: .sleep, before: .loadReference)
        XCTAssertEqual(layout.modules(in: .body), bodyBefore)
    }

    func testLayoutSanitizesDuplicatesAndWrongSectionModules() {
        let layout = TodayDashboardLayout(modulesBySection: [
            .body: [.loadReference, .walking, .loadReference]
        ])

        XCTAssertEqual(layout.modules(in: .body), [.loadReference])
        XCTAssertTrue(layout.modules(in: .daily).isEmpty)
    }
}
