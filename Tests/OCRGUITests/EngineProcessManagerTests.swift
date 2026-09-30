import Testing
import Foundation
@testable import OCRGUICore

// MARK: - EngineProcessManager（真实子进程 + 本地端口）

@Suite(.serialized)
struct EngineProcessManagerTests {

    /// 用 python3 申请一个空闲端口
    private func freePort() throws -> Int {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-c", "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Int(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    private func config(port: Int, command: String, readyTimeout: TimeInterval = 15) -> EngineConfig {
        EngineConfig(id: "proc-test", name: "Proc", kind: .openaiHTTP, enabled: true,
                     baseURL: "http://127.0.0.1:\(port)/v1", model: nil, prompt: nil, apiKey: nil,
                     timeout: 30,
                     launch: EngineLaunch(command: command,
                                          cwd: nil, environment: [:],
                                          healthURL: "http://127.0.0.1:\(port)/health",
                                          readyTimeout: readyTimeout, stopCommand: nil),
                     notes: nil)
    }

    @Test("健康探测成功前自动拉起服务，之后 shutdownOwned 停掉")
    func spawnsAndStopsProcess() async throws {
        let port = try freePort()
        #expect(port > 0)
        let manager = EngineProcessManager()
        let cfg = config(port: port,
                         command: "/usr/bin/python3 -m http.server \(port) --bind 127.0.0.1")

        let health = try await manager.ensureRunning(cfg)
        #expect(health == .ready)

        // 服务真实在监听
        #expect(await HTTPProbe.alive(URL(string: "http://127.0.0.1:\(port)/health")!) == true)

        await manager.stopAll()
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(await HTTPProbe.alive(URL(string: "http://127.0.0.1:\(port)/health")!) == false)
    }

    @Test("服务已在外部运行时直接复用，不接管进程")
    func reusesExternalService() async throws {
        let port = try freePort()
        let external = Process()
        external.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        external.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1"]
        try external.run()
        defer { external.terminate(); external.waitUntilExit() }

        // 等外部服务就绪
        for _ in 0..<20 {
            if await HTTPProbe.alive(URL(string: "http://127.0.0.1:\(port)/")!) { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let manager = EngineProcessManager()
        let cfg = config(port: port, command: "echo should-not-run")
        let health = try await manager.ensureRunning(cfg)
        #expect(health == .ready)

        await manager.stopAll()
        try await Task.sleep(nanoseconds: 300_000_000)
        // 外部进程不应被杀死
        #expect(external.isRunning)
        #expect(await HTTPProbe.alive(URL(string: "http://127.0.0.1:\(port)/")!) == true)
    }

    @Test("服务拉起后超时未就绪 → failed 且进程被清理")
    func failsWhenNotReadyInTime() async throws {
        let port = try freePort()
        let manager = EngineProcessManager()
        let cfg = config(port: port, command: "/bin/sleep 60", readyTimeout: 2)

        let health = try await manager.ensureRunning(cfg)
        guard case .failed = health else {
            Issue.record("期望 failed，实际 \(health)")
            return
        }
        // sleep 进程已被清理
        let state = await manager.state(of: "proc-test")
        #expect({ if case .failed = state { return true }; return false }())
    }
}
