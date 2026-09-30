import Foundation

/// 引擎服务进程管理（actor 保证串行）：
/// 1. 健康探测 → 已在跑（外部启动）则直接复用；
/// 2. 未运行 → 按 launch.command 拉起（zsh -c，合并 env 与 cwd），轮询 health_url 至就绪；
/// 3. stop/stopAll 只结束自己拉起的进程。
public actor EngineProcessManager {
    private var processes: [String: Process] = [:]
    private var states: [String: EngineHealth] = [:]
    private var log: @Sendable (String) -> Void

    public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
    }

    /// 允许初始化完成后再挂接日志出口（如 AppModel 建立后）
    public func updateLogSink(_ sink: @escaping @Sendable (String) -> Void) {
        log = sink
    }

    public func state(of id: String) -> EngineHealth {
        states[id] ?? .notRunning
    }

    @discardableResult
    public func ensureRunning(_ rawConfig: EngineConfig) async throws -> EngineHealth {
        let config = rawConfig.expandingTilde()

        // 已由本管理器托管且存活
        if let owned = processes[config.id], owned.isRunning {
            states[config.id] = .ready
            return .ready
        }
        processes[config.id] = nil

        // 外部已启动 → 复用
        if let probe = URL(string: config.launch?.healthURL ?? config.baseURL ?? "") {
            if await HTTPProbe.alive(probe) {
                states[config.id] = .ready
                return .ready
            }
        }

        guard let launch = config.launch else {
            states[config.id] = .notRunning
            return .notRunning
        }

        states[config.id] = .starting
        log("[\(config.id)] 启动服务: \(launch.command)")
        let process: Process
        do {
            process = try spawn(command: launch.command, cwd: launch.cwd, environment: launch.environment)
        } catch {
            states[config.id] = .failed("拉起进程失败：\(error.localizedDescription)")
            return states[config.id]!
        }
        processes[config.id] = process

        guard let healthURL = URL(string: launch.healthURL) else {
            stopOwned(config.id)
            states[config.id] = .failed("health_url 非法")
            return states[config.id]!
        }

        let deadline = Date().addingTimeInterval(launch.readyTimeout)
        while Date() < deadline {
            if Task.isCancelled {
                stopOwned(config.id)
                states[config.id] = .notRunning
                throw CancellationError()
            }
            if await HTTPProbe.alive(healthURL, timeout: 2) {
                states[config.id] = .ready
                return .ready
            }
            if !process.isRunning {
                let code = process.terminationStatus
                processes[config.id] = nil
                states[config.id] = .failed("服务进程提前退出（exit \(code)），请检查命令与模型路径")
                return states[config.id]!
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        stopOwned(config.id)
        states[config.id] = .failed("等待 \(Int(launch.readyTimeout))s 服务未就绪")
        return states[config.id]!
    }

    public func stop(_ id: String) async {
        stopOwned(id)
        states[id] = .notRunning
    }

    public func stopAll() async {
        for id in Array(processes.keys) {
            stopOwned(id)
            states[id] = .notRunning
        }
    }

    // MARK: - 私有

    private func spawn(command: String, cwd: String?, environment: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        if let cwd, !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let sink = log
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                sink(text)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                sink(text)
            }
        }
        try process.run()
        return process
    }

    private func stopOwned(_ id: String) {
        guard let process = processes[id] else { return }
        processes[id] = nil
        guard process.isRunning else { return }
        process.terminate()
        // 最多等 1.5s，仍存活则 SIGKILL
        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        log("[\(id)] 已停止服务进程")
    }
}
