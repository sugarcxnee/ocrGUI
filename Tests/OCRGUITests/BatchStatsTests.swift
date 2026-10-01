import Testing
import Foundation
import CoreGraphics
@testable import OCRGUICore

// MARK: - 批次统计（页级进度 / 已用时间 / 预计剩余）

@MainActor
@Suite(.serialized)
struct BatchStatsTests {

    @Test("页级计数与耗时：总页数、新识别页、断点复用页、elapsed 有值")
    func pageCountersAndElapsed() async throws {
        let historyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-stats-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: historyDir) }

        let runner = BatchRunner(history: HistoryStore(directory: historyDir))
        runner.addFile(URL(fileURLWithPath: "/tmp/a.pdf"))
        runner.addFile(URL(fileURLWithPath: "/tmp/b.png"))

        let engine = MockEngine(behavior: { _ in "p" }, delay: 0)
        #expect(runner.elapsed == nil)
        #expect(runner.estimatedRemainingSeconds == nil)

        await runner.start(engineConfig: engine.config, engine: engine,
                           loader: MockLoader(pagesPerJob: 2), dpi: 150).value

        #expect(runner.totalPagesKnown == 4)
        #expect(runner.pagesRecognized == 4)
        #expect(runner.pagesResumed == 0)
        // 每条记录带用时
        for record in runner.historyRecordsForTest() {
            #expect((record.duration ?? 0) > 0)
        }
        let elapsed = try #require(runner.elapsed)
        #expect(elapsed >= 0)
        // 已完成批次不再给 ETA
        #expect(runner.estimatedRemainingSeconds == nil)
    }

    @Test("断点复用页计入 pagesResumed，不计入新识别")
    func resumedPagesCounted() async throws {
        let historyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-stats2-\(UUID().uuidString)")
        let ckptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-stats2-ckpt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: historyDir)
            try? FileManager.default.removeItem(at: ckptDir) }

        let checkpoints = CheckpointStore(directory: ckptDir)
        let runner = BatchRunner(history: HistoryStore(directory: historyDir),
                                 checkpoints: checkpoints)

        let pdfDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocrgui-stats2-pdf-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: pdfDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pdfDir) }
        let pdf = try makeTestPDF(pages: [(200, 100), (200, 100)], dir: pdfDir)
        let size = Int64((try? pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let key = CheckpointStore.jobKey(path: pdf.path, fileSize: size,
                                         dpi: 150, engineID: "mock", prompt: nil)
        try checkpoints.save(JobCheckpoint(jobKey: key, pages: [
            OcrPage(pageNumber: 1, width: 1, height: 1, lines: [], markdown: "断点页"),
        ]))

        runner.addFile(pdf)
        let engine = MockEngine(behavior: { _ in "p" }, delay: 0)
        await runner.start(engineConfig: engine.config, engine: engine,
                           loader: FilePageLoader(), dpi: 150).value

        #expect(runner.totalPagesKnown == 2)
        #expect(runner.pagesRecognized == 1)
        #expect(runner.pagesResumed == 1)
    }
}
