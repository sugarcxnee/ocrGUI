import Foundation

// MARK: - 引擎配置

/// 引擎适配器类型：
/// - builtinVision: 系统 Vision 框架（零配置、离线）
/// - openaiHTTP:    OpenAI Chat Completions 兼容 HTTP 服务（PaddleOCR-VL / Xiaomi 等 VLM）
/// - jsonHTTP:      自定义 JSON HTTP（POST base64 图片 → {lines:[...]}，Paddle 经典引擎）
public enum EngineKind: String, Codable, Sendable, Equatable {
    case builtinVision = "builtin-vision"
    case openaiHTTP = "openai-http"
    case jsonHTTP = "json-http"
}

public enum EngineConfigError: Error, Equatable, CustomStringConvertible {
    case missingBaseURL
    case launchMissingCommand
    case launchMissingHealthURL
    case invalidBaseURL

    public var description: String {
        switch self {
        case .missingBaseURL: return "HTTP 类引擎必须配置 base_url"
        case .launchMissingCommand: return "声明 launch 时 command 不能为空"
        case .launchMissingHealthURL: return "声明 launch 时必须给出 health_url"
        case .invalidBaseURL: return "base_url 不是合法的 http(s) 地址"
        }
    }
}

/// 引擎的进程托管声明：App 负责拉起服务并等待就绪
public struct EngineLaunch: Codable, Sendable, Equatable {
    public var command: String
    public var cwd: String?
    public var environment: [String: String]
    public var healthURL: String
    /// 健康探测最长等待秒数（模型冷启动可能 40s+）
    public var readyTimeout: TimeInterval
    /// 可选的自定义停止命令；缺省时直接结束子进程
    public var stopCommand: String?

    public init(command: String,
                cwd: String? = nil,
                environment: [String: String] = [:],
                healthURL: String,
                readyTimeout: TimeInterval = 180,
                stopCommand: String? = nil) {
        self.command = command
        self.cwd = cwd
        self.environment = environment
        self.healthURL = healthURL
        self.readyTimeout = readyTimeout
        self.stopCommand = stopCommand
    }

    private enum CodingKeys: String, CodingKey {
        case command, cwd, environment
        case healthURL = "health_url"
        case readyTimeout = "ready_timeout"
        case stopCommand = "stop_command"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decode(String.self, forKey: .command)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        healthURL = try c.decode(String.self, forKey: .healthURL)
        readyTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .readyTimeout) ?? 180
        stopCommand = try c.decodeIfPresent(String.self, forKey: .stopCommand)
    }
}

/// 一个引擎 = 一个 JSON 文件（~/Library/Application Support/OCRGUI/Engines/<id>.json）。
/// setup 脚本或设置界面写入；新增引擎不改核心 UI。
public struct EngineConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: EngineKind
    public var enabled: Bool
    public var baseURL: String?
    public var model: String?
    public var prompt: String?
    public var apiKey: String?
    /// 单次识别请求超时（秒）
    public var timeout: TimeInterval
    public var launch: EngineLaunch?
    /// 配置说明 / 安装提示，显示在设置界面
    public var notes: String?

    public init(id: String, name: String, kind: EngineKind, enabled: Bool,
                baseURL: String?, model: String?, prompt: String?, apiKey: String?,
                timeout: TimeInterval, launch: EngineLaunch?, notes: String?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.baseURL = baseURL
        self.model = model
        self.prompt = prompt
        self.apiKey = apiKey
        self.timeout = timeout
        self.launch = launch
        self.notes = notes
    }

    /// 语义校验（保存/启动前调用）
    public func validate() throws {
        switch kind {
        case .builtinVision:
            return
        case .openaiHTTP, .jsonHTTP:
            guard let baseURL, !baseURL.isEmpty else { throw EngineConfigError.missingBaseURL }
            guard URL(string: baseURL)?.scheme?.hasPrefix("http") == true else { throw EngineConfigError.invalidBaseURL }
            if let launch {
                guard !launch.command.isEmpty else { throw EngineConfigError.launchMissingCommand }
                guard !launch.healthURL.isEmpty else { throw EngineConfigError.launchMissingHealthURL }
            }
        }
    }

    /// 展开 launch.command / cwd / stopCommand / model 中的 ~ 前缀
    public func expandingTilde() -> EngineConfig {
        var copy = self
        if let model, model.hasPrefix("~") {
            copy.model = (model as NSString).expandingTildeInPath
        }
        if var launch = copy.launch {
            if launch.command.hasPrefix("~") {
                launch.command = (launch.command as NSString).expandingTildeInPath
            }
            if let cwd = launch.cwd, cwd.hasPrefix("~") {
                launch.cwd = (cwd as NSString).expandingTildeInPath
            }
            if let stop = launch.stopCommand, stop.hasPrefix("~") {
                launch.stopCommand = (stop as NSString).expandingTildeInPath
            }
            copy.launch = launch
        }
        return copy
    }

    // MARK: - Codable（snake_case，容忍缺省字段）

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, enabled
        case baseURL = "base_url", model, prompt
        case apiKey = "api_key"
        case timeout, launch, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(EngineKind.self, forKey: .kind)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        timeout = try c.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 300
        launch = try c.decodeIfPresent(EngineLaunch.self, forKey: .launch)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}
