import Testing
import Foundation
@testable import OCRGUICore

// MARK: - HistoryStore 持久化

private func makeRecord(_ name: String, createdAt: Date = Date()) -> HistoryRecord {
    HistoryRecord(fileName: name, sourcePath: "/tmp/\(name)", sourceKind: .image,
                  engineID: "vision", engineName: "Vision",
                  pages: [OcrPage(pageNumber: 1, width: 10, height: 10, lines: [], markdown: "文本-\(name)")],
                  editedText: nil)
}

@Test("新增记录落盘，重启（新建 Store）后仍可读")
func addPersistsAcrossRestart() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store1 = HistoryStore(directory: dir)
    try store1.add(makeRecord("a.png"))
    #expect(store1.records.count == 1)

    let store2 = HistoryStore(directory: dir)
    #expect(store2.records.count == 1)
    #expect(store2.records.first?.pages.first?.markdown == "文本-a.png")
}

@Test("更新记录会重写文件")
func updateRewritesFile() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(directory: dir)
    let record = makeRecord("a.png")
    try store.add(record)

    var edited = record
    edited.editedText = "人工修正"
    try store.update(edited)

    let reloaded = HistoryStore(directory: dir)
    #expect(reloaded.records.first?.editedText == "人工修正")
}

@Test("删除记录同时删除文件")
func deleteRemovesFile() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(directory: dir)
    let record = makeRecord("a.png")
    try store.add(record)
    #expect(store.records.count == 1)

    try store.delete(id: record.id)
    #expect(store.records.isEmpty)
    #expect(HistoryStore(directory: dir).records.isEmpty)
}

@Test("缩略图 PNG 落盘且路径随记录保存")
func thumbnailPNGWritten() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG 魔数即可
    let store = HistoryStore(directory: dir)
    try store.add(makeRecord("a.png"), thumbnailPNG: png)

    let thumbPath = try #require(store.records.first?.thumbnailPath)
    #expect(FileManager.default.fileExists(atPath: thumbPath))
    #expect(try Data(contentsOf: URL(fileURLWithPath: thumbPath)) == png)
}

@Test("记录按创建时间倒序")
func recordsSortedDescByCreatedAt() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ocrgui-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(directory: dir)
    let older = makeRecord("old.png", createdAt: Date(timeIntervalSinceNow: -100))
    let newer = makeRecord("new.png", createdAt: Date())
    try store.add(older)
    try store.add(newer)
    #expect(store.records.map(\.fileName) == ["new.png", "old.png"])
}
