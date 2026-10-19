import XCTest

@testable import OllamaBarCore

final class BinaryDetectionTests: XCTestCase {
    func testFirstExecutablePicksTheFirstExistingCandidate() {
        let paths = ["/a/ollama", "/b/ollama", "/c/ollama"]
        XCTAssertEqual(
            OllamaService.firstExecutable(in: paths, isExecutable: { $0 == "/b/ollama" }),
            "/b/ollama")
    }

    func testFirstExecutableReturnsNilWhenNothingMatches() {
        XCTAssertNil(OllamaService.firstExecutable(in: [], isExecutable: { _ in true }))
        XCTAssertNil(OllamaService.firstExecutable(in: ["/a/ollama"], isExecutable: { _ in false }))
    }

    func testShellOutputParsingFindsThePath() {
        XCTAssertEqual(
            OllamaService.executableFromShell(
                output: "/opt/local/bin/ollama\n", isExecutable: { _ in true }),
            "/opt/local/bin/ollama")
    }

    func testShellOutputParsingKeepsTheLastMatchAndSkipsProfileNoise() {
        let output = "welcome back\n/opt/old/ollama\n/usr/local/bin/ollama\n"
        XCTAssertEqual(
            OllamaService.executableFromShell(output: output, isExecutable: { _ in true }),
            "/usr/local/bin/ollama")
    }

    func testShellOutputParsingRejectsNonPathsAndNonExecutables() {
        XCTAssertNil(
            OllamaService.executableFromShell(
                output: "ollama: aliased to /opt/ollama\n", isExecutable: { _ in true }))
        XCTAssertNil(
            OllamaService.executableFromShell(
                output: "ollama not found\n", isExecutable: { _ in true }))
        XCTAssertNil(
            OllamaService.executableFromShell(output: "", isExecutable: { _ in true }))
        XCTAssertNil(
            OllamaService.executableFromShell(
                output: "/tmp/ollama\n", isExecutable: { _ in false }))
        XCTAssertNil(
            OllamaService.executableFromShell(
                output: "./relative/ollama\n", isExecutable: { _ in true }))
    }

    func testCandidatesCoverNonHomebrewLocations() {
        let home = NSHomeDirectory()
        let expected = [
            "/opt/local/bin/ollama",
            home + "/.local/bin/ollama",
            home + "/bin/ollama",
            home + "/.asdf/shims/ollama",
            home + "/.local/share/mise/shims/ollama",
        ]
        for path in expected {
            XCTAssertTrue(OllamaService.binaryCandidates.contains(path), "missing candidate: \(path)")
        }
    }
}
