import XCTest

@testable import OllamaBarCore

final class OllamaProcessesTests: XCTestCase {
    func testParsePIDs() {
        XCTAssertEqual(OllamaProcesses.parsePIDs("123\n456\n"), [123, 456])
        XCTAssertEqual(OllamaProcesses.parsePIDs(""), [])
        XCTAssertEqual(OllamaProcesses.parsePIDs("abc\n 7 \n"), [7])
    }

    func testProcessesWithMatchingCommandLineButOtherExecutablesAreIgnored() throws {
        // A process whose command line contains "ollama serve" but whose
        // executable is not `ollama` must never be signalled.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec -a 'ollama serve' sleep 30"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(OllamaProcesses.runningIDs().contains(process.processIdentifier))
    }
}
