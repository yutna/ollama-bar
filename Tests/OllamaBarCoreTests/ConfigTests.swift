import XCTest

@testable import OllamaBarCore

final class ConfigTests: XCTestCase {
    func testEnvUsesOverride() {
        XCTAssertEqual(Config.env("KEY", "fallback", in: ["KEY": "value"]), "value")
    }

    func testEnvFallsBackWhenMissing() {
        XCTAssertEqual(Config.env("MISSING", "fallback", in: [:]), "fallback")
    }

    func testEnvTreatsEmptyValueAsMissing() {
        XCTAssertEqual(Config.env("EMPTY", "fallback", in: ["EMPTY": ""]), "fallback")
    }
}

final class OllamaErrorTests: XCTestCase {
    func testBinaryNotFoundHasDescription() {
        XCTAssertNotNil(OllamaError.binaryNotFound.errorDescription)
    }

    func testLaunchFailedCarriesReason() {
        XCTAssertEqual(OllamaError.launchFailed("boom").errorDescription, "boom")
    }
}
