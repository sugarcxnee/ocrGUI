import Foundation
import CoreGraphics

// MARK: - HTTP 健康探测

public enum HTTPProbe {
    /// 有任何 HTTP 响应（不限状态码）即视为服务存活；连接拒绝/超时 → false
    public static func alive(_ url: URL,
                             timeout: TimeInterval = 2,
                             session: URLSession = .shared) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await session.data(for: request)
            _ = response
            return true
        } catch {
            return false
        }
    }
}

// MARK: - OpenAI Chat Completions 兼容引擎

/// 适配 mlx_vlm.server / vlm_server.py 等本地 OpenAI 兼容服务。
/// 请求协议与 webUI/api_call_example.py 一致：base64 dataURL 图片 + 文本提示词。
public struct OpenAICompatEngine: OCREngine {
    public let config: EngineConfig
    public let capabilities = EngineCapabilities(hasLineBoxes: false, outputsMarkdown: true)
    private let session: URLSession

    public init(config: EngineConfig, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.config = config.expandingTilde()
        self.session = session
    }

    public func healthCheck() async -> EngineHealth {
        let probeURL = config.launch?.healthURL ?? config.baseURL
        guard let urlStr = probeURL, let url = URL(string: urlStr) else { return .failed("缺少可探测地址") }
        return await HTTPProbe.alive(url, session: session) ? .ready : .notRunning
    }

    public func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage {
        try Task.checkCancellation()

        guard let base = config.baseURL, let url = URL(string: base + "/chat/completions") else {
            throw EngineError.invalidResponse("base_url 非法")
        }
        guard let png = ImageTools.pngData(from: image) else {
            throw EngineError.imageDecodeFailed
        }

        let body: [String: Any] = [
            "model": config.model ?? "default",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "input_image", "image_url": "data:image/png;base64," + png.base64EncodedString()],
                    ["type": "text", "text": config.prompt ?? "Text Recognition:"],
                ],
            ]],
            "max_tokens": 4096,
            "temperature": 0,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw EngineError.canceled
        } catch {
            throw EngineError.notReady("无法连接服务：\(error.localizedDescription)。请在设置中启动引擎或检查配置。")
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw EngineError.invalidResponse("响应缺少 choices[0].message")
        }

        // content 兼容字符串与分段数组两种形态
        var text: String
        if let s = message["content"] as? String {
            text = s
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        } else {
            throw EngineError.invalidResponse("content 不是字符串或分段数组")
        }

        return OcrPage(pageNumber: options.pageNumber,
                       width: image.width, height: image.height,
                       lines: [], markdown: text)
    }
}

// MARK: - JsonHttp 引擎（Paddle 经典 PP-OCRv6）

/// POST {"image_b64": ...} → {"lines":[{text,score,box}]}，协议由 scripts/paddle_classic_server.py 提供。
public struct JsonHttpEngine: OCREngine {
    public let config: EngineConfig
    public let capabilities = EngineCapabilities(hasLineBoxes: true, outputsMarkdown: false)
    private let session: URLSession

    public init(config: EngineConfig, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.config = config.expandingTilde()
        self.session = session
    }

    public func healthCheck() async -> EngineHealth {
        let probeURL = config.launch?.healthURL ?? config.baseURL
        guard let urlStr = probeURL, let url = URL(string: urlStr) else { return .failed("缺少可探测地址") }
        return await HTTPProbe.alive(url, session: session) ? .ready : .notRunning
    }

    public func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage {
        try Task.checkCancellation()

        guard let base = config.baseURL, let url = URL(string: base + "/ocr") else {
            throw EngineError.invalidResponse("base_url 非法")
        }
        guard let png = ImageTools.pngData(from: image) else {
            throw EngineError.imageDecodeFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["image_b64": png.base64EncodedString()])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw EngineError.canceled
        } catch {
            throw EngineError.notReady("无法连接服务：\(error.localizedDescription)")
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw EngineError.invalidResponse("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Response: Decodable {
            struct Line: Decodable {
                let text: String
                let score: Double
                let box: [[Double]]
            }
            let width: Int?
            let height: Int?
            let lines: [Line]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EngineError.invalidResponse("响应不是 {lines:[{text,score,box}]} 结构")
        }

        let lines = decoded.lines.map { OcrLine(text: $0.text, score: $0.score, box: $0.box) }
        return OcrPage(pageNumber: options.pageNumber,
                       width: decoded.width ?? image.width,
                       height: decoded.height ?? image.height,
                       lines: lines, markdown: nil)
    }
}
