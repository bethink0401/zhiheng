import XCTest
@testable import Zhiheng

@MainActor
final class NotificationDeliverySettingsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testDefaultsAreEnabledDailyWithOvernightQuietHours() {
        XCTAssertEqual(
            NotificationDeliverySettings(),
            NotificationDeliverySettings(
                isEnabled: true,
                frequency: .daily,
                quietHours: .init(
                    isEnabled: true,
                    startHour: 22,
                    startMinute: 0,
                    endHour: 8,
                    endMinute: 0
                )
            )
        )
    }

    func testInvalidQuietTimeComponentsAreRepaired() {
        XCTAssertEqual(
            NotificationQuietHours(
                startHour: 24,
                startMinute: -1,
                endHour: 80,
                endMinute: 60
            ),
            NotificationQuietHours(
                startHour: 22,
                startMinute: 0,
                endHour: 8,
                endMinute: 0
            )
        )
    }

    func testOvernightQuietHoursUseInclusiveStartAndExclusiveEnd() {
        let settings = NotificationQuietHours(
            startHour: 22,
            endHour: 8
        )

        XCTAssertFalse(isQuiet(date(2026, 9, 6, 21, 59), settings: settings))
        XCTAssertTrue(isQuiet(date(2026, 9, 6, 22, 0), settings: settings))
        XCTAssertTrue(isQuiet(date(2026, 9, 7, 7, 59), settings: settings))
        XCTAssertFalse(isQuiet(date(2026, 9, 7, 8, 0), settings: settings))
    }

    func testSameQuietStartAndEndDoesNotSuppressWholeDay() {
        let settings = NotificationQuietHours(
            startHour: 8,
            endHour: 8
        )
        XCTAssertFalse(isQuiet(date(2026, 9, 6, 8, 0), settings: settings))
        XCTAssertFalse(isQuiet(date(2026, 9, 6, 22, 0), settings: settings))
    }

    func testGlobalDisableRejectsAllCandidates() {
        let candidates = dailyCandidates(dayOffsets: [0, 1, 2])
        let result = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: candidates,
            reservingHigherPriorityIdentifiers: [],
            settings: .init(isEnabled: false),
            timeZone: utc
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testQuietCandidatesAreSkippedInsteadOfMoved() {
        let candidates = [
            candidate(day: 6, hour: 7),
            candidate(day: 7, hour: 9),
            candidate(day: 8, hour: 23)
        ]
        let result = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: candidates,
            reservingHigherPriorityIdentifiers: [],
            settings: .init(),
            timeZone: utc
        )

        XCTAssertEqual(result, [candidates[1].identifier])
    }

    func testEveryOtherDayFrequencyUsesSharedMinimumSpacing() {
        let candidates = dailyCandidates(dayOffsets: [0, 1, 2, 3, 4])
        let result = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: candidates,
            reservingHigherPriorityIdentifiers: [],
            settings: .init(
                frequency: .everyOtherDay,
                quietHours: .init(isEnabled: false)
            ),
            timeZone: utc
        )

        XCTAssertEqual(
            result,
            Set([candidates[0], candidates[2], candidates[4]].map(\.identifier))
        )
    }

    func testWeeklyFrequencyKeepsCandidatesSevenDaysApart() {
        let candidates = dailyCandidates(dayOffsets: Array(0...8))
        let result = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: candidates,
            reservingHigherPriorityIdentifiers: [],
            settings: .init(
                frequency: .weekly,
                quietHours: .init(isEnabled: false)
            ),
            timeZone: utc
        )

        XCTAssertEqual(result, Set([candidates[0], candidates[7]].map(\.identifier)))
    }

    func testHigherPriorityReservationBlocksNearbyLowerPriorityCandidate() {
        let candidates = dailyCandidates(dayOffsets: [0, 1, 2, 3])
        let result = NotificationDeliveryPolicy.filteredIdentifiers(
            candidates: candidates,
            reservingHigherPriorityIdentifiers: [
                MicroPlanReminderPolicy.identifierPrefix + "2026-09-07"
            ],
            settings: .init(
                frequency: .everyOtherDay,
                quietHours: .init(isEnabled: false)
            ),
            timeZone: utc
        )

        XCTAssertEqual(result, [candidates[3].identifier])
    }

    func testHigherPriorityCandidateRemovesLowerRequestsWithinFrequencyWindow() {
        let pending = [
            DailyCheckInReminderPolicy.identifierPrefix + "2026-09-06",
            LowFrequencyTrendReminderPolicy.identifierPrefix + "2026-09-07",
            DailyCheckInReminderPolicy.identifierPrefix + "2026-09-08",
            "unrelated.request"
        ]
        let scheduled = [NotificationDeliveryCandidate(
            identifier: MicroPlanReminderPolicy.identifierPrefix + "2026-09-07",
            fireDate: date(2026, 9, 7, 18, 0)
        )]

        let result = NotificationDeliveryPolicy.lowerPriorityIdentifiersToRemove(
            from: pending,
            matchingPrefixes: [
                LowFrequencyTrendReminderPolicy.identifierPrefix,
                DailyCheckInReminderPolicy.identifierPrefix
            ],
            for: scheduled,
            settings: .init(
                frequency: .everyOtherDay,
                quietHours: .init(isEnabled: false)
            ),
            timeZone: utc
        )

        XCTAssertEqual(Set(result), Set(pending.prefix(3)))
    }

    func testStorePersistsSettingsWithoutClearingExistingReminderPreferences() async throws {
        let preferences = try makePreferences()
        preferences.set(true, forKey: DailyCheckInReminderSession.enabledKey)
        preferences.set(["existing-hash"], forKey: LowFrequencyTrendReminderSession.handledSemanticKeysKey)
        let store = NotificationDeliverySettingsStore(preferences: preferences)
        let updated = NotificationDeliverySettings(
            isEnabled: false,
            frequency: .weekly,
            quietHours: .init(
                isEnabled: true,
                startHour: 21,
                startMinute: 30,
                endHour: 7,
                endMinute: 15
            )
        )

        store.replace(with: updated)
        let restored = NotificationDeliverySettingsStore.load(from: preferences)

        XCTAssertEqual(restored, updated)
        XCTAssertTrue(preferences.bool(forKey: DailyCheckInReminderSession.enabledKey))
        XCTAssertEqual(
            preferences.stringArray(
                forKey: LowFrequencyTrendReminderSession.handledSemanticKeysKey
            ),
            ["existing-hash"]
        )
    }

    func testSessionUpdatesTimesAndFrequencyThroughSharedStore() async throws {
        let preferences = try makePreferences()
        let store = NotificationDeliverySettingsStore(preferences: preferences)
        let session = NotificationDeliverySettingsSession(
            store: store,
            initialSettings: NotificationDeliverySettingsStore.load(from: preferences)
        )

        await session.setFrequency(.everyOtherDay)
        await session.updateQuietStart(from: date(2026, 9, 6, 23, 20), timeZone: utc)
        await session.updateQuietEnd(from: date(2026, 9, 7, 6, 40), timeZone: utc)
        await session.setEnabled(false)

        let saved = store.current()
        XCTAssertEqual(saved.frequency, .everyOtherDay)
        XCTAssertEqual(saved.quietHours.startHour, 23)
        XCTAssertEqual(saved.quietHours.startMinute, 20)
        XCTAssertEqual(saved.quietHours.endHour, 6)
        XCTAssertEqual(saved.quietHours.endMinute, 40)
        XCTAssertFalse(saved.isEnabled)
    }

    private func isQuiet(
        _ date: Date,
        settings: NotificationQuietHours
    ) -> Bool {
        NotificationDeliveryPolicy.isQuietTime(
            date,
            settings: settings,
            timeZone: utc
        )
    }

    private func dailyCandidates(dayOffsets: [Int]) -> [NotificationDeliveryCandidate] {
        dayOffsets.map { offset in
            candidate(day: 6 + offset, hour: 10)
        }
    }

    private func candidate(day: Int, hour: Int) -> NotificationDeliveryCandidate {
        let localDayKey = String(format: "2026-09-%02d", day)
        return NotificationDeliveryCandidate(
            identifier: DailyCheckInReminderPolicy.identifierPrefix + localDayKey,
            fireDate: date(2026, 9, day, hour, 0)
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            timeZone: utc,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func makePreferences() throws -> UserDefaults {
        let suite = "NotificationDeliverySettingsTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.removePersistentDomain(forName: suite)
        return preferences
    }
}
