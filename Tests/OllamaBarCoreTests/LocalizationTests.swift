import XCTest

@testable import OllamaBarCore

final class LocalizationTests: XCTestCase {
    func testLaunchTimeoutMessageInterpolatesSeconds() {
        XCTAssertTrue(L10n.errorLaunchTimeout(8).contains("8"))
    }

    func testLaunchTimeoutMessageIncludesLogTail() {
        let message = L10n.errorLaunchTimeoutWithLog(8, "last log line")
        XCTAssertTrue(message.contains("8"))
        XCTAssertTrue(message.contains("last log line"))
    }

    func testBinaryNotFoundMessageIsNotEmpty() {
        XCTAssertFalse(L10n.errorBinaryNotFound.isEmpty)
    }

    func testStopFailedMessagesAreNotEmpty() {
        XCTAssertFalse(L10n.alertStopFailedTitle.isEmpty)
        XCTAssertTrue(L10n.alertStopFailedBody.contains("ollama"))
    }
}
