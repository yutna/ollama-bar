import XCTest

@testable import OllamaBarCore

/// URLProtocol stub so API tests never touch the network.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OllamaAPITests: XCTestCase {
    private var api: OllamaAPI!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        api = OllamaAPI(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            session: URLSession(configuration: configuration)
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        api = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func respond(_ status: Int, _ body: Data) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
    }

    private func json(_ payload: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    // MARK: - Version

    func testVersionReturnsValidatedVersion() async throws {
        respond(200, json(["version": "1.2.3"]))
        let version = try await api.version()
        XCTAssertEqual(version, "1.2.3")
    }

    func testVersionRejectsHTTPError() async {
        respond(404, Data("not found".utf8))
        await assertVersionFails()
    }

    func testVersionRejectsMalformedJSON() async {
        respond(200, Data("<html>hello</html>".utf8))
        await assertVersionFails()
    }

    func testVersionRejectsPayloadWithoutVersion() async {
        respond(200, json(["models": []]))
        await assertVersionFails()
    }

    func testVersionRejectsEmptyVersion() async {
        respond(200, json(["version": ""]))
        await assertVersionFails()
    }

    private func assertVersionFails(file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await api.version()
            XCTFail("expected the version check to fail", file: file, line: line)
        } catch {
            // expected
        }
    }

    // MARK: - Model lists

    func testLoadedModelNamesParsesModelAndNameFields() async throws {
        respond(200, json(["models": [["model": "a:latest"], ["name": "b:latest"]]]))
        let names = try await api.loadedModelNames()
        XCTAssertEqual(names, ["a:latest", "b:latest"])
    }

    func testLoadedModelNamesWithoutModelsKeyIsEmpty() async throws {
        respond(200, json([:]))
        let names = try await api.loadedModelNames()
        XCTAssertEqual(names, [])
    }

    func testInstalledModelNamesParsesModels() async throws {
        respond(200, json(["models": [["name": "first:latest"], ["name": "second:latest"]]]))
        let names = try await api.installedModelNames()
        XCTAssertEqual(names, ["first:latest", "second:latest"])
    }

    // MARK: - Sync bridge

    func testSyncVersionBridgesToAsyncImplementation() throws {
        respond(200, json(["version": "9.9.9"]))
        XCTAssertEqual(try api.syncVersion(), "9.9.9")
    }
}
