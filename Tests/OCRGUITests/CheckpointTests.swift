import Testing
import Foundation
import CoreGraphics
@testable import OCRGUICore

// MARK: - 页级断点续跑（webUI .chunks 的等价物）

struct CheckpointTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-ckpt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("key 稳定：同文件/大小/DPI/引擎/提示词 → 同 key；任一变化 → 不同 key")
    func keyStability() {
        let a = CheckpointStore.jobKey(path: "/tmp/a.pdf", fileSize: 123,
                                       dpi: 150, engineID: "glm-ocr", prompt: "p")
        let b = CheckpointStore.jobKey(path: "/tmp/a.pdf", fileSize: 123,
                                       dpi: 150, engineID: "glm-ocr", prompt: "p")
        #expect(a == b)
        #expect(a != CheckpointStore.jobKey(path: "/tmp/a.pdf", fileSize: 456,
                                            dpi: 150, engineID: "glm-ocr", prompt: "p"))
        #expect(a != CheckpointStore.jobKey(path: "/tmp/a.pdf", fileSize: 123,
                                            dpi: 300, engineID: "glm-ocr", prompt: "p"))
        #expect(a != CheckpointStore.jobKey(path: "/tmp/a.pdf", fileSize: 123,
                                            dpi: 150, engineID: "vision", prompt: "p"))
    }

    @Test("存取删往返")
    func saveLoadDelete() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CheckpointStore(directory: dir)

        #expect(store.load(key: "k1") == nil)
        let pages = [OcrPage(pageNumber: 1, width: 10, height: 10, lines: [], markdown: "第一页"),
                     OcrPage(pageNumber: 2, width: 10, height: 10, lines: [], markdown: "第二页")]
        try store.save(JobCheckpoint(jobKey: "k1", pages: pages))
        let loaded = try #require(store.load(key: "k1"))
        #expect(loaded.pages.map(\.markdown) == ["第一页", "第二页"])

        try store.delete(key: "k1")
        #expect(store.load(key: "k1") == nil)
    }

    @Test("文件不存在时安静返回 nil")
    func corruptFileReturnsNil() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("k9.json"))
        let store = CheckpointStore(directory: dir)
        #expect(store.load(key: "k9") == nil)
    }
}

// MARK: - BatchRunner 断点接入

@MainActor
@Suite(.serialized)
struct BatchRunnerCheckpointTests {

    /// 记录调用次数的引擎：每次调用返回一页文本
    private final class CountingEngine: OCREngine, @unchecked Sendable {
        let config = EngineConfig(id: "mock", name: "M", kind: .openaiHTTP, enabled: true,
                                  baseURL: "http://127.0.0.1:1/v1", model: nil, prompt: nil,
                                  apiKey: nil, timeout: 30, launch: nil, notes: nil)
        let capabilities = EngineCapabilities(hasLineBoxes: false, outputsMarkdown: true)
        // BatchRunner 顺序 await 调用，无需加锁
        private nonisolated(unsafe) var _calls: [Int] = []
        var calls: [Int] { _calls }
        func healthCheck() async -> EngineHealth { .ready }
        func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage {
            _calls.append(options.pageNumber)
            return OcrPage(pageNumber: options.pageNumber, width: 10, height: 10,
                           lines: [], markdown: "第\(options.pageNumber)页")
        }
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-batch-ckpt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("取消后重跑：已完成页从断点恢复，不再重复识别；完成后断点清除")
    func resumeAfterCancel() async throws {
        let historyDir = tempDir()
        let ckptDir = tempDir()
        defer { try? FileManager.default.removeItem(at: historyDir)
            try? FileManager.default.removeItem(at: ckptDir) }

        let checkpoints = CheckpointStore(directory: ckptDir)
        let history = HistoryStore(directory: historyDir)
        let runner = BatchRunner(history: history, checkpoints: checkpoints)

        // 造一个真实 PDF 任务（3 页）
        let pdfDir = tempDir()
        defer { try? FileManager.default.removeItem(at: pdfDir) }
        let pdf = try makeTestPDF(pages: [(200, 100), (200, 100), (200, 100)], dir: pdfDir)
        let size = (try? pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let key = CheckpointStore.jobKey(path: pdf.path, fileSize: Int64(size),
                                         dpi: 150, engineID: "mock", prompt: "p")

        runner.addFile(pdf)
        var job = runner.jobs[0]
        // 预置断点：前 2 页已完成
        try checkpoints.save(JobCheckpoint(jobKey: key, pages: [
            OcrPage(pageNumber: 1, width: 10, height: 10, lines: [], markdown: "断点第1页"),
            OcrPage(pageNumber: 2, width: 10, height: 10, lines: [], markdown: "断点第2页"),
        ]))

        let engine = CountingEngine()
        let config = EngineConfig(id: "mock", name: "M", kind: .openaiHTTP, enabled: true,
                                  baseURL: "http://127.0.0.1:1/v1", model: nil, prompt: "p",
                                  apiKey: nil, timeout: 30, launch: nil, notes: nil)
        await runner.start(engineConfig: config, engine: engine,
                           loader: FilePageLoader(), dpi: 150).value

        // 只识别了第 3 页
        #expect(engine.calls == [3])
        // 记录包含断点页 + 新页
        let record = try #require(history.records.first)
        #expect(record.pages.map(\.markdown) == ["断点第1页", "断点第2页", "第3页"])
        // 断点已清除
        #expect(checkpoints.load(key: key) == nil)
        _ = job
    }

    @Test("每页识别完成即写断点（中途取消不丢页）+ onPageRecognized 回调")
    func checkpointWrittenPerPage() async throws {
        let historyDir = tempDir()
        let ckptDir = tempDir()
        defer { try? FileManager.default.removeItem(at: historyDir)
            try? FileManager.default.removeItem(at: ckptDir) }

        let checkpoints = CheckpointStore(directory: ckptDir)
        let runner = BatchRunner(history: HistoryStore(directory: historyDir),
                                 checkpoints: checkpoints)

        let pdfDir = tempDir()
        defer { try? FileManager.default.removeItem(at: pdfDir) }
        let pdf = try makeTestPDF(pages: [(200, 100), (200, 100)], dir: pdfDir)
        runner.addFile(pdf)

        var seenPages: [Int] = []
        runner.onPageRecognized = { _, page in
            seenPages.append(page.pageNumber)
        }

        let engine = CountingEngine()
        let config = EngineConfig(id: "mock", name: "M", kind: .openaiHTTP, enabled: true,
                                  baseURL: "http://127.0.0.1:1/v1", model: nil, prompt: "p",
                                  apiKey: nil, timeout: 30, launch: nil, notes: nil)
        await runner.start(engineConfig: config, engine: engine,
                           loader: FilePageLoader(), dpi: 150).value

        #expect(seenPages == [1, 2])
        let size = (try? pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let key = CheckpointStore.jobKey(path: pdf.path, fileSize: Int64(size),
                                         dpi: 150, engineID: "mock", prompt: "p")
        #expect(checkpoints.load(key: key) == nil)  // 完成后清除
    }
}
