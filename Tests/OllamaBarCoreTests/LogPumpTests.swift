import XCTest

@testable import OllamaBarCore

/// The server's output only reaches `server.log` when the pipe, the pump
/// process and the rotating writer agree, and nothing exercised that path.
/// These tests push a short-lived child through both halves of it.
final class LogPumpTests: XCTestCase {
    private var directory: URL!
    private var logPath: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollamabar-pump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logPath = directory.appendingPathComponent("server.log").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func contents(_ path: String? = nil) -> String {
        (try? String(contentsOfFile: path ?? logPath, encoding: .utf8)) ?? ""
    }

    /// Runs `script` with stdout and stderr on one pipe (the way `attachLog`
    /// wires the server) and drains that pipe the way the pump process does.
    private func runThroughPipe(_ script: String, maxBytes: UInt64 = 4096) throws {
        let pipe = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        child.standardOutput = pipe
        child.standardError = pipe
        try child.run()
        try pipe.fileHandleForWriting.close()  // only the child keeps the write end

        LogPump.drain(
            from: pipe.fileHandleForReading,
            into: RotatingLogWriter(path: logPath, maxBytes: maxBytes))

        child.waitUntilExit()
    }

    func testChildOutputReachesTheLogThroughThePipe() throws {
        try runThroughPipe("echo line-one; echo line-two >&2")

        let log = contents()
        XCTAssertTrue(log.contains("line-one"), "log: \(log)")
        XCTAssertTrue(log.contains("line-two"), "log: \(log)")
    }

    func testDrainAppliesTheCapWhileTheServerRuns() throws {
        try runThroughPipe("printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'", maxBytes: 16)

        XCTAssertEqual(contents(logPath + ".1"), String(repeating: "a", count: 40))
        XCTAssertEqual(contents(), "")
    }

    /// `attachLog` is what keeps the log alive after the app exits: it spawns a
    /// `--log-pump <path>` helper with the pipe as its stdin. A stub stands in
    /// for this binary, so the test checks the wiring itself — the child's two
    /// streams reaching that helper, and the path it is handed.
    func testAttachLogSpawnsThePumpAndFeedsItTheChildOutput() throws {
        let stub = directory.appendingPathComponent("pump-stub.sh")
        try "#!/bin/sh\nexec cat >> \"$2\"\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let service = OllamaService(api: OllamaAPI(), logPath: logPath)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "echo hello-from-child; echo oops >&2"]
        service.attachLog(to: child, pumpExecutable: stub)
        try child.run()
        child.waitUntilExit()

        // The pump writes from another process, so poll instead of assuming it
        // has flushed already.
        let log = try waitForLog(containing: "hello-from-child")
        XCTAssertTrue(log.contains("oops"), "log: \(log)")
    }

    private func waitForLog(containing needle: String, timeout: TimeInterval = 5) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let log = contents()
            if log.contains(needle) { return log }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return contents()
    }
}
