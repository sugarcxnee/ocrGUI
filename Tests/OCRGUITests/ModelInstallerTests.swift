import Testing
import Foundation
@testable import OCRGUICore

// MARK: - 应用内模型安装器

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    func append(_ line: String) { lock.lock(); _lines.append(line); lock.unlock() }
}

struct ModelInstallerTests {

    private func makeProject() throws -> (URL, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        for script in ["setup_vlm_engine.sh", "setup_mlx_engine.sh"] {
            try Data("#!/bin/zsh\n".utf8)
                .write(to: dir.appendingPathComponent("scripts/\(script)"))
        }
        return (dir, dir.path)
    }

    private func request(backend: ModelInstallRequest.Backend,
                         repo: String = "mlx-community/GLM-OCR-4bit",
                         fallback: String? = nil,
                         project: String) -> ModelInstallRequest {
        ModelInstallRequest(backend: backend,
                            repo: repo,
                            engineID: "glm-ocr",
                            displayName: "GLM-OCR",
                            port: 8116,
                            prompt: "转写为 Markdown",
                            fallbackPrompt: fallback,
                            projectDirectory: project,
                            pipMirror: "https://pypi.tuna.tsinghua.edu.cn/simple",
                            hfMirror: "https://hf-mirror.com")
    }

    @Test("MLX 后端：脚本路径、参数与镜像环境变量")
    func mlxCommand() throws {
        let (url, project) = try makeProject()
        defer { try? FileManager.default.removeItem(at: url) }

        let command = try #require(ModelInstaller.command(for: request(backend: .mlx, project: project)))
        #expect(command.scriptPath.hasSuffix("setup_mlx_engine.sh"))
        let args = command.arguments
        #expect(args.contains("--repo") && args[args.firstIndex(of: "--repo")! + 1] == "mlx-community/GLM-OCR-4bit")
        #expect(args.contains("--id") && args[args.firstIndex(of: "--id")! + 1] == "glm-ocr")
        #expect(args.contains("--name") && args[args.firstIndex(of: "--name")! + 1] == "GLM-OCR")
        #expect(args.contains("--port") && args[args.firstIndex(of: "--port")! + 1] == "8116")
        #expect(args.contains("--prompt"))
        // mlx 脚本没有 fallback 参数
        #expect(!args.contains("--fallback-prompt"))
        #expect(command.environment["PIP_INDEX_URL"] == "https://pypi.tuna.tsinghua.edu.cn/simple")
        #expect(command.environment["HF_ENDPOINT"] == "https://hf-mirror.com")
    }

    @Test("transformers 后端：带兜底提示词")
    func vlmCommandWithFallback() throws {
        let (url, project) = try makeProject()
        defer { try? FileManager.default.removeItem(at: url) }

        let command = try #require(ModelInstaller.command(
            for: request(backend: .transformersVLM,
                         repo: "SeerRay-Lab/Xiaomi-OCR-0",
                         fallback: "Task: Text Extraction.",
                         project: project)))
        #expect(command.scriptPath.hasSuffix("setup_vlm_engine.sh"))
        let args = command.arguments
        #expect(args.contains("--fallback-prompt")
                && args[args.firstIndex(of: "--fallback-prompt")! + 1] == "Task: Text Extraction.")
        #expect(args.contains("--repo")
                && args[args.firstIndex(of: "--repo")! + 1] == "SeerRay-Lab/Xiaomi-OCR-0")
    }

    @Test("项目目录缺脚本时返回 nil；镜像为空时不注入环境变量")
    func missingScriptAndEmptyMirrors() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(ModelInstaller.command(for: request(backend: .mlx, project: empty.path)) == nil)

        let (url, project) = try makeProject()
        defer { try? FileManager.default.removeItem(at: url) }
        var noMirror = request(backend: .mlx, project: project)
        noMirror.pipMirror = nil
        noMirror.hfMirror = nil
        let command = try #require(ModelInstaller.command(for: noMirror))
        #expect(command.environment["PIP_INDEX_URL"] == nil)
        #expect(command.environment["HF_ENDPOINT"] == nil)
    }

    @Test("引擎 ID 从 repo 名推导")
    func engineIDDerivation() {
        #expect(ModelInstaller.defaultEngineID(forRepo: "SeerRay-Lab/Xiaomi-OCR-0") == "Xiaomi-OCR-0")
        #expect(ModelInstaller.defaultEngineID(forRepo: "mlx-community/GLM-OCR-4bit") == "GLM-OCR-4bit")
    }

    @Test("run：真实执行脚本并回传日志（echo 假脚本）")
    func runExecutesAndStreams() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-installer-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("""
        #!/bin/zsh
        echo "stage-1"
        echo "stage-2"
        """.utf8).write(to: dir.appendingPathComponent("scripts/setup_mlx_engine.sh"))

        let box = LogBox()
        try await ModelInstaller.run(request: request(backend: .mlx, project: dir.path)) { line in
            box.append(line)
        }
        #expect(box.lines.contains { $0.contains("stage-1") })
        #expect(box.lines.contains { $0.contains("stage-2") })
    }

    @Test("run：脚本非零退出码抛错")
    func runThrowsOnFailure() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-installer-fail-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try? Data("#!/bin/zsh\necho bad >&2\nexit 3\n".utf8)
            .write(to: dir.appendingPathComponent("scripts/setup_mlx_engine.sh"))

        await #expect(throws: ModelInstallerError.self) {
            try await ModelInstaller.run(request: request(backend: .mlx, project: dir.path)) { _ in }
        }
    }
}
