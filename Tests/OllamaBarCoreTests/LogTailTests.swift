import XCTest

@testable import OllamaBarCore

/// A failed start used to show the last lines of `server.log` whether or not
/// this start wrote them, so a "did not become ready" alert often carried the
/// previous session's output (a "Listening on 127.0.0.1:11434" line under it).
final class LogTailTests: XCTestCase {
    private var directory: URL!
    private var path: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollamabar-logtail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("server.log").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, appending: Bool = false) throws {
        if appending {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func testSizeIsZeroWhenTheFileDoesNotExist() {
        XCTAssertEqual(OllamaService.logFileSize(at: path), 0)
    }

    func testTailContainsOnlyWhatWasAppended() throws {
        try write("Listening on 127.0.0.1:11434\n")
        let offset = OllamaService.logFileSize(at: path)
        try write("Error: address already in use\nbind: address already in use\n", appending: true)

        let tail = OllamaService.logTail(at: path, since: offset)

        XCTAssertEqual(tail, "Error: address already in use\nbind: address already in use")
        XCTAssertFalse(tail.contains("Listening"))
    }

    func testTailIsEmptyWhenNothingWasAppended() throws {
        try write("Listening on 127.0.0.1:11434\n")
        let offset = OllamaService.logFileSize(at: path)

        XCTAssertEqual(OllamaService.logTail(at: path, since: offset), "")
    }

    func testTailReadsEverythingWhenTheFileWasRotated() throws {
        // A rotation during the start leaves a file shorter than the recorded
        // offset; everything in it belongs to this start.
        try write("time=... msg=\"rotated in\"\n")
        let offset = OllamaService.logFileSize(at: path) + 10_000

        XCTAssertEqual(OllamaService.logTail(at: path, since: offset), "time=... msg=\"rotated in\"")
    }

    func testTailKeepsTheLastLines() throws {
        try write("first\n")
        let offset = OllamaService.logFileSize(at: path)
        try write((1...20).map { "line \($0)" }.joined(separator: "\n") + "\n", appending: true)

        let tail = OllamaService.logTail(at: path, since: offset, lines: 3)

        XCTAssertEqual(tail, "line 18\nline 19\nline 20")
    }
}
