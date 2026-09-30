import Foundation

/// 历史记录存储：每条记录一个 JSON 文件 + 可选缩略图 PNG，保存在应用支持目录。
/// 重启后 init 自动加载（验收 #6）。
public final class HistoryStore {
    public let directory: URL
    public private(set) var records: [HistoryRecord] = []

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OCRGUI/History", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        load()
    }

    // MARK: - 增删改

    public func add(_ record: HistoryRecord, thumbnailPNG: Data? = nil) throws {
        var newRecord = record
        if let png = thumbnailPNG {
            let url = directory.appendingPathComponent("\(record.id.uuidString).png")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url)
            newRecord.thumbnailPath = url.path
        }
        try write(newRecord)
        insertSorted(newRecord)
    }

    public func update(_ record: HistoryRecord) throws {
        try write(record)
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            insertSorted(record)
        }
    }

    public func delete(id: UUID) throws {
        let jsonURL = directory.appendingPathComponent("\(id.uuidString).json")
        let pngURL = directory.appendingPathComponent("\(id.uuidString).png")
        try? FileManager.default.removeItem(at: jsonURL)
        try? FileManager.default.removeItem(at: pngURL)
        records.removeAll { $0.id == id }
    }

    public func deleteAll() throws {
        for record in records { try delete(id: record.id) }
    }

    // MARK: - 私有

    private func insertSorted(_ record: HistoryRecord) {
        if let idx = records.firstIndex(where: { $0.createdAt < record.createdAt }) {
            records.insert(record, at: idx)
        } else {
            records.append(record)
        }
    }

    private func write(_ record: HistoryRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
    }

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [HistoryRecord] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(HistoryRecord.self, from: data) else { continue }
            loaded.append(record)
        }
        records = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}
