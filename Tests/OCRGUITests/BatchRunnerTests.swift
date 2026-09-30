import Testing
import Foundation
import CoreGraphics
@testable import OCRGUICore

// MARK: - BatchRunner 批处理管线

/// 可编程 Mock 引擎：按页号返回结果或抛错，支持延迟模拟耗时
struct MockEngine: OCREngine {
    let config = EngineConfig(id: "mock", name: "Mock", kind: .builtinVision, enabled: true,
                              baseURL: nil, model: nil, prompt: nil, apiKey: nil,
                              timeout: 30, launch: nil, notes: nil)
    let capabilities = EngineCapabilities(hasLineBoxes: true, outputsMarkdown: false)
    let behavior: @Sendable (Int) throws -> String
    let delay: TimeInterval

    func healthCheck() async -> EngineHealth { .ready }

    func recognize(image: CGImage, options: RecognizeOptions) async throws -> OcrPage {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        let text = try behavior(options.pageNumber)
        return OcrPage(pageNumber: options.pageNumber, width: image.width, height: image.height,
                       lines: [OcrLine(text: text, score: 1, box: [])], markdown: nil)
    }
}

/// Mock 页面加载器：每个任务返回固定页数的纯色图
struct MockLoader: PageLoader {
    let pagesPerJob: Int
    func load(job: BatchJob, dpi: CGFloat) throws -> [PageLoad] {
        (1...pagesPerJob).map { pageNumber in
            PageLoad(image: solidImage(width: 40, height: 30),
                     pageNumber: pageNumber, totalPages: pagesPerJob)
        }
    }
}

@MainActor
@Suite(.serialized)
struct BatchRunnerTests {

    private func makeRunner(dir: URL) -> (BatchRunner, HistoryStore) {
        let history = HistoryStore(directory: dir)
        return (BatchRunner(history: history), history)
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-batch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("顺序处理全部任务，产出历史记录，回调收到新记录")
    func processesAllJobs() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (runner, history) = makeRunner(dir: dir)

        var added: [String] = []
        runner.onRecordAdded = { added.append($0.fileName) }

        runner.addFile(URL(fileURLWithPath: "/tmp/a.png"))
        runner.addFile(URL(fileURLWithPath: "/tmp/b.pdf"))
        #expect(runner.jobs.count == 2)
        #expect(runner.jobs.allSatisfy { $0.status == .pending })

        let engine = MockEngine(behavior: { page in "第\(page)页" }, delay: 0)
        await runner.start(engineConfig: engine.config, engine: engine, loader: MockLoader(pagesPerJob: 2), dpi: 150).value

        #expect(runner.jobs.allSatisfy { $0.status == .done })
        #expect(history.records.count == 2)
        #expect(added == ["a.png", "b.pdf"])
        // PDF 任务两页、每页一行
        let pdfRecord = history.records.first { $0.fileName == "b.pdf" }
        #expect(pdfRecord?.pages.count == 2)
        #expect(pdfRecord?.pages.first?.lines.first?.text == "第1页")
        #expect(!runner.isRunning)
    }

    @Test("单个任务失败不影响其余任务")
    func failureIsolated() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (runner, history) = makeRunner(dir: dir)

        runner.addFile(URL(fileURLWithPath: "/tmp/ok1.png"))
        let failing = runner.addFile(URL(fileURLWithPath: "/tmp/bad.png"))
        runner.addFile(URL(fileURLWithPath: "/tmp/ok2.png"))

        // 第 2 个文件对应任务：behavior 不知文件名 → 用页号模拟；改为在 loader 上抛错更直接
        struct FailingLoader: PageLoader {
            let failFile: String
            func load(job: BatchJob, dpi: CGFloat) throws -> [PageLoad] {
                guard job.fileName != failFile else {
                    throw EngineError.imageDecodeFailed
                }
                return [PageLoad(image: solidImage(width: 10, height: 10), pageNumber: 1, totalPages: 1)]
            }
        }

        let engine = MockEngine(behavior: { _ in "ok" }, delay: 0)
        await runner.start(engineConfig: engine.config, engine: engine,
                           loader: FailingLoader(failFile: "bad.png"), dpi: 150).value

        #expect(runner.jobs.first { $0.id == failing }?.status == .failed("图片解码失败"))
        #expect(runner.jobs.filter { $0.status == .done }.count == 2)
        #expect(history.records.count == 2)
    }

    @Test("取消：进行中任务标记取消，后续任务保持待处理")
    func cancellationStopsBatch() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (runner, history) = makeRunner(dir: dir)

        for name in ["1.png", "2.png", "3.png"] {
            runner.addFile(URL(fileURLWithPath: "/tmp/\(name)"))
        }

        let engine = MockEngine(behavior: { _ in "text" }, delay: 0.4)
        let task = runner.start(engineConfig: engine.config, engine: engine,
                                loader: MockLoader(pagesPerJob: 1), dpi: 150)
        // 等第 1 个完成后取消
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(history.records.count == 1)
        runner.cancel()
        await task.value

        #expect(!runner.isRunning)
        #expect(runner.jobs[0].status == .done)
        #expect(runner.jobs[1].status == .cancelled)
        #expect(runner.jobs[2].status == .pending)
        #expect(history.records.count == 1)
    }

    @Test("运行中页级进度可见")
    func reportsPageProgress() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (runner, _) = makeRunner(dir: dir)
        runner.addFile(URL(fileURLWithPath: "/tmp/multi.pdf"))

        let engine = MockEngine(behavior: { _ in "p" }, delay: 0.05)
        let progressTask = runner.start(engineConfig: engine.config, engine: engine,
                                        loader: MockLoader(pagesPerJob: 3), dpi: 150)
        try await Task.sleep(nanoseconds: 120_000_000)
        let sawRunning = runner.jobs.contains {
            if case .running(let page, let total) = $0.status { return page >= 1 && total == 3 }
            return false
        }
        await progressTask.value
        #expect(sawRunning)
        #expect(runner.jobs.allSatisfy { $0.status == .done })
    }
}

// MARK: - FilePageLoader（真实文件）

@Suite(.serialized)
struct FilePageLoaderTests {

    @Test("图片文件 → 单页；PDF 文件 → 多页")
    func loadsImagesAndPDFs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-loader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let pngURL = dir.appendingPathComponent("img.png")
        try #require(ImageTools.pngData(from: solidImage(width: 64, height: 48))).write(to: pngURL)
        let pdfURL = try makeTestPDF(pages: [(200, 100), (200, 100)], dir: dir)

        let loader = FilePageLoader()

        let imagePages = try #require(try loader.load(job: BatchJob(fileName: "img.png", kind: .image, url: pngURL), dpi: 72))
        #expect(imagePages.count == 1)
        #expect(imagePages[0].image.width == 64)

        let pdfPages = try #require(try loader.load(job: BatchJob(fileName: "t.pdf", kind: .pdf, url: pdfURL), dpi: 72))
        #expect(pdfPages.count == 2)
        #expect(pdfPages[0].totalPages == 2)
        // 200pt @72dpi = 200px
        #expect(pdfPages[0].image.width == 200)
    }

    @Test("携带图片的任务（剪贴板/截图）直接返回该图")
    func loadsCarriedImage() throws {
        let loader = FilePageLoader()
        let job = BatchJob(fileName: "clip.png", kind: .clipboard, carriedImage: solidImage(width: 30, height: 20))
        let pages = try #require(try loader.load(job: job, dpi: 150))
        #expect(pages.count == 1)
        #expect(pages[0].image.width == 30)
    }
}
