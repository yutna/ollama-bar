import XCTest

@testable import OllamaBarCore

final class WarmUpSelectionTests: XCTestCase {
    private func model(_ name: String, family: String? = nil) -> OllamaAPI.InstalledModel {
        OllamaAPI.InstalledModel(name: name, family: family)
    }

    func testSkipsEmbeddingModelsByName() {
        let models = [
            model("nomic-embed-text:latest", family: "nomic-bert"),
            model("llama3:latest", family: "llama"),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "llama3:latest")
    }

    func testSkipsEmbeddingModelsByFamily() {
        let models = [
            model("all-minilm:latest", family: "bert"),
            model("qwen2:latest", family: "qwen2"),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "qwen2:latest")
    }

    func testFallsBackToFirstModelWhenAllAreEmbedding() {
        let models = [
            model("nomic-embed-text:latest", family: "nomic-bert"),
            model("all-minilm:latest", family: "bert"),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "nomic-embed-text:latest")
    }

    func testUsesFirstGenerativeModelInServerOrder() {
        let models = [
            model("qwen2:latest", family: "qwen2"),
            model("llama3:latest", family: "llama"),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "qwen2:latest")
    }

    func testNilWhenNothingInstalled() {
        XCTAssertNil(OllamaService.warmUpCandidate(in: []))
    }

    func testShouldPreloadOnlyWhenNothingIsLoaded() {
        XCTAssertTrue(OllamaService.shouldPreloadModel(loadedModels: []))
        XCTAssertFalse(OllamaService.shouldPreloadModel(loadedModels: ["llama3:latest"]))
        XCTAssertFalse(
            OllamaService.shouldPreloadModel(loadedModels: ["llama3:latest", "qwen2:latest"]))
    }
}
