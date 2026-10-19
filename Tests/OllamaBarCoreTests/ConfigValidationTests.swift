import XCTest

@testable import OllamaBarCore

final class ConfigValidationTests: XCTestCase {
    func testValidPorts() {
        XCTAssertEqual(Config.validatedPort("11434"), "11434")
        XCTAssertEqual(Config.validatedPort("1"), "1")
        XCTAssertEqual(Config.validatedPort("65535"), "65535")
    }

    func testInvalidPortsAreRejected() {
        XCTAssertNil(Config.validatedPort("abc"))
        XCTAssertNil(Config.validatedPort(""))
        XCTAssertNil(Config.validatedPort("0"))
        XCTAssertNil(Config.validatedPort("65536"))
        XCTAssertNil(Config.validatedPort("-1"))
        XCTAssertNil(Config.validatedPort("12345abc"))
    }

    func testKeepAliveForms() {
        XCTAssertEqual(Config.validatedKeepAlive("-1"), "-1")
        XCTAssertEqual(Config.validatedKeepAlive("300"), "300")
        XCTAssertEqual(Config.validatedKeepAlive("5m"), "5m")
        XCTAssertEqual(Config.validatedKeepAlive("2h"), "2h")
        XCTAssertEqual(Config.validatedKeepAlive("1500ms"), "1500ms")
        XCTAssertNil(Config.validatedKeepAlive("forever"))
        XCTAssertNil(Config.validatedKeepAlive("0"))
        XCTAssertNil(Config.validatedKeepAlive("-2"))
    }

    func testPositiveIntValidation() {
        XCTAssertEqual(Config.validatedPositiveInt("65536"), "65536")
        XCTAssertNil(Config.validatedPositiveInt("0"))
        XCTAssertNil(Config.validatedPositiveInt("-5"))
        XCTAssertNil(Config.validatedPositiveInt("64k"))
    }

    func testFlagValidation() {
        XCTAssertEqual(Config.validatedFlag("0"), "0")
        XCTAssertEqual(Config.validatedFlag("1"), "1")
        XCTAssertNil(Config.validatedFlag("true"))
        XCTAssertNil(Config.validatedFlag(""))
    }

    func testKvCacheTypeValidation() {
        XCTAssertEqual(Config.validatedKvCacheType("q8_0"), "q8_0")
        XCTAssertEqual(Config.validatedKvCacheType("f16"), "f16")
        XCTAssertNil(Config.validatedKvCacheType("Q8_0"))
        XCTAssertNil(Config.validatedKvCacheType(""))
        XCTAssertNil(Config.validatedKvCacheType("q8 0"))
    }

    func testResolveUsesValidOverrides() {
        let settings = Config.resolve(env: [
            "OLLAMABAR_PORT": "12345",
            "OLLAMABAR_KEEP_ALIVE": "30m",
            "OLLAMABAR_CONTEXT_LENGTH": "8192",
            "OLLAMABAR_MAX_LOADED_MODELS": "2",
            "OLLAMABAR_FLASH_ATTENTION": "0",
            "OLLAMABAR_KV_CACHE_TYPE": "q4_0",
        ])
        XCTAssertEqual(settings.port, "12345")
        XCTAssertEqual(settings.keepAlive, "30m")
        XCTAssertEqual(settings.contextLength, "8192")
        XCTAssertEqual(settings.maxLoadedModels, "2")
        XCTAssertEqual(settings.flashAttention, "0")
        XCTAssertEqual(settings.kvCacheType, "q4_0")
        XCTAssertEqual(settings.listenHost, "127.0.0.1:12345")
        XCTAssertEqual(settings.apiBase, "http://127.0.0.1:12345")
    }

    func testResolveFallsBackForInvalidValues() {
        let settings = Config.resolve(env: [
            "OLLAMABAR_PORT": "abc",
            "OLLAMABAR_KEEP_ALIVE": "forever",
            "OLLAMABAR_CONTEXT_LENGTH": "-1",
            "OLLAMABAR_MAX_LOADED_MODELS": "0",
            "OLLAMABAR_FLASH_ATTENTION": "yes",
            "OLLAMABAR_KV_CACHE_TYPE": "F16",
        ])
        XCTAssertEqual(settings, Config.defaults)
    }

    func testResolveEmptyEnvironmentUsesDefaults() {
        XCTAssertEqual(Config.resolve(env: [:]), Config.defaults)
    }
}
