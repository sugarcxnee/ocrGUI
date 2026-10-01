import Foundation

// MARK: - 应用内模型安装

/// 一次"添加模型"请求：由设置界面的安装表单产生
public struct ModelInstallRequest: Sendable, Equatable {
    public enum Backend: String, Sendable, CaseIterable {
        case mlx = "MLX（mlx-community 模型，Apple GPU）"
        case transformersVLM = "transformers VLM（任意 HF 多模态模型）"

        public var scriptName: String {
            switch self {
            case .mlx: return "setup_mlx_engine.sh"
            case .transformersVLM: return "setup_vlm_engine.sh"
            }
        }

        public var sampleRepo: String {
            switch self {
            case .mlx: return "mlx-community/GLM-OCR-4bit"
            case .transformersVLM: return "SeerRay-Lab/Xiaomi-OCR-0"
            }
        }
    }

    public var backend: Backend
    public var repo: String
    public var engineID: String
    public var displayName: String
    public var port: Int
    public var prompt: String
    public var fallbackPrompt: String?
    /// ocrGUI 仓库根目录（须含 scripts/）
    public var projectDirectory: String
    /// 下载镜像（国内网络建议），nil = 直连
    public var pipMirror: String?
    public var hfMirror: String?

    public init(backend: Backend, repo: String, engineID: String, displayName: String,
                port: Int, prompt: String, fallbackPrompt: String?,
                projectDirectory: String, pipMirror: String?, hfMirror: String?) {
        self.backend = backend
        self.repo = repo
        self.engineID = engineID
        self.displayName = displayName
        self.port = port
        self.prompt = prompt
        self.fallbackPrompt = fallbackPrompt
        self.projectDirectory = projectDirectory
        self.pipMirror = pipMirror
        self.hfMirror = hfMirror
    }
}

public enum ModelInstallerError: Error, Equatable, CustomStringConvertible {
    case scriptNotFound(String)
    case exited(code: Int32, tail: String)

    public var description: String {
        switch self {
        case .scriptNotFound(let path):
            return "未找到安装脚本：\(path)（请确认项目目录正确）"
        case .exited(let code, let tail):
            return "安装失败（exit \(code)）：\(tail)"
        }
    }
}

/// 把"添加模型"翻译成对仓库内通用安装脚本的调用并执行——
/// 应用与终端脚本共用同一套安装逻辑（单一事实源），应用内只是包了进度与日志。
public enum ModelInstaller {

    public struct Command: Sendable, Equatable {
        /// 解释器（/bin/zsh）
        public let executable: URL
        /// 安装脚本绝对路径
        public let scriptPath: String
        /// 传给脚本的参数
        public let arguments: [String]
        public let environment: [String: String]
    }

    public static func defaultEngineID(forRepo repo: String) -> String {
        String(repo.split(separator: "/").last ?? Substring(repo))
    }

    /// 构造脚本命令（项目目录缺脚本返回 nil）
    public static func command(for request: ModelInstallRequest) -> Command? {
        let script = URL(fileURLWithPath: request.projectDirectory)
            .appendingPathComponent("scripts/\(request.backend.scriptName)")
        guard FileManager.default.fileExists(atPath: script.path) else {
            return nil
        }

        var arguments: [String] = [
            "--repo", request.repo,
            "--id", request.engineID,
            "--name", request.displayName,
            "--port", String(request.port),
            "--prompt", request.prompt,
        ]
        if request.backend == .transformersVLM, let fallback = request.fallbackPrompt, !fallback.isEmpty {
            arguments += ["--fallback-prompt", fallback]
        }

        var environment: [String: String] = [:]
        if let pip = request.pipMirror, !pip.isEmpty { environment["PIP_INDEX_URL"] = pip }
        if let hf = request.hfMirror, !hf.isEmpty { environment["HF_ENDPOINT"] = hf }
        return Command(executable: URL(fileURLWithPath: "/bin/zsh"),
                       scriptPath: script.path,
                       arguments: arguments,
                       environment: environment)
    }

    /// 执行安装脚本，实时回调日志行；非零退出抛错；外层 Task 取消时终止子进程。
    public static func run(request: ModelInstallRequest,
                           log: @escaping @Sendable (String) -> Void) async throws -> Void {
        guard let command = command(for: request) else {
            throw ModelInstallerError.scriptNotFound(
                request.projectDirectory + "/scripts/" + request.backend.scriptName)
        }

        let box = ProcessBox()

        try await withTaskCancellationHandler {
            let process = Process()
            process.executableURL = command.executable
            process.arguments = [command.scriptPath] + command.arguments
            var env = ProcessInfo.processInfo.environment
            for (key, value) in command.environment { env[key] = value }
            process.environment = env
            process.currentDirectoryURL = URL(fileURLWithPath: request.projectDirectory)

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            streamLines(of: out, box: box, log: log)
            streamLines(of: err, box: box, log: log)

            box.setProcess(process)
            do {
                try process.run()
            } catch {
                throw ModelInstallerError.exited(code: -1, tail: error.localizedDescription)
            }

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { terminated in
                    if terminated.terminationStatus == 0 {
                        cont.resume()
                    } else {
                        cont.resume(throwing: ModelInstallerError.exited(
                            code: terminated.terminationStatus,
                            tail: box.tailString()))
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    // MARK: - 私有

    private static func streamLines(of pipe: Pipe, box: ProcessBox,
                                    log: @escaping @Sendable (String) -> Void) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: chunk, encoding: .utf8) else { return }
            for fragment in text.split(separator: "\n") where !fragment.isEmpty {
                let line = String(fragment)
                box.appendTail(line)
                log(line)
            }
        }
    }

    /// 进程句柄与尾部日志（读回调在任意队列触发，加锁）
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var tail = ""

        func setProcess(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        func terminate() {
            lock.lock()
            let current = process
            lock.unlock()
            if current?.isRunning == true {
                current?.terminate()
            }
        }

        func appendTail(_ line: String) {
            lock.lock()
            tail = ((tail + line + "\n") as String).suffix(600).description
            lock.unlock()
        }

        func tailString() -> String {
            lock.lock()
            defer { lock.unlock() }
            return tail
        }
    }
}
