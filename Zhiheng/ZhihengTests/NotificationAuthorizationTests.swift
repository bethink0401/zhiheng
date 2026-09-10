import XCTest
@testable import Zhiheng

@MainActor
final class NotificationAuthorizationTests: XCTestCase {
    func testExplanationListsOnlyTheThreePlannedReminderPurposes() {
        XCTAssertEqual(
            NotificationReminderPurpose.allCases,
            [.dailyCheckIn, .microPlan, .lowFrequencyTrend]
        )
        XCTAssertEqual(
            Set(NotificationReminderPurpose.allCases.map(\.title)).count,
            3
        )
        XCTAssertEqual(
            Set(NotificationReminderPurpose.allCases.map(\.detail)).count,
            3
        )
    }

    func testExplanationStatesFrequencyPrivacyControlAndSafetyBoundaries() {
        XCTAssertTrue(NotificationPermissionCopy.introduction.contains("不会立即安排任何提醒"))
        XCTAssertTrue(NotificationPermissionCopy.lockScreenPrivacy.contains("不显示提醒类型"))
        XCTAssertTrue(NotificationPermissionCopy.lockScreenPrivacy.contains("健康数值"))
        XCTAssertTrue(NotificationPermissionCopy.frequency.contains("每天最多一条"))
        XCTAssertTrue(NotificationPermissionCopy.safetyBoundary.contains("不是急救"))
        XCTAssertTrue(NotificationPermissionCopy.control.contains("暂不开启"))
        XCTAssertTrue(NotificationPermissionCopy.control.contains("系统设置"))
    }

    func testStatusPresentationDoesNotMisreportDeniedOrUnknownAsEnabled() {
        XCTAssertEqual(
            NotificationPermissionViewState(status: .notDetermined),
            .notRequested
        )
        XCTAssertEqual(
            NotificationPermissionViewState(status: .denied),
            .denied
        )
        XCTAssertEqual(
            NotificationPermissionViewState(status: .unknown),
            .unavailable
        )
        XCTAssertFalse(NotificationAuthorizationStatus.denied.isEnabled)
        XCTAssertFalse(NotificationAuthorizationStatus.unknown.isEnabled)
        XCTAssertTrue(NotificationAuthorizationStatus.authorized.isEnabled)
        XCTAssertTrue(NotificationAuthorizationStatus.provisional.isEnabled)
    }

    func testRefreshOnlyReadsStatusAndNeverRequestsAuthorization() async {
        let client = NotificationAuthorizationClientSpy(status: .notDetermined)
        let session = NotificationAuthorizationSession(client: client)

        await session.refresh()

        XCTAssertEqual(session.state, .notRequested)
        let calls = await client.calls()
        XCTAssertEqual(calls.status, 1)
        XCTAssertEqual(calls.request, 0)
        XCTAssertFalse(session.showsExplanation)
    }

    func testOpeningAndCancellingExplanationNeverRequestsAuthorization() async {
        let client = NotificationAuthorizationClientSpy(status: .notDetermined)
        let session = NotificationAuthorizationSession(client: client)
        await session.refresh()

        session.beginRequest()
        XCTAssertTrue(session.showsExplanation)
        var calls = await client.calls()
        XCTAssertEqual(calls.request, 0)

        session.cancelExplanation()
        XCTAssertFalse(session.showsExplanation)
        calls = await client.calls()
        XCTAssertEqual(calls.request, 0)
    }

    func testExplicitConfirmationRequestsOnceAndPublishesSystemResult() async {
        let client = NotificationAuthorizationClientSpy(
            status: .notDetermined,
            requestResult: .authorized
        )
        let session = NotificationAuthorizationSession(client: client)
        await session.refresh()
        session.beginRequest()

        await session.confirmExplanation()
        await session.confirmExplanation()

        XCTAssertEqual(session.state, .authorized)
        XCTAssertFalse(session.showsExplanation)
        XCTAssertNil(session.requestErrorMessage)
        let calls = await client.calls()
        XCTAssertEqual(calls.request, 1)
    }

    func testDeniedStatusCannotOpenExplanationOrRepeatSystemRequest() async {
        let client = NotificationAuthorizationClientSpy(status: .denied)
        let session = NotificationAuthorizationSession(client: client)
        await session.refresh()

        session.beginRequest()
        await session.confirmExplanation()

        XCTAssertEqual(session.state, .denied)
        XCTAssertFalse(session.showsExplanation)
        let calls = await client.calls()
        XCTAssertEqual(calls.request, 0)
    }

    func testRequestFailureKeepsExplanationAndAllowsExplicitRetry() async {
        let client = NotificationAuthorizationClientSpy(
            status: .notDetermined,
            requestError: NotificationAuthorizationTestError.requestFailed
        )
        let session = NotificationAuthorizationSession(client: client)
        await session.refresh()
        session.beginRequest()

        await session.confirmExplanation()

        XCTAssertEqual(session.state, .notRequested)
        XCTAssertTrue(session.showsExplanation)
        XCTAssertEqual(
            session.requestErrorMessage,
            "暂时无法请求通知权限，请稍后重试。"
        )
        let calls = await client.calls()
        XCTAssertEqual(calls.request, 1)
    }
}

private enum NotificationAuthorizationTestError: Error {
    case requestFailed
}

private actor NotificationAuthorizationClientSpy: NotificationAuthorizationClient {
    private var currentStatus: NotificationAuthorizationStatus
    private let requestResult: NotificationAuthorizationStatus
    private let requestError: Error?
    private var statusCallCount = 0
    private var requestCallCount = 0

    init(
        status: NotificationAuthorizationStatus,
        requestResult: NotificationAuthorizationStatus = .denied,
        requestError: Error? = nil
    ) {
        currentStatus = status
        self.requestResult = requestResult
        self.requestError = requestError
    }

    func authorizationStatus() -> NotificationAuthorizationStatus {
        statusCallCount += 1
        return currentStatus
    }

    func requestAuthorization() throws -> NotificationAuthorizationStatus {
        requestCallCount += 1
        if let requestError { throw requestError }
        currentStatus = requestResult
        return requestResult
    }

    func calls() -> (status: Int, request: Int) {
        (statusCallCount, requestCallCount)
    }
}
