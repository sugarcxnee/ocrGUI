import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import OCRGUICore

// MARK: - URLProtocol Mock（serialized 避免并行访问共享 handler）

@Suite(.serialized)
struct HTTPEnginesTests {

    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
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

    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func sampleImage() throws -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return try #require(rep.cgImage)
    }

    private func openAIConfig() -> EngineConfig {
        EngineConfig(id: "t-openai", name: "T", kind: .openaiHTTP, enabled: true,
                     baseURL: "http://127.0.0.1:9/v1", model: "test-model", prompt: "Text Recognition:",
                     apiKey: "sk-x", timeout: 30, launch: nil, notes: nil)
    }

    private func jsonConfig() -> EngineConfig {
        EngineConfig(id: "t-json", name: "T", kind: .jsonHTTP, enabled: true,
                     baseURL: "http://127.0.0.1:9", model: nil, prompt: nil, apiKey: nil,
                     timeout: 30, launch: nil, notes: nil)
    }

    private func httpOK(_ url: URL, json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         Data(json.utf8))
    }

    /// URLProtocol 路径上 httpBody 会转为 httpBodyStream，这里统一读出 Data
    private func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: OpenAI 兼容引擎

    @Test("openai-http：请求体含模型/dataURL图片/prompt，响应 content → markdown")
    func openAIRequestAndParse() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return self.httpOK(request.url!, json: """
            {"choices":[{"message":{"role":"assistant","content":"# 识别结果\\n| 表格 |"}}]}
            """)
        }
        let engine = OpenAICompatEngine(config: openAIConfig(), session: mockedSession())
        let page = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())

        let req = try #require(captured)
        #expect(req.url?.absoluteString == "http://127.0.0.1:9/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-x")

        let body = try JSONSerialization.jsonObject(with: bodyData(of: req) ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "test-model")
        #expect(body?["temperature"] as? Double == 0)
        let messages = try #require(body?["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let hasImage = content.contains {
            ($0["type"] as? String) == "input_image"
                && (($0["image_url"] as? String) ?? "").hasPrefix("data:image/png;base64,")
        }
        #expect(hasImage)
        #expect(content.contains { ($0["type"] as? String) == "text" && ($0["text"] as? String) == "Text Recognition:" })

        #expect(page.markdown == "# 识别结果\n| 表格 |")
        #expect(page.lines.isEmpty)
        #expect(!engine.capabilities.hasLineBoxes)
        #expect(engine.capabilities.outputsMarkdown)
    }

    @Test("openai-http：content 为分段数组时拼接文本")
    func openAIMultipartContent() async throws {
        MockURLProtocol.handler = { request in
            self.httpOK(request.url!, json: """
            {"choices":[{"message":{"content":[{"type":"text","text":"第一段"},{"type":"text","text":"第二段"}]}}]}
            """)
        }
        let engine = OpenAICompatEngine(config: openAIConfig(), session: mockedSession())
        let page = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())
        #expect(page.markdown == "第一段第二段")
    }

    @Test("openai-http：500 抛 httpStatus，坏 JSON 抛 invalidResponse")
    func openAIErrorPaths() async throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
             Data("boom".utf8))
        }
        let engine = OpenAICompatEngine(config: openAIConfig(), session: mockedSession())
        await #expect(throws: EngineError.self) {
            _ = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())
        }

        MockURLProtocol.handler = { request in self.httpOK(request.url!, json: "not-json{") }
        await #expect(throws: EngineError.self) {
            _ = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())
        }
    }

    @Test("openai-http：健康探测 2xx → ready")
    func openAIHealthReady() async throws {
        MockURLProtocol.handler = { request in self.httpOK(request.url!, json: "{}") }
        let engine = OpenAICompatEngine(config: openAIConfig(), session: mockedSession())
        let health = await engine.healthCheck()
        #expect(health == .ready)
    }

    // MARK: JsonHttp 引擎（Paddle 经典）

    @Test("json-http：POST base64 图片，解析 lines（文本/置信度/四点框）")
    func jsonHTTPRoundtrip() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return self.httpOK(request.url!, json: """
            {"width": 40, "height": 20, "lines": [
              {"text": "你好", "score": 0.99, "box": [[1,2],[10,2],[10,8],[1,8]]},
              {"text": "world", "score": 0.87, "box": [[1,10],[20,10],[20,16],[1,16]]}
            ]}
            """)
        }
        let engine = JsonHttpEngine(config: jsonConfig(), session: mockedSession())
        let page = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())

        let req = try #require(captured)
        #expect(req.url?.absoluteString == "http://127.0.0.1:9/ocr")
        let body = try JSONSerialization.jsonObject(with: bodyData(of: req) ?? Data()) as? [String: Any]
        let b64 = try #require(body?["image_b64"] as? String)
        #expect(!b64.isEmpty)

        #expect(page.lines.count == 2)
        #expect(page.lines[0].text == "你好")
        #expect(page.lines[0].score == 0.99)
        #expect(page.lines[0].box.count == 4)
        #expect(page.width == 40)
        #expect(engine.capabilities.hasLineBoxes)
    }

    @Test("json-http：响应缺 lines 抛 invalidResponse")
    func jsonHTTPBadResponse() async throws {
        MockURLProtocol.handler = { request in
            self.httpOK(request.url!, json: "{\"oops\": 1}")
        }
        let engine = JsonHttpEngine(config: jsonConfig(), session: mockedSession())
        await #expect(throws: EngineError.self) {
            _ = try await engine.recognize(image: try sampleImage(), options: RecognizeOptions())
        }
    }
}
