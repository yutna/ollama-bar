import XCTest

@testable import OllamaBarCore

final class LogRotationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollamabar-log-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var logPath: String { directory.appendingPathComponent("server.log").path }

    private func fileSize(_ path: String) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64) ?? 0
    }

    private func makeWriter(maxBytes: UInt64) -> RotatingLogWriter {
        RotatingLogWriter(path: logPath, maxBytes: maxBytes)
    }

    func testAppendsToTheLogFile() {
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data("hello".utf8))
        writer.close()
        XCTAssertEqual(try? Data(contentsOf: URL(fileURLWithPath: logPath)), Data("hello".utf8))
    }

    func testSmallLogIsKept() {
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data(count: 10))
        writer.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logPath + ".1"))
    }

    func testRotatesWhileWritingPastTheCap() {
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data(count: 60))
        XCTAssertEqual(fileSize(logPath), 60)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logPath + ".1"))

        // Crosses the cap: the finished file moves aside and logging restarts.
        writer.append(Data(count: 60))
        XCTAssertEqual(fileSize(logPath + ".1"), 120)
        XCTAssertEqual(fileSize(logPath), 0)

        writer.append(Data(count: 10))
        writer.close()
        XCTAssertEqual(fileSize(logPath), 10)
        XCTAssertEqual(fileSize(logPath + ".1"), 120)
    }

    func testOpenRotatesAnOversizedFileFromAPreviousSession() {
        try? Data(count: 200).write(to: URL(fileURLWithPath: logPath))
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data(count: 5))
        writer.close()
        XCTAssertEqual(fileSize(logPath + ".1"), 200)
        XCTAssertEqual(fileSize(logPath), 5)
    }

    func testPreviousRotationIsReplaced() {
        try? Data("old".utf8).write(to: URL(fileURLWithPath: logPath + ".1"))
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data(count: 150))
        writer.close()
        XCTAssertEqual(fileSize(logPath + ".1"), 150)
    }

    func testAppendsAfterCloseAreIgnored() {
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data("first".utf8))
        writer.close()
        writer.append(Data("second".utf8))
        XCTAssertEqual(try? Data(contentsOf: URL(fileURLWithPath: logPath)), Data("first".utf8))
    }

    func testReopeningContinuesAnExistingLog() {
        try? Data("first".utf8).write(to: URL(fileURLWithPath: logPath))
        let writer = makeWriter(maxBytes: 100)
        writer.open()
        writer.append(Data("second".utf8))
        writer.close()
        XCTAssertEqual(
            try? Data(contentsOf: URL(fileURLWithPath: logPath)), Data("firstsecond".utf8))
    }
}
