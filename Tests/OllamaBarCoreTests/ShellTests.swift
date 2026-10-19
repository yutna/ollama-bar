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

    /// A background process that inherited stdout keeps the write end of the
    /// pipe open after the child exits; the drain must not wait for it.
    func testCaptureDoesNotWaitForADescendantHoldingStdout() throws {
        let start = Date()
        let output = try XCTUnwrap(
            Shell.capture("/bin/sh", ["-c", "sleep 10 & echo $!; echo done"]))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(output.contains("done"), "captured: \(output)")
        XCTAssertLessThan(elapsed, 2, "the drain waited for the background process")
        if let first = output.split(separator: "\n").first, let pid = Int32(first) {
            kill(pid, SIGKILL)  // clean up the sleeping grandchild
        }
    }

    /// Same bound on the timeout path: once the command is killed the caller
    /// must not wait for whatever else still holds the pipe.
    func testTimeoutDoesNotWaitForADescendantHoldingStdout() {
        let start = Date()
        let output = Shell.capture("/bin/sh", ["-c", "sleep 3 & exec sleep 30"], timeout: 0.5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(output)
        XCTAssertLessThan(elapsed, 2, "the drain waited for the background process")
    }
}
