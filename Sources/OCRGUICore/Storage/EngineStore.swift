import Foundation

/// 引擎配置存储：目录内每个 <id>.json 即一个引擎。
/// 首次启动种子化内置 Vision 与外部引擎模板（模板默认禁用，等 setup 脚本改写）。
public final class EngineStore {
    public let directory: URL
    public private(set) var configs: [EngineConfig] = []
    /// 加载时跳过的坏文件（文件名: 原因），供设置界面提示
    public private(set) var loadErrors: [String] = []

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OCRGUI/Engines", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    /// 加载；目录不存在或为空时写入默认引擎。不抛错（坏文件记入 loadErrors）。
    public func loadOrCreateDefaults() throws {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        if jsonFiles.isEmpty {
            for config in Self.defaultConfigs {
                try? persist(config)
            }
        }

        let decoder = JSONDecoder()
        var loaded: [EngineConfig] = []
        var errors: [String] = []
        for file in jsonFiles {
            do {
                let data = try Data(contentsOf: file)
                loaded.append(try decoder.decode(EngineConfig.self, from: data))
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // 种子化可能发生在本函数内（目录原为空），重新枚举
        if jsonFiles.isEmpty {
            for file in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let config = try? decoder.decode(EngineConfig.self, from: data) {
                    loaded.append(config)
                }
            }
        }
        configs = stableOrder(loaded)
        loadErrors = errors
    }

    /// 仅供测试：同步加载一次，返回配置数组
    public func loadForTest() -> [EngineConfig] {
        try? loadOrCreateDefaults()
        return configs
    }

    public func save(_ config: EngineConfig) throws {
        try config.validate()
        try persist(config)
        if let idx = configs.firstIndex(where: { $0.id == config.id }) {
            configs[idx] = config
        } else {
            configs.append(config)
            configs = stableOrder(configs)
        }
    }

    public func delete(id: String) throws {
        let url = directory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
        configs.removeAll { $0.id == id }
    }

    // MARK: - 私有

    private func stableOrder(_ list: [EngineConfig]) -> [EngineConfig] {
        // vision 永远排最前，其余按 id 稳定排序
        list.sorted { a, b in
            if a.id == "vision" { return b.id != "vision" }
            if b.id == "vision" { return false }
            return a.id < b.id
        }
    }

    private func persist(_ config: EngineConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: directory.appendingPathComponent("\(config.id).json"), options: .atomic)
    }

    // MARK: - 默认引擎（内置 + 中性模板）

    public static let defaultConfigs: [EngineConfig] = [
        EngineConfig(
            id: "vision",
            name: "Vision（系统内置）",
            kind: .builtinVision,
            enabled: true,
            baseURL: nil, model: nil, prompt: nil, apiKey: nil,
            timeout: 120,
            launch: nil,
            notes: "macOS 自带 Vision 框架，零配置、完全离线，支持中英文行级识别（准确度中等）。"),
        EngineConfig(
            id: "custom-vlm",
            name: "VLM 引擎（OpenAI 兼容，待安装）",
            kind: .openaiHTTP,
            enabled: false,
            baseURL: "http://127.0.0.1:8114/v1",
            model: nil,
            prompt: nil,
            apiKey: nil,
            timeout: 600,
            launch: EngineLaunch(
                command: "/path/to/runtime/vlm-env/bin/python /path/to/scripts/vlm_server.py --model /path/to/models/<模型名> --host 127.0.0.1 --port 8114",
                cwd: "/path/to/ocrGUI",
                environment: [:],
                healthURL: "http://127.0.0.1:8114/health",
                readyTimeout: 300),
            notes: "任意 HuggingFace VLM 模型：运行 scripts/setup_vlm_engine.sh --repo <HF repo> 一键安装；或连接任何已运行的 OpenAI 兼容服务（只填 base_url，不填 launch）。"),
        EngineConfig(
            id: "paddle-classic",
            name: "Paddle 经典 PP-OCRv6（det+rec）",
            kind: .jsonHTTP,
            enabled: false,
            baseURL: "http://127.0.0.1:8113",
            model: nil,
            prompt: nil,
            apiKey: nil,
            timeout: 300,
            launch: EngineLaunch(
                command: "/path/to/ocrGUI/runtime/paddle-classic-env/bin/python /path/to/ocrGUI/scripts/paddle_classic_server.py --host 127.0.0.1 --port 8113",
                cwd: "/path/to/ocrGUI",
                environment: ["PADDLE_PDX_CACHE_HOME": "/path/to/ocrGUI/models/paddlex_cache"],
                healthURL: "http://127.0.0.1:8113/health",
                readyTimeout: 180),
            notes: "项目自带的 json-http 引擎示例：行级坐标框+置信度。运行 scripts/setup_paddle_classic.sh 自动配置。"),
    ]
}
