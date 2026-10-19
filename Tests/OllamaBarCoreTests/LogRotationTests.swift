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

    func testSmallLogIsKept() throws {
        let file = directory.appendingPathComponent("server.log")
        try Data(count: 10).write(to: file)
        OllamaService.rotateLogIfNeeded(at: file.path, maxBytes: 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path + ".1"))
    }

    func testLargeLogIsRotated() throws {
        let file = directory.appendingPathComponent("server.log")
        try Data(count: 200).write(to: file)
        OllamaService.rotateLogIfNeeded(at: file.path, maxBytes: 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".1"))
    }

    func testPreviousRotationIsReplaced() throws {
        let file = directory.appendingPathComponent("server.log")
        try Data(count: 200).write(to: file)
        let rotated = URL(fileURLWithPath: file.path + ".1")
        try Data("old".utf8).write(to: rotated)
        OllamaService.rotateLogIfNeeded(at: file.path, maxBytes: 100)
        XCTAssertEqual(try Data(contentsOf: rotated).count, 200)
    }
}
