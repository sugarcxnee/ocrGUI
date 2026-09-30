import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import OCRGUICore

// MARK: - OpenAI 引擎退化兜底（fallback_prompt）

@Suite(.serialized)
struct EngineFallbackTests {

    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responses: [(URLRequest) -> (HTTPURLResponse, Data)] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard !Self.responses.isEmpty else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            let (response, data) = Self.responses.removeFirst()(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func image() throws -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return try #require(rep.cgImage)
    }

    private func ok(_ url: URL, _ json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         Data(json.utf8))
    }

    private func jsonResponse(_ content: String) -> String {
        let payload: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }


    private func config(fallback: String?) -> EngineConfig {
        EngineConfig(id: "x", name: "X", kind: .openaiHTTP, enabled: true,
                     baseURL: "http://127.0.0.1:9/v1", model: "m",
                     prompt: "把图片转写为 Markdown。", apiKey: nil,
                     timeout: 30, launch: nil, notes: nil,
                     fallbackPrompt: fallback)
    }

    @Test("主提示词输出退化时，用 fallback_prompt 重试并采用其结果")
    func retriesWithFallbackPrompt() async throws {
        var requests: [String] = [] // 每次请求里的文本段
        let degenerate = (0..<5).map { _ in "重复的行" }.joined(separator: "\n")
        MockURLProtocol.responses = [
            { request in
                requests.append("primary")
                return self.ok(request.url!, self.jsonResponse(degenerate))
            },
            { request in
                requests.append("fallback")
                return self.ok(request.url!, self.jsonResponse("正常的转写结果，这里补足长度用于通过退化检测门槛。"))
            },
        ]
        let engine = OpenAICompatEngine(config: config(fallback: "Task: Text Extraction."),
                                        session: mockedSession())
        let page = try await engine.recognize(image: try image(), options: RecognizeOptions())
        #expect(requests == ["primary", "fallback"])
        #expect(page.markdown == "正常的转写结果，这里补足长度用于通过退化检测门槛。")
    }

    @Test("未配置 fallback_prompt 时不重试")
    func noRetryWithoutFallback() async throws {
        var count = 0
        let degenerate = (0..<5).map { _ in "重复的行" }.joined(separator: "\n")
        MockURLProtocol.responses = [
            { request in
                count += 1
                return self.ok(request.url!, self.jsonResponse(degenerate))
            },
        ]
        let engine = OpenAICompatEngine(config: config(fallback: nil), session: mockedSession())
        let page = try await engine.recognize(image: try image(), options: RecognizeOptions())
        #expect(count == 1)
        #expect(page.markdown == degenerate)
    }

    @Test("主输出正常时只用一次请求")
    func singleRequestWhenHealthy() async throws {
        var count = 0
        MockURLProtocol.responses = [
            { request in
                count += 1
                return self.ok(request.url!, self.jsonResponse("设 $G$ 是一个群，对于任意 $a,b\\in G$ 都有 $(ab)^{-1}=b^{-1}a^{-1}$，命题得证。"))
            },
        ]
        let engine = OpenAICompatEngine(config: config(fallback: "Task: Text Extraction."),
                                        session: mockedSession())
        let page = try await engine.recognize(image: try image(), options: RecognizeOptions())
        #expect(count == 1)
        #expect(page.markdown == "设 $G$ 是一个群，对于任意 $a,b\\in G$ 都有 $(ab)^{-1}=b^{-1}a^{-1}$，命题得证。")
    }

    @Test("EngineConfig 解析/编码 fallback_prompt 字段")
    func configDecodesFallbackPrompt() throws {
        let json = """
        {"id": "x", "name": "X", "kind": "openai-http", "base_url": "http://127.0.0.1:1/v1",
         "prompt": "主", "fallback_prompt": "Task: Text Extraction."}
        """
        let config = try JSONDecoder().decode(EngineConfig.self, from: Data(json.utf8))
        #expect(config.fallbackPrompt == "Task: Text Extraction.")

        let roundtrip = try JSONDecoder().decode(EngineConfig.self, from: JSONEncoder().encode(config))
        #expect(roundtrip.fallbackPrompt == "Task: Text Extraction.")

        let minimal = try JSONDecoder().decode(EngineConfig.self, from: Data(
            #"{"id":"y","name":"Y","kind":"openai-http","base_url":"http://127.0.0.1:1/v1"}"#.utf8))
        #expect(minimal.fallbackPrompt == nil)
    }
}
