import XCTest

@testable import OllamaBarCore

final class CLITests: XCTestCase {
    func testFlagsCoversEveryDocumentedOption() {
        let documented = [
            "--start", "--stop", "--status", "--warm", "--help", "-h", "--version", "-v",
        ]
        for flag in documented {
            XCTAssertTrue(CLI.flags.contains(flag), "missing flag: \(flag)")
        }
        XCTAssertEqual(CLI.flags.count, documented.count)
    }

    func testVersionComesFromTheInfoDictionary() {
        XCTAssertEqual(CLI.version(from: ["CFBundleShortVersionString": "1.2.3"]), "1.2.3")
    }

    func testVersionFallsBackWhenMissing() {
        XCTAssertEqual(CLI.version(from: nil), "unknown")
        XCTAssertEqual(CLI.version(from: [:]), "unknown")
        XCTAssertEqual(CLI.version(from: ["CFBundleShortVersionString": 42]), "unknown")
    }
}
