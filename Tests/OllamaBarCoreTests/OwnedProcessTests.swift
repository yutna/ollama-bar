import XCTest

@testable import OllamaBarCore

/// The menu offers Stop whenever the app owns a live `ollama serve` process,
/// even if the HTTP API does not answer (starting up, or hung). These tests
/// pin down `ownsRunningServer`, the signal that decision reads.
final class OwnedProcessTests: XCTestCase {
    private func service() -> OllamaService {
        OllamaService(api: OllamaAPI())
    }

    /// `/bin/sleep` stands in for `ollama serve`: the property only cares
    /// about the process being alive.
    private func launchSleep() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func testNoProcessIsNotOwned() {
        XCTAssertFalse(service().ownsRunningServer)
    }

    func testLiveProcessIsOwnedEvenWhenTheAPIDoesNotAnswer() throws {
        let service = service()
        let process = try launchSleep()
        defer { process.terminate() }

        service.serverProcess = process

        XCTAssertTrue(service.ownsRunningServer)
    }

    func testExitedProcessIsNotOwned() throws {
        let service = service()
        let process = try launchSleep()
        service.serverProcess = process

        process.terminate()
        process.waitUntilExit()

        XCTAssertFalse(service.ownsRunningServer)
    }

    /// A menu read must not wait for `start()` to finish: that is why the
    /// process reference has its own lock instead of the lifecycle gate.
    func testOwnsRunningServerAnswersWhileTheLifecycleGateIsHeld() throws {
        let service = service()
        let process = try launchSleep()
        defer { process.terminate() }
        service.serverProcess = process

        let read = expectation(description: "read while the gate is held")
        service.lifecycle.withLock {
            DispatchQueue.global().async {
                XCTAssertTrue(service.ownsRunningServer)
                read.fulfill()
            }
            wait(for: [read], timeout: 2)
        }
    }
}
