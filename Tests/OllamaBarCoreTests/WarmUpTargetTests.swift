import XCTest

@testable import OllamaBarCore

/// The Warm-up menu item used to say "No models installed" whenever the model
/// list could not be read, which pointed users with models at the wrong fix.
/// `warmUpTarget()` keeps the two cases apart.
final class WarmUpTargetTests: XCTestCase {
    private func service(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> OllamaService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = handler
        return OllamaService(
            api: OllamaAPI(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                session: URLSession(configuration: configuration)
            ))
    }

    private func tags(_ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:11434/api/tags")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testNoModelsWhenTheServerReportsAnEmptyList() {
        let service = service { _ in self.tags(#"{"models":[]}"#) }

        XCTAssertEqual(service.warmUpTarget(), .noModels)
    }

    func testModelWhenOneIsInstalled() {
        let service = service { _ in self.tags(#"{"models":[{"name":"llama3:latest"}]}"#) }

        XCTAssertEqual(service.warmUpTarget(), .model("llama3:latest"))
    }

    func testEmbeddingOnlyModelsStillPickTheFirstModel() {
        let service = service { _ in
            self.tags(#"{"models":[{"name":"nomic-embed-text:latest","capabilities":["embedding"]}]}"#)
        }

        XCTAssertEqual(service.warmUpTarget(), .model("nomic-embed-text:latest"))
    }

    func testUnreachableWhenTheRequestFails() {
        let service = service { _ in throw URLError(.cannotConnectToHost) }

        XCTAssertEqual(service.warmUpTarget(), .serverUnreachable)
    }

    func testUnreachableWhenTheServerErrors() {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:11434/api/tags")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let service = service { _ in (response, Data("boom".utf8)) }

        XCTAssertEqual(service.warmUpTarget(), .serverUnreachable)
    }

    func testUnreachableMessageDoesNotBlameTheModelList() {
        XCTAssertFalse(L10n.alertUnreachableTitle.isEmpty)
        XCTAssertFalse(L10n.alertUnreachableBody.isEmpty)
        XCTAssertNotEqual(L10n.alertUnreachableBody, L10n.alertNoModelsBody)
    }
}
