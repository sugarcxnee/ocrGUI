import Testing
import Foundation
@testable import OCRGUICore

// MARK: - EngineConfig 解析 / 校验 / 占位符

@Test("解码最小 vision 配置，缺省字段取默认值")
func decodeMinimalVision() throws {
    let json = """
    {"id": "vision", "name": "Vision", "kind": "builtin-vision"}
    """
    let config = try JSONDecoder().decode(EngineConfig.self, from: Data(json.utf8))
    #expect(config.kind == .builtinVision)
    #expect(config.enabled)               // 默认启用
    #expect(config.timeout == 300)        // 默认请求超时
    #expect(config.launch == nil)
}

@Test("解码完整 openai-http 配置（含 launch），与 setup 脚本写入格式一致")
func decodeFullOpenAIConfig() throws {
    let json = """
    {
      "id": "paddle-vl",
      "name": "PaddleOCR-VL",
      "kind": "openai-http",
      "enabled": true,
      "base_url": "http://127.0.0.1:8112/v1",
      "model": "PaddleOCR-VL-1.6-4bit",
      "prompt": "Text Recognition:",
      "timeout": 600,
      "launch": {
        "command": "/repo/runtime/paddle-vl-env/bin/mlx_vlm.server --model /repo/models/PaddleOCR-VL-1.6-4bit --trust-remote-code --host 127.0.0.1 --port 8112",
        "cwd": "/repo",
        "environment": {"HF_HOME": "/repo/models/.hf"},
        "health_url": "http://127.0.0.1:8112/health",
        "ready_timeout": 200
      }
    }
    """
    let config = try JSONDecoder().decode(EngineConfig.self, from: Data(json.utf8))
    #expect(config.kind == .openaiHTTP)
    #expect(config.baseURL == "http://127.0.0.1:8112/v1")
    let launch = try #require(config.launch)
    #expect(launch.command.hasPrefix("/repo/runtime/"))
    #expect(launch.environment["HF_HOME"] == "/repo/models/.hf")
    #expect(launch.healthURL == "http://127.0.0.1:8112/health")
    #expect(launch.readyTimeout == 200)
}

@Test("launch 缺省字段取默认就绪超时 180s")
func launchDefaultReadyTimeout() throws {
    let json = """
    {"id": "x", "name": "X", "kind": "json-http", "base_url": "http://127.0.0.1:9/v1",
     "launch": {"command": "true", "health_url": "http://127.0.0.1:9/health"}}
    """
    let config = try JSONDecoder().decode(EngineConfig.self, from: Data(json.utf8))
    #expect(config.launch?.readyTimeout == 180)
}

@Test("~ 在 launch.command/cwd 与 model 中展开")
func tildeExpansion() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let json = """
    {"id": "x", "name": "X", "kind": "openai-http", "base_url": "http://127.0.0.1:1/v1",
     "model": "~/models/xiaomi",
     "launch": {"command": "~/runtime/env/bin/srv", "cwd": "~/proj", "health_url": "http://127.0.0.1:1/health"}}
    """
    let config = try JSONDecoder().decode(EngineConfig.self, from: Data(json.utf8))
    let expanded = config.expandingTilde()
    #expect(expanded.model == "\(home)/models/xiaomi")
    #expect(expanded.launch?.command == "\(home)/runtime/env/bin/srv")
    #expect(expanded.launch?.cwd == "\(home)/proj")
}

@Test("编码往返保持内容一致")
func encodeRoundtrip() throws {
    let config = EngineConfig(id: "a", name: "A", kind: .jsonHTTP, enabled: false,
                              baseURL: "http://127.0.0.1:2/v1", model: nil, prompt: nil, apiKey: nil,
                              timeout: 120,
                              launch: EngineLaunch(command: "run", cwd: nil, environment: ["K": "V"],
                                                          healthURL: "http://127.0.0.1:2/h", readyTimeout: 60, stopCommand: nil),
                              notes: "说明")
    let data = try JSONEncoder().encode(config)
    #expect(try JSONDecoder().decode(EngineConfig.self, from: data) == config)
}

