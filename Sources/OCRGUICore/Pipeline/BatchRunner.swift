import Foundation
import CoreGraphics

// MARK: - 批处理数据结构

/// 一页待识别图像
public struct PageLoad: Sendable {
    public let image: CGImage
    public let pageNumber: Int
    public let totalPages: Int

    public init(image: CGImage, pageNumber: Int, totalPages: Int) {
        self.image = image
        self.pageNumber = pageNumber
        self.totalPages = totalPages
    }
}

/// 批处理任务（图片文件 / PDF / 剪贴板 / 截图）
public struct BatchJob: Identifiable, @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case pending
        case running(page: Int, totalPages: Int)
        case done
        case failed(String)
        case cancelled
    }

    public let id = UUID()
    public let fileName: String
    public let kind: SourceKind
    public let url: URL?
    /// 剪贴板/截图直接携带的图像（无文件来源）
    public let carriedImage: CGImage?
    public var status: Status = .pending

    public init(fileName: String, kind: SourceKind, url: URL? = nil, carriedImage: CGImage? = nil) {
        self.fileName = fileName
        self.kind = kind
        self.url = url
        self.carriedImage = carriedImage
    }
}

/// 页面加载器：任务 → 待识别页列表
public protocol PageLoader: Sendable {
    func load(job: BatchJob, dpi: CGFloat) throws -> [PageLoad]
}

/// 默认加载器：图片文件单页；PDF 逐页渲染；携带图像直通
public struct FilePageLoader: PageLoader {
    public init() {}

    public func load(job: BatchJob, dpi: CGFloat) throws -> [PageLoad] {
        if let image = job.carriedImage {
            return [PageLoad(image: image, pageNumber: 1, totalPages: 1)]
        }
        guard let url = job.url else { throw EngineError.imageDecodeFailed }
        if job.kind == .pdf {
            return try PDFRenderer.render(url: url, dpi: dpi)
        }
        guard let data = try? Data(contentsOf: url),
              let cg = ImageTools.cgImage(from: data) else {
            throw EngineError.imageDecodeFailed
        }
        return [PageLoad(image: cg, pageNumber: 1, totalPages: 1)]
    }
}

// MARK: - 批处理运行器

/// 批量识别调度：顺序处理队列任务，页级进度、可取消、失败隔离、产出历史记录。
/// AppModel 持有并通过回调接 UI。
@MainActor
@Observable
public final class BatchRunner {
    public private(set) var jobs: [BatchJob] = []
    public private(set) var isRunning = false

    /// 每完成一个任务回调一次（用于选中最新记录等）
    public var onRecordAdded: ((HistoryRecord) -> Void)?
    /// 整批失败（如服务启动失败）回调
    public var onBatchError: ((String) -> Void)?

    private let history: HistoryStore
    private var runTask: Task<Void, Never>?

    public init(history: HistoryStore) {
        self.history = history
    }

    // MARK: - 队列操作

    @discardableResult
    public func addFile(_ url: URL) -> UUID {
        let kind = FileScanner.kind(forExtension: url.pathExtension) ?? .other
        let job = BatchJob(fileName: url.lastPathComponent, kind: kind, url: url)
        jobs.append(job)
        return job.id
    }

    @discardableResult
    public func addImage(_ image: CGImage, fileName: String, kind: SourceKind) -> UUID {
        let job = BatchJob(fileName: fileName, kind: kind, carriedImage: image)
        jobs.append(job)
        return job.id
    }

    public func removeJob(id: UUID) {
        guard jobs.first(where: { $0.id == id })?.status != .running(page: 0, totalPages: 0) else { return }
        jobs.removeAll { $0.id == id }
    }

    public func clearFinished() {
        jobs.removeAll { job in
            switch job.status {
            case .done, .failed, .cancelled: return true
            case .pending, .running: return false
            }
        }
    }

    public var pendingCount: Int {
        jobs.filter { $0.status == .pending }.count
    }

    public var doneCount: Int {
        jobs.filter { $0.status == .done }.count
    }

    // MARK: - 运行

    public func cancel() {
        runTask?.cancel()
    }

    /// 启动批处理（返回 Task 句柄，可 await 等待完成）
    @discardableResult
    public func start(engineConfig: EngineConfig,
                      engine: OCREngine,
                      loader: PageLoader,
                      dpi: CGFloat,
                      ensureService: (@Sendable () async throws -> Void)? = nil) -> Task<Void, Never> {
        let task = Task { @MainActor in
            await runBody(engineConfig: engineConfig, engine: engine,
                          loader: loader, dpi: dpi, ensureService: ensureService)
        }
        runTask = task
        return task
    }

    private func runBody(engineConfig: EngineConfig,
                         engine: OCREngine,
                         loader: PageLoader,
                         dpi: CGFloat,
                         ensureService: (@Sendable () async throws -> Void)?) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        if let ensureService {
            do {
                try await ensureService()
            } catch is CancellationError {
                return
            } catch {
                onBatchError?(error.described)
                return
            }
        }

        while true {
            guard let index = jobs.firstIndex(where: { $0.status == .pending }) else { break }

            do {
                try Task.checkCancellation()
            } catch {
                jobs[index].status = .cancelled
                return
            }

            // 加载页面（文件不可读等 → 仅该任务失败）
            let loads: [PageLoad]
            do {
                loads = try loader.load(job: jobs[index], dpi: dpi)
            } catch {
                jobs[index].status = .failed(error.described)
                continue
            }

            // 逐页识别
            var pages: [OcrPage] = []
            do {
                for load in loads {
                    jobs[index].status = .running(page: load.pageNumber, totalPages: load.totalPages)
                    try Task.checkCancellation()
                    pages.append(try await engine.recognize(
                        image: load.image,
                        options: RecognizeOptions(pageNumber: load.pageNumber)))
                }
            } catch is CancellationError {
                jobs[index].status = .cancelled
                return
            } catch {
                jobs[index].status = .failed(error.described)
                continue
            }

            let record = HistoryRecord(fileName: jobs[index].fileName,
                                       sourcePath: jobs[index].url?.path,
                                       sourceKind: jobs[index].kind,
                                       engineID: engineConfig.id,
                                       engineName: engineConfig.name,
                                       pages: pages,
                                       editedText: nil)
            let thumbnail = loads.first.flatMap { ImageTools.thumbnailPNG(from: $0.image) }
            do {
                try history.add(record, thumbnailPNG: thumbnail)
            } catch {
                jobs[index].status = .failed("保存历史失败：\(error.localizedDescription)")
                continue
            }
            jobs[index].status = .done
            onRecordAdded?(record)
        }
    }
}

// MARK: - 错误描述

extension Error {
    /// 引擎错误用中文描述，其余用系统本地化描述
    public var described: String {
        if let engineError = self as? EngineError {
            return engineError.description
        }
        return localizedDescription
    }
}
