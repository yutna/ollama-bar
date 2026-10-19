import XCTest

@testable import OllamaBarCore

final class ShellTests: XCTestCase {
    func testRunReturnsExitCode() {
        XCTAssertEqual(Shell.run("/bin/sh", ["-c", "exit 0"]), 0)
        XCTAssertEqual(Shell.run("/bin/sh", ["-c", "exit 3"]), 3)
    }

    func testRunReturnsNilWhenBinaryCannotLaunch() {
        XCTAssertNil(Shell.run("/nonexistent/definitely-not-here", []))
    }

    func testRunTimesOutAndReturnsNil() {
        let start = Date()
        XCTAssertNil(Shell.run("/bin/sh", ["-c", "sleep 30"], timeout: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testCaptureReturnsOutput() {
        XCTAssertEqual(Shell.capture("/bin/sh", ["-c", "printf hello"]), "hello")
    }

    func testCaptureReturnsNilWhenCommandFails() {
        XCTAssertNil(Shell.capture("/bin/sh", ["-c", "printf out; exit 2"]))
    }

    func testCaptureHandlesOutputLargerThanPipeBuffer() throws {
        let output = try XCTUnwrap(
            Shell.capture("/bin/sh", ["-c", "yes x | head -c 200000"], timeout: 10))
        XCTAssertEqual(output.count, 200_000)
    }

    func testCaptureUsesProvidedEnvironment() {
        let output = Shell.capture(
            "/bin/sh",
            ["-c", "printf %s \"$OLLAMABAR_TEST\""],
            environment: ["OLLAMABAR_TEST": "value"]
        )
        XCTAssertEqual(output, "value")
    }
}