@Test("校验：http 类引擎必须有 base_url")
func validateRequiresBaseURL() throws {
    let bad = EngineConfig(id: "b", name: "B", kind: .openaiHTTP, enabled: true,
                           baseURL: nil, model: nil, prompt: nil, apiKey: nil, timeout: 300, launch: nil, notes: nil)
    #expect(throws: EngineConfigError.self) { try bad.validate() }

    let good = EngineConfig(id: "b", name: "B", kind: .openaiHTTP, enabled: true,
                            baseURL: "http://127.0.0.1:1/v1", model: nil, prompt: nil, apiKey: nil,
                            timeout: 300, launch: nil, notes: nil)
    try good.validate()
}

@Test("校验：openai 引擎若声明 launch 必须给出 health_url 与 command")
func validateLaunchFields() throws {
    let bad = EngineConfig(id: "b", name: "B", kind: .openaiHTTP, enabled: true,
                           baseURL: "http://127.0.0.1:1/v1", model: nil, prompt: nil, apiKey: nil, timeout: 300,
                           launch: EngineLaunch(command: "", cwd: nil, environment: [:],
                                                       healthURL: "http://127.0.0.1:1/h", readyTimeout: 180, stopCommand: nil),
                           notes: nil)
    #expect(throws: EngineConfigError.self) { try bad.validate() }
}

// MARK: - EngineStore

@Test("空目录首次加载会种子化默认引擎（vision 可用，其余为中性模板）")
func engineStoreSeedsDefaults() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-engines-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = EngineStore(directory: dir)
    try store.loadOrCreateDefaults()

    let ids = store.configs.map(\.id)
    #expect(ids.contains("vision"))
    #expect(ids.contains("paddle-classic"))
    #expect(ids.contains("custom-vlm"))
    // 引擎模板不预设具体第三方模型——保持 GUI 引擎中立
    #expect(!ids.contains("paddle-vl"))
    #expect(!ids.contains("xiaomi-ocr-0"))

    let vision = store.configs.first { $0.id == "vision" }
    #expect(vision?.enabled == true)
    #expect(store.configs.filter { $0.id != "vision" }.allSatisfy { !$0.enabled })

    // 文件确实写盘，重启后仍能读到
    let reloaded = EngineStore(directory: dir)
    try reloaded.loadOrCreateDefaults()
    #expect(reloaded.configs.count == store.configs.count)
}

@Test("损坏的引擎文件被跳过并记录错误，不影响其他引擎加载")
func invalidEngineFileCollectedAsError() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-engines-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let good = """
    {"id": "vision", "name": "Vision", "kind": "builtin-vision"}
    """
    try Data(good.utf8).write(to: dir.appendingPathComponent("vision.json"))
    try Data("not-json{".utf8).write(to: dir.appendingPathComponent("broken.json"))

    let store = EngineStore(directory: dir)
    try store.loadOrCreateDefaults()
    #expect(store.configs.count == 1)
    #expect(store.loadErrors.count == 1)
    #expect(store.loadErrors.first?.contains("broken.json") == true)
}

@Test("保存新引擎落盘，删除引擎移除文件")
func saveAndDeleteEngine() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-engines-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = EngineStore(directory: dir)
    try store.loadOrCreateDefaults()

    let custom = EngineConfig(id: "my-engine", name: "我的引擎", kind: .openaiHTTP, enabled: true,
                              baseURL: "http://127.0.0.1:9000/v1", model: "m", prompt: "p", apiKey: nil,
                              timeout: 300, launch: nil, notes: nil)
    try store.save(custom)
    #expect(EngineStore(directory: dir).loadForTest().contains { $0.id == "my-engine" })

    try store.delete(id: "my-engine")
    #expect(!EngineStore(directory: dir).loadForTest().contains { $0.id == "my-engine" })
}
