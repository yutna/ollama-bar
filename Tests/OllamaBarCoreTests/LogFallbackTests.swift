import XCTest

@testable import OllamaBarCore

/// When the log pump cannot be started, `ollama serve` is handed the log file
/// descriptor directly. That fallback used to open the file without `O_APPEND`
/// (so a concurrent writer's lines were overwritten) and with the default cap
/// instead of the configured `OLLAMABAR_LOG_MAX_BYTES`.
final class LogFallbackTests: XCTestCase {
    private var directory: URL!
    private var logPath: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollamabar-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Nested on purpose: the fallback has to create the log directory.
        logPath = directory.appendingPathComponent("logs/server.log").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func service() -> OllamaService {
        OllamaService(api: OllamaAPI(), logPath: logPath)
    }

    private func contents(_ path: String? = nil) -> String {
        (try? String(contentsOfFile: path ?? logPath, encoding: .utf8)) ?? ""
    }

    private func prefill(_ text: String) throws {
        let directoryPath = (logPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directoryPath, withIntermediateDirectories: true)
        try text.write(toFile: logPath, atomically: true, encoding: .utf8)
    }

    private func makeChild(_ script: String) -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        return child
    }

    func testFallbackCreatesTheLogDirectoryAndCapturesBothStreams() throws {
        let child = makeChild("echo out; echo err >&2")
        service().attachFileLog(to: child, maxBytes: 4096)

        try child.run()
        child.waitUntilExit()

        let log = contents()
        XCTAssertTrue(log.contains("out"), "log: \(log)")
        XCTAssertTrue(log.contains("err"), "log: \(log)")
    }

    func testFallbackKeepsWhatAnEarlierSessionWrote() throws {
        try prefill("earlier session\n")

        let child = makeChild("echo new session")
        service().attachFileLog(to: child, maxBytes: 4096)

        try child.run()
        child.waitUntilExit()

        XCTAssertEqual(contents(), "earlier session\nnew session\n")
    }

    /// Without `O_APPEND` the child keeps the offset it was spawned with, so its
    /// next line lands on top of whatever was appended in the meantime.
    func testFallbackAppendsOnTopOfAConcurrentWrite() throws {
        let child = makeChild("sleep 0.5; echo from-child")
        service().attachFileLog(to: child, maxBytes: 4096)
        try child.run()

        // Another writer (a second instance, or a pump left over from an
        // earlier start) appends while the child is still asleep.
        let other = try XCTUnwrap(RotatingLogWriter.openForAppending(logPath))
        try other.write(contentsOf: Data("from-someone-else\n".utf8))
        try other.close()

        child.waitUntilExit()

        XCTAssertEqual(contents(), "from-someone-else\nfrom-child\n")
    }

    func testFallbackRotatesAnOversizedLeftoverFile() throws {
        let oversized = String(repeating: "x", count: 200)
        try prefill(oversized)

        let child = makeChild("echo fresh")
        service().attachFileLog(to: child, maxBytes: 100)

        try child.run()
        child.waitUntilExit()

        XCTAssertEqual(contents(logPath + ".1"), oversized)
        XCTAssertEqual(contents(), "fresh\n")
    }
}
