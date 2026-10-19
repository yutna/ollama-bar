import XCTest

@testable import OllamaBarCore

final class WarmUpSelectionTests: XCTestCase {
    private func model(
        _ name: String,
        family: String? = nil,
        capabilities: [String] = []
    ) -> OllamaAPI.InstalledModel {
        OllamaAPI.InstalledModel(name: name, family: family, capabilities: capabilities)
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

    func testCapabilitiesBeatTheNameHeuristic() {
        let models = [
            model("bge-m3:latest", family: "", capabilities: ["embedding"]),
            model("qwen3:latest", family: "", capabilities: ["completion", "tools"]),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "qwen3:latest")
    }

    func testCapabilitiesKeepGenerativeModelsThatLookLikeEmbeddings() {
        // A vision/tool model whose name mentions "embed" would be skipped by
        // the old heuristic; the server's capabilities say otherwise.
        let models = [
            model("embedding-lookalike:latest", family: "", capabilities: ["completion", "vision"]),
            model("llama3:latest", family: "llama", capabilities: ["completion"]),
        ]
        XCTAssertEqual(OllamaService.warmUpCandidate(in: models), "embedding-lookalike:latest")
    }

    func testCapabilitiesTreatHybridsWithCompletionAsGenerative() {
        XCTAssertFalse(
            OllamaService.isEmbeddingModel(
                model("hybrid:latest", capabilities: ["embedding", "completion"])))
    }

    func testFallsBackToNameAndFamilyWhenCapabilitiesAreMissing() {
        XCTAssertTrue(
            OllamaService.isEmbeddingModel(model("nomic-embed-text:latest", family: "")))
        XCTAssertTrue(OllamaService.isEmbeddingModel(model("all-minilm:latest", family: "bert")))
        XCTAssertFalse(OllamaService.isEmbeddingModel(model("llama3:latest", family: "llama")))
    }
}
