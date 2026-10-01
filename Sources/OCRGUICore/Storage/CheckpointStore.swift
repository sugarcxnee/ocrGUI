import Foundation
import CryptoKit

/// 单个任务的页级断点（对应 webUI outputs/.chunks 的语义）
public struct JobCheckpoint: Codable, Equatable, Sendable {
    public let jobKey: String
    public var pages: [OcrPage]

    public init(jobKey: String, pages: [OcrPage]) {
        self.jobKey = jobKey
        self.pages = pages
    }
}

/// 大 PDF 逐页识别的断点存取：每页完成即落盘，
/// 取消/崩溃后重跑同一文件（同大小/DPI/引擎/提示词）自动跳过已完成页。
public final class CheckpointStore {
    public let directory: URL

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OCRGUI/Checkpoints", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    /// 任务指纹：文件路径 + 大小 + DPI + 引擎 + 提示词（任一变化视为不同任务）
    public static func jobKey(path: String, fileSize: Int64, dpi: Int,
                              engineID: String, prompt: String?) -> String {
        let raw = [path, String(fileSize), String(dpi), engineID, prompt ?? ""].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    public func load(key: String) -> JobCheckpoint? {
        let url = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JobCheckpoint.self, from: data)
    }

    public func save(_ checkpoint: JobCheckpoint) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(checkpoint)
        try data.write(to: directory.appendingPathComponent("\(checkpoint.jobKey).json"), options: .atomic)
    }

    public func delete(key: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).json"))
    }

    public func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
