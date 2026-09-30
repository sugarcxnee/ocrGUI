import Foundation
import CoreGraphics

// MARK: - 引擎协议

/// 引擎健康/就绪状态（设置界面状态灯、启动流程共用）
public enum EngineHealth: Sendable, Equatable {
    case ready
    case notRunning
    case starting
    case failed(String)
}

/// 引擎输出能力，UI 据此决定是否展示坐标框 overlay 等
public struct EngineCapabilities: Sendable, Equatable {
    public var hasLineBoxes: Bool
    public var outputsMarkdown: Bool

    public init(hasLineBoxes: Bool, outputsMarkdown: Bool) {
        self.hasLineBoxes = hasLineBoxes
        self.outputsMarkdown = outputsMarkdown
    }
}

/// 识别选项（语言偏好等，随请求传递）
public struct RecognizeOptions: Sendable {
    public var languages: [String]
    public var pageNumber: Int

    public init(languages: [String] = ["zh-Hans", "en-US"], pageNumber: Int = 1) {
        self.languages = languages
        self.pageNumber = pageNumber
    }
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case canceled
    case imageDecodeFailed
    case invalidResponse(String)
    case httpStatus(Int, String)
    case notReady(String)
    case launchFailed(String)
    case requestFailed(String)

    public var description: String {
        switch self {
        case .canceled: return "已取消"
        case .imageDecodeFailed: return "图片解码失败"
        case .invalidResponse(let detail): return "响应无效：\(detail)"
        case .httpStatus(let code, let body): return "服务返回 HTTP \(code)：\(body.prefix(200))"
        case .notReady(let detail): return "服务未就绪：\(detail)"
        case .launchFailed(let detail): return "启动失败：\(detail)"
        case .requestFailed(let detail): return "请求失败：\(detail)"
        }
    }
}

/// 所有 OCR 引擎的统一接口。新增引擎 = 新配置 + 对应适配器，核心 UI 不变。
public protocol OCREngine: Sendable {
    var config: EngineConfig { get }
    var capabilities: EngineCapabilities { get }
    func healthCheck() async -> EngineHealth
    func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage
}

// MARK: - 工厂

public enum EngineFactoryError: Error, Equatable {
    case unsupportedKind(EngineKind)
}

public enum EngineFactory {
    public static func make(config: EngineConfig) throws -> OCREngine {
        switch config.kind {
        case .builtinVision:
            return VisionEngine(config: config)
        case .openaiHTTP:
            return OpenAICompatEngine(config: config)
        case .jsonHTTP:
            return JsonHttpEngine(config: config)
        }
    }
}
